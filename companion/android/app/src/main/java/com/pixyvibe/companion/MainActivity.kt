package com.pixyvibe.companion

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import com.pixyvibe.companion.capture.ScreenCaptureService
import com.pixyvibe.companion.discovery.DesktopDiscovery
import com.pixyvibe.companion.network.WebSocketClient
import com.pixyvibe.companion.ui.screens.HomeScreen
import com.pixyvibe.companion.ui.screens.OnboardingScreen
import com.pixyvibe.companion.ui.theme.PixyVibeTheme

class MainActivity : ComponentActivity() {

    private lateinit var discovery: DesktopDiscovery
    private lateinit var webSocketClient: WebSocketClient

    private val projectionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_START
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, result.resultCode)
                putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, result.data)
            }
            startForegroundService(intent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        discovery = DesktopDiscovery(this)
        webSocketClient = WebSocketClient(this)

        // Wire up capture callbacks
        webSocketClient.onScreenshotRequested = {
            if (ScreenCaptureService.isRunning) {
                ScreenCaptureService.requestScreenshot()
            }
        }

        setContent {
            PixyVibeTheme {
                val onboardingComplete = remember {
                    mutableStateOf(
                        getSharedPreferences("pixyvibe_companion", MODE_PRIVATE)
                            .getBoolean("onboarding_complete", false)
                    )
                }

                Box(modifier = Modifier.fillMaxSize()) {
                    HomeScreen(
                        discovery = discovery,
                        webSocketClient = webSocketClient,
                        isCaptureRunning = ScreenCaptureService.isRunning,
                        onStartCapture = ::requestScreenCapture,
                        onStopCapture = ::stopScreenCapture,
                    )

                    AnimatedVisibility(
                        visible = !onboardingComplete.value,
                        enter = fadeIn(),
                        exit = fadeOut(),
                    ) {
                        OnboardingScreen(
                            onComplete = {
                                getSharedPreferences("pixyvibe_companion", MODE_PRIVATE)
                                    .edit()
                                    .putBoolean("onboarding_complete", true)
                                    .apply()
                                onboardingComplete.value = true
                            }
                        )
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        discovery.startSearching()
    }

    override fun onStop() {
        super.onStop()
        discovery.stopSearching()
    }

    override fun onDestroy() {
        super.onDestroy()
        webSocketClient.destroy()
    }

    private fun requestScreenCapture() {
        val pm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        projectionLauncher.launch(pm.createScreenCaptureIntent())
    }

    private fun stopScreenCapture() {
        val intent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_STOP
        }
        startService(intent)
    }
}
