package com.royp.maccysync.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// "Terminal Citrus" — dark, monospace-forward utility aesthetic for a clipboard tool.
object Ink {
  val bg = Color(0xFF0C0D0E)        // near-black canvas
  val surface = Color(0xFF151719)   // cards
  val surfaceHi = Color(0xFF1E2125) // raised / segmented track
  val border = Color(0xFF2A2F34)    // hairline borders
  val text = Color(0xFFEAEDE6)      // primary text
  val muted = Color(0xFF848C84)     // secondary text
  val faint = Color(0xFF5A615A)

  val lime = Color(0xFFB6F24E)      // phone · live · primary accent
  val amber = Color(0xFFF4B860)     // mac clips
  val coral = Color(0xFFFF6B5E)     // destructive · offline
  val onAccent = Color(0xFF0F1409)  // text on lime
}

private val MaccyScheme = darkColorScheme(
  primary = Ink.lime,
  onPrimary = Ink.onAccent,
  secondary = Ink.amber,
  onSecondary = Ink.onAccent,
  background = Ink.bg,
  onBackground = Ink.text,
  surface = Ink.surface,
  onSurface = Ink.text,
  surfaceVariant = Ink.surfaceHi,
  onSurfaceVariant = Ink.muted,
  error = Ink.coral,
  onError = Ink.onAccent,
  outline = Ink.border,
  outlineVariant = Ink.border
)

private val mono = FontFamily.Monospace

private val MaccyTypography = Typography(
  headlineSmall = TextStyle(fontFamily = mono, fontWeight = FontWeight.Bold, fontSize = 22.sp, letterSpacing = (-0.5).sp),
  titleLarge = TextStyle(fontFamily = mono, fontWeight = FontWeight.Bold, fontSize = 18.sp, letterSpacing = 0.5.sp),
  titleMedium = TextStyle(fontFamily = mono, fontWeight = FontWeight.Bold, fontSize = 14.sp, letterSpacing = 0.5.sp),
  titleSmall = TextStyle(fontFamily = mono, fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 2.sp),
  bodyLarge = TextStyle(fontFamily = mono, fontSize = 14.sp, lineHeight = 20.sp),
  bodyMedium = TextStyle(fontFamily = mono, fontSize = 13.sp, lineHeight = 19.sp),
  bodySmall = TextStyle(fontFamily = mono, fontSize = 11.sp, lineHeight = 15.sp),
  labelLarge = TextStyle(fontFamily = mono, fontWeight = FontWeight.Bold, fontSize = 13.sp, letterSpacing = 0.5.sp),
  labelMedium = TextStyle(fontFamily = mono, fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 1.sp),
  labelSmall = TextStyle(fontFamily = mono, fontWeight = FontWeight.Medium, fontSize = 10.sp, letterSpacing = 1.5.sp)
)

@Composable
fun MaccyTheme(content: @Composable () -> Unit) {
  MaterialTheme(colorScheme = MaccyScheme, typography = MaccyTypography, content = content)
}
