package com.baseonline.zammadmobile.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.webkit.MimeTypeMap
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.InsertDriveFile
import androidx.compose.material.icons.automirrored.filled.Reply
import androidx.compose.material.icons.automirrored.outlined.StickyNote2
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PictureAsPdf
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.DeleteForever
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.Attachment
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.TicketArticle
import com.baseonline.zammadmobile.data.TimeAccounting
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.data.formattedDateTime
import com.baseonline.zammadmobile.managers.DraftManager
import com.baseonline.zammadmobile.managers.ReadStatusManager
import com.baseonline.zammadmobile.managers.ReviewRequestManager
import com.baseonline.zammadmobile.managers.SLADeadline
import com.baseonline.zammadmobile.managers.SLAStatus
import com.baseonline.zammadmobile.managers.hasSLA
import com.baseonline.zammadmobile.managers.slaDeadlines
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.GlassCard
import com.baseonline.zammadmobile.ui.components.Pill
import com.baseonline.zammadmobile.ui.components.StyledSection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant

/**
 * The last article thread loaded per ticket. Navigating to the reply screen
 * disposes the detail screen; coming back (or opening the reply) can show the
 * thread at once from here while a fresh copy loads.
 */
internal object TicketArticleCache {
    private const val MAX_TICKETS = 20
    private val threads = LinkedHashMap<Int, List<TicketArticle>>()

    fun get(ticketId: Int): List<TicketArticle>? = threads[ticketId]

    fun put(ticketId: Int, articles: List<TicketArticle>) {
        threads.remove(ticketId)
        threads[ticketId] = articles
        while (threads.size > MAX_TICKETS) threads.remove(threads.keys.first())
    }
}

@Composable
fun TicketDetailScreen(vm: TicketViewModel, nav: Nav, ticketId: Int) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var ticket by remember { mutableStateOf(vm.cachedTicket(ticketId)) }
    var articles by remember { mutableStateOf(TicketArticleCache.get(ticketId).orEmpty()) }
    var timeAccountings by remember { mutableStateOf<List<TimeAccounting>>(emptyList()) }
    var isLoading by remember { mutableStateOf(true) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    // Whether this visit has been counted towards the review request; survives
    // the trip to the reply screen and back.
    var hasCountedAsOpened by rememberSaveable { mutableStateOf(false) }
    var hasMarkedRead by remember { mutableStateOf(false) }

    var isMenuOpen by remember { mutableStateOf(false) }
    var isConfirmingSpam by remember { mutableStateOf(false) }
    var isClosingAsSpam by remember { mutableStateOf(false) }
    var spamError by remember { mutableStateOf<String?>(null) }
    var picker by remember { mutableStateOf<TicketEditField?>(null) }
    /** The edit waiting for a pending time, if Zammad asked for one. */
    var pendingTimeFor by remember { mutableStateOf<Ticket?>(null) }
    var isSaving by remember { mutableStateOf(false) }

    var downloadingAttachmentId by remember { mutableStateOf<Int?>(null) }
    var attachmentError by remember { mutableStateOf<Pair<Int, String>?>(null) }
    val bodyStore = remember { TicketArticleBodyStore() }

    suspend fun loadDetails() {
        if (ticket == null) isLoading = true
        errorMessage = null
        try {
            coroutineScope {
                val ticketTask = async { ZammadApi.fetchTicket(ticketId) }
                val articlesTask = async { ZammadApi.fetchArticles(ticketId) }
                val timeTask = async { ZammadApi.gracefully(emptyList()) { ZammadApi.fetchTimeAccountings(ticketId) } }
                val loadedTicket = ticketTask.await()
                val loadedArticles = articlesTask.await()
                timeAccountings = timeTask.await()
                ticket = loadedTicket
                articles = loadedArticles
                TicketArticleCache.put(ticketId, loadedArticles)
            }
            // Count the ticket as opened once it has actually loaded, and only
            // once per visit: reloads after a reply or handoff do not count again.
            if (!hasCountedAsOpened) {
                hasCountedAsOpened = true
                ReviewRequestManager.recordTicketOpened()
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = e.message ?: e.toString()
        }
        isLoading = false
    }

    // Leaving for the reply/edit/handoff screens disposes this screen, so
    // coming back loads again by itself. The observer covers the other case:
    // the app returning from the background (browser, file viewer).
    var resumeCount by remember { mutableIntStateOf(0) }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        var sawFirstResume = false
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (sawFirstResume) resumeCount++ else sawFirstResume = true
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(ticketId, resumeCount) { loadDetails() }

    LaunchedEffect(ticket?.id) {
        val current = ticket
        if (current != null && !hasMarkedRead) {
            hasMarkedRead = true
            ReadStatusManager.markAsRead(current)
        }
    }

    /** Saves an inline edit; asks for a pending time when Zammad requires one. */
    fun saveChanges(updated: Ticket, pendingTime: Instant? = null) {
        if (isSaving) return
        isSaving = true
        scope.launch {
            try {
                val needsPendingTime = vm.updateTicket(updated, pendingTime)
                if (needsPendingTime) {
                    pendingTimeFor = updated
                } else {
                    ticket = updated
                    loadDetails()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                loadDetails()
                errorMessage = e.message ?: e.toString()
            } finally {
                isSaving = false
            }
        }
    }

    /** Tags the ticket as spam and closes it; it has then left the open queue, so leave the screen too. */
    fun closeAsSpam() {
        val current = ticket ?: return
        if (isClosingAsSpam) return
        isClosingAsSpam = true
        scope.launch {
            try {
                vm.closeAsSpam(current)
                nav.back()
            } catch (e: CancellationException) {
                throw e
            } catch (e: TicketViewModel.NoClosedStateException) {
                spamError = context.getString(R.string.close_as_spam_no_closed_state)
            } catch (e: Exception) {
                spamError = e.message ?: e.toString()
                loadDetails()
            } finally {
                isClosingAsSpam = false
            }
        }
    }

    fun withAttachment(attachment: Attachment, articleId: Int, share: Boolean) {
        if (downloadingAttachmentId != null) return
        downloadingAttachmentId = attachment.id
        attachmentError = null
        scope.launch {
            try {
                val file = vm.downloadAttachment(attachment, articleId, ticketId)
                if (!openOrShareFile(context, file, attachment, share)) {
                    attachmentError = articleId to context.getString(R.string.no_app_for_file)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                attachmentError = articleId to (e.message ?: e.toString())
            } finally {
                downloadingAttachmentId = null
            }
        }
    }

    val mostRecentArticleId = articles.maxByOrNull { it.created_at }?.id ?: 0
    val current = ticket

    AppScaffold(
        title = current?.title.orEmpty(),
        subtitle = current?.let { "#${it.number}" },
        onBack = { nav.back() },
        actions = {
            if (current != null) {
                IconButton(onClick = { nav.openHandoff(ticketId) }) {
                    Icon(Icons.Outlined.Group, contentDescription = stringResource(R.string.handoff_ticket))
                }
                IconButton(onClick = { nav.openEdit(ticketId) }) {
                    Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.edit_ticket))
                }
                IconButton(onClick = { nav.openReply(ticketId, false, mostRecentArticleId) }) {
                    Icon(Icons.AutoMirrored.Filled.Reply, contentDescription = stringResource(R.string.reply_to_ticket))
                }
                Box {
                    IconButton(onClick = { isMenuOpen = true }, enabled = !isClosingAsSpam) {
                        Icon(Icons.Filled.MoreVert, contentDescription = null)
                    }
                    DropdownMenu(expanded = isMenuOpen, onDismissRequest = { isMenuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.internal_note_toggle)) },
                            leadingIcon = { Icon(Icons.AutoMirrored.Outlined.StickyNote2, null) },
                            onClick = { isMenuOpen = false; nav.openReply(ticketId, true, 0) },
                        )
                        if (vm.isTimeAccountingEnabled) {
                            DropdownMenuItem(
                                text = { Text(stringResource(R.string.add_spent_time)) },
                                leadingIcon = { Icon(Icons.Outlined.Schedule, null) },
                                onClick = { isMenuOpen = false; nav.openTimeAccounting(ticketId) },
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.mark_unread)) },
                            leadingIcon = { Icon(Icons.Outlined.MarkEmailUnread, null) },
                            onClick = {
                                isMenuOpen = false
                                // Leave the ticket: staying would only mark it read again.
                                ReadStatusManager.markAsUnread(current)
                                nav.back()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.open_in_browser)) },
                            leadingIcon = { Icon(Icons.Outlined.OpenInBrowser, null) },
                            onClick = {
                                isMenuOpen = false
                                try {
                                    context.startActivity(Intent(Intent.ACTION_VIEW,
                                        Uri.parse(ZammadApi.webBaseUrl() + "/#ticket/zoom/$ticketId")))
                                } catch (e: Exception) {
                                    errorMessage = e.message ?: context.getString(R.string.no_app_for_file)
                                }
                            },
                        )
                        HorizontalDivider()
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.close_as_spam), color = MaterialTheme.colorScheme.error) },
                            leadingIcon = { Icon(Icons.Outlined.DeleteForever, null, tint = MaterialTheme.colorScheme.error) },
                            onClick = { isMenuOpen = false; isConfirmingSpam = true },
                        )
                    }
                }
            }
        },
    ) { padding ->
        if (current == null) {
            val message = errorMessage
            if (isLoading || message == null) {
                CenteredLoading(Modifier.padding(padding), stringResource(R.string.loading_ticket_details))
            } else {
                Box(Modifier.fillMaxSize().padding(padding).padding(16.dp), contentAlignment = Alignment.Center) {
                    GlassCard(contentPadding = PaddingValues(20.dp)) {
                        Text(message, color = MaterialTheme.colorScheme.error)
                        TextButton(onClick = { scope.launch { loadDetails() } },
                            modifier = Modifier.align(Alignment.CenterHorizontally)) {
                            Text(stringResource(R.string.try_again))
                        }
                    }
                }
            }
            return@AppScaffold
        }

        val sortedArticles = remember(articles) { articles.sortedByDescending { it.created_at } }
        val draft = DraftManager.draft(ticketId)

        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 16.dp, end = 16.dp,
                top = padding.calculateTopPadding() + 16.dp, bottom = padding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            errorMessage?.let { message ->
                item(key = "error") {
                    GlassCard(Modifier.fillMaxWidth(), contentPadding = PaddingValues(start = 16.dp, end = 4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(message, Modifier.weight(1f).padding(vertical = 12.dp),
                                color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
                            TextButton(onClick = { scope.launch { loadDetails() } }) {
                                Text(stringResource(R.string.try_again))
                            }
                        }
                    }
                }
            }

            if (draft != null) {
                item(key = "draft") {
                    GlassCard(Modifier.fillMaxWidth(),
                        onClick = { nav.openReply(ticketId, draft.isInternalNote, mostRecentArticleId) },
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Description, null)
                            Spacer(Modifier.width(10.dp))
                            Column(Modifier.weight(1f)) {
                                Text(stringResource(R.string.draft_indicator), fontWeight = FontWeight.SemiBold)
                                Text(Instant.ofEpochMilli(draft.updatedAt).formattedDateTime(),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            item(key = "details") {
                StyledSection(stringResource(R.string.details_section_header)) {
                    Text(current.title, Modifier.padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 4.dp),
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    DetailRow(stringResource(R.string.ticket_number), "#${current.number}")
                    RowDivider()
                    DetailRow(stringResource(R.string.customer), vm.userName(current.customer_id), enabled = !isSaving) {
                        picker = TicketEditField.CUSTOMER
                    }
                    vm.organizationName(current.organization_id)?.let { organization ->
                        RowDivider()
                        // Hardcoded: the shared strings have no "organization" key.
                        DetailRow(stringResource(R.string.organization), organization)
                    }
                    RowDivider()
                    val stateName = vm.stateName(current.state_id)
                    DetailRow(stringResource(R.string.status), vm.localizedStatusName(stateName),
                        valueColor = vm.colorForStatus(stateName), enabled = !isSaving) { picker = TicketEditField.STATE }
                    RowDivider()
                    val priorityName = vm.priorityName(current.priority_id)
                    DetailRow(stringResource(R.string.priority), vm.localizedPriorityName(priorityName),
                        valueColor = vm.colorForPriority(priorityName), enabled = !isSaving) { picker = TicketEditField.PRIORITY }
                    RowDivider()
                    DetailRow(stringResource(R.string.owner), ticketOwnerName(vm, current.owner_id), enabled = !isSaving) {
                        picker = TicketEditField.OWNER
                    }
                    if (vm.isTimeAccountingEnabled) {
                        RowDivider()
                        val total = timeAccountings.sumOf { it.time_unit.toDoubleOrNull() ?: 0.0 }
                        DetailRow(stringResource(R.string.time_spent), "$total ${stringResource(R.string.hours)}") {
                            nav.openTimeAccounting(ticketId)
                        }
                    }
                    RowDivider()
                    DetailRow(stringResource(R.string.created_at), current.created_at.formattedDateTime())
                }
            }

            if (current.hasSLA) {
                item(key = "sla") {
                    StyledSection(stringResource(R.string.sla)) {
                        if (SettingsManager.isPremium) {
                            current.slaDeadlines.forEachIndexed { index, deadline ->
                                if (index > 0) RowDivider()
                                SlaRow(deadline)
                            }
                        } else {
                            // The ticket has an SLA, but the deadlines are a
                            // Premium feature: say so, and offer the upgrade.
                            Row(
                                Modifier.fillMaxWidth().clickable { nav.openPremium() }
                                    .padding(horizontal = 16.dp, vertical = 14.dp),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                Icon(Icons.Filled.WorkspacePremium, null, tint = Color(0xFFFFC107))
                                Text(stringResource(R.string.sla_premium_required), Modifier.weight(1f),
                                    style = MaterialTheme.typography.bodyMedium)
                                Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }

            item(key = "history-header") {
                Row(Modifier.padding(start = 12.dp, end = 12.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.communication_history).uppercase(), Modifier.weight(1f),
                        style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (isLoading || (articles.isEmpty() && errorMessage == null && current.article_count > 0)) {
                        CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                    }
                }
            }

            items(sortedArticles, key = { it.id }) { article ->
                ArticleCard(
                    article = article,
                    ticketId = ticketId,
                    senderName = articleSenderName(vm, article),
                    bodyStore = bodyStore,
                    downloadingAttachmentId = downloadingAttachmentId,
                    attachmentError = attachmentError?.takeIf { it.first == article.id }?.second,
                    onOpenAttachment = { withAttachment(it, article.id, share = false) },
                    onShareAttachment = { withAttachment(it, article.id, share = true) },
                )
            }
        }

        when (picker) {
            TicketEditField.CUSTOMER -> TicketCustomerSearchDialog(vm,
                onSelect = { picker = null; if (it != current.customer_id) saveChanges(current.copy(customer_id = it)) },
                onDismiss = { picker = null })
            TicketEditField.STATE -> TicketOptionPickerDialog(
                stringResource(R.string.status), ticketStateOptions(vm), current.state_id,
                onSelect = { picker = null; if (it != current.state_id) saveChanges(current.copy(state_id = it)) },
                onDismiss = { picker = null })
            TicketEditField.PRIORITY -> TicketOptionPickerDialog(
                stringResource(R.string.priority), ticketPriorityOptions(vm), current.priority_id,
                onSelect = { picker = null; if (it != current.priority_id) saveChanges(current.copy(priority_id = it)) },
                onDismiss = { picker = null })
            TicketEditField.OWNER -> TicketOptionPickerDialog(
                stringResource(R.string.owner), ticketOwnerOptions(vm), current.owner_id,
                onSelect = { picker = null; if (it != current.owner_id) saveChanges(current.copy(owner_id = it)) },
                onDismiss = { picker = null })
            null -> {}
        }

        pendingTimeFor?.let { waiting ->
            TicketPendingTimeDialog(
                onConfirm = { pendingTimeFor = null; saveChanges(waiting, it) },
                // Cancelled: the edit was never saved, so show the server's state again.
                onDismiss = { pendingTimeFor = null; scope.launch { loadDetails() } },
            )
        }

        if (isConfirmingSpam) {
            AlertDialog(
                onDismissRequest = { isConfirmingSpam = false },
                title = { Text(stringResource(R.string.close_as_spam_confirm_title)) },
                text = { Text(stringResource(R.string.close_as_spam_confirm_message)) },
                confirmButton = {
                    TextButton(onClick = { isConfirmingSpam = false; closeAsSpam() }) {
                        Text(stringResource(R.string.close_as_spam), color = MaterialTheme.colorScheme.error)
                    }
                },
                dismissButton = {
                    TextButton(onClick = { isConfirmingSpam = false }) { Text(stringResource(R.string.cancel)) }
                },
            )
        }

        spamError?.let { message ->
            AlertDialog(
                onDismissRequest = { spamError = null },
                title = { Text(stringResource(R.string.close_as_spam_failed)) },
                text = { Text(message) },
                confirmButton = { TextButton(onClick = { spamError = null }) { Text(stringResource(R.string.ok)) } },
            )
        }
    }
}

/**
 * iOS shows the creating user's name. A customer who is not in the loaded
 * user list would come out as "Unassigned" that way, so fall back to the
 * article's own From line.
 */
private fun articleSenderName(vm: TicketViewModel, article: TicketArticle): String =
    if (vm.allUsers.any { it.id == article.created_by_id }) vm.userName(article.created_by_id)
    else article.from.ifBlank { vm.userName(article.created_by_id) }

@Composable
private fun RowDivider() =
    HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))

@Composable
private fun DetailRow(label: String, value: String, valueColor: Color? = null, enabled: Boolean = true,
                      onClick: (() -> Unit)? = null) {
    val base = Modifier.fillMaxWidth()
    Row(
        (if (onClick != null) base.clickable(enabled = enabled, onClick = onClick) else base)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.width(12.dp))
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
            if (valueColor != null) {
                Pill(value, valueColor)
            } else {
                Text(value, textAlign = TextAlign.End, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (onClick != null) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Filled.ChevronRight, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/** One SLA target: met (green check), overdue (red), or the deadline with the time left, coloured by how close it is. */
@Composable
private fun SlaRow(deadline: SLADeadline) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
        Text(stringResource(deadline.kind.titleRes), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val completedAt = deadline.completedAt
            val status = deadline.status()
            val due = deadline.deadline
            if (completedAt != null) {
                SlaLabel(Icons.Filled.CheckCircle, stringResource(R.string.sla_met), Color(0xFF43A047))
                SlaDate(completedAt)
            } else if (status != null && due != null) {
                SlaLabel(if (status is SLAStatus.Escalated) Icons.Filled.Warning else Icons.Filled.Schedule,
                    stringResource(status.textRes, status.shortText), status.color)
                SlaDate(due)
            }
        }
    }
}

@Composable
private fun SlaLabel(icon: ImageVector, text: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, null, Modifier.size(16.dp), tint = color)
        Text(text, color = color)
    }
}

@Composable
private fun SlaDate(date: Instant) {
    Text(date.formattedDateTime(), style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}

/**
 * One article as its own card: an opaque light card for HTML mail (which
 * brings its own colours and expects a white page, so the header on it is
 * dark-on-light too), the translucent card otherwise.
 */
@Composable
private fun ArticleCard(
    article: TicketArticle,
    ticketId: Int,
    senderName: String,
    bodyStore: TicketArticleBodyStore,
    downloadingAttachmentId: Int?,
    attachmentError: String?,
    onOpenAttachment: (Attachment) -> Unit,
    onShareAttachment: (Attachment) -> Unit,
) {
    val isHtml = article.isHTMLBody
    val isInternal = article.isInternal == true
    val primary = if (isHtml) Color(0xFF1C1C1E) else MaterialTheme.colorScheme.onSurface
    val secondary = if (isHtml) Color(0xFF5A5A60) else MaterialTheme.colorScheme.onSurfaceVariant
    val noteColor = Color(0xFFFF9500)

    val content: @Composable () -> Unit = {
        CompositionLocalProvider(LocalContentColor provides primary) {
            Row {
                Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(senderName, Modifier.weight(1f), fontWeight = FontWeight.SemiBold, maxLines = 1,
                            overflow = TextOverflow.Ellipsis)
                        Text(article.created_at.formattedDateTime(), style = MaterialTheme.typography.labelSmall, color = secondary)
                    }
                    if (isInternal) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Icon(Icons.Filled.Lock, null, Modifier.size(12.dp), tint = noteColor)
                            Pill(stringResource(R.string.internal_note_toggle), noteColor)
                        }
                    }
                    TicketArticleBody(article, ticketId, bodyStore)

                    val attachments = article.attachments.orEmpty().filter { !it.isInline }
                    if (attachments.isNotEmpty()) {
                        Text(stringResource(R.string.attachments), style = MaterialTheme.typography.labelSmall, color = secondary)
                        attachments.forEach { attachment ->
                            AttachmentRow(
                                attachment = attachment,
                                isDownloading = downloadingAttachmentId == attachment.id,
                                enabled = downloadingAttachmentId == null,
                                primary = primary, secondary = secondary,
                                onOpen = { onOpenAttachment(attachment) },
                                onShare = { onShareAttachment(attachment) },
                            )
                        }
                        if (attachmentError != null) {
                            Text(attachmentError, style = MaterialTheme.typography.labelSmall, color = Color(0xFFD32F2F))
                        }
                    }
                }
            }
        }
    }

    // Internal notes carry a coloured outline so they stand apart from mail.
    val shape = RoundedCornerShape(16.dp)
    val outline = if (isInternal) Modifier.border(1.5.dp, noteColor, shape) else Modifier
    if (isHtml) {
        Surface(Modifier.fillMaxWidth().then(outline), shape = shape, color = Color.White, content = content)
    } else {
        GlassCard(Modifier.fillMaxWidth().then(outline), shape = shape) { content() }
    }
}

@Composable
private fun AttachmentRow(
    attachment: Attachment,
    isDownloading: Boolean,
    enabled: Boolean,
    primary: Color,
    secondary: Color,
    onOpen: () -> Unit,
    onShare: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .background(Color.Gray.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
            .clickable(enabled = enabled, onClick = onOpen)
            .padding(start = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) {
            if (isDownloading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = primary)
            else Icon(attachmentIcon(attachment), null, tint = primary)
        }
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f).padding(vertical = 6.dp)) {
            Text(attachment.filename, style = MaterialTheme.typography.bodyMedium, color = primary, maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis)
            if (attachment.sizeFormatted.isNotEmpty()) {
                Text(attachment.sizeFormatted, style = MaterialTheme.typography.labelSmall, color = secondary)
            }
        }
        IconButton(onClick = onShare, enabled = enabled) {
            Icon(Icons.Outlined.Share, contentDescription = null, tint = secondary, modifier = Modifier.size(20.dp))
        }
        Icon(Icons.Outlined.FileDownload, null, Modifier.padding(end = 10.dp).size(20.dp), tint = secondary)
    }
}

private fun attachmentMimeType(attachment: Attachment): String {
    val declared = attachment.resolvedMimeType
    if (declared != "application/octet-stream") return declared
    val extension = attachment.filename.substringAfterLast('.', "").lowercase()
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: declared
}

private fun attachmentIcon(attachment: Attachment): ImageVector {
    val mime = attachmentMimeType(attachment)
    return when {
        mime.startsWith("image/") -> Icons.Filled.Image
        mime.startsWith("video/") -> Icons.Filled.Movie
        mime.startsWith("audio/") -> Icons.Filled.MusicNote
        mime == "application/pdf" -> Icons.Filled.PictureAsPdf
        mime.startsWith("text/") -> Icons.Filled.Description
        else -> Icons.AutoMirrored.Filled.InsertDriveFile
    }
}

/** Hands a downloaded attachment to another app. False when nothing on the device can take it. */
private fun openOrShareFile(context: Context, file: File, attachment: Attachment, share: Boolean): Boolean {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val mime = attachmentMimeType(attachment)
    val intent = if (share) {
        Intent.createChooser(
            Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .apply { clipData = android.content.ClipData.newRawUri(attachment.filename, uri) },
            null,
        )
    } else {
        Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    return try {
        context.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }
}
