package com.baseonline.zammadmobile.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.SmsFailed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.chat.ChatBlockList
import com.baseonline.zammadmobile.chat.ChatDirectory
import com.baseonline.zammadmobile.chat.ChatHistoryStore
import com.baseonline.zammadmobile.chat.ChatMessage
import com.baseonline.zammadmobile.chat.ChatReporter
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.chat.ChatTarget
import com.baseonline.zammadmobile.chat.ChatUser
import com.baseonline.zammadmobile.chat.PendingChatAttachment
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.data.formattedTime
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.glassColor
import com.baseonline.zammadmobile.ui.theme.ChatTheme
import com.baseonline.zammadmobile.ui.theme.LocalIsDark
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Same interval as iOS: the relay is polled once a minute while the conversation is visible. */
private const val POLL_INTERVAL_MS = 60_000L

private val Orange = Color(0xFFFF9800)

/**
 * Message thread with a colleague or a group. Shows the on-device history
 * first, tops it up from the relay and then polls for new messages,
 * tombstones and delivery/read ticks. Also the landing point of a chat
 * notification, so it registers and resolves the target itself.
 */
@Composable
fun ChatConversationScreen(vm: TicketViewModel, nav: Nav, targetId: String) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val theme = ChatTheme.current(LocalIsDark.current)
    var target by remember(targetId) { mutableStateOf<ChatTarget?>(null) }
    var setupError by remember(targetId) { mutableStateOf<String?>(null) }
    var attempt by remember { mutableIntStateOf(0) }

    LaunchedEffect(targetId, attempt) {
        setupError = null
        try {
            ensureChatRegistered(vm)
            val resolved = ChatDirectory.resolve(targetId)
            if (resolved != null) {
                target = resolved
            } else {
                val partnerId = targetId.takeIf { it.startsWith("dm-") }?.substringAfter('-')?.toIntOrNull()
                setupError = context.getString(
                    if (partnerId != null && ChatBlockList.isBlocked(partnerId)) R.string.chat_user_blocked else R.string.chat_unavailable)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            setupError = chatErrorText(context, e)
        }
    }

    // The conversation draws its own themed background over the wallpaper.
    Box(Modifier.fillMaxSize().background(theme.background)) {
        AppScaffold(title = target?.displayName ?: stringResource(R.string.chat), onBack = { nav.back() }) { padding ->
            val resolved = target
            val error = setupError
            when {
                resolved != null -> ConversationContent(vm, nav, resolved, theme,
                    Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding())
                error != null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    ChatStateCard(Icons.Outlined.SmsFailed, error, actionLabel = stringResource(R.string.try_again),
                        onAction = { scope.launch { attempt++ } })
                }
                else -> CenteredLoading(Modifier.padding(padding))
            }
        }
    }
}

private sealed interface ChatRow {
    data class Day(val date: LocalDate) : ChatRow
    data class Message(val message: ChatMessage) : ChatRow
}

private data class BlockCandidate(val id: Int, val name: String)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ConversationContent(vm: TicketViewModel, nav: Nav, target: ChatTarget, theme: ChatTheme, modifier: Modifier) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current
    val listState = rememberLazyListState()

    var messages by remember(target.id) { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var isLoaded by remember(target.id) { mutableStateOf(false) }
    var draft by rememberSaveable(target.id, stateSaver = TextFieldValue.Saver) { mutableStateOf(TextFieldValue("")) }
    var isSending by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var lastPoll by remember(target.id) { mutableStateOf(Instant.now()) }
    var blockCandidate by remember { mutableStateOf<BlockCandidate?>(null) }
    var showTicketSearch by remember { mutableStateOf(false) }
    var pendingTicket by remember { mutableStateOf<Ticket?>(null) }
    var pendingAttachment by remember { mutableStateOf<PendingChatAttachment?>(null) }
    var attachMenuOpen by remember { mutableStateOf(false) }

    val me = ChatService.myChatUserId
    val isGroup = target is ChatTarget.Group

    // Nothing from a blocked sender stays on screen (matters in groups); reading
    // the block list here makes a fresh block take effect immediately.
    val blocked = ChatBlockList.blocked
    val visible = remember(messages, blocked, me) {
        val ids = blocked.map { it.id }.toSet()
        messages.filter { it.fromUserId == me || it.fromUserId !in ids }
    }
    val rows = remember(visible) {
        val zone = ZoneId.systemDefault()
        val chronological = ArrayList<ChatRow>(visible.size + 8)
        var day: LocalDate? = null
        for (message in visible) {
            val date = message.createdAt.atZone(zone).toLocalDate()
            if (date != day) { chronological += ChatRow.Day(date); day = date }
            chronological += ChatRow.Message(message)
        }
        // The list is laid out bottom-up, so the newest row comes first.
        chronological.asReversed().toList()
    }

    /** People that can be @mentioned in this conversation. */
    val mentionCandidates: List<ChatUser> = remember(target, me) {
        when (target) {
            is ChatTarget.Direct -> listOf(target.user)
            is ChatTarget.Group -> target.group.members.orEmpty().filter { it.id != me }
        }
    }
    val mentionNames = remember(mentionCandidates, vm.currentUser) {
        (mentionCandidates.map { it.name } + listOfNotNull(vm.currentUser?.fullname)).filter { it.isNotBlank() }
    }
    /** Active "@…" token at the end of the draft, if any. */
    val mentionSuggestions: List<ChatUser> = remember(draft.text, mentionCandidates) {
        val at = draft.text.lastIndexOf('@')
        if (at < 0) return@remember emptyList()
        val token = draft.text.substring(at + 1)
        when {
            token.contains('\n') -> emptyList()
            token.isEmpty() -> mentionCandidates
            else -> mentionCandidates.filter { it.name.lowercase().startsWith(token.lowercase()) }
        }
    }

    /** Merges by id into the on-device history, so tombstones and ticks replace their originals in place. */
    suspend fun absorb(new: List<ChatMessage>) {
        val known = messages.associateBy { it.id }
        val newestKnown = messages.lastOrNull()?.id
        val incoming = new.filter { message ->
            if (message.deleted != true) return@filter true
            // The attachment of a deleted message goes too.
            known[message.id]?.let { ChatAttachmentStore.evict(context, it) }
            // A tombstone for an older message we no longer hold (pruned, or
            // deleted for me) must not bring it back as a grey bubble.
            newestKnown == null || message.id > newestKnown || message.id in known
        }
        messages = withContext(Dispatchers.IO) { ChatHistoryStore.merge(incoming, target.id) }
    }

    // Cached history first, then top up from the relay.
    LaunchedEffect(target.id) {
        val cached = withContext(Dispatchers.IO) { ChatHistoryStore.load(target.id) }
        if (cached.isNotEmpty()) messages = cached
        try {
            // `changedAfter` from the newest cached message also brings in the
            // deletions and ticks that happened while this conversation was closed.
            val last = cached.lastOrNull()
            val new = ChatService.fetchMessages(target, last?.id, last?.createdAt)
            absorb(new)
            ChatService.markRead(target)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (messages.isEmpty()) errorMessage = chatErrorText(context, e)
        }
        isLoaded = true
    }

    suspend fun poll() {
        // Timestamp taken before the request so a change racing with the fetch
        // is picked up by the next poll rather than lost.
        val pollStart = Instant.now()
        try {
            val new = ChatService.fetchMessages(target, messages.lastOrNull()?.id, lastPoll)
            lastPoll = pollStart
            if (new.isNotEmpty()) {
                absorb(new)
                ChatService.markRead(target)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
        }
    }

    // Poll while visible; coming back to the foreground polls straight away.
    LaunchedEffect(target.id, lifecycleOwner) {
        var isFirstStart = true
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
            if (!isFirstStart) poll()
            isFirstStart = false
            while (true) {
                delay(POLL_INTERVAL_MS)
                poll()
            }
        }
    }

    // Keep the newest message in view.
    val newestId = visible.lastOrNull()?.id
    LaunchedEffect(newestId) {
        if (newestId != null) listState.animateScrollToItem(0)
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            try {
                loadPhotoAttachment(context, uri)?.let { pendingAttachment = it; errorMessage = null }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = chatErrorText(context, e)
            }
        }
    }
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) scope.launch {
            try {
                loadFileAttachment(context, uri)?.let { pendingAttachment = it; errorMessage = null }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = chatErrorText(context, e)
            }
        }
    }

    fun send() {
        val body = draft.text.trim()
        val attachment = pendingAttachment
        val ticket = pendingTicket
        if ((body.isEmpty() && attachment == null) || isSending) return
        isSending = true
        errorMessage = null
        scope.launch {
            try {
                val message = ChatService.send(target, body, ticket, attachment)
                absorb(listOf(message))
                draft = TextFieldValue("")
                pendingTicket = null
                pendingAttachment = null
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = chatErrorText(context, e)
            } finally {
                isSending = false
            }
        }
    }

    /** Deletes one of our own messages on the relay; locally the bubble becomes the tombstone the receiver sees. */
    fun deleteForEveryone(message: ChatMessage) {
        scope.launch {
            try {
                ChatService.deleteMessage(message.id)
                ChatAttachmentStore.evict(context, message)
                val tombstone = message.copy(deleted = true, body = context.getString(R.string.chat_message_deleted), isEncrypted = true)
                messages = withContext(Dispatchers.IO) { ChatHistoryStore.merge(listOf(tombstone), target.id) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = chatErrorText(context, e)
            }
        }
    }

    /** Removes a received message from this device only. */
    fun deleteForMe(message: ChatMessage) {
        messages = messages.filter { it.id != message.id }
        scope.launch(Dispatchers.IO) { ChatHistoryStore.remove(message.id, target.id) }
    }

    fun senderName(message: ChatMessage): String =
        if (target is ChatTarget.Direct) target.user.name else message.fromUserName ?: message.fromUserId.toString()

    Column(modifier) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(
                Modifier.fillMaxSize(),
                state = listState,
                reverseLayout = true,
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(rows, key = { row ->
                    when (row) {
                        is ChatRow.Day -> "day-${row.date}"
                        is ChatRow.Message -> row.message.id
                    }
                }, contentType = { it is ChatRow.Day }) { row ->
                    when (row) {
                        is ChatRow.Day -> DaySeparator(row.date, theme)
                        is ChatRow.Message -> MessageBubble(
                            message = row.message,
                            isMine = row.message.fromUserId == me,
                            isGroup = isGroup,
                            target = target,
                            theme = theme,
                            mentionNames = mentionNames,
                            blockLabel = stringResource(R.string.chat_block_user, senderName(row.message)),
                            onOpenTicket = { nav.openTicket(it) },
                            onDeleteForEveryone = { deleteForEveryone(row.message) },
                            onDeleteForMe = { deleteForMe(row.message) },
                            onReport = {
                                // Hands the message to the mail app, pre-filled; shows the address when there is none.
                                if (!ChatReporter.reportMessage(context, row.message, target, vm.currentUser?.fullname)) {
                                    errorMessage = context.getString(R.string.chat_report_mail_unavailable, ChatReporter.ADDRESS)
                                }
                            },
                            onBlock = { blockCandidate = BlockCandidate(row.message.fromUserId, senderName(row.message)) },
                            onError = { errorMessage = it },
                        )
                    }
                }
            }
            if (!isLoaded && messages.isEmpty()) {
                CircularProgressIndicator(Modifier.align(Alignment.Center).size(28.dp), color = theme.metaText, strokeWidth = 2.5.dp)
            }
        }

        errorMessage?.let { message ->
            Text(message, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 14.dp, vertical = 2.dp).clip(RoundedCornerShape(10.dp))
                    .background(glassColor()).clickable { errorMessage = null }.padding(horizontal = 10.dp, vertical = 6.dp))
        }

        if (mentionSuggestions.isNotEmpty()) {
            LazyRow(contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(mentionSuggestions, key = { it.id }) { user ->
                    Surface(onClick = {
                        val at = draft.text.lastIndexOf('@')
                        if (at >= 0) {
                            val text = draft.text.substring(0, at) + "@${user.name} "
                            draft = TextFieldValue(text, TextRange(text.length))
                        }
                    }, shape = CircleShape, color = glassColor()) {
                        Text("@${user.name}", Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                            fontWeight = FontWeight.Bold, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }

        if (pendingTicket != null || pendingAttachment != null) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pendingTicket?.let { ticket ->
                    PendingChip(Icons.Filled.ConfirmationNumber, stringResource(R.string.chat_ticket_reference, ticket.number),
                        Modifier.weight(1f, fill = false)) { pendingTicket = null }
                }
                pendingAttachment?.let { attachment ->
                    PendingChip(if (attachment.isImage) Icons.Filled.Image else Icons.AutoMirrored.Filled.InsertDriveFile,
                        attachment.filename, Modifier.weight(1f, fill = false)) { pendingAttachment = null }
                }
            }
        }

        // Composer: no bar behind it, just a glass field and round buttons on the chat background.
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
            Box {
                ComposerButton(Icons.Filled.AttachFile, stringResource(R.string.attachments)) { attachMenuOpen = true }
                DropdownMenu(expanded = attachMenuOpen, onDismissRequest = { attachMenuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.chat_search_ticket)) },
                        leadingIcon = { Icon(Icons.Filled.ConfirmationNumber, null) },
                        onClick = { attachMenuOpen = false; showTicketSearch = true },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.chat_attach_file)) },
                        leadingIcon = { Icon(Icons.AutoMirrored.Filled.InsertDriveFile, null) },
                        onClick = { attachMenuOpen = false; filePicker.launch(arrayOf("*/*")) },
                    )
                }
            }
            Spacer(Modifier.width(6.dp))
            ComposerButton(Icons.Filled.Image, stringResource(R.string.add_photo)) {
                photoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
            }
            Spacer(Modifier.width(6.dp))
            TextField(
                value = draft,
                onValueChange = { new ->
                    // Typing '#' opens the ticket search, as on iOS.
                    if (new.text.endsWith("#") && new.text.length == draft.text.length + 1) showTicketSearch = true
                    draft = new
                },
                modifier = Modifier.weight(1f),
                placeholder = { Text(stringResource(R.string.chat_message_placeholder)) },
                maxLines = 4,
                shape = RoundedCornerShape(22.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = glassColor(), unfocusedContainerColor = glassColor(),
                    disabledContainerColor = glassColor(),
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
                    disabledIndicatorColor = Color.Transparent,
                ),
            )
            Spacer(Modifier.width(6.dp))
            FilledIconButton(
                onClick = { send() },
                enabled = !isSending && (draft.text.isNotBlank() || pendingAttachment != null),
                modifier = Modifier.padding(bottom = 4.dp),
            ) {
                if (isSending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                else Icon(Icons.Filled.ArrowUpward, contentDescription = stringResource(R.string.handoff_send))
            }
        }
    }

    blockCandidate?.let { candidate ->
        AlertDialog(
            onDismissRequest = { blockCandidate = null },
            title = { Text(stringResource(R.string.chat_block_user, candidate.name)) },
            text = { Text(stringResource(R.string.chat_block_confirm, candidate.name)) },
            confirmButton = {
                TextButton(onClick = {
                    blockCandidate = null
                    // In a direct conversation blocking ends it (the list no longer
                    // shows it); in a group the sender's messages just vanish.
                    val email = (target as? ChatTarget.Direct)?.user?.email
                    ChatBlockList.block(candidate.id, candidate.name, email)
                    if (target is ChatTarget.Direct) nav.back()
                }) { Text(stringResource(R.string.chat_block), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { blockCandidate = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    if (showTicketSearch) {
        TicketSearchSheet(
            onDismiss = { showTicketSearch = false },
            onSelect = { ticket ->
                showTicketSearch = false
                // Remove the trailing '#' that triggered the search.
                if (draft.text.endsWith("#")) {
                    val text = draft.text.dropLast(1)
                    draft = TextFieldValue(text, TextRange(text.length))
                }
                pendingTicket = ticket
            },
        )
    }
}

@Composable
private fun DaySeparator(date: LocalDate, theme: ChatTheme) {
    Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = Alignment.Center) {
        Text(chatDayLabel(date), color = theme.partnerText.copy(alpha = 0.75f), style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.clip(CircleShape).background(theme.partnerBubble.copy(alpha = 0.85f)).padding(horizontal = 10.dp, vertical = 3.dp))
    }
}

@Composable
private fun ComposerButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = CircleShape, color = glassColor(), modifier = Modifier.padding(bottom = 8.dp).size(40.dp)) {
        Box(contentAlignment = Alignment.Center) { Icon(icon, contentDescription = label, modifier = Modifier.size(22.dp)) }
    }
}

@Composable
private fun PendingChip(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, modifier: Modifier, onRemove: () -> Unit) {
    Surface(modifier = modifier, shape = CircleShape, color = glassColor()) {
        Row(Modifier.padding(start = 10.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, Modifier.size(16.dp))
            Text(text, Modifier.padding(horizontal = 6.dp).weight(1f, fill = false), style = MaterialTheme.typography.labelMedium,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            Icon(Icons.Filled.Cancel, contentDescription = stringResource(R.string.close),
                modifier = Modifier.size(24.dp).clip(CircleShape).clickable(onClick = onRemove).padding(3.dp))
        }
    }
}

/** Bolds @mentions of conversation members (and ourselves) in the body. */
private fun attributedBody(body: String, names: List<String>): AnnotatedString = buildAnnotatedString {
    append(body)
    for (name in names) {
        val needle = "@$name"
        var index = body.indexOf(needle)
        while (index >= 0) {
            addStyle(SpanStyle(fontWeight = FontWeight.Bold), index, index + needle.length)
            index = body.indexOf(needle, index + needle.length)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun MessageBubble(
    message: ChatMessage,
    isMine: Boolean,
    isGroup: Boolean,
    target: ChatTarget,
    theme: ChatTheme,
    mentionNames: List<String>,
    blockLabel: String,
    onOpenTicket: (Int) -> Unit,
    onDeleteForEveryone: () -> Unit,
    onDeleteForMe: () -> Unit,
    onReport: () -> Unit,
    onBlock: () -> Unit,
    onError: (String) -> Unit,
) {
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val isDeleted = message.deleted == true
    var menuOpen by remember { mutableStateOf(false) }
    val openMenu = {
        // A tombstone has no actions, as on iOS.
        if (!isDeleted) { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menuOpen = true }
    }
    val bubbleShape = RoundedCornerShape(14.dp)

    Box(Modifier.fillMaxWidth(), contentAlignment = if (isMine) Alignment.CenterEnd else Alignment.CenterStart) {
        Column(
            Modifier.widthIn(max = 320.dp).padding(start = if (isMine) 40.dp else 0.dp, end = if (isMine) 0.dp else 40.dp),
            horizontalAlignment = if (isMine) Alignment.End else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // Sender name for group messages from others.
            if (isGroup && !isMine && message.fromUserName != null) {
                Text(message.fromUserName, color = theme.metaText, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
            }

            Box {
                Column(
                    Modifier.combinedClickable(
                        interactionSource = remember { MutableInteractionSource() }, indication = null,
                        onClick = {}, onLongClick = openMenu,
                    ),
                    horizontalAlignment = if (isMine) Alignment.End else Alignment.Start,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    if (isDeleted) {
                        // Tombstone: neutral grey bubble, no ticket/attachment chips.
                        Text("🗑 " + stringResource(R.string.chat_message_deleted), fontStyle = FontStyle.Italic,
                            color = theme.partnerText.copy(alpha = 0.6f), style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.clip(bubbleShape).background(Color.Gray.copy(alpha = 0.25f)).padding(10.dp))
                    } else {
                        message.ticketId?.let { ticketId ->
                            Surface(onClick = { onOpenTicket(ticketId) }, shape = CircleShape, color = glassColor()) {
                                Row(Modifier.padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.ConfirmationNumber, null, Modifier.size(14.dp))
                                    Text(stringResource(R.string.chat_ticket_reference, message.ticketNumber ?: ticketId.toString()),
                                        Modifier.padding(start = 6.dp), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                                }
                            }
                        }
                        if (message.attachmentId != null) {
                            AttachmentView(message, target, onLongClick = openMenu, onError = onError)
                        }
                        if (message.body.isNotEmpty()) {
                            if (message.isUndecryptable) {
                                // No key for this message on this device (sent before the device existed).
                                Text(message.body, fontStyle = FontStyle.Italic,
                                    color = (if (isMine) theme.myText else theme.partnerText).copy(alpha = 0.75f),
                                    modifier = Modifier.clip(bubbleShape)
                                        .background((if (isMine) theme.myBubble else theme.partnerBubble).copy(alpha = 0.6f)).padding(10.dp))
                            } else {
                                Text(attributedBody(message.body, mentionNames), color = if (isMine) theme.myText else theme.partnerText,
                                    modifier = Modifier.clip(bubbleShape)
                                        .background(if (isMine) theme.myBubble else theme.partnerBubble).padding(10.dp))
                            }
                        }
                    }
                }

                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    if (message.body.isNotEmpty() && !message.isUndecryptable) {
                        DropdownMenuItem(
                            text = { Text(stringResource(android.R.string.copy)) },
                            leadingIcon = { Icon(Icons.Filled.ContentCopy, null) },
                            onClick = {
                                menuOpen = false
                                context.getSystemService(ClipboardManager::class.java)
                                    ?.setPrimaryClip(ClipData.newPlainText("", message.body))
                            },
                        )
                    }
                    if (isMine) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_delete_message), color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Filled.Delete, null, tint = MaterialTheme.colorScheme.error) },
                            onClick = { menuOpen = false; onDeleteForEveryone() },
                        )
                    } else {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_delete_for_me)) },
                            leadingIcon = { Icon(Icons.Filled.Delete, null) },
                            onClick = { menuOpen = false; onDeleteForMe() },
                        )
                        // Report objectionable content, block its author.
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_report_message)) },
                            leadingIcon = { Icon(Icons.Filled.Flag, null) },
                            onClick = { menuOpen = false; onReport() },
                        )
                        DropdownMenuItem(
                            text = { Text(blockLabel, color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Filled.Block, null, tint = MaterialTheme.colorScheme.error) },
                            onClick = { menuOpen = false; onBlock() },
                        )
                    }
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(
                    if (message.isEncrypted) Icons.Filled.Lock else Icons.Filled.LockOpen,
                    contentDescription = stringResource(if (message.isEncrypted) R.string.chat_encrypted_label else R.string.chat_unencrypted_label),
                    tint = if (message.isEncrypted) theme.metaText else Orange,
                    modifier = Modifier.size(11.dp),
                )
                if (!message.isEncrypted) {
                    Text(stringResource(R.string.chat_unencrypted_label), color = Orange, style = MaterialTheme.typography.labelSmall)
                }
                Text(message.createdAt.formattedTime(), color = theme.metaText, style = MaterialTheme.typography.labelSmall)
                if (isMine && !isDeleted) DeliveryTicks(message.deliveryStatus, theme.metaText)
            }
        }
    }
}

/**
 * An encrypted chat attachment: inline picture for images, a document chip
 * for other files. Tapping opens it in another app.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun AttachmentView(message: ChatMessage, target: ChatTarget, onLongClick: () -> Unit, onError: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val mimeType = message.attachmentMime ?: "application/octet-stream"
    var isOpening by remember { mutableStateOf(false) }

    val open: () -> Unit = {
        if (!isOpening) {
            isOpening = true
            scope.launch {
                try {
                    val file = ChatAttachmentStore.file(context, message, target)
                    if (!ChatAttachmentStore.open(context, file, mimeType)) onError(context.getString(R.string.no_app_for_file))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    onError(chatErrorText(context, e))
                } finally {
                    isOpening = false
                }
            }
        }
    }

    if (message.isImageAttachment) {
        var bitmap by remember(message.attachmentId) { mutableStateOf<Bitmap?>(ChatAttachmentStore.cachedThumbnail(message.attachmentId)) }
        var failed by remember(message.attachmentId) { mutableStateOf(false) }
        LaunchedEffect(message.attachmentId) {
            if (bitmap != null) return@LaunchedEffect
            try {
                bitmap = ChatAttachmentStore.thumbnail(context, message, target)
                if (bitmap == null) failed = true
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed = true
            }
        }
        val shape = RoundedCornerShape(14.dp)
        val image = bitmap
        if (image != null) {
            val height = (220f * image.height / image.width.coerceAtLeast(1)).coerceIn(60f, 260f)
            Image(
                image.asImageBitmap(),
                contentDescription = message.attachmentName,
                contentScale = ContentScale.Crop,
                modifier = Modifier.width(220.dp).height(height.dp).clip(shape)
                    .combinedClickable(onClick = open, onLongClick = onLongClick),
            )
        } else {
            Box(
                Modifier.width(220.dp).height(160.dp).clip(shape).background(Color.Gray.copy(alpha = 0.25f))
                    .combinedClickable(onClick = { if (failed) open() }, onLongClick = onLongClick),
                contentAlignment = Alignment.Center,
            ) {
                if (failed) Icon(Icons.Filled.BrokenImage, null, tint = Color.Gray)
                else CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp, color = Color.Gray)
            }
        }
    } else {
        Row(
            Modifier.clip(CircleShape).background(glassColor())
                .combinedClickable(onClick = open, onLongClick = onLongClick)
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (isOpening) CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
            else Icon(Icons.AutoMirrored.Filled.InsertDriveFile, null, Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurface)
            Text(message.attachmentName ?: stringResource(R.string.chat_attachment), Modifier.padding(start = 6.dp),
                color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** Search tickets and pick one to attach to the outgoing chat message. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TicketSearchSheet(onDismiss: () -> Unit, onSelect: (Ticket) -> Unit) {
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Ticket>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }
    var hasSearched by remember { mutableStateOf(false) }

    LaunchedEffect(query) {
        val trimmed = query.trim()
        if (trimmed.length < 2) return@LaunchedEffect
        delay(350)
        isSearching = true
        results = try {
            ZammadApi.searchTickets(trimmed)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
        hasSearched = true
        isSearching = false
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.85f).padding(horizontal = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.chat_search_ticket), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).padding(start = 4.dp))
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
            }
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                placeholder = { Text(stringResource(R.string.search_placeholder)) },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            )
            Box(Modifier.fillMaxWidth().weight(1f)) {
                LazyColumn(Modifier.fillMaxSize()) {
                    items(results, key = { it.id }) { ticket ->
                        Column(Modifier.fillMaxWidth().clickable { onSelect(ticket) }.padding(horizontal = 4.dp, vertical = 10.dp)) {
                            Text(ticket.title, style = MaterialTheme.typography.titleSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text("#${ticket.number}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                    }
                }
                if (isSearching) {
                    CircularProgressIndicator(Modifier.align(Alignment.TopCenter).padding(top = 32.dp))
                } else if (results.isEmpty() && hasSearched && query.isNotBlank()) {
                    Text(stringResource(R.string.no_search_results), Modifier.align(Alignment.TopCenter).padding(top = 32.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
