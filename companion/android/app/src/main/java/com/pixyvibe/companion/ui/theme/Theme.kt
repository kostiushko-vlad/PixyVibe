package com.pixyvibe.companion.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = PVi.AccentStart,
    secondary = PVi.AccentEnd,
    background = PVi.Base,
    surface = PVi.Surface,
    onPrimary = PVi.TextPrimary,
    onBackground = PVi.TextPrimary,
    onSurface = PVi.TextPrimary,
    outline = PVi.Border,
)

@Composable
fun PixyVibeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = PViTypography,
        content = content,
    )
}
