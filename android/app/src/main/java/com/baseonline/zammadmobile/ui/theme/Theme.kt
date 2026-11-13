package com.baseonline.zammadmobile.ui.theme

import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.LocalActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.baseonline.zammadmobile.data.ColorSchemeOption
import com.baseonline.zammadmobile.data.SettingsManager

/** Whether the app is currently rendering dark (the user's choice, else the system's). */
val LocalIsDark = staticCompositionLocalOf { false }

// The iOS accent colour is black in light mode and white in dark mode: a
// monochrome look where the wallpaper provides the colour.
private val LightColors = lightColorScheme(
    primary = Color(0xFF111111), onPrimary = Color.White,
    primaryContainer = Color(0xFFE6E6EA), onPrimaryContainer = Color(0xFF111111),
    secondary = Color(0xFF3A3A3C), onSecondary = Color.White,
    secondaryContainer = Color(0xFFE6E6EA), onSecondaryContainer = Color(0xFF111111),
    tertiary = Color(0xFF007AFF),
    background = Color(0xFFF2F2F7), onBackground = Color(0xFF111111),
    surface = Color(0xFFFFFFFF), onSurface = Color(0xFF111111),
    surfaceVariant = Color(0xFFE9E9EE), onSurfaceVariant = Color(0xFF5A5A60),
    surfaceContainer = Color(0xFFF4F4F8), surfaceContainerHigh = Color(0xFFEDEDF2),
    surfaceContainerHighest = Color(0xFFE6E6EB), surfaceContainerLow = Color(0xFFF8F8FB),
    outline = Color(0xFFB0B0B8), outlineVariant = Color(0xFFD6D6DC),
    error = Color(0xFFD32F2F),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFFFFFFF), onPrimary = Color(0xFF111111),
    primaryContainer = Color(0xFF3A3A3F), onPrimaryContainer = Color.White,
    secondary = Color(0xFFD0D0D5), onSecondary = Color(0xFF111111),
    secondaryContainer = Color(0xFF3A3A3F), onSecondaryContainer = Color.White,
    tertiary = Color(0xFF4DA3FF),
    background = Color(0xFF0E0E10), onBackground = Color(0xFFF2F2F2),
    surface = Color(0xFF1A1A1D), onSurface = Color(0xFFF2F2F2),
    surfaceVariant = Color(0xFF2A2A2E), onSurfaceVariant = Color(0xFFB4B4BA),
    surfaceContainer = Color(0xFF202024), surfaceContainerHigh = Color(0xFF29292E),
    surfaceContainerHighest = Color(0xFF323237), surfaceContainerLow = Color(0xFF19191C),
    outline = Color(0xFF6A6A72), outlineVariant = Color(0xFF3C3C42),
    error = Color(0xFFFF6B6B),
)

@Composable
fun resolveIsDark(forceDark: Boolean = false): Boolean = forceDark || when (SettingsManager.theme) {
    ColorSchemeOption.LIGHT -> false
    ColorSchemeOption.DARK -> true
    ColorSchemeOption.SYSTEM -> isSystemInDarkTheme()
}

@Composable
fun HelpdeskTheme(forceDark: Boolean = false, content: @Composable () -> Unit) {
    val dark = resolveIsDark(forceDark)
    // Status/navigation bar icons follow the app's own theme (which may differ
    // from the system's), so they stay visible over the wallpaper.
    val activity = LocalActivity.current as? ComponentActivity
    DisposableEffect(dark, activity) {
        val style = if (dark) SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
                    else SystemBarStyle.light(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT)
        activity?.enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
        onDispose { }
    }
    CompositionLocalProvider(LocalIsDark provides dark) {
        MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
    }
}
