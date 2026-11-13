package com.baseonline.zammadmobile.ui.screens

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.provider.OpenableColumns
import android.text.format.DateUtils
import android.util.LruCache
import android.webkit.MimeTypeMap
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Done
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.chat.ChatException
import com.baseonline.zammadmobile.chat.ChatMessage
import com.baseonline.zammadmobile.chat.ChatMessageStatus
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.chat.ChatTarget
import com.baseonline.zammadmobile.chat.PendingChatAttachment
import com.baseonline.zammadmobile.data.formattedDate
import com.baseonline.zammadmobile.ui.components.GlassCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.max
import kotlin.math.min

// Shared pieces of the colleague chat screens (list + conversation).

/**
 * Makes sure this device is registered with the relay before any chat call.
 * Both chat screens can be the first one shown (the conversation is the
 * landing point of a notification), so the current user may still be loading.
 */
internal suspend fun ensureChatRegistered(vm: TicketViewModel) {
    if (ChatService.myChatUserId != null) return
    if (vm.currentUser == null) {
        // A load may already be running (app start); wait for it rather than restart it.
        if (vm.isLoading) snapshotFlow { vm.currentUser != null || !vm.isLoading }.first { it }
        if (vm.currentUser == null) vm.refreshAllData()
    }
    val user = vm.currentUser ?: throw ChatException.NotRegistered()
    if (ChatService.myChatUserId == null) ChatService.register(user)
}

/** The text to show for a failed chat call. */
internal fun chatErrorText(context: Context, e: Throwable): String =
    (e as? ChatException)?.localized(context) ?: e.message ?: e.toString()

/** "Today" / "Yesterday" (system-localised), otherwise the date. */
internal fun chatDayLabel(date: LocalDate): String {
    val zone = ZoneId.systemDefault()
    val start = date.atStartOfDay(zone).toInstant()
    return if (!date.isBefore(LocalDate.now(zone).minusDays(1))) {
        DateUtils.getRelativeTimeSpanString(start.toEpochMilli(), System.currentTimeMillis(), DateUtils.DAY_IN_MILLIS)
            .toString().replaceFirstChar { it.uppercase() }
    } else start.formattedDate()
}

// --- Small composables ---

@Composable
internal fun ChatAvatar(isGroup: Boolean, modifier: Modifier = Modifier, size: Dp = 44.dp) {
    Icon(
        if (isGroup) Icons.Filled.Groups else Icons.Filled.AccountCircle,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.size(size).padding(if (isGroup) 5.dp else 0.dp),
    )
}

/** WhatsApp-style ticks: one grey = sent, two grey = delivered, two blue = read. */
@Composable
internal fun DeliveryTicks(status: ChatMessageStatus, neutral: Color, modifier: Modifier = Modifier) {
    val label = stringResource(when (status) {
        ChatMessageStatus.SENT -> R.string.chat_status_sent
        ChatMessageStatus.DELIVERED -> R.string.chat_status_delivered
        ChatMessageStatus.READ -> R.string.chat_status_read
    })
    Icon(
        if (status == ChatMessageStatus.SENT) Icons.Filled.Done else Icons.Filled.DoneAll,
        contentDescription = label,
        tint = if (status == ChatMessageStatus.READ) Color(0.20f, 0.60f, 1.0f) else neutral,
        modifier = modifier.size(14.dp),
    )
}

/** Centered card for the empty / error states. */
@Composable
internal fun ChatStateCard(
    icon: ImageVector,
    text: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: () -> Unit = {},
) {
    GlassCard(modifier.padding(16.dp).widthIn(max = 420.dp), cornerRadius = 12.dp, contentPadding = PaddingValues(28.dp)) {
        Icon(icon, null, Modifier.size(40.dp).align(Alignment.CenterHorizontally), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(text, Modifier.padding(top = 12.dp).align(Alignment.CenterHorizontally), textAlign = TextAlign.Center,
            style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (actionLabel != null) {
            OutlinedButton(onClick = onAction, Modifier.padding(top = 12.dp).align(Alignment.CenterHorizontally)) { Text(actionLabel) }
        }
    }
}

// --- Incoming attachments ---

/**
 * Decrypted attachments, kept under `cacheDir/chat/` (shareable through the
 * FileProvider) with decoded thumbnails in memory.
 */
internal object ChatAttachmentStore {
    private val thumbnails = object : LruCache<Int, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: Int, value: Bitmap) = value.byteCount
    }

    private fun fileFor(context: Context, message: ChatMessage): File {
        val dir = File(context.cacheDir, "chat").apply { mkdirs() }
        val name = (message.attachmentName ?: "attachment").replace(Regex("[^A-Za-z0-9._-]"), "_").takeLast(80)
        return File(dir, "${message.attachmentId ?: 0}_$name")
    }

    /** The decrypted attachment as a file, downloading it on first use. */
    suspend fun file(context: Context, message: ChatMessage, target: ChatTarget): File {
        val file = fileFor(context, message)
        if (withContext(Dispatchers.IO) { file.length() > 0 }) return file
        val bytes = ChatService.downloadAttachment(message, target)
        withContext(Dispatchers.IO) {
            val part = File(file.parentFile, "${file.name}.part")
            part.writeBytes(bytes)
            if (!part.renameTo(file)) { file.writeBytes(bytes); part.delete() }
        }
        return file
    }

    fun cachedThumbnail(attachmentId: Int?): Bitmap? = attachmentId?.let { thumbnails.get(it) }

    /** A display-sized bitmap of an image attachment, or null when it cannot be decoded. */
    suspend fun thumbnail(context: Context, message: ChatMessage, target: ChatTarget): Bitmap? {
        val id = message.attachmentId ?: return null
        thumbnails.get(id)?.let { return it }
        val file = file(context, message, target)
        val bitmap = withContext(Dispatchers.Default) {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(file.path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@withContext null
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1024) sample *= 2
            BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return null
        thumbnails.put(id, bitmap)
        return bitmap
    }

    /** Drops the local copy of a message's attachment (the message was deleted). */
    fun evict(context: Context, message: ChatMessage) {
        val id = message.attachmentId ?: return
        thumbnails.remove(id)
        try { fileFor(context, message).delete() } catch (e: Exception) { }
    }

    /** Opens the file in another app, falling back to the share sheet. False when nothing can take it. */
    fun open(context: Context, file: File, mimeType: String): Boolean {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeType)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        try { context.startActivity(view); return true } catch (e: ActivityNotFoundException) { }
        val send = Intent(Intent.ACTION_SEND).setType(mimeType).putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri(null, uri)
        return try {
            context.startActivity(Intent.createChooser(send, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: ActivityNotFoundException) { false }
    }
}

// --- Outgoing attachments ---

/**
 * A picked photo, downscaled for transfer like iOS does (max 2048 px, JPEG 80%).
 * Null when the image cannot be read; throws [ChatException.AttachmentTooLarge].
 */
internal suspend fun loadPhotoAttachment(context: Context, uri: Uri): PendingChatAttachment? = withContext(Dispatchers.IO) {
    try {
        val resolver = context.contentResolver
        val maxDimension = 2048
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@withContext null
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxDimension) sample *= 2
        var bitmap = resolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
        } ?: return@withContext null
        val rotation = try {
            resolver.openInputStream(uri)?.use {
                when (ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } ?: 0f
        } catch (e: Exception) { 0f }
        val scale = min(1f, maxDimension.toFloat() / max(bitmap.width, bitmap.height))
        if (scale < 1f || rotation != 0f) {
            val matrix = Matrix().apply { postScale(scale, scale); postRotate(rotation) }
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }
        val out = ByteArrayOutputStream()
        if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)) return@withContext null
        if (out.size() > PendingChatAttachment.MAX_BYTES) throw ChatException.AttachmentTooLarge()
        PendingChatAttachment(out.toByteArray(), "photo-${System.currentTimeMillis() / 1000}.jpg", "image/jpeg")
    } catch (e: ChatException) {
        throw e
    } catch (e: Exception) {
        null
    } catch (e: OutOfMemoryError) {
        null
    }
}

/** A picked document, as is. Null when unreadable; throws [ChatException.AttachmentTooLarge]. */
internal suspend fun loadFileAttachment(context: Context, uri: Uri): PendingChatAttachment? = withContext(Dispatchers.IO) {
    try {
        val resolver = context.contentResolver
        var name: String? = null
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameColumn >= 0 && !cursor.isNull(nameColumn)) name = cursor.getString(nameColumn)
                if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) size = cursor.getLong(sizeColumn)
            }
        }
        if (size > PendingChatAttachment.MAX_BYTES) throw ChatException.AttachmentTooLarge()
        val out = ByteArrayOutputStream()
        resolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
                if (out.size() > PendingChatAttachment.MAX_BYTES) throw ChatException.AttachmentTooLarge()
            }
        } ?: return@withContext null
        val filename = name ?: uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        val mime = resolver.getType(uri)
            ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(filename.substringAfterLast('.', "").lowercase())
            ?: "application/octet-stream"
        PendingChatAttachment(out.toByteArray(), filename, mime)
    } catch (e: ChatException) {
        throw e
    } catch (e: Exception) {
        null
    } catch (e: OutOfMemoryError) {
        null
    }
}
