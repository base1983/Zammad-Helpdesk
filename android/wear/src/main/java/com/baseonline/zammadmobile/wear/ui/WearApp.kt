package com.baseonline.zammadmobile.wear.ui

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.CircularProgressIndicator
import androidx.wear.compose.material3.FilledTonalButton
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import com.baseonline.zammadmobile.wear.R
import com.baseonline.zammadmobile.wear.TicketFilter
import com.baseonline.zammadmobile.wear.TicketViewModel
import com.baseonline.zammadmobile.wear.data.CredentialStore
import com.baseonline.zammadmobile.wear.data.Ticket
import com.baseonline.zammadmobile.wear.data.parseIsoDate
import java.text.DateFormat
import java.util.Date

private object Routes {
    const val LIST = "list"
    const val FILTER = "filter"
    const val DETAIL = "detail"
    const val PICK_STATUS = "pick/status"
    const val PICK_PRIORITY = "pick/priority"
    const val PICK_OWNER = "pick/owner"
}

@Composable
fun WearApp(viewModel: TicketViewModel) {
    val credentials by CredentialStore.state.collectAsState()
    MaterialTheme {
        AppScaffold {
            if (credentials == null) {
                LaunchedEffect(Unit) { viewModel.reset() }
                SignInScreen()
            } else {
                // Keyed on the credentials: a different account starts clean.
                LaunchedEffect(credentials) {
                    viewModel.reset()
                    viewModel.loadTickets()
                }
                val navController = rememberSwipeDismissableNavController()
                SwipeDismissableNavHost(navController = navController, startDestination = Routes.LIST) {
                    composable(Routes.LIST) {
                        TicketListScreen(
                            viewModel = viewModel,
                            onFilter = { navController.navigate(Routes.FILTER) },
                            onTicket = {
                                viewModel.openTicket(it.id)
                                navController.navigate(Routes.DETAIL)
                            },
                        )
                    }
                    composable(Routes.FILTER) {
                        FilterScreen(viewModel) {
                            viewModel.selectFilter(it)
                            navController.popBackStack()
                        }
                    }
                    composable(Routes.DETAIL) {
                        TicketDetailScreen(viewModel) { navController.navigate(it) }
                    }
                    composable(Routes.PICK_STATUS) {
                        val current = viewModel.detailTicket?.state_id
                        PickerScreen(
                            title = stringResource(R.string.status),
                            options = viewModel.ticketStates.map {
                                PickerOption(it.id, viewModel.localizedStatusName(it.name), viewModel.statusColor(it.id))
                            },
                            selectedId = current,
                        ) { id ->
                            viewModel.updateDetail { it.copy(state_id = id) }
                            navController.popBackStack()
                        }
                    }
                    composable(Routes.PICK_PRIORITY) {
                        PickerScreen(
                            title = stringResource(R.string.priority),
                            options = viewModel.ticketPriorities.map { PickerOption(it.id, it.name) },
                            selectedId = viewModel.detailTicket?.priority_id,
                        ) { id ->
                            viewModel.updateDetail { it.copy(priority_id = id) }
                            navController.popBackStack()
                        }
                    }
                    composable(Routes.PICK_OWNER) {
                        PickerScreen(
                            title = stringResource(R.string.owner),
                            options = viewModel.agentUsers.map { PickerOption(it.id, it.fullname) },
                            selectedId = viewModel.detailTicket?.owner_id,
                        ) { id ->
                            viewModel.updateDetail { it.copy(owner_id = id) }
                            navController.popBackStack()
                        }
                    }
                }
            }
        }
    }
}

// Sign-in hint

@Composable
private fun SignInScreen() {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 28.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_phone),
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.size(8.dp))
        Text(
            text = stringResource(R.string.sign_in_on_phone),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

// Ticket list

@Composable
private fun filterTitle(viewModel: TicketViewModel, filter: TicketFilter): String = when (filter) {
    TicketFilter.MyTickets -> stringResource(R.string.my_assigned_tickets)
    TicketFilter.Unassigned -> stringResource(R.string.unassigned_tickets)
    TicketFilter.AllOpen -> stringResource(R.string.all_open_tickets)
    is TicketFilter.ByStatus -> viewModel.localizedStatusName(filter.name)
}

@Composable
private fun TicketListScreen(viewModel: TicketViewModel, onFilter: () -> Unit, onTicket: (Ticket) -> Unit) {
    val listState = rememberScalingLazyListState()
    val error = viewModel.errorMessage
    ScreenScaffold(scrollState = listState) { contentPadding ->
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            contentPadding = contentPadding,
        ) {
            item { ListHeader { Text(stringResource(R.string.tickets)) } }
            item {
                FilledTonalButton(
                    onClick = onFilter,
                    modifier = Modifier.fillMaxWidth(),
                    icon = { Icon(painterResource(R.drawable.ic_filter), stringResource(R.string.filter)) },
                    label = { Text(filterTitle(viewModel, viewModel.filter), maxLines = 2, overflow = TextOverflow.Ellipsis) },
                )
            }
            when {
                viewModel.isLoading -> item { LoadingRow(stringResource(R.string.loading_data)) }
                error != null -> {
                    item {
                        Icon(
                            painter = painterResource(R.drawable.ic_warning),
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                    item { Message(error) }
                    item {
                        Button(onClick = { viewModel.loadTickets() }) { Text(stringResource(R.string.try_again)) }
                    }
                }
                viewModel.tickets.isEmpty() -> item { Message(stringResource(R.string.no_tickets_in_view)) }
                else -> items(viewModel.tickets, key = { it.id }) { ticket ->
                    TicketRow(ticket, viewModel) { onTicket(ticket) }
                }
            }
        }
    }
}

@Composable
private fun TicketRow(ticket: Ticket, viewModel: TicketViewModel, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.filledTonalButtonColors(),
    ) {
        Column(Modifier.fillMaxWidth()) {
            Text(
                text = "#${ticket.number}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = ticket.title,
                style = MaterialTheme.typography.labelMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                val color = viewModel.statusColor(ticket.state_id)
                Dot(color)
                Spacer(Modifier.width(4.dp))
                Text(
                    text = viewModel.localizedStateName(ticket.state_id),
                    style = MaterialTheme.typography.labelSmall,
                    color = color,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = timeAgo(ticket.updated_at),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun FilterScreen(viewModel: TicketViewModel, onSelect: (TicketFilter) -> Unit) {
    val listState = rememberScalingLazyListState()
    ScreenScaffold(scrollState = listState) { contentPadding ->
        ScalingLazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = contentPadding) {
            item { ListHeader { Text(stringResource(R.string.filter)) } }
            val fixed = listOf(TicketFilter.MyTickets, TicketFilter.Unassigned, TicketFilter.AllOpen)
            items(fixed) { filter ->
                OptionButton(filterTitle(viewModel, filter), viewModel.filter == filter) { onSelect(filter) }
            }
            if (viewModel.ticketStates.isNotEmpty()) {
                item { ListHeader { Text(stringResource(R.string.filter_by_status)) } }
                items(viewModel.ticketStates, key = { it.id }) { state ->
                    val filter = TicketFilter.ByStatus(state.id, state.name)
                    OptionButton(viewModel.localizedStatusName(state.name), viewModel.filter == filter) { onSelect(filter) }
                }
            }
        }
    }
}

// Ticket detail

@Composable
private fun TicketDetailScreen(viewModel: TicketViewModel, onPick: (String) -> Unit) {
    val listState = rememberScalingLazyListState()
    val ticket = viewModel.detailTicket
    ScreenScaffold(scrollState = listState) { contentPadding ->
        ScalingLazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = contentPadding) {
            when {
                viewModel.detailLoading -> item { LoadingRow(stringResource(R.string.loading_ticket_details)) }
                ticket == null -> item { Message(stringResource(R.string.ticket_not_found)) }
                else -> detailItems(ticket, viewModel, onPick)
            }
        }
    }
}

private fun ScalingLazyListScope.detailItems(ticket: Ticket, viewModel: TicketViewModel, onPick: (String) -> Unit) {
    item { ListHeader { Text("#${ticket.number}") } }
    item {
        Text(
            text = ticket.title,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
        )
    }
    item { ListHeader { Text(stringResource(R.string.details_section_header)) } }
    item { InfoRow(stringResource(R.string.customer), viewModel.userName(ticket.customer_id)) }
    item {
        FieldButton(
            title = stringResource(R.string.status),
            value = viewModel.localizedStateName(ticket.state_id),
            dot = viewModel.statusColor(ticket.state_id),
        ) { onPick(Routes.PICK_STATUS) }
    }
    item {
        FieldButton(stringResource(R.string.priority), viewModel.priorityName(ticket.priority_id)) {
            onPick(Routes.PICK_PRIORITY)
        }
    }
    item {
        FieldButton(stringResource(R.string.owner), viewModel.userName(ticket.owner_id)) {
            onPick(Routes.PICK_OWNER)
        }
    }
    item { InfoRow(stringResource(R.string.created_at), formatDate(ticket.created_at)) }
}

private data class PickerOption(val id: Int, val title: String, val dot: Color? = null)

@Composable
private fun PickerScreen(title: String, options: List<PickerOption>, selectedId: Int?, onSelect: (Int) -> Unit) {
    val listState = rememberScalingLazyListState()
    ScreenScaffold(scrollState = listState) { contentPadding ->
        ScalingLazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = contentPadding) {
            item { ListHeader { Text(title) } }
            items(options, key = { it.id }) { option ->
                OptionButton(option.title, option.id == selectedId, option.dot) { onSelect(option.id) }
            }
        }
    }
}

// Shared pieces

@Composable
private fun Dot(color: Color) {
    Box(Modifier.size(8.dp).background(color, CircleShape))
}

@Composable
private fun OptionButton(title: String, selected: Boolean, dot: Color? = null, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.filledTonalButtonColors(),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (dot != null) {
                Dot(dot)
                Spacer(Modifier.width(6.dp))
            }
            Text(title, modifier = Modifier.weight(1f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (selected) {
                Icon(
                    painter = painterResource(R.drawable.ic_check),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(18.dp),
                )
            }
        }
    }
}

@Composable
private fun FieldButton(title: String, value: String, dot: Color? = null, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        colors = ButtonDefaults.filledTonalButtonColors(),
    ) {
        Column(Modifier.fillMaxWidth()) {
            Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (dot != null) {
                    Dot(dot)
                    Spacer(Modifier.width(4.dp))
                }
                Text(value, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun InfoRow(title: String, value: String) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 4.dp)) {
        Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun LoadingRow(text: String) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        CircularProgressIndicator(Modifier.size(32.dp))
        Spacer(Modifier.size(8.dp))
        Message(text)
    }
}

@Composable
private fun Message(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
    )
}

private fun timeAgo(iso: String): String {
    val instant = parseIsoDate(iso) ?: return ""
    return DateUtils.getRelativeTimeSpanString(
        instant.toEpochMilli(),
        System.currentTimeMillis(),
        DateUtils.MINUTE_IN_MILLIS,
        DateUtils.FORMAT_ABBREV_RELATIVE,
    ).toString()
}

private fun formatDate(iso: String): String {
    val instant = parseIsoDate(iso) ?: return ""
    return DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date.from(instant))
}
