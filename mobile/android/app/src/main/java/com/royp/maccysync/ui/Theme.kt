package com.royp.maccysync.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.royp.maccysync.R

// "Aurora" — modern fintech-style, deep blue + deep purple (not bright), dark.
object Hue {
  val bg0 = Color(0xFF161235)      // deep indigo (gradient top)
  val bg1 = Color(0xFF0B0917)      // near-black (gradient bottom)
  val surface = Color(0xFF191534)  // card
  val surfaceHi = Color(0xFF221C45)
  val border = Color(0xFF2C2658)
  val text = Color(0xFFEDEAFA)
  val muted = Color(0xFF9A93C2)
  val faint = Color(0xFF675F95)

  val blue = Color(0xFF4750C4)     // phone accent — deep blue-violet
  val blueDeep = Color(0xFF2A2C82)
  val purple = Color(0xFF7A3FC0)   // mac accent — deep purple
  val purpleDeep = Color(0xFF45236F)
  val coral = Color(0xFFD75A6A)    // destructive
  val onAccent = Color(0xFFF5F3FF)

  val bgGradient = Brush.verticalGradient(listOf(bg0, bg1))
  val heroGradient = Brush.linearGradient(listOf(Color(0xFF2E2C86), Color(0xFF5C2E8E)))
  fun phoneTile() = Brush.linearGradient(listOf(blue, blueDeep))
  fun macTile() = Brush.linearGradient(listOf(purple, purpleDeep))
}

val Poppins = FontFamily(
  Font(R.font.poppins_regular, FontWeight.Normal),
  Font(R.font.poppins_medium, FontWeight.Medium),
  Font(R.font.poppins_semibold, FontWeight.SemiBold),
  Font(R.font.poppins_bold, FontWeight.Bold)
)

private val MaccyScheme = darkColorScheme(
  primary = Hue.blue, onPrimary = Hue.onAccent,
  secondary = Hue.purple, onSecondary = Hue.onAccent,
  background = Hue.bg1, onBackground = Hue.text,
  surface = Hue.surface, onSurface = Hue.text,
  surfaceVariant = Hue.surfaceHi, onSurfaceVariant = Hue.muted,
  error = Hue.coral, onError = Hue.onAccent,
  outline = Hue.border, outlineVariant = Hue.border
)

private val MaccyTypography = Typography(
  displaySmall = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Bold, fontSize = 30.sp, letterSpacing = (-0.5).sp),
  headlineSmall = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.SemiBold, fontSize = 23.sp, letterSpacing = (-0.3).sp),
  titleLarge = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.SemiBold, fontSize = 18.sp),
  titleMedium = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
  titleSmall = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Medium, fontSize = 11.sp, letterSpacing = 1.2.sp),
  bodyLarge = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
  bodyMedium = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 19.sp),
  bodySmall = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Normal, fontSize = 12.sp, lineHeight = 16.sp),
  labelLarge = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.SemiBold, fontSize = 14.sp),
  labelMedium = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Medium, fontSize = 12.sp),
  labelSmall = TextStyle(fontFamily = Poppins, fontWeight = FontWeight.Medium, fontSize = 10.sp, letterSpacing = 0.8.sp)
)

@Composable
fun MaccyTheme(content: @Composable () -> Unit) {
  MaterialTheme(colorScheme = MaccyScheme, typography = MaccyTypography, content = content)
}
