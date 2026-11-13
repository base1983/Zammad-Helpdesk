package com.baseonline.zammadmobile.ui.screens

import com.baseonline.zammadmobile.App

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.AttachmentDraft
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.TicketArticle
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.data.formattedDateTime
import com.baseonline.zammadmobile.data.strippingHTML
import com.baseonline.zammadmobile.managers.DraftManager
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.GlassCard
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant

/** Zammad stores attachments base64 in the JSON body; keep single files within reason. */
private const val MAX_ATTACHMENT_BYTES = 25L * 1024 * 1024

@Composable
fun TicketReplyScreen(vm: TicketViewModel, nav: Nav, ticketId: Int, isInternalNote: Boolean, replyToArticleId: Int) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var ticket by remember { mutableStateOf(vm.cachedTicket(ticketId)) }
    var articleToReplyTo by remember { mutableStateOf<TicketArticle?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }

    var replyBody by rememberSaveable { mutableStateOf("") }
    var internalNote by rememberSaveable { mutableStateOf(isInternalNote) }
    var isInitialised by rememberSaveable { mutableStateOf(false) }
    // What the editor was filled with (the quote or the restored draft): a
    // draft is only written once the user has changed something.
    var seededBody by rememberSaveable { mutableStateOf("") }
    var seededInternalNote by rememberSaveable { mutableStateOf(isInternalNote) }
    var restoredDraftAt by rememberSaveable { mutableStateOf<Long?>(null) }

    val attachments = remember { mutableStateListOf<AttachmentDraft>() }
    var attachmentError by remember { mutableStateOf<String?>(null) }
    var isSending by remember { mutableStateOf(false) }
    var wasSent by remember { mutableStateOf(false) }

    val onText = stringResource(R.string.s_on)
    val wroteText = stringResource(R.string.wrote)

    fun quoteOf(article: TicketArticle?): String {
        if (article == null) return ""
        val header = "\n\n--- $onText ${article.created_at.formattedDateTime()} ${vm.userName(article.created_by_id)} $wroteText:\n>"
        return header + article.body.strippingHTML().replace("\n", "\n> ")
    }

    LaunchedEffect(ticketId) {
        // A saved draft wins over the quote and is shown without waiting for the network.
        if (!isInitialised) {
            DraftManager.draft(ticketId)?.let { draft ->
                replyBody = draft.body
                internalNote = draft.isInternalNote
                seededBody = draft.body
                seededInternalNote = draft.isInternalNote
                restoredDraftAt = draft.updatedAt
                isInitialised = true
            }
        }
        try {
            if (ticket == null) ticket = ZammadApi.fetchTicket(ticketId)
            if (replyToArticleId != 0) {
                articleToReplyTo = TicketArticleCache.get(ticketId)?.firstOrNull { it.id == replyToArticleId }
                    ?: ZammadApi.gracefully(emptyList()) { ZammadApi.fetchArticles(ticketId) }
                        .also { if (it.isNotEmpty()) TicketArticleCache.put(ticketId, it) }
                        .firstOrNull { it.id == replyToArticleId }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            loadError = e.message ?: e.toString()
        }
        if (!isInitialised) {
            // Keep whatever was typed while the article was loading.
            val seeded = replyBody + quoteOf(articleToReplyTo)
            replyBody = seeded
            seededBody = seeded
            isInitialised = true
        }
    }

    val isDirty = isInitialised && !wasSent && (replyBody != seededBody || internalNote != seededInternalNote)

    // Autosave, half a second after the last change.
    LaunchedEffect(replyBody, internalNote, isDirty) {
        if (!isDirty) return@LaunchedEffect
        delay(500)
        DraftManager.save(ticketId, replyBody, internalNote)
    }
    // Leaving within that half second must not lose the last words.
    DisposableEffect(ticketId) {
        onDispose {
            // Read the state itself, not a composition-time copy: a reply that
            // was just sent must not come back as a draft.
            if (isInitialised && !wasSent && (replyBody != seededBody || internalNote != seededInternalNote)) {
                DraftManager.save(ticketId, replyBody, internalNote)
            }
        }
    }

    fun discardDraft() {
        DraftManager.delete(ticketId)
        restoredDraftAt = null
        internalNote = isInternalNote
        seededInternalNote = isInternalNote
        // Re-seed the quote if there is an article to reply to.
        val seeded = quoteOf(articleToReplyTo)
        replyBody = seeded
        seededBody = seeded
    }

    fun addFiles(uris: List<Uri>, fallbackPrefix: String) {
        if (uris.isEmpty()) return
        scope.launch {
            for (uri in uris) {
                try {
                    attachments += readAttachment(context, uri, fallbackPrefix)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    attachmentError = e.message ?: e.toString()
                }
            }
        }
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris ->
        addFiles(uris, "image")
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        addFiles(uris, "file")
    }

    fun sendMessage() {
        val current = ticket ?: return
        if (isSending) return
        attachmentError = null
        val recipient = vm.userEmail(current.customer_id)?.takeIf { it.isNotBlank() }
        if (!internalNote && recipient == null) {
            // iOS only logs this; say it, or the button would seem dead.
            attachmentError = App.ctx.getString(R.string.customer_email_missing)
            return
        }
        isSending = true
        scope.launch {
            try {
                if (internalNote) {
                    vm.addInternalNote(current, replyBody, attachments.toList())
                } else {
                    vm.sendReply(current, replyBody, current.title, recipient!!, attachments.toList())
                }
                wasSent = true
                DraftManager.delete(ticketId)
                nav.back()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                attachmentError = e.message ?: e.toString()
            } finally {
                isSending = false
            }
        }
    }

    AppScaffold(
        title = stringResource(R.string.reply_to_ticket),
        subtitle = ticket?.let { "#${it.number}" },
        onBack = { nav.back() },
        actions = {
            if (isSending) {
                CircularProgressIndicator(Modifier.padding(horizontal = 12.dp).size(24.dp), strokeWidth = 2.dp)
            } else {
                IconButton(onClick = { sendMessage() },
                    enabled = ticket != null && isInitialised && (replyBody.isNotBlank() || attachments.isNotEmpty())) {
                    Icon(Icons.AutoMirrored.Filled.Send, contentDescription = stringResource(R.string.handoff_send))
                }
            }
        },
    ) { padding ->
        if (ticket == null) {
            val message = loadError
            if (message != null) TicketMessageCard(message, Modifier.padding(padding).padding(16.dp))
            else CenteredLoading(Modifier.padding(padding), stringResource(R.string.loading_ticket))
            return@AppScaffold
        }

        Column(
            Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            restoredDraftAt?.let { savedAt ->
                GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(start = 14.dp, end = 8.dp, top = 8.dp, bottom = 8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Description, null)
                        Spacer(Modifier.width(10.dp))
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.draft_restored), style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold)
                            Text(Instant.ofEpochMilli(savedAt).formattedDateTime(), style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        OutlinedButton(onClick = { discardDraft() }) { Text(stringResource(R.string.discard_draft)) }
                    }
                }
            }

            GlassCard(Modifier.fillMaxWidth().weight(1f)) {
                OutlinedTextField(
                    value = replyBody,
                    onValueChange = { replyBody = it },
                    modifier = Modifier.fillMaxSize().padding(8.dp),
                    enabled = !isSending,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                )
            }

            if (attachments.isNotEmpty()) {
                GlassCard(Modifier.fillMaxWidth().heightIn(max = 160.dp), contentPadding = PaddingValues(8.dp)) {
                    Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        attachments.forEach { attachment ->
                            Row(
                                Modifier.fillMaxWidth().background(Color.Gray.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                                    .padding(start = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(
                                    when {
                                        attachment.mimeType.startsWith("image/") -> Icons.Filled.Image
                                        attachment.mimeType.startsWith("video/") -> Icons.Filled.Movie
                                        else -> Icons.AutoMirrored.Filled.InsertDriveFile
                                    }, null, Modifier.size(22.dp))
                                Spacer(Modifier.width(10.dp))
                                Column(Modifier.weight(1f)) {
                                    Text(attachment.filename, style = MaterialTheme.typography.bodyMedium, maxLines = 1,
                                        overflow = TextOverflow.MiddleEllipsis)
                                    Text(attachment.sizeFormatted, style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                                IconButton(onClick = { attachments.remove(attachment) }, enabled = !isSending) {
                                    Icon(Icons.Filled.Cancel, contentDescription = stringResource(R.string.cancel),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }

            attachmentError?.let { TicketMessageCard(it) }

            GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.internal_note_toggle), Modifier.weight(1f))
                    Switch(checked = internalNote, onCheckedChange = { internalNote = it }, enabled = !isSending)
                }
                Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedButton(enabled = !isSending, onClick = {
                        photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                    }) {
                        Icon(Icons.Filled.PhotoLibrary, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.add_photo))
                    }
                    OutlinedButton(enabled = !isSending, onClick = { filePicker.launch(arrayOf("*/*")) }) {
                        Icon(Icons.Filled.AttachFile, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.add_file))
                    }
                }
            }
        }
    }
}

/** Reads a picked document or photo into memory, with its display name and MIME type. */
private suspend fun readAttachment(context: Context, uri: Uri, fallbackPrefix: String): AttachmentDraft =
    withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        var name: String? = null
        var size = -1L
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
            }
        }
        if (size > MAX_ATTACHMENT_BYTES) throw java.io.IOException(App.ctx.getString(R.string.attachment_too_large, name ?: "File"))
        val mimeType = resolver.getType(uri)
            ?: name?.substringAfterLast('.', "")?.lowercase()
                ?.let { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) }
            ?: "application/octet-stream"
        val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw java.io.IOException(App.ctx.getString(R.string.attachment_unreadable, name ?: uri.lastPathSegment ?: "File"))
        if (bytes.size > MAX_ATTACHMENT_BYTES) throw java.io.IOException(App.ctx.getString(R.string.attachment_too_large, name ?: "File"))
        val filename = name?.takeIf { it.isNotBlank() } ?: run {
            val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "bin"
            "$fallbackPrefix-${System.currentTimeMillis() / 1000}.$extension"
        }
        AttachmentDraft(filename, bytes, mimeType)
    }
