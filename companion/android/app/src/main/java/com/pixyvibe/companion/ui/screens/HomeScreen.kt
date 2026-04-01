package com.pixyvibe.companion.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixyvibe.companion.discovery.DesktopDiscovery
import com.pixyvibe.companion.discovery.DiscoveredDesktop
import com.pixyvibe.companion.network.ConnectionState
import com.pixyvibe.companion.network.WebSocketClient
import com.pixyvibe.companion.ui.components.AvailableDesktopCard
import com.pixyvibe.companion.ui.components.StatusIndicator
import com.pixyvibe.companion.ui.theme.PVi

@Composable
fun HomeScreen(
    discovery: DesktopDiscovery,
    webSocketClient: WebSocketClient,
    isCaptureRunning: Boolean,
    onStartCapture: () -> Unit,
    onStopCapture: () -> Unit,
) {
    val desktops by discovery.desktops.collectAsState()
    val isSearching by discovery.isSearching.collectAsState()
    val connections by webSocketClient.connections.collectAsState()

    // Auto-connect to resolved desktops
    LaunchedEffect(desktops) {
        for (desktop in desktops) {
            if (desktop.isResolved && webSocketClient.stateFor(desktop.name) == ConnectionState.DISCONNECTED) {
                webSocketClient.connect(desktop)
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PVi.Base),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Header
            HeaderView()

            // Device name card
            DeviceNameCard(webSocketClient)

            // Broadcast control
            BroadcastCard(
                isCaptureRunning = isCaptureRunning,
                hasConnections = connections.values.any { it.state == ConnectionState.CONNECTED },
                onStart = onStartCapture,
                onStop = onStopCapture,
            )

            // Connected desktops
            val connectedList = connections.values
                .filter { it.state != ConnectionState.DISCONNECTED }
                .sortedBy { it.id }

            if (connectedList.isNotEmpty()) {
                ConnectedDesktopsCard(connectedList)
            }

            // Available (unconnected) desktops
            val unconnected = desktops.filter {
                webSocketClient.stateFor(it.name) == ConnectionState.DISCONNECTED
            }
            if (unconnected.isNotEmpty()) {
                AvailableDesktopsSection(unconnected, webSocketClient)
            }

            // Empty / searching state
            if (isSearching && desktops.isEmpty()) {
                SearchingView()
            } else if (desktops.isEmpty() && connections.isEmpty()) {
                EmptyStateView()
            }

            Spacer(modifier = Modifier.height(20.dp))
        }
    }
}

@Composable
private fun HeaderView() {
    Column {
        Text(
            text = "PixyVibe",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = PVi.TextPrimary,
        )
        Text(
            text = "Companion",
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = PVi.AccentStart,
        )
    }
}

@Composable
private fun DeviceNameCard(webSocketClient: WebSocketClient) {
    var editingName by remember { mutableStateOf(false) }
    var nameText by remember { mutableStateOf("") }

    val cardShape = RoundedCornerShape(14.dp)

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(PVi.Surface, cardShape)
            .border(0.5.dp, PVi.Border, cardShape)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Phone icon
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(PVi.AccentSolid.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painter = painterResource(android.R.drawable.ic_menu_call),
                contentDescription = null,
                tint = PVi.AccentStart,
                modifier = Modifier.size(18.dp),
            )
        }

        if (editingName) {
            BasicTextField(
                value = nameText,
                onValueChange = { nameText = it },
                modifier = Modifier
                    .weight(1f)
                    .background(PVi.SurfaceHigh, RoundedCornerShape(8.dp))
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                textStyle = TextStyle(fontSize = 15.sp, color = PVi.TextPrimary),
                cursorBrush = SolidColor(PVi.AccentStart),
                singleLine = true,
            )
            PillButton("Save") {
                if (nameText.isNotBlank()) {
                    webSocketClient.deviceName = nameText
                }
                editingName = false
            }
        } else {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = webSocketClient.deviceName,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    color = PVi.TextPrimary,
                )
                Text(
                    text = "This device",
                    fontSize = 11.sp,
                    color = PVi.TextSecondary,
                )
            }
            PillButton("Rename") {
                nameText = webSocketClient.deviceName
                editingName = true
            }
        }
    }
}

@Composable
private fun BroadcastCard(
    isCaptureRunning: Boolean,
    hasConnections: Boolean,
    onStart: () -> Unit,
    onStop: () -> Unit,
) {
    val cardShape = RoundedCornerShape(14.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(PVi.Surface, cardShape)
            .border(0.5.dp, PVi.Border, cardShape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .background(
                        if (isCaptureRunning) PVi.Success else PVi.TextSecondary.copy(alpha = 0.4f),
                        CircleShape,
                    )
            )
            Text(
                text = if (isCaptureRunning) "Streaming" else "Not streaming",
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = PVi.TextPrimary,
            )
        }

        if (isCaptureRunning) {
            Button(
                onClick = onStop,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = PVi.TextSecondary.copy(alpha = 0.2f),
                ),
                contentPadding = PaddingValues(vertical = 12.dp),
            ) {
                Text("Stop Streaming", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = PVi.TextPrimary)
            }
        } else {
            Button(
                onClick = onStart,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(10.dp),
                enabled = hasConnections,
                colors = ButtonDefaults.buttonColors(containerColor = PVi.AccentStart),
                contentPadding = PaddingValues(vertical = 12.dp),
            ) {
                Text("Start Streaming", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = PVi.TextPrimary)
            }

            if (!hasConnections) {
                Text(
                    text = "Connect to a desktop first",
                    fontSize = 11.sp,
                    color = PVi.TextSecondary,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun ConnectedDesktopsCard(
    connections: List<com.pixyvibe.companion.network.DesktopConnection>,
) {
    val cardShape = RoundedCornerShape(14.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(PVi.Surface, cardShape)
            .border(0.5.dp, PVi.Border, cardShape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SectionLabel("CONNECTED")
        Spacer(modifier = Modifier.height(4.dp))

        for (conn in connections) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(PVi.SurfaceHigh.copy(alpha = 0.5f), RoundedCornerShape(8.dp))
                    .padding(vertical = 8.dp, horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    painter = painterResource(android.R.drawable.ic_menu_manage),
                    contentDescription = null,
                    tint = PVi.TextSecondary,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    text = conn.id,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = PVi.TextPrimary,
                    modifier = Modifier.weight(1f),
                )
                StatusIndicator(state = conn.state)
                Text(
                    text = when (conn.state) {
                        ConnectionState.CONNECTED -> "Connected"
                        ConnectionState.CONNECTING -> "Connecting"
                        ConnectionState.DISCONNECTED -> "Disconnected"
                    },
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                    color = PVi.TextSecondary,
                )
            }
        }
    }
}

@Composable
private fun AvailableDesktopsSection(
    desktops: List<DiscoveredDesktop>,
    webSocketClient: WebSocketClient,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel("AVAILABLE")

        for (desktop in desktops) {
            AvailableDesktopCard(
                desktop = desktop,
                onConnect = { webSocketClient.connect(desktop) },
            )
        }
    }
}

@Composable
private fun SearchingView() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        CircularProgressIndicator(
            color = PVi.AccentStart,
            modifier = Modifier.size(32.dp),
            strokeWidth = 2.dp,
        )
        Text(
            text = "Looking for PixyVibe on your network...",
            fontSize = 14.sp,
            color = PVi.TextSecondary,
            textAlign = TextAlign.Center,
        )
        InfoBox()
    }
}

@Composable
private fun EmptyStateView() {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .background(PVi.AccentSolid.copy(alpha = 0.08f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painter = painterResource(android.R.drawable.ic_dialog_alert),
                contentDescription = null,
                tint = PVi.AccentStart.copy(alpha = 0.6f),
                modifier = Modifier.size(28.dp),
            )
        }

        Text(
            text = "No desktops found",
            fontSize = 17.sp,
            fontWeight = FontWeight.SemiBold,
            color = PVi.TextPrimary,
        )

        InfoBox()
    }
}

@Composable
private fun InfoBox() {
    val cardShape = RoundedCornerShape(12.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(PVi.Surface, cardShape)
            .border(0.5.dp, PVi.Border, cardShape)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        InfoRow("1", "Open PixyVibe on your desktop")
        InfoRow("2", "Both devices on the same Wi-Fi")
        InfoRow("3", "Desktops connect automatically")
    }
}

@Composable
private fun InfoRow(number: String, text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = number,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = PVi.TextPrimary,
            modifier = Modifier
                .background(PVi.AccentSolid.copy(alpha = 0.3f), RoundedCornerShape(5.dp))
                .padding(horizontal = 6.dp, vertical = 2.dp),
        )
        Text(
            text = text,
            fontSize = 13.sp,
            color = PVi.TextSecondary,
        )
    }
}

@Composable
private fun SectionLabel(title: String) {
    Text(
        text = title,
        fontSize = 10.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.sp,
        color = PVi.TextSecondary.copy(alpha = 0.6f),
    )
}

@Composable
private fun PillButton(label: String, onClick: () -> Unit) {
    val shape = RoundedCornerShape(6.dp)
    Text(
        text = label,
        fontSize = 12.sp,
        fontWeight = FontWeight.Medium,
        color = PVi.AccentSolid,
        modifier = Modifier
            .clip(shape)
            .clickable(onClick = onClick)
            .background(PVi.AccentSolid.copy(alpha = 0.1f), shape)
            .border(0.5.dp, PVi.AccentSolid.copy(alpha = 0.2f), shape)
            .padding(horizontal = 10.dp, vertical = 5.dp),
    )
}
