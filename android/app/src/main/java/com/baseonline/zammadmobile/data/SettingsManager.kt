package com.baseonline.zammadmobile.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import com.baseonline.zammadmobile.R
import java.util.UUID

enum class WallpaperMode { LIGHT, DARK }

enum class ColorSchemeOption(val raw: String, val labelRes: Int) {
    SYSTEM("system", R.string.theme_system),
    LIGHT("light", R.string.theme_light),
    DARK("dark", R.string.theme_dark);

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: SYSTEM
    }
}

/** Backgrounds, same raw values as the iOS `BackgroundOption` enum. */
enum class BackgroundOption(
    val raw: String,
    val labelRes: Int,
    val imageRes: Int? = null,
    val thumbRes: Int? = null,
    val color: Color? = null,
    val customMode: WallpaperMode? = null,
) {
    FLOWERS("flowers", R.string.wallpaper_flowers, R.drawable.wallpaper_flowers, R.drawable.wallpaper_flowers_thumb),
    DESERT("desert", R.string.wallpaper_desert, R.drawable.wallpaper_desert, R.drawable.wallpaper_desert_thumb),
    MEADOW("meadow", R.string.wallpaper_meadow, R.drawable.wallpaper_meadow, R.drawable.wallpaper_meadow_thumb),
    ABSTRACT("abstract", R.string.wallpaper_abstract, R.drawable.wallpaper_abstract, R.drawable.wallpaper_abstract_thumb),
    LAGOON("lagoon", R.string.wallpaper_lagoon, R.drawable.wallpaper_lagoon, R.drawable.wallpaper_lagoon_thumb),
    PEBBLES("pebbles", R.string.wallpaper_pebbles, R.drawable.wallpaper_pebbles, R.drawable.wallpaper_pebbles_thumb),
    WAVES("waves", R.string.wallpaper_waves, R.drawable.wallpaper_waves, R.drawable.wallpaper_waves_thumb),
    NIGHT_LAKE("nightLake", R.string.wallpaper_night_lake, R.drawable.wallpaper_night_lake, R.drawable.wallpaper_night_lake_thumb),
    CONCRETE("concrete", R.string.wallpaper_concrete, R.drawable.wallpaper_concrete, R.drawable.wallpaper_concrete_thumb),
    CITY("city", R.string.wallpaper_city, R.drawable.wallpaper_city, R.drawable.wallpaper_city_thumb),
    GOLD("gold", R.string.wallpaper_gold, R.drawable.wallpaper_gold, R.drawable.wallpaper_gold_thumb),
    EMBER("ember", R.string.wallpaper_ember, R.drawable.wallpaper_ember, R.drawable.wallpaper_ember_thumb),
    ICE("ice", R.string.wallpaper_ice, R.drawable.wallpaper_ice, R.drawable.wallpaper_ice_thumb),
    CLASSIC("classic", R.string.wallpaper_classic, R.drawable.app_background, R.drawable.app_background_thumb),
    PASTEL_BLUE("pastelBlue", R.string.color_pastel_blue, color = Color(0.85f, 0.90f, 0.96f)),
    PASTEL_PINK("pastelPink", R.string.color_pastel_pink, color = Color(0.97f, 0.87f, 0.90f)),
    PASTEL_GREEN("pastelGreen", R.string.color_pastel_green, color = Color(0.87f, 0.94f, 0.87f)),
    PASTEL_SAND("pastelSand", R.string.color_pastel_sand, color = Color(0.96f, 0.93f, 0.86f)),
    MIDNIGHT("midnight", R.string.color_midnight, color = Color(0.08f, 0.10f, 0.16f)),
    CHARCOAL("charcoal", R.string.color_charcoal, color = Color(0.11f, 0.11f, 0.12f)),
    FOREST("forest", R.string.color_forest, color = Color(0.06f, 0.13f, 0.11f)),
    PLUM("plum", R.string.color_plum, color = Color(0.13f, 0.09f, 0.16f)),
    CUSTOM_LIGHT("customLight", R.string.wallpaper_custom, customMode = WallpaperMode.LIGHT),
    CUSTOM_DARK("customDark", R.string.wallpaper_custom, customMode = WallpaperMode.DARK);

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw }
        fun custom(mode: WallpaperMode) = if (mode == WallpaperMode.DARK) CUSTOM_DARK else CUSTOM_LIGHT
        fun default(mode: WallpaperMode) = if (mode == WallpaperMode.DARK) PEBBLES else FLOWERS
        val lightWallpapers = listOf(FLOWERS, DESERT, MEADOW, ABSTRACT, LAGOON, CLASSIC)
        val darkWallpapers = listOf(PEBBLES, WAVES, NIGHT_LAKE, CONCRETE, CITY, GOLD, EMBER, ICE, CLASSIC)
        val lightColors = listOf(PASTEL_BLUE, PASTEL_PINK, PASTEL_GREEN, PASTEL_SAND)
        val darkColors = listOf(MIDNIGHT, CHARCOAL, FOREST, PLUM)
    }
}

/**
 * App settings, the counterpart of the iOS `SettingsManager`. Plain preferences
 * use the same snake_case keys as iOS; the API token goes through [SecureStore].
 * Values the UI reacts to are exposed as Compose state.
 */
object SettingsManager {
    private const val TOKEN_KEY = "zammad_api_token"
    const val PROXY_BASE = "https://zammadproxy.world-ict.nl"

    lateinit var prefs: SharedPreferences
        private set

    var isSetupComplete by mutableStateOf(false); private set
    var theme by mutableStateOf(ColorSchemeOption.SYSTEM); private set
    var lightBackground by mutableStateOf(BackgroundOption.FLOWERS); private set
    var darkBackground by mutableStateOf(BackgroundOption.PEBBLES); private set
    var isPremium by mutableStateOf(false); private set
    var isLockEnabled by mutableStateOf(false); private set
    var realtimeNotificationsEnabled by mutableStateOf(false); private set
    var chatThemeLight by mutableStateOf("classicLight"); private set
    var chatThemeDark by mutableStateOf("classicDark"); private set
    var chatRetentionDays by mutableStateOf(90); private set

    fun init(context: Context) {
        prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)
        isSetupComplete = prefs.getBoolean("is_setup_complete", false)
        theme = ColorSchemeOption.from(prefs.getString("color_scheme_option", null))
        lightBackground = BackgroundOption.from(prefs.getString("background_light_option", null)) ?: BackgroundOption.FLOWERS
        darkBackground = BackgroundOption.from(prefs.getString("background_dark_option", null)) ?: BackgroundOption.PEBBLES
        isPremium = prefs.getBoolean("are_ads_removed", false)
        isLockEnabled = prefs.getBoolean("is_biometric_lock_enabled", false)
        realtimeNotificationsEnabled = prefs.getBoolean("realtime_notifications_enabled", false)
        chatThemeLight = prefs.getString("chat_theme_light", null) ?: "classicLight"
        chatThemeDark = prefs.getString("chat_theme_dark", null) ?: "classicDark"
        chatRetentionDays = prefs.getInt("chat_history_retention_days", 90)
    }

    // --- Server & token ---
    fun saveToken(token: String) {
        if (token.isEmpty()) SecureStore.delete(TOKEN_KEY) else SecureStore.save(token, TOKEN_KEY)
    }
    fun loadToken(): String? = SecureStore.load(TOKEN_KEY)?.takeIf { it.isNotEmpty() }

    fun saveServerURL(url: String) = prefs.edit().putString("zammad_server_url", url).apply()
    fun loadServerURL(): String = prefs.getString("zammad_server_url", "") ?: ""

    fun saveSetupComplete(value: Boolean) {
        prefs.edit().putBoolean("is_setup_complete", value).apply(); isSetupComplete = value
    }

    // --- Appearance & security ---
    fun saveTheme(value: ColorSchemeOption) {
        prefs.edit().putString("color_scheme_option", value.raw).apply(); theme = value
    }
    fun saveLightBackground(value: BackgroundOption) {
        prefs.edit().putString("background_light_option", value.raw).apply(); lightBackground = value
    }
    fun saveDarkBackground(value: BackgroundOption) {
        prefs.edit().putString("background_dark_option", value.raw).apply(); darkBackground = value
    }
    fun saveLockEnabled(value: Boolean) {
        prefs.edit().putBoolean("is_biometric_lock_enabled", value).apply(); isLockEnabled = value
    }
    fun saveChatThemeLight(value: String) {
        prefs.edit().putString("chat_theme_light", value).apply(); chatThemeLight = value
    }
    fun saveChatThemeDark(value: String) {
        prefs.edit().putString("chat_theme_dark", value).apply(); chatThemeDark = value
    }
    fun saveChatRetentionDays(value: Int) {
        prefs.edit().putInt("chat_history_retention_days", value).apply(); chatRetentionDays = value
    }

    // --- Premium (derived from Play Billing by StoreManager, from nothing else) ---
    fun savePremium(value: Boolean) {
        prefs.edit().putBoolean("are_ads_removed", value).apply(); isPremium = value
    }

    // --- Notifications ---
    fun saveRealtimeNotificationsEnabled(value: Boolean) {
        prefs.edit().putBoolean("realtime_notifications_enabled", value).apply(); realtimeNotificationsEnabled = value
    }
    fun saveProxyUserID(id: String) = prefs.edit().putString("proxy_user_id_key", id).apply()
    fun getProxyUserID(): String? = prefs.getString("proxy_user_id_key", null)?.takeIf { it.isNotEmpty() }
    fun getOrCreateProxyUserID(): String =
        getProxyUserID() ?: UUID.randomUUID().toString().uppercase().also { saveProxyUserID(it) }
    fun saveDeviceToken(token: String) = prefs.edit().putString("fcm_device_token", token).apply()
    fun loadDeviceToken(): String? = prefs.getString("fcm_device_token", null)?.takeIf { it.isNotEmpty() }

    /** The per-device relay URL the user pastes into a Zammad webhook. */
    fun getWebhookURL(): String? = getProxyUserID()?.let { "$PROXY_BASE/api/webhook/$it" }

    // --- Background refresh ---
    fun saveLastFetchMillis(value: Long) = prefs.edit().putLong("background_last_fetch_date", value).apply()
    fun loadLastFetchMillis(): Long = prefs.getLong("background_last_fetch_date", 0L)

    /**
     * Forgets the server and everything tied to the account on it. Appearance,
     * purchases and the FCM token stay: they belong to the device.
     */
    fun clearAccountData() {
        SecureStore.delete(TOKEN_KEY)
        prefs.edit()
            .remove("zammad_server_url")
            .remove("realtime_notifications_enabled")
            .remove("proxy_user_id_key")
            .remove("background_last_fetch_date")
            .putBoolean("is_biometric_lock_enabled", false)
            .apply()
        realtimeNotificationsEnabled = false
        isLockEnabled = false
    }
}
