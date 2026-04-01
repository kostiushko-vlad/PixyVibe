package com.pixyvibe.companion.capture

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import com.pixyvibe.companion.R
import com.pixyvibe.companion.network.FrameTransport
import com.pixyvibe.companion.network.WebSocketClient

/**
 * Foreground service that captures the screen via MediaProjection and streams
 * frames to connected desktops. Equivalent to iOS BroadcastExtension/SampleHandler.
 */
class ScreenCaptureService : Service() {

    companion object {
        const val CHANNEL_ID = "pixyvibe_capture"
        const val NOTIFICATION_ID = 1

        const val ACTION_START = "com.pixyvibe.companion.START_CAPTURE"
        const val ACTION_STOP = "com.pixyvibe.companion.STOP_CAPTURE"
        const val ACTION_SCREENSHOT = "com.pixyvibe.companion.SCREENSHOT"

        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"

        private var instance: ScreenCaptureService? = null
        val isRunning: Boolean get() = instance != null

        fun requestScreenshot() {
            instance?.captureScreenshot()
        }
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null

    private var webSocketClient: WebSocketClient? = null
    private var frameTransport: FrameTransport? = null

    private var isStreaming = false
    private var screenshotRequested = false
    private var screenWidth = 720
    private var screenHeight = 1280
    private var screenDensity = DisplayMetrics.DENSITY_DEFAULT

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()

        // Get screen metrics
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)

        // Scale down for streaming (max 720p width to save bandwidth)
        val scale = if (metrics.widthPixels > 720) 720f / metrics.widthPixels else 1f
        screenWidth = (metrics.widthPixels * scale).toInt()
        screenHeight = (metrics.heightPixels * scale).toInt()
        screenDensity = metrics.densityDpi

        // Background thread for image processing
        handlerThread = HandlerThread("ScreenCapture").also { it.start() }
        handler = Handler(handlerThread!!.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val resultData = intent.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
                if (resultData != null) {
                    startForeground()
                    startCapture(resultCode, resultData)
                }
            }
            ACTION_STOP -> {
                stopCapture()
                stopSelf()
            }
            ACTION_SCREENSHOT -> {
                screenshotRequested = true
            }
        }
        return START_NOT_STICKY
    }

    private fun startForeground() {
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.capture_notification_title))
            .setContentText(getString(R.string.capture_notification_text))
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startCapture(resultCode: Int, resultData: Intent) {
        val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, resultData)

        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopCapture()
                stopSelf()
            }
        }, handler)

        // Initialize WebSocket client and frame transport
        webSocketClient = WebSocketClient(this).also { client ->
            frameTransport = FrameTransport(client, fps = 10)

            client.onScreenshotRequested = {
                screenshotRequested = true
            }

            // Connect to all saved desktops
            val desktops = client.getSavedDesktops()
            for ((name, host, port) in desktops) {
                client.connect(host, port, name)
            }
        }

        // Set up ImageReader for frame capture
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)

        imageReader?.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener

            try {
                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * screenWidth

                val bitmap = Bitmap.createBitmap(
                    screenWidth + rowPadding / pixelStride,
                    screenHeight,
                    Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)

                // Crop out padding if any
                val cropped = if (rowPadding > 0) {
                    Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight).also {
                        if (it !== bitmap) bitmap.recycle()
                    }
                } else {
                    bitmap
                }

                if (screenshotRequested) {
                    screenshotRequested = false
                    frameTransport?.sendScreenshot(cropped)
                } else if (isStreaming) {
                    frameTransport?.sendFrame(cropped)
                }

                cropped.recycle()
            } finally {
                image.close()
            }
        }, handler)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "PixyVibeCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, handler
        )

        isStreaming = true
    }

    private fun captureScreenshot() {
        screenshotRequested = true
    }

    private fun stopCapture() {
        isStreaming = false
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null
        webSocketClient?.destroy()
        webSocketClient = null
        frameTransport = null
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.capture_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Screen capture streaming notification"
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        stopCapture()
        handlerThread?.quitSafely()
        instance = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
