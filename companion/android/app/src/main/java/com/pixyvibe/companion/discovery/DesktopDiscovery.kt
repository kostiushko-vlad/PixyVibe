package com.pixyvibe.companion.discovery

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class DiscoveredDesktop(
    val name: String,
    val host: String? = null,
    val port: Int? = null,
) {
    val isResolved: Boolean get() = host != null && port != null && port > 0
}

/**
 * Discovers PixyVibe desktop instances via mDNS/NSD.
 * Mirrors iOS DesktopDiscovery which uses NWBrowser for _screenshottool._tcp.
 */
class DesktopDiscovery(context: Context) {

    companion object {
        private const val TAG = "DesktopDiscovery"
        private const val SERVICE_TYPE = "_screenshottool._tcp."
    }

    private val appContext = context.applicationContext
    private val nsdManager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager

    // Multicast lock is required for mDNS to work on Android WiFi
    private val multicastLock: WifiManager.MulticastLock =
        (appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
            .createMulticastLock("PixyVibe_mDNS").apply {
                setReferenceCounted(true)
            }

    private val _desktops = MutableStateFlow<List<DiscoveredDesktop>>(emptyList())
    val desktops: StateFlow<List<DiscoveredDesktop>> = _desktops.asStateFlow()

    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private var discoveryListener: NsdManager.DiscoveryListener? = null
    private val pendingResolves = mutableSetOf<String>()

    fun startSearching() {
        if (discoveryListener != null) return

        // Acquire multicast lock so mDNS packets are delivered
        if (!multicastLock.isHeld) {
            multicastLock.acquire()
            Log.d(TAG, "Multicast lock acquired")
        }

        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {
                Log.d(TAG, "Discovery started for $serviceType")
                _isSearching.value = true
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                val name = serviceInfo.serviceName
                Log.d(TAG, "Service found: $name")
                // Add unresolved entry immediately
                addOrUpdateDesktop(DiscoveredDesktop(name = name))
                resolveService(serviceInfo)
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                val name = serviceInfo.serviceName
                Log.d(TAG, "Service lost: $name")
                _desktops.value = _desktops.value.filter { it.name != name }
            }

            override fun onDiscoveryStopped(serviceType: String) {
                Log.d(TAG, "Discovery stopped")
                _isSearching.value = false
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "Discovery start failed: errorCode=$errorCode")
                _isSearching.value = false
                discoveryListener = null
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.e(TAG, "Discovery stop failed: errorCode=$errorCode")
            }
        }

        discoveryListener = listener
        nsdManager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val name = serviceInfo.serviceName
        if (name in pendingResolves) return
        pendingResolves.add(name)

        Log.d(TAG, "Resolving service: $name")

        nsdManager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "Resolve failed for $name: errorCode=$errorCode")
                pendingResolves.remove(name)
            }

            override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                pendingResolves.remove(name)
                val host = serviceInfo.host?.hostAddress ?: return
                val port = serviceInfo.port
                Log.d(TAG, "Resolved $name -> $host:$port")
                addOrUpdateDesktop(DiscoveredDesktop(name = name, host = host, port = port))
            }
        })
    }

    private fun addOrUpdateDesktop(desktop: DiscoveredDesktop) {
        val current = _desktops.value.toMutableList()
        val index = current.indexOfFirst { it.name == desktop.name }
        if (index >= 0) {
            // Only update if new info is better (has host/port)
            if (desktop.isResolved || !current[index].isResolved) {
                current[index] = desktop
            }
        } else {
            current.add(desktop)
        }
        _desktops.value = current
    }

    fun stopSearching() {
        discoveryListener?.let { listener ->
            try {
                nsdManager.stopServiceDiscovery(listener)
            } catch (_: IllegalArgumentException) {
                // Already stopped
            }
        }
        discoveryListener = null
        pendingResolves.clear()
        _isSearching.value = false

        // Release multicast lock
        if (multicastLock.isHeld) {
            multicastLock.release()
            Log.d(TAG, "Multicast lock released")
        }
    }
}
