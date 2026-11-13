package com.baseonline.zammadmobile.ui.screens

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.ConfirmationNumber
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.MarkEmailRead
import androidx.compose.material.icons.outlined.MarkEmailUnread
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketFilter
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.data.ApiException
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.managers.AdBanner
import com.baseonline.zammadmobile.managers.DeepLinkManager
import com.baseonline.zammadmobile.managers.InterstitialAdManager
import com.baseonline.zammadmobile.managers.PremiumPromptManager
import com.baseonline.zammadmobile.managers.ReadStatusManager
import com.baseonline.zammadmobile.managers.ReviewRequestManager
import com.baseonline.zammadmobile.managers.showsAds
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.GlassCard
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** A banner sits between every [TICKETS_PER_AD] tickets, as on iOS. */
private const val TICKETS_PER_AD = 10

/** A ticket, or an ad slot between two groups of tickets. */
private sealed class ListEntry {
    abstract val key: String
    data class TicketEntry(val ticket: Ticket) : ListEntry() { override val key get() = "ticket-${ticket.id}" }
    data class AdEntry(val slot: Int) : ListEntry() { override val key get() = "ad-$slot" }
}

/**
 * The home screen, the counterpart of the iOS `TicketListContainerView`:
 * filtered ticket list with search, pull to refresh, read/unread and spam
 * actions, ads for non-Premium users, and the way into chat, settings and a
 * new ticket.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TicketListScreen(vm: TicketViewModel, nav: Nav) {
    val activity = LocalActivity.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val keyboard = LocalSoftwareKeyboardController.current

    var searchText by rememberSaveable { mutableStateOf("") }
    var isSearchActive by rememberSaveable { mutableStateOf(false) }
    var isFilterMenuOpen by remember { mutableStateOf(false) }
    var isPullRefreshing by remember { mutableStateOf(false) }
    var ticketPendingSpam by remember { mutableStateOf<Ticket?>(null) }
    var spamError by remember { mutableStateOf<String?>(null) }
    // Set when a ticket is opened from the list; read when the list comes back.
    var didOpenTicket by rememberSaveable { mutableStateOf(false) }

    val isPremium = SettingsManager.isPremium
    val ads = showsAds
    val tickets = vm.displayTickets

    // Runs when the list becomes visible: first composition, coming back from
    // another screen, and the app returning to the foreground.
    LifecycleEventEffect(Lifecycle.Event.ON_START) {
        // A pending notification ticket loads the data itself (AppRoot).
        if (DeepLinkManager.pendingTicketID == null) {
            scope.launch {
                if (vm.currentUser == null) vm.refreshAllData()
                // Quiet reload of the current filter; never on top of a full
                // load, which it would cancel.
                else if (!vm.isLoading) vm.applyFilter(vm.activeFilter)
            }
        }
        scope.launch {
            try { ChatService.refreshUnreadCount() } catch (e: CancellationException) { throw e } catch (e: Exception) { }
        }
    }

    // Leaving a ticket is the moment to ask for a review, if enough tickets
    // have been read, or failing that to suggest Premium. Never both at once,
    // and a moment after the transition.
    LaunchedEffect(Unit) {
        if (!didOpenTicket) return@LaunchedEffect
        didOpenTicket = false
        delay(1000)
        if (ReviewRequestManager.consumeRequestIfEarned()) {
            activity?.let { ReviewRequestManager.launch(it) }
        } else if (!SettingsManager.isPremium && PremiumPromptManager.consumePromptIfDue()) {
            nav.openPremium()
        }
    }

    // The open itself is counted by TicketDetailScreen once the ticket has
    // loaded (ReviewRequestManager.recordTicketOpened), as on iOS; counting it
    // here too would count every ticket twice.
    fun openTicket(ticket: Ticket) {
        didOpenTicket = true
        nav.openTicket(ticket.id)
    }

    // Settings sits behind a full-screen interstitial for non-Premium users;
    // the manager calls back immediately when no ad is ready.
    fun openSettings() {
        if (ads && activity != null) InterstitialAdManager.present(activity) { nav.openSettings() }
        else nav.openSettings()
    }

    fun closeSearch() {
        searchText = ""
        vm.clearSearch()
        isSearchActive = false
        keyboard?.hide()
    }

    fun toggleRead(ticket: Ticket) {
        if (ReadStatusManager.isUnread(ticket, vm.currentUser)) ReadStatusManager.markAsRead(ticket)
        else ReadStatusManager.markAsUnread(ticket)
    }

    val entries = remember(tickets, ads) {
        if (!ads) tickets.map { ListEntry.TicketEntry(it) }
        else buildList<ListEntry> {
            tickets.forEachIndexed { index, ticket ->
                add(ListEntry.TicketEntry(ticket))
                val position = index + 1
                // Strictly between tickets: a list of exactly ten does not end on an ad.
                if (position % TICKETS_PER_AD == 0 && position < tickets.size) add(ListEntry.AdEntry(position / TICKETS_PER_AD))
            }
        }
    }

    val filter = vm.activeFilter
    val title = filter.labelRes?.let { stringResource(it) }
        ?: vm.localizedStatusName((filter as TicketFilter.ByStatus).name)
    val showEscalatedBadge = isPremium && vm.escalatedCount > 0
    val escalatedLabel = stringResource(R.string.filter_escalated)
    val chatLabel = stringResource(R.string.chat)

    AppScaffold(
        title = title,
        actions = {
            IconButton(onClick = { nav.openChatList() }) {
                DotBadge(ChatService.totalUnread > 0) {
                    Icon(Icons.AutoMirrored.Outlined.Chat,
                        contentDescription = if (ChatService.totalUnread > 0) "$chatLabel (${ChatService.totalUnread})" else chatLabel)
                }
            }
            IconButton(onClick = { if (isSearchActive) closeSearch() else isSearchActive = true }) {
                Icon(Icons.Outlined.Search, contentDescription = stringResource(R.string.search))
            }
            Box {
                IconButton(onClick = { isFilterMenuOpen = true }) {
                    DotBadge(showEscalatedBadge) {
                        Icon(Icons.Outlined.FilterList,
                            contentDescription = if (showEscalatedBadge) "$escalatedLabel (${vm.escalatedCount})"
                            else stringResource(R.string.filter_by_status))
                    }
                }
                DropdownMenu(expanded = isFilterMenuOpen, onDismissRequest = { isFilterMenuOpen = false }) {
                    fun apply(target: TicketFilter) {
                        isFilterMenuOpen = false
                        scope.launch { vm.applyFilter(target) }
                    }
                    DropdownMenuItem(text = { Text(stringResource(R.string.my_assigned_tickets)) },
                        onClick = { apply(TicketFilter.MyTickets) })
                    DropdownMenuItem(text = { Text(stringResource(R.string.unassigned_tickets)) },
                        onClick = { apply(TicketFilter.Unassigned) })
                    DropdownMenuItem(text = { Text(stringResource(R.string.all_open_tickets)) },
                        onClick = { apply(TicketFilter.AllOpen) })
                    // SLA is Premium: the filter shows for everyone, with a
                    // crown and the Premium screen for non-Premium users.
                    DropdownMenuItem(
                        text = {
                            Text(if (isPremium && vm.escalatedCount > 0) "$escalatedLabel (${vm.escalatedCount})" else escalatedLabel)
                        },
                        leadingIcon = if (isPremium) null else {
                            { Icon(Icons.Filled.WorkspacePremium, contentDescription = null) }
                        },
                        onClick = {
                            if (isPremium) apply(TicketFilter.Escalated)
                            else { isFilterMenuOpen = false; nav.openPremium() }
                        },
                    )
                    if (vm.ticketStates.isNotEmpty()) {
                        HorizontalDivider()
                        Text(stringResource(R.string.filter_by_status),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp))
                        vm.ticketStates.forEach { state ->
                            DropdownMenuItem(text = { Text(vm.localizedStatusName(state.name)) },
                                onClick = { apply(TicketFilter.ByStatus(state.id, state.name)) })
                        }
                    }
                }
            }
            IconButton(onClick = { openSettings() }) {
                Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.settings))
            }
        },
        // Mounted whenever ads are allowed; zero-height until an ad has loaded.
        bottomBar = { Box(Modifier.navigationBarsPadding()) { AdBanner() } },
        floatingActionButton = {
            FloatingActionButton(onClick = { nav.openCreateTicket() }) {
                Icon(Icons.Filled.Add, contentDescription = stringResource(R.string.new_ticket))
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            // Tablets and unfolded foldables: one centred column, not edge to edge.
            Column(Modifier.widthIn(max = 720.dp).fillMaxSize()) {
                if (isSearchActive) {
                    val focus = remember { FocusRequester() }
                    LaunchedEffect(Unit) { focus.requestFocus() }
                    GlassCard(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), cornerRadius = 12.dp) {
                        TextField(
                            value = searchText,
                            onValueChange = {
                                searchText = it
                                if (it.isEmpty()) vm.clearSearch()
                            },
                            modifier = Modifier.fillMaxWidth().focusRequester(focus),
                            placeholder = { Text(stringResource(R.string.search_placeholder)) },
                            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                            trailingIcon = {
                                Row {
                                    if (searchText.isNotEmpty()) {
                                        IconButton(onClick = { searchText = ""; vm.clearSearch() }) {
                                            Icon(Icons.Filled.Cancel, contentDescription = null)
                                        }
                                    }
                                    IconButton(onClick = { closeSearch() }) {
                                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close))
                                    }
                                }
                            },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                            keyboardActions = KeyboardActions(onSearch = {
                                keyboard?.hide()
                                scope.launch { vm.performSearch(searchText) }
                            }),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = Color.Transparent,
                                unfocusedContainerColor = Color.Transparent,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                            ),
                        )
                    }
                }

                PullToRefreshBox(
                    isRefreshing = isPullRefreshing,
                    onRefresh = {
                        scope.launch {
                            isPullRefreshing = true
                            try { vm.refreshAllData() } finally { isPullRefreshing = false }
                        }
                    },
                    modifier = Modifier.fillMaxSize(),
                ) {
                    LazyColumn(
                        Modifier.fillMaxSize(),
                        // Room at the bottom so the last row clears the create button.
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 88.dp),
                    ) {
                        items(entries, key = { it.key }, contentType = { it::class }) { entry ->
                            when (entry) {
                                is ListEntry.TicketEntry -> TicketListItem(
                                    ticket = entry.ticket,
                                    vm = vm,
                                    onOpen = { openTicket(entry.ticket) },
                                    onToggleRead = { toggleRead(entry.ticket) },
                                    onSpam = { ticketPendingSpam = entry.ticket },
                                )
                                // Collapses to nothing until an ad has arrived.
                                is ListEntry.AdEntry -> AdBanner(Modifier.padding(vertical = 8.dp))
                            }
                        }
                    }

                    StatusOverlay(
                        vm = vm,
                        isPullRefreshing = isPullRefreshing,
                        isSearching = searchText.isNotEmpty(),
                        onOpenSettings = { nav.openSettings() },
                        onRetry = { scope.launch { vm.refreshAllData() } },
                    )
                }
            }
        }
    }

    ticketPendingSpam?.let { ticket ->
        AlertDialog(
            onDismissRequest = { ticketPendingSpam = null },
            title = { Text(stringResource(R.string.close_as_spam_confirm_title)) },
            text = { Text("#${ticket.number} · ${ticket.title}\n${stringResource(R.string.close_as_spam_confirm_message)}") },
            confirmButton = {
                TextButton(onClick = {
                    ticketPendingSpam = null
                    scope.launch {
                        try {
                            vm.closeAsSpam(ticket)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: TicketViewModel.NoClosedStateException) {
                            spamError = context.getString(R.string.close_as_spam_no_closed_state)
                        } catch (e: Exception) {
                            spamError = e.message ?: e.toString()
                        }
                    }
                }) { Text(stringResource(R.string.close_as_spam), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { ticketPendingSpam = null }) { Text(stringResource(R.string.cancel)) } },
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

/**
 * A ticket row with its actions: swipe right to toggle read/unread, swipe left
 * to close as spam (after confirmation), long press for the same as a menu.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TicketListItem(
    ticket: Ticket,
    vm: TicketViewModel,
    onOpen: () -> Unit,
    onToggleRead: () -> Unit,
    onSpam: () -> Unit,
) {
    @Suppress("UNUSED_VARIABLE")
    val readVersion = ReadStatusManager.version
    val isUnread = ReadStatusManager.isUnread(ticket, vm.currentUser)
    val currentToggleRead by rememberUpdatedState(onToggleRead)
    val currentSpam by rememberUpdatedState(onSpam)
    var isMenuOpen by remember { mutableStateOf(false) }

    // Neither swipe dismisses the row: the action runs and the row snaps back.
    val swipeState = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        when (value) {
            SwipeToDismissBoxValue.StartToEnd -> currentToggleRead()
            SwipeToDismissBoxValue.EndToStart -> currentSpam()
            SwipeToDismissBoxValue.Settled -> { }
        }
        false
    })

    val readLabel = stringResource(if (isUnread) R.string.mark_read else R.string.mark_unread)
    val readIcon = if (isUnread) Icons.Outlined.MarkEmailRead else Icons.Outlined.MarkEmailUnread

    Box(Modifier.padding(vertical = 8.dp)) {
        SwipeToDismissBox(
            state = swipeState,
            backgroundContent = {
                when (swipeState.dismissDirection) {
                    SwipeToDismissBoxValue.StartToEnd -> SwipeBackground(
                        readLabel, readIcon, if (isUnread) Color(0xFF007AFF) else Color(0xFFFF9500), Alignment.CenterStart)
                    SwipeToDismissBoxValue.EndToStart -> SwipeBackground(
                        stringResource(R.string.spam), Icons.Outlined.Delete, Color(0xFFE53935), Alignment.CenterEnd)
                    SwipeToDismissBoxValue.Settled -> { }
                }
            },
        ) {
            TicketListRow(ticket, vm, onClick = onOpen, onLongClick = { isMenuOpen = true })
        }
        DropdownMenu(expanded = isMenuOpen, onDismissRequest = { isMenuOpen = false }) {
            DropdownMenuItem(
                text = { Text(readLabel) },
                leadingIcon = { Icon(readIcon, contentDescription = null) },
                onClick = { isMenuOpen = false; onToggleRead() },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.close_as_spam)) },
                leadingIcon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                onClick = { isMenuOpen = false; onSpam() },
            )
        }
    }
}

@Composable
private fun SwipeBackground(label: String, icon: ImageVector, color: Color, alignment: Alignment) {
    Box(
        Modifier.fillMaxSize().clip(RoundedCornerShape(12.dp)).background(color).padding(horizontal = 20.dp),
        contentAlignment = alignment,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, contentDescription = null, tint = Color.White)
            Text(label, color = Color.White, style = MaterialTheme.typography.labelSmall)
        }
    }
}

/** Loading, error and empty states, centred over the list. */
@Composable
private fun StatusOverlay(
    vm: TicketViewModel,
    isPullRefreshing: Boolean,
    isSearching: Boolean,
    onOpenSettings: () -> Unit,
    onRetry: () -> Unit,
) {
    val error = vm.errorMessage
    when {
        vm.isLoading && vm.searchedTickets == null -> {
            // The pull-to-refresh indicator already says "loading".
            if (!isPullRefreshing) CenteredLoading(text = stringResource(R.string.loading_data))
        }
        error != null -> {
            val isTokenMissing = error == ApiException.TokenNotSet().message
            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                GlassCard(contentPadding = PaddingValues(30.dp), cornerRadius = 12.dp) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Icon(Icons.Filled.Warning, contentDescription = null,
                            modifier = Modifier.size(40.dp), tint = MaterialTheme.colorScheme.error)
                        Text(stringResource(R.string.error), style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSurface)
                        Text(error, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurface)
                        Button(onClick = if (isTokenMissing) onOpenSettings else onRetry) {
                            Text(stringResource(if (isTokenMissing) R.string.open_settings else R.string.try_again))
                        }
                    }
                }
            }
        }
        vm.displayTickets.isEmpty() -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                GlassCard(contentPadding = PaddingValues(30.dp), cornerRadius = 12.dp) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(if (isSearching) Icons.Outlined.Search else Icons.Outlined.ConfirmationNumber,
                            contentDescription = null, modifier = Modifier.size(40.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(if (isSearching) R.string.no_search_results else R.string.no_tickets_in_view),
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

/** Small red dot in the top right corner of [content], e.g. unread chat messages. */
@Composable
private fun DotBadge(isPresented: Boolean, content: @Composable () -> Unit) {
    Box {
        content()
        if (isPresented) {
            Box(Modifier.align(Alignment.TopEnd).offset(x = 2.dp, y = (-2).dp).size(8.dp).background(Color.Red, CircleShape))
        }
    }
}
