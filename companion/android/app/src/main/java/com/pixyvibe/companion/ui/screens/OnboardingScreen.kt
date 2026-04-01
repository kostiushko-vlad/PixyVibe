package com.pixyvibe.companion.ui.screens

import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.pixyvibe.companion.ui.theme.PVi

@Composable
fun OnboardingScreen(onComplete: () -> Unit) {
    var page by remember { mutableIntStateOf(0) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PVi.Base),
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AnimatedContent(targetState = page, label = "onboarding") { currentPage ->
                when (currentPage) {
                    0 -> WelcomePage(onNext = { page = 1 })
                    1 -> SetupPage(onDone = onComplete)
                }
            }
        }

        // Page dots
        Row(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 40.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            repeat(2) { i ->
                Box(
                    modifier = Modifier
                        .size(6.dp)
                        .clip(CircleShape)
                        .background(
                            if (i == page) {
                                Brush.horizontalGradient(listOf(PVi.AccentStart, PVi.AccentEnd))
                            } else {
                                SolidColor(PVi.Border)
                            }
                        )
                )
            }
        }
    }
}

@Composable
private fun WelcomePage(onNext: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.weight(1f))

        // Icon circle
        Box(
            modifier = Modifier
                .size(96.dp)
                .background(PVi.AccentSolid.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                painter = painterResource(android.R.drawable.ic_menu_send),
                contentDescription = null,
                tint = PVi.AccentStart,
                modifier = Modifier.size(40.dp),
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "PixyVibe",
            fontSize = 32.sp,
            fontWeight = FontWeight.Bold,
            color = PVi.TextPrimary,
        )
        Text(
            text = "Companion",
            fontSize = 16.sp,
            fontWeight = FontWeight.Medium,
            color = PVi.AccentStart,
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Connect to your desktop for wireless phone screenshots and live previews.",
            fontSize = 15.sp,
            color = PVi.TextSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 20.dp),
        )

        Spacer(modifier = Modifier.weight(1f))

        AccentButton(label = "Get Started", onClick = onNext)

        Spacer(modifier = Modifier.height(60.dp))
    }
}

@Composable
private fun SetupPage(onDone: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.weight(1f))

        Text(
            text = "How It Works",
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = PVi.TextPrimary,
        )

        Spacer(modifier = Modifier.height(24.dp))

        val cardShape = RoundedCornerShape(14.dp)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(PVi.Surface, cardShape)
                .border(0.5.dp, PVi.Border, cardShape)
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SetupRow("1", "Open PixyVibe on your desktop")
            SetupRow("2", "Make sure both devices are on the same Wi-Fi")
            SetupRow("3", "Your devices will connect automatically")
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Your phone will appear in the PixyVibe menu on your desktop.",
            fontSize = 13.sp,
            color = PVi.TextSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 8.dp),
        )

        Spacer(modifier = Modifier.weight(1f))

        AccentButton(label = "Done", onClick = onDone)

        Spacer(modifier = Modifier.height(60.dp))
    }
}

@Composable
private fun SetupRow(number: String, text: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text(
            text = number,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            color = PVi.TextPrimary,
            modifier = Modifier
                .background(PVi.AccentSolid.copy(alpha = 0.3f), RoundedCornerShape(7.dp))
                .padding(horizontal = 8.dp, vertical = 4.dp),
        )
        Text(
            text = text,
            fontSize = 14.sp,
            color = PVi.TextSecondary,
        )
    }
}

@Composable
private fun AccentButton(label: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = PVi.AccentStart),
        contentPadding = PaddingValues(vertical = 14.dp),
    ) {
        Text(
            text = label,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = PVi.TextPrimary,
        )
    }
}
