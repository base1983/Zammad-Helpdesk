package com.baseonline.zammadmobile.managers

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.baseonline.zammadmobile.BuildConfig
import com.baseonline.zammadmobile.data.AppJson
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.User
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/** Per-ticket "last read" timestamps; a ticket updated after that is unread. */
object ReadStatusManager {
    private const val KEY = "read_ticket_timestamps"
    private val serializer = MapSerializer(Int.serializer(), Long.serializer())
    private var timestamps: Map<Int, Long> = emptyMap()

    /** Bumped on every change so list rows recompose. */
    var version by mutableIntStateOf(0); private set

    fun init() {
        timestamps = try {
            AppJson.decodeFromString(serializer, SettingsManager.prefs.getString(KEY, "{}")!!)
        } catch (e: Exception) { emptyMap() }
    }

    private fun persist() {
        SettingsManager.prefs.edit().putString(KEY, AppJson.encodeToString(serializer, timestamps)).apply()
        version++
    }

    fun reset() { timestamps = emptyMap(); persist() }

    fun isUnread(ticket: Ticket, currentUser: User?): Boolean {
        val lastRead = timestamps[ticket.id] ?: return ticket.created_by_id != currentUser?.id
        return ticket.updated_at.toEpochMilli() > lastRead
    }

    fun markAsRead(ticket: Ticket) { timestamps = timestamps + (ticket.id to System.currentTimeMillis()); persist() }
    fun markAsUnread(ticket: Ticket) { timestamps = timestamps + (ticket.id to 0L); persist() }
}

/** Unsent reply/note text per ticket, kept across app restarts. */
object DraftManager {
    @Serializable
    data class ReplyDraft(val ticketId: Int, val body: String, val isInternalNote: Boolean, val updatedAt: Long)

    private val serializer = MapSerializer(Int.serializer(), ReplyDraft.serializer())
    private lateinit var file: File

    var drafts by mutableStateOf<Map<Int, ReplyDraft>>(emptyMap()); private set

    fun init(context: Context) {
        file = File(context.filesDir, "zammad_reply_drafts.json")
        drafts = try { AppJson.decodeFromString(serializer, file.readText()) } catch (e: Exception) { emptyMap() }
    }

    fun draft(ticketId: Int): ReplyDraft? = drafts[ticketId]
    fun hasDraft(ticketId: Int): Boolean = drafts.containsKey(ticketId)

    fun save(ticketId: Int, body: String, isInternalNote: Boolean) {
        if (body.isBlank()) { delete(ticketId); return }
        drafts = drafts + (ticketId to ReplyDraft(ticketId, body, isInternalNote, System.currentTimeMillis()))
        persist()
    }

    fun delete(ticketId: Int) {
        if (!drafts.containsKey(ticketId)) return
        drafts = drafts - ticketId
        persist()
    }

    fun deleteAll() { drafts = emptyMap(); file.delete() }

    private fun persist() {
        try { file.writeText(AppJson.encodeToString(serializer, drafts)) } catch (e: Exception) { }
    }
}

/**
 * Where a notification or link wants the app to go. Structured payload keys
 * are read before the regex fallback: the fallback would misread a chat
 * payload as a ticket id.
 */
object DeepLinkManager {
    var pendingTicketID by mutableStateOf<Int?>(null)
    var pendingChatPartnerID by mutableStateOf<Int?>(null)
    var pendingChatGroupID by mutableStateOf<Int?>(null)

    fun handleUrl(url: String) = findIdInString(url)

    fun handlePayload(data: Map<String, String?>) {
        data["ticketID"]?.toIntOrNull()?.let { pendingTicketID = it; return }
        data["chat_group_id"]?.toIntOrNull()?.let { pendingChatGroupID = it; return }
        data["chat_from_user_id"]?.toIntOrNull()?.let { pendingChatPartnerID = it; return }
        data["ticket_id"]?.toIntOrNull()?.let { pendingTicketID = it; return }
        findIdInString(data.entries.joinToString(" ") { "${it.key}: ${it.value}" })
    }

    private fun findIdInString(text: String) {
        val patterns = listOf("(?i)Ticket\\s*#\\s*(\\d+)", "(?i)(?:ticket_id|id)[\"\\s:]+(\\d+)", "(?i)zoom[\\\\/]+(\\d+)")
        for (pattern in patterns) {
            Regex(pattern).find(text)?.groupValues?.get(1)?.toIntOrNull()?.let { pendingTicketID = it; return }
        }
    }
}

/**
 * Paces the in-app Premium suggestion: at most once per 15 opened tickets and
 * never more often than once a week.
 */
object PremiumPromptManager {
    private const val TICKETS_BETWEEN = 15
    private const val MIN_INTERVAL_MS = 7L * 24 * 60 * 60 * 1000

    fun consumePromptIfDue(): Boolean {
        val prefs = SettingsManager.prefs
        val count = prefs.getInt("premium_prompt_tickets_left", 0) + 1
        prefs.edit().putInt("premium_prompt_tickets_left", count).apply()
        if (count < TICKETS_BETWEEN) return false
        val last = prefs.getLong("premium_prompt_last_shown", 0L)
        if (last != 0L && System.currentTimeMillis() - last < MIN_INTERVAL_MS) return false
        prefs.edit().putInt("premium_prompt_tickets_left", 0)
            .putLong("premium_prompt_last_shown", System.currentTimeMillis()).apply()
        return true
    }
}

/** Earns the Play in-app review prompt: 10 opened tickets, once per app version. */
object ReviewRequestManager {
    private const val TICKETS_REQUIRED = 10

    fun recordTicketOpened() {
        val prefs = SettingsManager.prefs
        prefs.edit().putInt("review_tickets_opened_count", prefs.getInt("review_tickets_opened_count", 0) + 1).apply()
    }

    fun consumeRequestIfEarned(): Boolean {
        val prefs = SettingsManager.prefs
        if (prefs.getInt("review_tickets_opened_count", 0) < TICKETS_REQUIRED) return false
        if (!BuildConfig.DEBUG && prefs.getString("review_last_prompted_version", null) == BuildConfig.VERSION_NAME) return false
        prefs.edit().putString("review_last_prompted_version", BuildConfig.VERSION_NAME)
            .putInt("review_tickets_opened_count", 0).apply()
        return true
    }

    /** Asks Play for the review sheet; Play decides whether it actually shows. */
    fun launch(activity: android.app.Activity) {
        val manager = com.google.android.play.core.review.ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnSuccessListener { info -> manager.launchReviewFlow(activity, info) }
    }
}
