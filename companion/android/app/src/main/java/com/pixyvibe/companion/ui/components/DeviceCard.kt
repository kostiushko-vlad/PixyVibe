package com.pixyvibe.companion.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixyvibe.companion.discovery.DiscoveredDesktop
import com.pixyvibe.companion.ui.theme.PVi

@Composable
fun AvailableDesktopCard(
    desktop: DiscoveredDesktop,
    onConnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(12.dp)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(PVi.Surface, shape)
            .border(0.5.dp, PVi.Border, shape)
            .clickable(enabled = desktop.isResolved) { onConnect() }
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            painter = painterResource(android.R.drawable.ic_menu_manage),
            contentDescription = null,
            tint = PVi.AccentStart,
            modifier = Modifier.size(20.dp),
        )

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                text = desktop.name,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                color = PVi.TextPrimary,
            )
            if (desktop.isResolved) {
                Text(
                    text = "${desktop.host}:${desktop.port}",
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    color = PVi.TextSecondary,
                )
            } else {
                Text(
                    text = "Resolving...",
                    fontSize = 10.sp,
                    color = PVi.Orange,
                )
            }
        }

        val pillShape = RoundedCornerShape(8.dp)
        Text(
            text = "Connect",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            color = PVi.TextPrimary,
            modifier = Modifier
                .background(
                    brush = Brush.horizontalGradient(listOf(PVi.AccentStart, PVi.AccentEnd)),
                    shape = pillShape,
                )
                .padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
}
