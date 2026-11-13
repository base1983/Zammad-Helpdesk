package com.baseonline.zammadmobile.ui.theme

import androidx.compose.ui.graphics.Color
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.SettingsManager

/** Chat colour themes; raw values and colours match the iOS `ChatTheme` enum. */
enum class ChatTheme(
    val raw: String,
    val labelRes: Int,
    val isLight: Boolean,
    val background: Color,
    val myBubble: Color,
    val myText: Color,
    val partnerBubble: Color,
) {
    CLASSIC_LIGHT("classicLight", R.string.chat_theme_classic, true, Color(0.95f, 0.95f, 0.97f), Color(0.00f, 0.48f, 1.00f), Color.White, Color(0.90f, 0.90f, 0.92f)),
    SKY("sky", R.string.chat_theme_sky, true, Color(0.87f, 0.93f, 0.98f), Color(0.05f, 0.40f, 0.75f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    MINT("mint", R.string.chat_theme_mint, true, Color(0.88f, 0.96f, 0.90f), Color(0.13f, 0.60f, 0.33f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    ROSE("rose", R.string.chat_theme_rose, true, Color(0.99f, 0.91f, 0.93f), Color(0.85f, 0.25f, 0.45f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    LAVENDER("lavender", R.string.chat_theme_lavender, true, Color(0.93f, 0.91f, 0.98f), Color(0.48f, 0.35f, 0.80f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    SAND("sand", R.string.chat_theme_sand, true, Color(0.96f, 0.93f, 0.86f), Color(0.65f, 0.45f, 0.20f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    PEACH("peach", R.string.chat_theme_peach, true, Color(0.99f, 0.92f, 0.87f), Color(0.90f, 0.45f, 0.20f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    SEAFOAM("seafoam", R.string.chat_theme_seafoam, true, Color(0.88f, 0.96f, 0.95f), Color(0.10f, 0.55f, 0.55f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    LEMON("lemon", R.string.chat_theme_lemon, true, Color(0.99f, 0.97f, 0.85f), Color(0.72f, 0.55f, 0.05f), Color.White, Color(1.00f, 1.00f, 1.00f)),
    PAPER("paper", R.string.chat_theme_paper, true, Color(0.98f, 0.97f, 0.94f), Color(0.20f, 0.20f, 0.22f), Color.White, Color(0.90f, 0.89f, 0.86f)),
    CLASSIC_DARK("classicDark", R.string.chat_theme_classic, false, Color(0.07f, 0.07f, 0.08f), Color(0.04f, 0.42f, 0.90f), Color.White, Color(0.20f, 0.20f, 0.22f)),
    MIDNIGHT("midnight", R.string.chat_theme_midnight, false, Color(0.06f, 0.08f, 0.15f), Color(0.30f, 0.40f, 0.85f), Color.White, Color(0.14f, 0.17f, 0.26f)),
    GRAPHITE("graphite", R.string.chat_theme_graphite, false, Color(0.10f, 0.10f, 0.11f), Color(0.45f, 0.45f, 0.50f), Color.White, Color(0.19f, 0.19f, 0.21f)),
    FOREST("forest", R.string.chat_theme_forest, false, Color(0.05f, 0.11f, 0.08f), Color(0.15f, 0.55f, 0.32f), Color.White, Color(0.12f, 0.19f, 0.15f)),
    PLUM("plum", R.string.chat_theme_plum, false, Color(0.10f, 0.06f, 0.13f), Color(0.55f, 0.32f, 0.75f), Color.White, Color(0.19f, 0.13f, 0.24f)),
    OCEAN("ocean", R.string.chat_theme_ocean, false, Color(0.04f, 0.10f, 0.14f), Color(0.10f, 0.55f, 0.65f), Color.White, Color(0.10f, 0.18f, 0.23f)),
    EMBER("ember", R.string.chat_theme_ember, false, Color(0.11f, 0.07f, 0.05f), Color(0.85f, 0.42f, 0.12f), Color.White, Color(0.21f, 0.15f, 0.12f)),
    CRIMSON("crimson", R.string.chat_theme_crimson, false, Color(0.11f, 0.05f, 0.06f), Color(0.75f, 0.20f, 0.25f), Color.White, Color(0.20f, 0.12f, 0.13f)),
    GOLD("gold", R.string.chat_theme_gold, false, Color(0.10f, 0.08f, 0.04f), Color(0.85f, 0.65f, 0.15f), Color.Black, Color(0.20f, 0.17f, 0.10f)),
    NEON("neon", R.string.chat_theme_neon, false, Color(0.02f, 0.02f, 0.02f), Color(0.15f, 0.90f, 0.45f), Color.Black, Color(0.15f, 0.15f, 0.15f));

    val partnerText: Color get() = if (isLight) Color.Black else Color.White
    val metaText: Color get() = if (isLight) Color.Black.copy(alpha = 0.45f) else Color.White.copy(alpha = 0.5f)

    companion object {
        val lightThemes get() = entries.filter { it.isLight }
        val darkThemes get() = entries.filter { !it.isLight }
        fun from(raw: String?, dark: Boolean): ChatTheme =
            entries.firstOrNull { it.raw == raw && it.isLight != dark } ?: if (dark) CLASSIC_DARK else CLASSIC_LIGHT

        /** The theme the user chose for the current appearance. */
        fun current(dark: Boolean): ChatTheme =
            from(if (dark) SettingsManager.chatThemeDark else SettingsManager.chatThemeLight, dark)
    }
}
