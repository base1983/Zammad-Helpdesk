package com.baseonline.zammadmobile.chat

import android.util.Base64
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.baseonline.zammadmobile.App
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.ApiException
import com.baseonline.zammadmobile.data.AppJson
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.User
import com.baseonline.zammadmobile.data.ZammadApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.serializer
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * REST client for the chat endpoints on the relay. The contract is
 * PROXY_CHAT_API.md in the repository root (protocol v4, per-device keys);
 * this file must stay in step with `ChatService.swift` and `proxy/chat.js`.
 */
object ChatService {
    private const val TAG = "ChatService"
    private const val BASE = "${SettingsManager.PROXY_BASE}/api/chat"

    /** Our own chat identity on the relay, set after [register]. */
    var myChatUserId by mutableStateOf<Int?>(null); private set
    var myChatDeviceId: Int? = null; private set
    var myDevices: List<ChatDevice> = emptyList(); private set

    /** Total unread messages across all conversations, for the toolbar badge. */
    var totalUnread by mutableStateOf(0); private set

    /** Unwrapped group keys, cached per group id for this session. */
    private val groupKeys = HashMap<Int, ByteArray>()

    private fun string(res: Int) = App.ctx.getString(res)

    // --- Requests ---

    private fun makeRequest(path: String, method: String = "GET", query: List<Pair<String, String>> = emptyList(),
                            body: JsonObject? = null): Request {
        val token = SettingsManager.loadToken() ?: throw ApiException.TokenNotSet()
        val url = "$BASE/$path".toHttpUrl().newBuilder().apply {
            query.forEach { (name, value) -> addQueryParameter(name, value) }
        }.build()
        val requestBody = body?.toString()?.toRequestBody(ZammadApi.JSON_TYPE)
            ?: if (method == "GET") null else "{}".toRequestBody(ZammadApi.JSON_TYPE)
        return Request.Builder().url(url)
            .header("Content-Type", "application/json")
            .header("Authorization", "Token token=$token")
            .header("X-Zammad-Url", SettingsManager.loadServerURL())
            // Which of our devices is calling, so the relay returns its key envelopes.
            .header("X-Device-Id", ChatCrypto.deviceId)
            .method(method, requestBody)
            .build()
    }

    private suspend inline fun <reified T> perform(request: Request): T {
        val text = withContext(Dispatchers.IO) {
            try {
                ZammadApi.client.newCall(request).execute().use { response ->
                    when {
                        // 404: the relay does not have the chat endpoints.
                        response.code == 404 -> throw ChatException.ServerUnavailable()
                        response.code == 401 -> throw ApiException.AuthenticationFailed()
                        response.code !in 200..299 -> throw ChatException.ServerError(response.code)
                    }
                    response.body.string()
                }
            } catch (e: IOException) {
                throw ChatException.ServerUnavailable()
            }
        }
        return try {
            AppJson.decodeFromString(serializer<T>(), text)
        } catch (e: Exception) {
            // A required field is missing: in practice a relay on the pre-v4 protocol.
            Log.w(TAG, "Decode failed for ${T::class.simpleName}: ${e.message}")
            throw ChatException.ProtocolMismatch()
        }
    }

    /** Forgets the session's chat identity and cached keys (disconnect). */
    fun reset() {
        myChatUserId = null
        myChatDeviceId = null
        myDevices = emptyList()
        synchronized(groupKeys) { groupKeys.clear() }
        totalUnread = 0
    }

    // --- Registration & directory ---

    @Serializable
    private data class RegisterResponse(
        @SerialName("chat_user_id") val chatUserId: Int,
        @SerialName("chat_device_id") val chatDeviceId: Int,
        val devices: List<ChatDevice>,
    )

    /**
     * Registers (or refreshes) this device in the relay's chat directory. Each
     * device publishes its own public key and its own push registration.
     */
    suspend fun register(currentUser: User): Int {
        val body = buildJsonObject {
            put("zammad_user_id", currentUser.id)
            put("name", currentUser.fullname)
            put("email", currentUser.email)
            put("proxy_user_id", SettingsManager.getProxyUserID() ?: "")
            put("public_key", ChatCrypto.publicKeyBase64)
            put("device_id", ChatCrypto.deviceId)
        }
        val response: RegisterResponse = perform(makeRequest("register", "POST", body = body))
        myChatUserId = response.chatUserId
        myChatDeviceId = response.chatDeviceId
        myDevices = response.devices
        return response.chatUserId
    }

    /** All engineers registered for chat on the same instance (excluding ourselves and blocked). */
    suspend fun fetchEngineers(): List<ChatUser> {
        val users: List<ChatUser> = perform(makeRequest("users"))
        val blocked = ChatBlockList.blockedIDs
        return users.filter { it.id != myChatUserId && it.id !in blocked }
    }

    // --- Conversations ---

    suspend fun fetchConversations(): List<ChatConversation> {
        val all: List<ChatConversation> = perform(makeRequest("conversations"))
        val blocked = ChatBlockList.blockedIDs
        // A blocked colleague's direct conversation leaves the list and the unread
        // total; groups stay, their messages are filtered on fetch.
        val conversations = all.filter { it.partner == null || it.partner.id !in blocked }.map { conversation ->
            val last = conversation.lastMessage ?: return@map conversation
            val key = conversation.group?.let { groupKey(it) } ?: messageKey(last)
            conversation.copy(lastMessage = decrypted(last, key))
        }
        totalUnread = conversations.sumOf { it.unreadCount }
        return conversations
    }

    private fun decrypted(message: ChatMessage, key: ByteArray?): ChatMessage {
        if (message.deleted == true) {
            // Tombstone: the sender deleted this message for everyone.
            return message.copy(body = string(R.string.chat_message_deleted), isEncrypted = true)
        }
        val encrypted = ChatCrypto.isEncrypted(message.body)
        val plain = ChatCrypto.decrypt(message.body, key)
        return message.copy(
            body = plain ?: string(R.string.chat_encrypted_placeholder),
            isEncrypted = encrypted,
            isUndecryptable = plain == null,
        )
    }

    // --- Groups ---

    private fun envelope(device: ChatDevice, key: ByteArray, withWrapper: Boolean) = buildJsonObject {
        put("device_id", device.id)
        put("wrapped_key", ChatCrypto.wrapKey(key, device.publicKey))
        if (withWrapper) put("wrapper_public_key", ChatCrypto.publicKeyBase64)
    }

    /**
     * Creates a group. The group key is wrapped once per member device, plus
     * each of our own devices (wrapping to ourselves works because
     * ECDH(our private, our public) is a valid shared secret).
     */
    suspend fun createGroup(name: String, members: List<ChatUser>): ChatGroup {
        val me = myChatUserId ?: throw ChatException.NotRegistered()
        val groupKey = ChatCrypto.generateContentKey()
        if (members.any { !it.canReceiveEncrypted }) throw ChatException.EncryptionUnavailable()
        val envelopes = withContext(Dispatchers.Default) {
            (members.flatMap { it.devices } + myDevices).distinctBy { it.id }.map { envelope(it, groupKey, true) }
        }
        val body = buildJsonObject {
            put("name", name)
            put("member_ids", JsonArray((members.map { it.id } + me).map { JsonPrimitive(it) }))
            put("wrapped_keys", JsonArray(envelopes))
        }
        val group: ChatGroup = perform(makeRequest("groups", "POST", body = body))
        synchronized(groupKeys) { groupKeys[group.id] = groupKey }
        return group
    }

    suspend fun fetchGroups(): List<ChatGroup> {
        val groups: List<ChatGroup> = perform(makeRequest("groups"))
        shareGroupKeysWithNewDevices(groups)
        return groups
    }

    @Serializable private data class TopUpResponse(val added: Int = 0)

    /**
     * Re-wraps the group key for member devices that hold no envelope yet (a
     * colleague who added a device after the group was created). Best effort.
     */
    private suspend fun shareGroupKeysWithNewDevices(groups: List<ChatGroup>) {
        for (group in groups) {
            val missing = group.devicesMissingKeys.orEmpty()
            if (missing.isEmpty()) continue
            val key = groupKey(group) ?: continue
            val envelopes = missing.mapNotNull { device ->
                try { envelope(device, key, true) } catch (e: Exception) { null }
            }
            if (envelopes.isEmpty()) continue
            try {
                perform<TopUpResponse>(makeRequest("groups/${group.id}/keys", "POST",
                    body = buildJsonObject { put("wrapped_keys", JsonArray(envelopes)) }))
            } catch (e: Exception) { }
        }
    }

    /** The unwrapped group key, or null when this device has no envelope for it. */
    fun groupKey(group: ChatGroup): ByteArray? {
        synchronized(groupKeys) { groupKeys[group.id] }?.let { return it }
        val wrapped = group.myWrappedKey ?: return null
        val wrapper = group.wrapperPublicKey ?: return null
        val key = ChatCrypto.unwrapKey(wrapped, wrapper) ?: return null
        synchronized(groupKeys) { groupKeys[group.id] = key }
        return key
    }

    /** The content key of one direct message: our envelope, unwrapped against the sending device. */
    private fun messageKey(message: ChatMessage): ByteArray? {
        val wrapped = message.wrappedKey ?: return null
        val sender = message.senderPublicKey ?: return null
        return ChatCrypto.unwrapKey(wrapped, sender)
    }

    // --- Messages ---

    /**
     * Messages for a target, decrypted for display. Pass [since] (last known id)
     * for incremental polling and [changedAfter] to also receive tombstones and
     * delivery/read ticks for messages already on screen.
     */
    suspend fun fetchMessages(target: ChatTarget, since: Int? = null, changedAfter: Instant? = null): List<ChatMessage> {
        val query = mutableListOf(
            when (target) {
                is ChatTarget.Direct -> "with" to target.user.id.toString()
                is ChatTarget.Group -> "group" to target.group.id.toString()
            }
        )
        since?.let { query += "since" to it.toString() }
        changedAfter?.let { query += "deleted_after" to it.truncatedTo(ChronoUnit.SECONDS).toString() }
        val raw: List<ChatMessage> = perform(makeRequest("messages", query = query))
        // Nothing from a blocked sender reaches the screen (matters in groups).
        val blocked = ChatBlockList.blockedIDs
        return withContext(Dispatchers.Default) {
            raw.filter { it.fromUserId !in blocked || it.fromUserId == myChatUserId }.map { message ->
                val key = when (target) {
                    is ChatTarget.Direct -> if (message.deleted == true) null else messageKey(message)
                    is ChatTarget.Group -> groupKey(target.group)
                }
                decrypted(message, key)
            }
        }
    }

    /**
     * Sends a message, always end-to-end encrypted. Refuses to send when no
     * encryption key is available, so plaintext never reaches the relay.
     */
    suspend fun send(target: ChatTarget, body: String, ticket: Ticket? = null,
                     attachment: PendingChatAttachment? = null): ChatMessage {
        val contentKey: ByteArray
        val fields = HashMap<String, kotlinx.serialization.json.JsonElement>()
        when (target) {
            is ChatTarget.Direct -> {
                val partner = target.user
                if (ChatBlockList.isBlocked(partner.id)) throw ChatException.UserBlocked()
                if (!partner.canReceiveEncrypted) throw ChatException.EncryptionUnavailable()
                // Without our own device list we would send a message we could not read back.
                if (myDevices.isEmpty()) throw ChatException.NotRegistered()
                // One random key per message, wrapped for every device that may read
                // it: all of the recipient's and all of ours, including this one.
                contentKey = ChatCrypto.generateContentKey()
                val envelopes = withContext(Dispatchers.Default) {
                    (partner.devices + myDevices).distinctBy { it.id }.map { envelope(it, contentKey, false) }
                }
                fields["to_user_id"] = JsonPrimitive(partner.id)
                fields["sender_public_key"] = JsonPrimitive(ChatCrypto.publicKeyBase64)
                fields["keys"] = JsonArray(envelopes)
            }
            is ChatTarget.Group -> {
                contentKey = groupKey(target.group) ?: throw ChatException.EncryptionUnavailable()
                fields["group_id"] = JsonPrimitive(target.group.id)
            }
        }
        if (attachment != null) {
            val sealed = withContext(Dispatchers.Default) { ChatCrypto.encryptData(attachment.data, contentKey) }
            fields["attachment_id"] = JsonPrimitive(uploadAttachment(sealed, attachment.filename, attachment.mimeType))
            fields["attachment_name"] = JsonPrimitive(attachment.filename)
            fields["attachment_mime"] = JsonPrimitive(attachment.mimeType)
        }
        fields["body"] = JsonPrimitive(ChatCrypto.encrypt(body, contentKey))
        if (ticket != null) {
            fields["ticket_id"] = JsonPrimitive(ticket.id)
            fields["ticket_number"] = JsonPrimitive(ticket.number)
        }
        val message: ChatMessage = perform(makeRequest("messages", "POST", body = JsonObject(fields)))
        // Return the plaintext for local display; reached only when the body was encrypted.
        return message.copy(body = body, isEncrypted = true)
    }

    @Serializable private data class OkResponse(val ok: Boolean = true)

    suspend fun markRead(target: ChatTarget) {
        val body = buildJsonObject {
            when (target) {
                is ChatTarget.Direct -> put("with_user_id", target.user.id)
                is ChatTarget.Group -> put("group_id", target.group.id)
            }
        }
        try { perform<OkResponse>(makeRequest("read", "POST", body = body)) } catch (e: Exception) { }
        refreshUnreadCount()
    }

    /** Refreshes the unread total for the toolbar badge. */
    suspend fun refreshUnreadCount() {
        try { fetchConversations() } catch (e: Exception) { }
    }

    // --- Deletion ---

    /** Deletes one of our own messages for everyone (the relay tombstones it). */
    suspend fun deleteMessage(id: Int) {
        perform<OkResponse>(makeRequest("messages/$id", "DELETE"))
    }

    /**
     * Deletes a conversation on the relay: a direct chat for both participants;
     * a group for everyone when we created it, otherwise we leave it.
     */
    suspend fun deleteConversation(target: ChatTarget) {
        val body = buildJsonObject {
            when (target) {
                is ChatTarget.Direct -> put("with_user_id", target.user.id)
                is ChatTarget.Group -> put("group_id", target.group.id)
            }
        }
        perform<OkResponse>(makeRequest("conversations/delete", "POST", body = body))
        ChatHistoryStore.clear(target.id)
        refreshUnreadCount()
    }

    // --- Attachments ---

    @Serializable private data class AttachmentUploadResponse(val id: Int)
    @Serializable private data class AttachmentDownloadResponse(val data: String)

    private suspend fun uploadAttachment(sealed: ByteArray, filename: String, mimeType: String): Int {
        if (sealed.size > PendingChatAttachment.MAX_BYTES + 1024) throw ChatException.AttachmentTooLarge()
        val body = buildJsonObject {
            put("data", Base64.encodeToString(sealed, Base64.NO_WRAP))
            put("filename", filename)
            put("mime_type", mimeType)
        }
        return perform<AttachmentUploadResponse>(makeRequest("attachments", "POST", body = body)).id
    }

    /**
     * Downloads and decrypts a message's attachment. It is sealed with the same
     * content key as the message that carries it.
     */
    suspend fun downloadAttachment(message: ChatMessage, target: ChatTarget): ByteArray {
        val attachmentId = message.attachmentId ?: throw ChatException.ServerUnavailable()
        val contentKey = when (target) {
            is ChatTarget.Direct -> messageKey(message)
            is ChatTarget.Group -> groupKey(target.group)
        } ?: throw ChatException.EncryptionUnavailable()
        val response: AttachmentDownloadResponse = perform(makeRequest("attachments/$attachmentId"))
        return withContext(Dispatchers.Default) {
            try {
                ChatCrypto.decryptData(Base64.decode(response.data, Base64.DEFAULT), contentKey)
            } catch (e: Exception) {
                throw ChatException.EncryptionUnavailable()
            }
        }
    }
}
