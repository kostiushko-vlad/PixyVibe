package com.pixyvibe.companion.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.unit.dp
import com.pixyvibe.companion.network.ConnectionState
import com.pixyvibe.companion.ui.theme.PVi

@Composable
fun StatusIndicator(state: ConnectionState, modifier: Modifier = Modifier) {
    val color = when (state) {
        ConnectionState.CONNECTED -> PVi.Success
        ConnectionState.CONNECTING -> PVi.Orange
        ConnectionState.DISCONNECTED -> PVi.TextSecondary.copy(alpha = 0.4f)
    }

    Box(
        modifier = modifier
            .size(6.dp)
            .then(
                if (state == ConnectionState.CONNECTED) {
                    Modifier.shadow(4.dp, CircleShape, ambientColor = PVi.Success, spotColor = PVi.Success)
                } else {
                    Modifier
                }
            )
            .background(color, CircleShape)
    )
}
