package com.baseonline.zammadmobile.managers

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.baseonline.zammadmobile.App
import com.baseonline.zammadmobile.MainActivity
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.ZammadApi
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Push notifications. Zammad cannot talk to FCM, so the app registers its FCM
 * token with the relay under a per-device id, the user adds a webhook trigger
 * in Zammad pointing at that id's relay URL, and the relay turns webhook calls
 * into pushes. Same flow as iOS, with `platform: "android"` so the relay sends
 * through FCM instead of APNs. Notifications are a Premium feature.
 */
object PushManager {
    private const val TAG = "PushManager"
    const val CHANNEL_TICKETS = "tickets"
    const val CHANNEL_CHAT = "chat"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var isLoading by mutableStateOf(false); private set
    var isRegistered by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set

    /** False when the build has no google-services.json: push cannot work at all. */
    val isAvailable: Boolean get() = FirebaseApp.getApps(App.ctx).isNotEmpty()

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_TICKETS, context.getString(R.string.channel_tickets), NotificationManager.IMPORTANCE_HIGH))
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_CHAT, context.getString(R.string.channel_chat), NotificationManager.IMPORTANCE_HIGH))
    }

    fun hasPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(
            context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /**
     * Turns real-time notifications on: fetch the FCM token, register it with
     * the relay, refresh the chat registration so chat pushes reach this device.
     * The caller has already obtained the POST_NOTIFICATIONS permission.
     */
    fun enableNotifications(onDone: (Boolean) -> Unit = {}) {
        val context = App.ctx
        if (!SettingsManager.isPremium) {
            errorMessage = context.getString(R.string.notifications_premium_required_android)
            onDone(false); return
        }
        if (!isAvailable) {
            errorMessage = context.getString(R.string.push_not_configured)
            onDone(false); return
        }
        isLoading = true
        errorMessage = null
        scope.launch {
            val ok = try {
                val token = FirebaseMessaging.getInstance().token.await()
                SettingsManager.saveDeviceToken(token)
                updateRegistration(true)
            } catch (e: Exception) {
                Log.w(TAG, "FCM token fetch failed: ${e.message}")
                false
            }
            if (ok) {
                SettingsManager.saveRealtimeNotificationsEnabled(true)
                refreshChatRegistration()
            } else {
                errorMessage = context.getString(R.string.push_registration_failed)
            }
            isRegistered = ok
            isLoading = false
            onDone(ok)
        }
    }

    fun disableNotifications() {
        SettingsManager.saveRealtimeNotificationsEnabled(false)
        isRegistered = false
        scope.launch { updateRegistration(false) }
    }

    /** Premium ended: notifications are a Premium feature, so stop them. */
    fun onPremiumLost() {
        if (SettingsManager.realtimeNotificationsEnabled) disableNotifications()
    }

    /** FCM rotated the token: keep the relay's copy current. */
    fun onNewToken(token: String) {
        SettingsManager.saveDeviceToken(token)
        if (SettingsManager.realtimeNotificationsEnabled && SettingsManager.isPremium) {
            scope.launch { updateRegistration(true) }
        }
    }

    private suspend fun refreshChatRegistration() {
        try { ChatService.register(ZammadApi.fetchCurrentUser()) } catch (e: Exception) { }
    }

    /**
     * Registers or unregisters this device with the relay. Unlike the iOS
     * client this does not send the Zammad API token: the relay never uses it
     * for push, so there is no reason for it to hold a copy.
     */
    suspend fun updateRegistration(isSubscribing: Boolean): Boolean {
        if (isSubscribing && !SettingsManager.isPremium) return false
        val deviceToken = SettingsManager.loadDeviceToken() ?: return false
        val zammadURL = SettingsManager.loadServerURL()
        val userID = if (isSubscribing) SettingsManager.getOrCreateProxyUserID()
                     else SettingsManager.getProxyUserID() ?: return false
        val payload = buildJsonObject {
            put("deviceToken", deviceToken)
            put("proxyUserID", userID)
            put("zammadURL", zammadURL)
            put("platform", "android")
        }.toString()
        val endpoint = if (isSubscribing) "register" else "unregister"
        return withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder().url("${SettingsManager.PROXY_BASE}/api/$endpoint")
                    .post(payload.toRequestBody(ZammadApi.JSON_TYPE)).build()
                ZammadApi.client.newCall(request).execute().use { it.isSuccessful }
            } catch (e: Exception) {
                Log.w(TAG, "Relay $endpoint failed: ${e.message}"); false
            }
        }
    }

    /**
     * Shows a notification that opens the right screen when tapped. [extras]
     * carries the deep-link keys (`ticketID`, `chat_from_user_id`, `chat_group_id`).
     */
    fun notify(context: Context, channel: String, title: String, body: String, extras: Map<String, String>) {
        if (!hasPermission(context)) return
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            extras.forEach { (key, value) -> putExtra(key, value) }
        }
        val id = (extras.values.joinToString() + title).hashCode()
        val pending = PendingIntent.getActivity(context, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pending)
            .build()
        try { NotificationManagerCompat.from(context).notify(id, notification) } catch (e: SecurityException) { }
    }
}
