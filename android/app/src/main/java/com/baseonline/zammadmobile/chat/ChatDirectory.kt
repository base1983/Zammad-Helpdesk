package com.baseonline.zammadmobile.chat

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * In-memory cache of what the chat screens share: the engineer directory, the
 * caller's groups and the conversation list. Screens navigate by target id
 * (`dm-<chat user id>` / `group-<group id>`) and resolve it here.
 */
object ChatDirectory {
    var engineers by mutableStateOf<List<ChatUser>>(emptyList()); private set
    var groups by mutableStateOf<List<ChatGroup>>(emptyList()); private set
    var conversations by mutableStateOf<List<ChatConversation>>(emptyList()); private set

    /** Reloads directory, groups and conversations. Throws what ChatService throws. */
    suspend fun refresh() {
        engineers = ChatService.fetchEngineers()
        groups = ChatService.fetchGroups()
        conversations = ChatService.fetchConversations()
    }

    suspend fun refreshConversations() { conversations = ChatService.fetchConversations() }

    fun addGroup(group: ChatGroup) { groups = groups.filter { it.id != group.id } + group }

    private fun lookup(targetId: String): ChatTarget? {
        val id = targetId.substringAfter('-').toIntOrNull() ?: return null
        return if (targetId.startsWith("group-")) {
            (groups.firstOrNull { it.id == id } ?: conversations.firstNotNullOfOrNull { c -> c.group?.takeIf { it.id == id } })
                ?.let { ChatTarget.Group(it) }
        } else {
            // Prefer the directory entry: it carries the current device list.
            (engineers.firstOrNull { it.id == id } ?: conversations.firstNotNullOfOrNull { c -> c.partner?.takeIf { it.id == id } })
                ?.let { ChatTarget.Direct(it) }
        }
    }

    /** The target for an id, loading the directory when it is not cached yet (deep links). */
    suspend fun resolve(targetId: String): ChatTarget? {
        lookup(targetId)?.let { return it }
        return try { refresh(); lookup(targetId) } catch (e: Exception) { null }
    }

    /** The engineer with this Zammad user id, if they are registered for chat. */
    fun engineerForZammadUser(zammadUserId: Int): ChatUser? = engineers.firstOrNull { it.zammadUserId == zammadUserId }

    fun clear() { engineers = emptyList(); groups = emptyList(); conversations = emptyList() }
}
