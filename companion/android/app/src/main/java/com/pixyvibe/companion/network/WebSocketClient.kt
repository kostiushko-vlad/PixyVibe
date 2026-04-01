package com.pixyvibe.companion.network

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import com.pixyvibe.companion.discovery.DiscoveredDesktop
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow

enum class ConnectionState {
    DISCONNECTED, CONNECTING, CONNECTED
}

data class DesktopConnection(
    val id: String,  // desktop name
    val host: String,
    val port: Int,
    val state: ConnectionState = ConnectionState.DISCONNECTED,
    val reconnectAttempts: Int = 0,
    val shouldReconnect: Boolean = true,
)

/**
 * Manages WebSocket connections to multiple desktop PixyVibe instances.
 * Mirrors iOS WebSocketClient.swift — same JSON protocol.
 */
class WebSocketClient(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("pixyvibe_companion", Context.MODE_PRIVATE)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _connections = MutableStateFlow<Map<String, DesktopConnection>>(emptyMap())
    val connections: StateFlow<Map<String, DesktopConnection>> = _connections.asStateFlow()

    val connectedCount: Int
        get() = _connections.value.values.count { it.state == ConnectionState.CONNECTED }

    val hasAnyConnection: Boolean
        get() = connectedCount > 0

    private val okClient = OkHttpClient.Builder()
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    private val webSockets = mutableMapOf<String, WebSocket>()

    val deviceId: String = prefs.getString("device_id", null)
        ?: UUID.randomUUID().toString().also { prefs.edit().putString("device_id", it).apply() }

    var deviceName: String
        get() = prefs.getString("custom_device_name", null) ?: Build.MODEL
        set(value) { prefs.edit().putString("custom_device_name", value).apply() }

    /** Callback invoked when desktop requests a screenshot. */
    var onScreenshotRequested: (() -> Unit)? = null

    /** Callback invoked when desktop requests start recording. */
    var onStartRecording: ((fps: Int) -> Unit)? = null

    /** Callback invoked when desktop requests stop recording. */
    var onStopRecording: (() -> Unit)? = null

    // MARK: - Connection Management

    fun connect(desktop: DiscoveredDesktop) {
        val host = desktop.host ?: return
        val port = desktop.port ?: return
        if (!desktop.isResolved) return
        connect(host, port, desktop.name)
    }

    fun connect(host: String, port: Int, name: String) {
        val existing = _connections.value[name]
        if (existing != null && existing.state != ConnectionState.DISCONNECTED
            && existing.host == host && existing.port == port) {
            return
        }

        // Disconnect existing if any
        disconnectDesktop(name)

        val conn = DesktopConnection(
            id = name, host = host, port = port,
            state = ConnectionState.CONNECTING,
            shouldReconnect = true,
        )
        updateConnection(name, conn)
        saveAllConnectionInfo()

        val request = Request.Builder()
            .url("ws://$host:$port")
            .build()

        val ws = okClient.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                updateConnection(name, _connections.value[name]?.copy(
                    state = ConnectionState.CONNECTED,
                    reconnectAttempts = 0,
                ))
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handleMessage(text, name)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                updateConnection(name, _connections.value[name]?.copy(
                    state = ConnectionState.DISCONNECTED,
                ))
                attemptReconnect(name)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                updateConnection(name, _connections.value[name]?.copy(
                    state = ConnectionState.DISCONNECTED,
                ))
                attemptReconnect(name)
            }
        })

        webSockets[name] = ws
    }

    fun disconnectDesktop(name: String) {
        val conn = _connections.value[name] ?: return
        updateConnection(name, conn.copy(shouldReconnect = false))
        webSockets.remove(name)?.close(1000, "User disconnect")
        val updated = _connections.value.toMutableMap()
        updated.remove(name)
        _connections.value = updated
        saveAllConnectionInfo()
    }

    fun disconnectAll() {
        for (name in _connections.value.keys.toList()) {
            updateConnection(name, _connections.value[name]?.copy(shouldReconnect = false))
            webSockets.remove(name)?.close(1000, "Disconnect all")
        }
        _connections.value = emptyMap()
        saveAllConnectionInfo()
    }

    fun stateFor(desktopName: String): ConnectionState {
        return _connections.value[desktopName]?.state ?: ConnectionState.DISCONNECTED
    }

    // MARK: - Sending

    fun sendFrameToAll(base64Jpeg: String) {
        val json = JSONObject().apply {
            put("type", "frame")
            put("data", base64Jpeg)
            put("timestamp", System.currentTimeMillis() / 1000)
        }.toString()

        for ((name, ws) in webSockets) {
            if (_connections.value[name]?.state == ConnectionState.CONNECTED) {
                ws.send(json)
            }
        }
    }

    fun sendScreenshotToAll(base64Png: String) {
        val json = JSONObject().apply {
            put("type", "screenshot_result")
            put("data", base64Png)
        }.toString()

        for ((name, ws) in webSockets) {
            if (_connections.value[name]?.state == ConnectionState.CONNECTED) {
                ws.send(json)
            }
        }
    }

    // MARK: - Message Handling

    private fun handleMessage(text: String, desktopName: String) {
        val json = try { JSONObject(text) } catch (_: Exception) { return }
        val type = json.optString("type")

        when (type) {
            "ping" -> {
                val pong = JSONObject().apply {
                    put("type", "pong")
                    put("device_name", deviceName)
                    put("device_id", deviceId)
                }.toString()
                webSockets[desktopName]?.send(pong)

                updateConnection(desktopName, _connections.value[desktopName]?.copy(
                    state = ConnectionState.CONNECTED,
                ))
            }
            "screenshot" -> {
                onScreenshotRequested?.invoke()
            }
            "start_recording" -> {
                val fps = json.optInt("fps", 10)
                onStartRecording?.invoke(fps)
            }
            "stop_recording" -> {
                onStopRecording?.invoke()
            }
        }
    }

    // MARK: - Reconnection

    private fun attemptReconnect(desktopName: String) {
        val conn = _connections.value[desktopName] ?: return
        if (!conn.shouldReconnect) return

        val maxAttempts = 5
        if (conn.reconnectAttempts >= maxAttempts) {
            val updated = _connections.value.toMutableMap()
            updated.remove(desktopName)
            _connections.value = updated
            return
        }

        val newAttempts = conn.reconnectAttempts + 1
        updateConnection(desktopName, conn.copy(reconnectAttempts = newAttempts))

        val delay = min(2.0.pow(newAttempts.toDouble()), 30.0).toLong() * 1000

        scope.launch {
            delay(delay)
            val current = _connections.value[desktopName]
            if (current?.shouldReconnect == true) {
                connect(current.host, current.port, desktopName)
            }
        }
    }

    // MARK: - Persistence

    private fun saveAllConnectionInfo() {
        val desktopList = JSONArray()
        for (conn in _connections.value.values) {
            desktopList.put(JSONObject().apply {
                put("host", conn.host)
                put("port", conn.port)
                put("name", conn.id)
            })
        }

        prefs.edit()
            .putString("desktop_list", desktopList.toString())
            .putString("device_id", deviceId)
            .putString("device_name_display", deviceName)
            .apply()
    }

    /** Get the saved desktop list (used by ScreenCaptureService). */
    fun getSavedDesktops(): List<Triple<String, String, Int>> {
        val raw = prefs.getString("desktop_list", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val obj = arr.getJSONObject(i)
                val name = obj.optString("name", "Desktop")
                val host = obj.optString("host") ?: return@mapNotNull null
                val port = obj.optInt("port", 0)
                if (port > 0) Triple(name, host, port) else null
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun updateConnection(name: String, conn: DesktopConnection?) {
        if (conn == null) return
        val updated = _connections.value.toMutableMap()
        updated[name] = conn
        _connections.value = updated
    }

    fun destroy() {
        disconnectAll()
        scope.cancel()
        okClient.dispatcher.executorService.shutdown()
    }
}
