package com.baseonline.zammadmobile.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ExitToApp
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.LockOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.SmsFailed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.chat.ChatBlockList
import com.baseonline.zammadmobile.chat.ChatConversation
import com.baseonline.zammadmobile.chat.ChatDirectory
import com.baseonline.zammadmobile.chat.ChatGroup
import com.baseonline.zammadmobile.chat.ChatMessage
import com.baseonline.zammadmobile.chat.ChatReporter
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.chat.ChatTarget
import com.baseonline.zammadmobile.chat.ChatUser
import com.baseonline.zammadmobile.data.formattedDate
import com.baseonline.zammadmobile.data.formattedTime
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.StyledSection
import com.baseonline.zammadmobile.ui.components.glassColor
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId

/** How often the conversation list refreshes while it is on screen. */
private const val LIST_REFRESH_MS = 60_000L

/**
 * Standalone chat: the direct and group conversations with other engineers on
 * the same Zammad instance, delivered via the notification relay.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatListScreen(vm: TicketViewModel, nav: Nav) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current
    val snackbar = remember { SnackbarHostState() }

    val conversations = ChatDirectory.conversations
    val engineers = ChatDirectory.engineers

    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var showNewChat by remember { mutableStateOf(false) }
    var showNoEngineers by remember { mutableStateOf(false) }
    var showNewGroup by remember { mutableStateOf(false) }
    var conversationToDelete by remember { mutableStateOf<ChatConversation?>(null) }
    var partnerToBlock by remember { mutableStateOf<ChatUser?>(null) }
    var infoMessage by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        errorMessage = null
        try {
            ensureChatRegistered(vm)
            ChatDirectory.refresh()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = chatErrorText(context, e)
        }
        isLoading = false
    }

    // Load when the list comes on screen (also when returning from a
    // conversation), then keep previews and unread badges fresh while visible.
    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            load()
            while (true) {
                delay(LIST_REFRESH_MS)
                try { ChatDirectory.refreshConversations() } catch (e: CancellationException) { throw e } catch (e: Exception) { }
            }
        }
    }

    // With conversations on screen an error has no place in the layout; show it briefly.
    LaunchedEffect(errorMessage) {
        val message = errorMessage
        if (message != null && ChatDirectory.conversations.isNotEmpty()) snackbar.showSnackbar(message)
    }

    /** A member (non-creator) leaves a group; everything else is a full delete. */
    fun isLeavingGroup(conversation: ChatConversation): Boolean {
        val group = conversation.group ?: return false
        return group.creatorId != ChatService.myChatUserId
    }

    /** Prefers the full group record (with members) over the slim one in the summary. */
    fun resolvedTarget(conversation: ChatConversation): ChatTarget? {
        val group = conversation.group ?: return conversation.target
        return ChatTarget.Group(ChatDirectory.groups.firstOrNull { it.id == group.id } ?: group)
    }

    fun delete(conversation: ChatConversation) {
        val target = resolvedTarget(conversation) ?: return
        scope.launch {
            try {
                // Also clears the on-device history of this conversation.
                ChatService.deleteConversation(target)
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = chatErrorText(context, e)
            }
        }
    }

    AppScaffold(
        title = stringResource(R.string.chat),
        onBack = { nav.back() },
        actions = {
            IconButton(onClick = { if (engineers.isEmpty()) showNoEngineers = true else showNewChat = true }) {
                Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.chat_new_message))
            }
        },
        snackbarHostState = snackbar,
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = { scope.launch { isRefreshing = true; load(); isRefreshing = false } },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            when {
                isLoading && conversations.isEmpty() -> CenteredLoading()
                conversations.isEmpty() -> {
                    // Scrollable so pull-to-refresh also works on the empty states.
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                        verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                        val error = errorMessage
                        if (error != null) {
                            ChatStateCard(Icons.Outlined.SmsFailed, error, actionLabel = stringResource(R.string.try_again),
                                onAction = { scope.launch { isLoading = true; load() } })
                        } else {
                            ChatStateCard(Icons.Filled.Forum, stringResource(R.string.chat_no_conversations))
                        }
                    }
                }
                else -> LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(conversations, key = { it.id }) { conversation ->
                        ConversationRow(
                            conversation = conversation,
                            deleteLabel = stringResource(if (isLeavingGroup(conversation)) R.string.chat_leave_group else R.string.chat_delete_chat),
                            isLeaving = isLeavingGroup(conversation),
                            onOpen = { resolvedTarget(conversation)?.let { nav.openConversation(it.id) } },
                            onDelete = { conversationToDelete = conversation },
                            onBlock = { partnerToBlock = it },
                            onReport = { partner ->
                                if (!ChatReporter.reportUser(context, partner, vm.currentUser?.fullname)) {
                                    infoMessage = context.getString(R.string.chat_report_mail_unavailable, ChatReporter.ADDRESS)
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    if (showNewChat) {
        NewChatSheet(
            engineers = engineers,
            onDismiss = { showNewChat = false },
            onPick = { engineer -> showNewChat = false; nav.openConversation(ChatTarget.Direct(engineer).id) },
            onNewGroup = { showNewChat = false; showNewGroup = true },
        )
    }

    if (showNewGroup) {
        NewGroupSheet(
            engineers = engineers,
            onDismiss = { showNewGroup = false },
            onCreated = { group ->
                ChatDirectory.addGroup(group)
                showNewGroup = false
                nav.openConversation(ChatTarget.Group(group).id)
            },
        )
    }

    if (showNoEngineers) {
        AlertDialog(
            onDismissRequest = { showNoEngineers = false },
            title = { Text(stringResource(R.string.chat)) },
            text = { Text(stringResource(R.string.chat_no_engineers)) },
            confirmButton = { TextButton(onClick = { showNoEngineers = false }) { Text(stringResource(R.string.ok)) } },
        )
    }

    conversationToDelete?.let { conversation ->
        val leaving = isLeavingGroup(conversation)
        val label = stringResource(if (leaving) R.string.chat_leave_group else R.string.chat_delete_chat)
        AlertDialog(
            onDismissRequest = { conversationToDelete = null },
            title = { Text(label) },
            text = { Text(stringResource(if (leaving) R.string.chat_leave_group_confirm else R.string.chat_delete_chat_confirm)) },
            confirmButton = {
                TextButton(onClick = { conversationToDelete = null; delete(conversation) }) {
                    Text(label, color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { conversationToDelete = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    partnerToBlock?.let { partner ->
        AlertDialog(
            onDismissRequest = { partnerToBlock = null },
            title = { Text(stringResource(R.string.chat_block_user, partner.name)) },
            text = { Text(stringResource(R.string.chat_block_confirm, partner.name)) },
            confirmButton = {
                TextButton(onClick = {
                    partnerToBlock = null
                    ChatBlockList.block(partner)
                    scope.launch { load() }
                }) { Text(stringResource(R.string.chat_block), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { partnerToBlock = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }

    infoMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { infoMessage = null },
            title = { Text(stringResource(R.string.chat)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { infoMessage = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

private fun previewText(message: ChatMessage, attachmentLabel: String): String = when {
    message.attachmentId != null && message.body.isEmpty() -> "📎 ${message.attachmentName ?: attachmentLabel}"
    message.fromUserName != null && message.groupId != null -> "${message.fromUserName}: ${message.body}"
    else -> message.body
}

/** One conversation on a glass card; tap opens it, long-press or ⋮ shows the actions. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConversationRow(
    conversation: ChatConversation,
    deleteLabel: String,
    isLeaving: Boolean,
    onOpen: () -> Unit,
    onDelete: () -> Unit,
    onBlock: (ChatUser) -> Unit,
    onReport: (ChatUser) -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(12.dp)
    val last = conversation.lastMessage

    Surface(
        modifier = Modifier.fillMaxWidth().clip(shape).combinedClickable(
            onClick = onOpen,
            onLongClick = { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menuOpen = true },
        ),
        shape = shape,
        color = glassColor(),
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)),
    ) {
        Row(Modifier.padding(start = 12.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            ChatAvatar(isGroup = conversation.group != null)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(conversation.partner?.name ?: conversation.group?.name ?: "",
                    style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (last != null) {
                    Text(previewText(last, stringResource(R.string.chat_attachment)),
                        style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            Spacer(Modifier.width(8.dp))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                if (last != null) {
                    val zone = ZoneId.systemDefault()
                    val isToday = last.createdAt.atZone(zone).toLocalDate() == LocalDate.now(zone)
                    Text(if (isToday) last.createdAt.formattedTime() else last.createdAt.formattedDate(),
                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (conversation.unreadCount > 0) {
                    Surface(shape = CircleShape, color = Color(0xFFE53935)) {
                        Text("${conversation.unreadCount}", Modifier.padding(horizontal = 7.dp, vertical = 2.dp),
                            color = Color.White, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                    }
                }
            }
            Box {
                IconButton(onClick = { menuOpen = true }) {
                    Icon(Icons.Filled.MoreVert, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    val partner = conversation.partner
                    if (partner != null) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.chat_block)) },
                            leadingIcon = { Icon(Icons.Filled.Block, null) },
                            onClick = { menuOpen = false; onBlock(partner) },
                        )
                        DropdownMenuItem(
                            // No resource key for reporting a colleague (iOS only reports messages).
                            text = { Text(stringResource(R.string.report)) },
                            leadingIcon = { Icon(Icons.Filled.Flag, null) },
                            onClick = { menuOpen = false; onReport(partner) },
                        )
                    }
                    DropdownMenuItem(
                        text = { Text(deleteLabel, color = MaterialTheme.colorScheme.error) },
                        leadingIcon = {
                            Icon(if (isLeaving) Icons.AutoMirrored.Filled.ExitToApp else Icons.Filled.Delete, null,
                                tint = MaterialTheme.colorScheme.error)
                        },
                        onClick = { menuOpen = false; onDelete() },
                    )
                }
            }
        }
    }
}

/** Pick a colleague for a direct chat, or start a new group. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewChatSheet(
    engineers: List<ChatUser>,
    onDismiss: () -> Unit,
    onPick: (ChatUser) -> Unit,
    onNewGroup: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text(stringResource(R.string.chat_new_message), style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        LazyColumn(Modifier.fillMaxWidth().navigationBarsPadding()) {
            items(engineers, key = { it.id }) { engineer ->
                Row(Modifier.fillMaxWidth().clickable { onPick(engineer) }.padding(horizontal = 20.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    ChatAvatar(isGroup = false, size = 36.dp)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(engineer.name, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (!engineer.email.isNullOrBlank()) {
                            Text(engineer.email, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    // No device key published yet: the conversation opens, sending is refused.
                    if (!engineer.canReceiveEncrypted) {
                        Icon(Icons.Filled.LockOpen, contentDescription = stringResource(R.string.chat_unencrypted_label),
                            tint = Color(0xFFFF9800), modifier = Modifier.size(18.dp))
                    }
                }
            }
            item {
                HorizontalDivider(Modifier.padding(vertical = 4.dp))
                Row(Modifier.fillMaxWidth().clickable(onClick = onNewGroup).padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Groups, null, Modifier.size(36.dp).padding(4.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(12.dp))
                    Text(stringResource(R.string.chat_new_group), style = MaterialTheme.typography.bodyLarge)
                }
            }
        }
    }
}

/**
 * Create a group chat: name it and pick members. Members without a published
 * encryption key can't be added (the group key must be wrapped for everyone).
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewGroupSheet(
    engineers: List<ChatUser>,
    onDismiss: () -> Unit,
    onCreated: (ChatGroup) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val selectable = remember(engineers) { engineers.filter { it.canReceiveEncrypted } }
    var name by rememberSaveable { mutableStateOf("") }
    var selected by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var isCreating by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding()
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.chat_new_group).trimEnd('…', '.'), style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f).padding(start = 4.dp))
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
            }

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(stringResource(R.string.chat_group_name)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            StyledSection(stringResource(R.string.chat_group_members), footer = stringResource(R.string.chat_group_encryption_footer)) {
                selectable.forEachIndexed { index, engineer ->
                    if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                    val isSelected = engineer.id in selected
                    Row(
                        Modifier.fillMaxWidth()
                            .clickable { selected = if (isSelected) selected - engineer.id else selected + engineer.id }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(engineer.name, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (isSelected) Icon(Icons.Filled.Check, null, tint = MaterialTheme.colorScheme.primary)
                    }
                }
            }

            errorMessage?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.padding(horizontal = 4.dp))
            }

            Button(
                onClick = {
                    isCreating = true
                    errorMessage = null
                    scope.launch {
                        try {
                            // The service adds us (and each of our own devices) to the group itself.
                            val members = selectable.filter { it.id in selected }
                            onCreated(ChatService.createGroup(name.trim(), members))
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Exception) {
                            errorMessage = chatErrorText(context, e)
                        }
                        isCreating = false
                    }
                },
                enabled = !isCreating && name.isNotBlank() && selected.isNotEmpty(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isCreating) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(R.string.chat_create_group))
            }
        }
    }
}
