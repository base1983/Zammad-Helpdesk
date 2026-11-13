package com.baseonline.zammadmobile.chat

import android.content.Context
import com.baseonline.zammadmobile.data.AppJson
import com.baseonline.zammadmobile.data.SettingsManager
import kotlinx.serialization.builtins.ListSerializer
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * On-device message history, one JSON file per conversation, pruned to the
 * configured retention window. Messages are stored decrypted in the app's
 * private files dir (excluded from backup).
 */
object ChatHistoryStore {
    private lateinit var directory: File
    private val serializer = ListSerializer(ChatMessage.serializer())

    fun init(context: Context) {
        directory = File(context.filesDir, "ChatHistory").apply { mkdirs() }
    }

    private fun cutoff(): Instant? {
        val days = SettingsManager.chatRetentionDays
        return if (days > 0) Instant.now().minus(days.toLong(), ChronoUnit.DAYS) else null
    }

    private fun file(key: String) = File(directory, "$key.json")

    private fun prune(messages: List<ChatMessage>): List<ChatMessage> {
        val cutoff = cutoff() ?: return messages
        return messages.filter { it.createdAt >= cutoff }
    }

    private fun write(key: String, messages: List<ChatMessage>) {
        try { file(key).writeText(AppJson.encodeToString(serializer, messages)) } catch (e: Exception) { }
    }

    @Synchronized
    fun load(key: String): List<ChatMessage> = try {
        prune(AppJson.decodeFromString(serializer, file(key).readText()))
    } catch (e: Exception) { emptyList() }

    /** Merges by id, prunes, persists, and returns the merged list. */
    @Synchronized
    fun merge(new: List<ChatMessage>, key: String): List<ChatMessage> {
        val byId = load(key).associateBy { it.id }.toMutableMap()
        for (message in new) byId[message.id] = message
        val merged = prune(byId.values.sortedBy { it.id })
        write(key, merged)
        return merged
    }

    @Synchronized
    fun remove(id: Int, key: String) = write(key, load(key).filter { it.id != id })

    @Synchronized
    fun clear(key: String) { file(key).delete() }

    @Synchronized
    fun clearAll() { directory.listFiles()?.forEach { it.delete() } }

    /** Re-prunes every conversation file; called at app launch. */
    fun pruneAll() {
        directory.listFiles()?.filter { it.extension == "json" }?.forEach { merge(emptyList(), it.nameWithoutExtension) }
    }
}
