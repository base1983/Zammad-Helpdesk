package com.baseonline.zammadmobile.push

import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.managers.PushManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Receives the relay's FCM *data* messages and turns them into notifications.
 * Data-only messages are used (rather than FCM "notification" messages) so the
 * app always builds the notification itself: it can localise the chat text on
 * the device and attach the deep-link keys in every app state.
 *
 * Payload keys (see proxy/fcm.js): `title`, `body` or `body_loc_key`, and the
 * same routing keys iOS uses: `ticketID`, `chat_from_user_id`, `chat_group_id`.
 */
class HelpdeskMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = PushManager.onNewToken(token)

    override fun onMessageReceived(message: RemoteMessage) {
        // Notifications are a Premium feature; a late push after Premium ended is dropped.
        if (!SettingsManager.isPremium || !SettingsManager.realtimeNotificationsEnabled) return
        val data = message.data
        val isChat = data.containsKey("chat_from_user_id") || data.containsKey("chat_group_id")
        val title = data["title"] ?: getString(R.string.app_name)
        val body = when (data["body_loc_key"]) {
            "chat_new_message" -> getString(R.string.chat_new_message)
            else -> data["body"] ?: ""
        }
        val extras = data.filterKeys { it in ROUTING_KEYS }
        PushManager.notify(this, if (isChat) PushManager.CHANNEL_CHAT else PushManager.CHANNEL_TICKETS, title, body, extras)
        if (isChat) CoroutineScope(Dispatchers.Main).launch { ChatService.refreshUnreadCount() }
    }

    companion object {
        val ROUTING_KEYS = setOf("ticketID", "ticket_id", "chat_from_user_id", "chat_group_id")
    }
}
