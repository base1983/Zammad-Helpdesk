package com.baseonline.zammadmobile.data

import android.util.Base64
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.time.Instant
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit
import java.util.UUID

/** ISO 8601 with or without fractional seconds and with `Z` or an offset. */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): Instant = parse(decoder.decodeString())
    override fun serialize(encoder: Encoder, value: Instant) =
        encoder.encodeString(value.truncatedTo(ChronoUnit.SECONDS).toString())

    fun parse(text: String): Instant = try {
        Instant.parse(text)
    } catch (e: Exception) {
        OffsetDateTime.parse(text).toInstant()
    }
}

typealias Date = @Serializable(with = InstantSerializer::class) Instant

/** Shared lenient JSON: Zammad adds fields between versions and omits others. */
val AppJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true
    explicitNulls = false
    isLenient = true
}

@Serializable
data class Ticket(
    val id: Int,
    val group_id: Int = 0,
    val priority_id: Int = 0,
    val state_id: Int = 0,
    val organization_id: Int? = null,
    val number: String = "",
    val title: String = "",
    val owner_id: Int = 1,
    val customer_id: Int = 0,
    val note: String? = null,
    val first_response_at: Date? = null,
    val first_response_escalation_at: Date? = null,
    val first_response_in_min: Int? = null,
    val first_response_diff_in_min: Int? = null,
    val close_at: Date? = null,
    val close_escalation_at: Date? = null,
    val close_in_min: Int? = null,
    val close_diff_in_min: Int? = null,
    val update_escalation_at: Date? = null,
    val update_in_min: Int? = null,
    val update_diff_in_min: Int? = null,
    val last_contact_at: Date? = null,
    val last_contact_agent_at: Date? = null,
    val last_contact_customer_at: Date? = null,
    val last_owner_update_at: Date? = null,
    val article_count: Int = 0,
    val escalation_at: Date? = null,
    val pending_time: Date? = null,
    val time_unit: String? = null,
    val updated_by_id: Int = 0,
    val created_by_id: Int = 0,
    val created_at: Date = Instant.EPOCH,
    val updated_at: Date = Instant.EPOCH,
)

@Serializable
data class TicketState(
    val id: Int,
    val state_type_id: Int = 0,
    val name: String = "",
    val next_state_id: Int? = null,
    val ignore_escalation: Boolean = false,
    val active: Boolean = true,
)

@Serializable
data class TicketPriority(
    val id: Int,
    val name: String = "",
    val ui_color: String? = null,
    val active: Boolean = true,
)

@Serializable
data class TicketArticle(
    val id: Int,
    val ticket_id: Int = 0,
    val type_id: Int = 0,
    val sender_id: Int = 0,
    val from: String = "",
    val to: String? = null,
    val cc: String? = null,
    val subject: String? = null,
    val reply_to: String? = null,
    val content_type: String = "text/plain",
    val body: String = "",
    @SerialName("internal") val isInternal: Boolean? = null,
    val type: String? = null,
    val sender: String? = null,
    val created_by_id: Int = 0,
    val created_at: Date = Instant.EPOCH,
    val updated_at: Date = Instant.EPOCH,
    val attachments: List<Attachment>? = null,
)

@Serializable
data class Attachment(
    val id: Int,
    val filename: String = "",
    val size: String? = null,
    val preferences: Preferences? = null,
) {
    @Serializable
    data class Preferences(
        @SerialName("Content-Type") val contentType: String? = null,
        @SerialName("Mime-Type") val mimeType: String? = null,
        @SerialName("Content-ID") val contentID: String? = null,
    )

    val resolvedMimeType: String
        get() = preferences?.mimeType ?: preferences?.contentType?.substringBefore(';') ?: "application/octet-stream"

    /** Bare Content-ID (no angle brackets) used by inline `cid:` references. */
    val contentIDValue: String?
        get() = preferences?.contentID?.trim('<', '>', ' ', '"')?.takeIf { it.isNotEmpty() }

    val isInline: Boolean get() = contentIDValue != null

    val sizeFormatted: String
        get() = size?.toLongOrNull()?.let { formatBytes(it) } ?: ""
}

fun formatBytes(bytes: Long): String = when {
    bytes < 1000 -> "$bytes B"
    bytes < 1_000_000 -> String.format("%.0f kB", bytes / 1000.0)
    bytes < 1_000_000_000 -> String.format("%.1f MB", bytes / 1_000_000.0)
    else -> String.format("%.2f GB", bytes / 1_000_000_000.0)
}

@Serializable
data class User(
    val id: Int,
    val organization_id: Int? = null,
    val login: String = "",
    val firstname: String = "",
    val lastname: String = "",
    val email: String = "",
    val phone: String? = null,
    val mobile: String? = null,
    val vip: Boolean = false,
    val active: Boolean = true,
    val role_ids: List<Int>? = null,
    // Zammad returns {"<group id>": ["full", ...]}; only presence matters here.
    val group_ids: JsonElement? = null,
) {
    val fullname: String get() = "$firstname $lastname".trim()
}

@Serializable
data class Role(val id: Int, val name: String = "", val active: Boolean = true)

@Serializable
data class TicketGroup(val id: Int, val name: String = "", val active: Boolean = true)

@Serializable
data class Organization(val id: Int, val name: String = "")

@Serializable
data class TicketUpdatePayload(
    val owner_id: Int,
    val state_id: Int,
    val priority_id: Int,
    val customer_id: Int,
    val pending_time: String? = null,
)

@Serializable
data class ArticleCreationPayload(
    val ticket_id: Int,
    val body: String,
    val to: String,
    val subject: String,
    @SerialName("internal") val isInternal: Boolean,
    val type: String? = null,
    val attachments: List<AttachmentUploadPayload>? = null,
)

@Serializable
data class AttachmentUploadPayload(
    val filename: String,
    val data: String,
    @SerialName("mime-type") val mimeType: String,
)

/** A file picked for an outgoing reply, before upload. */
data class AttachmentDraft(
    val filename: String,
    val data: ByteArray,
    val mimeType: String,
    val id: String = UUID.randomUUID().toString(),
) {
    val sizeFormatted: String get() = formatBytes(data.size.toLong())
    val uploadPayload: AttachmentUploadPayload
        get() = AttachmentUploadPayload(filename, Base64.encodeToString(data, Base64.NO_WRAP), mimeType)

    override fun equals(other: Any?) = other is AttachmentDraft && other.id == id
    override fun hashCode() = id.hashCode()
}

@Serializable
data class TicketCreationPayload(
    val title: String,
    val group_id: Int,
    val customer_id: Int,
    val state_id: Int,
    val priority_id: Int,
    val owner_id: Int? = null,
    val tags: String? = null,
    val article: ArticlePayload,
) {
    @Serializable
    data class ArticlePayload(
        val body: String,
        val type: String,
        @SerialName("internal") val isInternal: Boolean,
    )
}

@Serializable
data class TimeAccountingPayload(val time_unit: String, val type_id: Int)

@Serializable
data class TimeAccountingType(val id: Int, val name: String = "", val active: Boolean = true)

@Serializable
data class TimeAccounting(
    val id: Int,
    val ticket_id: Int = 0,
    val time_unit: String = "",
    val ticket_article_id: Int? = null,
    val type_id: Int? = null,
    val created_by_id: Int = 0,
    val created_at: Date = Instant.EPOCH,
)
