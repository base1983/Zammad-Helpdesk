package com.baseonline.zammadmobile.chat

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.AppJson
import com.baseonline.zammadmobile.data.SettingsManager
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant
import java.time.temporal.ChronoUnit

@Serializable
data class BlockedChatUser(val id: Int, val name: String, val email: String? = null, val blockedAt: Long = 0)

/**
 * Client-side block list. Blocking is local to the device: the relay cannot
 * read messages, so filtering what reaches the screen happens here.
 */
object ChatBlockList {
    private const val KEY = "chat_blocked_users"
    private val serializer = ListSerializer(BlockedChatUser.serializer())

    var blocked by mutableStateOf<List<BlockedChatUser>>(emptyList()); private set

    fun init() {
        blocked = try {
            AppJson.decodeFromString(serializer, SettingsManager.prefs.getString(KEY, "[]")!!)
        } catch (e: Exception) { emptyList() }
    }

    val blockedIDs: Set<Int> get() = blocked.map { it.id }.toSet()
    fun isBlocked(id: Int) = blocked.any { it.id == id }

    fun block(user: ChatUser) = block(user.id, user.name, user.email)
    fun block(id: Int, name: String, email: String?) {
        if (isBlocked(id)) return
        blocked = blocked + BlockedChatUser(id, name, email, System.currentTimeMillis())
        persist()
    }
    fun unblock(id: Int) { blocked = blocked.filter { it.id != id }; persist() }
    fun removeAll() { blocked = emptyList(); persist() }

    private fun persist() {
        SettingsManager.prefs.edit().putString(KEY, AppJson.encodeToString(serializer, blocked)).apply()
    }
}

/**
 * Reporting is a pre-filled e-mail: only the reporter holds the plaintext, so
 * the report has to leave from their device.
 */
object ChatReporter {
    const val ADDRESS = "b.jonkers@world-ict.nl"

    private fun iso(instant: Instant) = instant.truncatedTo(ChronoUnit.SECONDS).toString()

    fun reportMessage(context: Context, message: ChatMessage, target: ChatTarget, reporterName: String?): Boolean {
        val where = when (target) {
            is ChatTarget.Direct -> "Direct conversation with ${target.user.name} (chat user ${target.user.id})"
            is ChatTarget.Group -> "Group \"${target.group.name}\" (group ${target.group.id})"
        }
        val lines = mutableListOf(
            "I want to report the following chat message.",
            "",
            "Server:        ${SettingsManager.loadServerURL()}",
            "Reported by:   ${reporterName ?: "unknown"}",
            "Sender:        ${message.fromUserName ?: message.fromUserId} (chat user ${message.fromUserId})",
            "Where:         $where",
            "Message id:    ${message.id}",
            "Sent at:       ${iso(message.createdAt)}",
        )
        if (message.attachmentId != null) {
            lines += "Attachment:    ${message.attachmentName ?: "yes"} (${message.attachmentMime ?: "unknown type"})"
        }
        lines += listOf("", "Message text:", message.body, "", "Why I am reporting it:", "")
        return send(context, lines.joinToString("\n"))
    }

    fun reportUser(context: Context, user: ChatUser, reporterName: String?): Boolean = send(
        context,
        listOf(
            "I want to report a colleague in the chat.",
            "",
            "Server:        ${SettingsManager.loadServerURL()}",
            "Reported by:   ${reporterName ?: "unknown"}",
            "Colleague:     ${user.name} (chat user ${user.id}, ${user.email ?: "no e-mail"})",
            "",
            "Why I am reporting them:",
            "",
        ).joinToString("\n")
    )

    /** False when no mail app can take it; the caller then shows the address. */
    private fun send(context: Context, body: String): Boolean {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:")).apply {
            putExtra(Intent.EXTRA_EMAIL, arrayOf(ADDRESS))
            putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.chat_report_subject))
            putExtra(Intent.EXTRA_TEXT, body)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try { context.startActivity(intent); true } catch (e: ActivityNotFoundException) { false }
    }
}
