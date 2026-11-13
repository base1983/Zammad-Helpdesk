package com.baseonline.zammadmobile.chat

import com.baseonline.zammadmobile.data.Date
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** One installation of the app belonging to a colleague. */
@Serializable
data class ChatDevice(
    val id: Int,
    @SerialName("public_key") val publicKey: String,
)

/** An engineer registered for chat on the same Zammad instance. */
@Serializable
data class ChatUser(
    val id: Int,
    @SerialName("zammad_user_id") val zammadUserId: Int,
    val name: String,
    val email: String? = null,
    val devices: List<ChatDevice>,
) {
    /** False until the colleague has opened the app once and published a device key. */
    val canReceiveEncrypted: Boolean get() = devices.isNotEmpty()
}

@Serializable
data class ChatGroup(
    val id: Int,
    val name: String,
    @SerialName("creator_id") val creatorId: Int,
    @SerialName("my_wrapped_key") val myWrappedKey: String? = null,
    @SerialName("wrapper_public_key") val wrapperPublicKey: String? = null,
    val members: List<ChatUser>? = null,
    @SerialName("devices_missing_keys") val devicesMissingKeys: List<ChatDevice>? = null,
)

@Serializable
data class ChatMessage(
    val id: Int,
    @SerialName("from_user_id") val fromUserId: Int,
    @SerialName("to_user_id") val toUserId: Int? = null,
    @SerialName("group_id") val groupId: Int? = null,
    @SerialName("from_user_name") val fromUserName: String? = null,
    val body: String,
    @SerialName("ticket_id") val ticketId: Int? = null,
    @SerialName("ticket_number") val ticketNumber: String? = null,
    @SerialName("attachment_id") val attachmentId: Int? = null,
    @SerialName("attachment_name") val attachmentName: String? = null,
    @SerialName("attachment_mime") val attachmentMime: String? = null,
    @SerialName("created_at") val createdAt: Date,
    val deleted: Boolean? = null,
    @SerialName("delivered_at") val deliveredAt: Date? = null,
    @SerialName("read_at") val readAt: Date? = null,
    @SerialName("sender_public_key") val senderPublicKey: String? = null,
    @SerialName("wrapped_key") val wrappedKey: String? = null,
    /** Local only (history cache): whether the message travelled encrypted. */
    @SerialName("is_encrypted") val isEncrypted: Boolean = false,
    /** Local only: no key for this message on this device; show the placeholder. */
    @SerialName("is_undecryptable") val isUndecryptable: Boolean = false,
) {
    val deliveryStatus: ChatMessageStatus
        get() = when {
            readAt != null -> ChatMessageStatus.READ
            deliveredAt != null -> ChatMessageStatus.DELIVERED
            else -> ChatMessageStatus.SENT
        }
    val isImageAttachment: Boolean get() = attachmentId != null && attachmentMime?.startsWith("image/") == true
}

/** WhatsApp-style delivery ladder for our own messages. */
enum class ChatMessageStatus { SENT, DELIVERED, READ }

/** A pending outgoing attachment (photo or file), before encryption. */
class PendingChatAttachment(val data: ByteArray, val filename: String, val mimeType: String) {
    val isImage: Boolean get() = mimeType.startsWith("image/")
    companion object { const val MAX_BYTES = 10 * 1024 * 1024 }
}

/** Either a direct conversation partner or a group. */
sealed class ChatTarget {
    data class Direct(val user: ChatUser) : ChatTarget()
    data class Group(val group: ChatGroup) : ChatTarget()

    val id: String get() = when (this) {
        is Direct -> "dm-${user.id}"
        is Group -> "group-${group.id}"
    }
    val displayName: String get() = when (this) {
        is Direct -> user.name
        is Group -> group.name
    }
}

@Serializable
data class ChatConversation(
    val partner: ChatUser? = null,
    val group: ChatGroup? = null,
    @SerialName("last_message") val lastMessage: ChatMessage? = null,
    @SerialName("unread_count") val unreadCount: Int = 0,
) {
    val id: String get() = partner?.let { "dm-${it.id}" } ?: group?.let { "group-${it.id}" } ?: "unknown"
    val target: ChatTarget? get() = partner?.let { ChatTarget.Direct(it) } ?: group?.let { ChatTarget.Group(it) }
}

sealed class ChatException(val messageRes: Int, val code: Int = 0) : Exception() {
    class NotRegistered : ChatException(com.baseonline.zammadmobile.R.string.chat_unavailable)
    class ServerUnavailable : ChatException(com.baseonline.zammadmobile.R.string.chat_unavailable)
    class ServerError(statusCode: Int) : ChatException(com.baseonline.zammadmobile.R.string.chat_server_error, statusCode)
    class EncryptionUnavailable : ChatException(com.baseonline.zammadmobile.R.string.chat_encryption_unavailable)
    class AttachmentTooLarge : ChatException(com.baseonline.zammadmobile.R.string.chat_attachment_too_large)
    class UserBlocked : ChatException(com.baseonline.zammadmobile.R.string.chat_user_blocked)
    /** The relay answered in a shape this app does not understand (pre-v4 relay). */
    class ProtocolMismatch : ChatException(com.baseonline.zammadmobile.R.string.chat_server_outdated)

    fun localized(context: android.content.Context): String =
        if (this is ServerError) context.getString(messageRes, code) else context.getString(messageRes)
}
