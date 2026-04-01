package com.pixyvibe.companion.network

import android.graphics.Bitmap
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * Converts Bitmap frames to base64 JPEG/PNG and sends via WebSocketClient.
 * Mirrors iOS FrameTransport.swift.
 */
class FrameTransport(
    private val client: WebSocketClient,
    fps: Int = 10,
) {
    private val minFrameIntervalMs = 1000L / fps
    private var lastFrameTimeMs = 0L

    /**
     * Compress bitmap to JPEG and send as a frame to all connected desktops.
     * Rate-limited to configured fps.
     */
    fun sendFrame(bitmap: Bitmap) {
        val now = System.currentTimeMillis()
        if (now - lastFrameTimeMs < minFrameIntervalMs) return
        lastFrameTimeMs = now

        val base64 = bitmapToBase64Jpeg(bitmap, quality = 50)
        client.sendFrameToAll(base64)
    }

    /**
     * Compress bitmap to PNG and send as a screenshot result to all desktops.
     */
    fun sendScreenshot(bitmap: Bitmap) {
        val base64 = bitmapToBase64Png(bitmap)
        client.sendScreenshotToAll(base64)
    }

    private fun bitmapToBase64Jpeg(bitmap: Bitmap, quality: Int): String {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }

    private fun bitmapToBase64Png(bitmap: Bitmap): String {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
    }
}
