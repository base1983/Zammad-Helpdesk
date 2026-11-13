package com.baseonline.zammadmobile.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.StyledSection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

@Composable
fun TicketEditScreen(vm: TicketViewModel, nav: Nav, ticketId: Int) {
    val scope = rememberCoroutineScope()
    var ticket by remember { mutableStateOf(vm.cachedTicket(ticketId)) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    var showPendingTimePicker by remember { mutableStateOf(false) }
    var picker by remember { mutableStateOf<TicketEditField?>(null) }

    LaunchedEffect(ticketId) {
        if (ticket == null) {
            try {
                ticket = ZammadApi.fetchTicket(ticketId)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                loadError = e.message ?: e.toString()
            }
        }
    }

    fun save(pendingTime: Instant? = null) {
        val current = ticket ?: return
        if (isSaving) return
        isSaving = true
        error = null
        scope.launch {
            try {
                val needsPendingTime = vm.updateTicket(current, pendingTime)
                if (needsPendingTime) showPendingTimePicker = true else nav.back()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = e.message ?: e.toString()
            } finally {
                isSaving = false
            }
        }
    }

    AppScaffold(
        title = stringResource(R.string.edit_ticket),
        onBack = { nav.back() },
        actions = {
            if (isSaving) {
                CircularProgressIndicator(Modifier.padding(horizontal = 12.dp).size(24.dp), strokeWidth = 2.dp)
            } else {
                IconButton(onClick = { save() }, enabled = ticket != null) {
                    Icon(Icons.Filled.Check, contentDescription = stringResource(R.string.save))
                }
            }
        },
    ) { padding ->
        val current = ticket
        if (current == null) {
            if (loadError != null) TicketMessageCard(loadError!!, Modifier.padding(padding).padding(16.dp))
            else CenteredLoading(Modifier.padding(padding), stringResource(R.string.loading_ticket))
            return@AppScaffold
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            error?.let { TicketMessageCard(it) }

            StyledSection(stringResource(R.string.details_section_header)) {
                // Zammad's update call (as used on iOS) carries no title, so it is shown, not edited.
                Text(current.title, Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                    fontWeight = FontWeight.SemiBold)
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                TicketPickerRow(stringResource(R.string.customer), vm.userName(current.customer_id)) {
                    picker = TicketEditField.CUSTOMER
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                TicketPickerRow(stringResource(R.string.status_picker_label),
                    vm.localizedStatusName(vm.stateName(current.state_id))) { picker = TicketEditField.STATE }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                TicketPickerRow(stringResource(R.string.priority_picker_label),
                    vm.localizedPriorityName(vm.priorityName(current.priority_id))) { picker = TicketEditField.PRIORITY }
            }

            StyledSection(stringResource(R.string.assignment_section_header)) {
                TicketPickerRow(stringResource(R.string.owner_picker_label), ticketOwnerName(vm, current.owner_id)) {
                    picker = TicketEditField.OWNER
                }
            }
        }

        when (picker) {
            TicketEditField.CUSTOMER -> TicketCustomerSearchDialog(vm,
                onSelect = { ticket = current.copy(customer_id = it); picker = null },
                onDismiss = { picker = null })
            TicketEditField.STATE -> TicketOptionPickerDialog(
                stringResource(R.string.status), ticketStateOptions(vm), current.state_id,
                onSelect = { ticket = current.copy(state_id = it); picker = null }, onDismiss = { picker = null })
            TicketEditField.PRIORITY -> TicketOptionPickerDialog(
                stringResource(R.string.priority), ticketPriorityOptions(vm), current.priority_id,
                onSelect = { ticket = current.copy(priority_id = it); picker = null }, onDismiss = { picker = null })
            TicketEditField.OWNER -> TicketOptionPickerDialog(
                stringResource(R.string.owner), ticketOwnerOptions(vm), current.owner_id,
                onSelect = { ticket = current.copy(owner_id = it); picker = null }, onDismiss = { picker = null })
            null -> {}
        }

        if (showPendingTimePicker) {
            TicketPendingTimeDialog(
                onConfirm = { showPendingTimePicker = false; save(it) },
                onDismiss = { showPendingTimePicker = false },
            )
        }
    }
}

// --- Shared by the ticket detail, edit, handoff and time accounting screens ---

internal enum class TicketEditField { CUSTOMER, STATE, PRIORITY, OWNER }

internal fun ticketStateOptions(vm: TicketViewModel): List<Pair<Int, String>> =
    vm.ticketStates.map { it.id to vm.localizedStatusName(it.name) }

internal fun ticketPriorityOptions(vm: TicketViewModel): List<Pair<Int, String>> =
    vm.ticketPriorities.map { it.id to vm.localizedPriorityName(it.name) }

/** "Unassigned" (Zammad's built-in user 1) followed by the agents. */
@Composable
internal fun ticketOwnerOptions(vm: TicketViewModel): List<Pair<Int, String>> =
    listOf(1 to stringResource(R.string.unassigned)) + vm.agentUsers.filter { it.id != 1 }.map { it.id to it.fullname }

@Composable
internal fun ticketOwnerName(vm: TicketViewModel, ownerId: Int): String =
    if (ownerId == 1) stringResource(R.string.unassigned) else vm.userName(ownerId)

/** A red message on a readable card. */
@Composable
internal fun TicketMessageCard(message: String, modifier: Modifier = Modifier) {
    com.baseonline.zammadmobile.ui.components.GlassCard(modifier.fillMaxWidth()) {
        Text(message, Modifier.padding(16.dp), color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyMedium)
    }
}

/** Label on the left, current value and a chooser glyph on the right. */
@Composable
internal fun TicketPickerRow(label: String, value: String, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.width(12.dp))
        Text(value, Modifier.weight(1f), textAlign = TextAlign.End, maxLines = 2, overflow = TextOverflow.Ellipsis,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.width(6.dp))
        Icon(Icons.Filled.UnfoldMore, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** Single-choice list in a dialog; choosing an entry reports it straight away. */
@Composable
internal fun TicketOptionPickerDialog(
    title: String,
    options: List<Pair<Int, String>>,
    selectedId: Int?,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            LazyColumn(Modifier.heightIn(max = 420.dp)) {
                items(options, key = { it.first }) { (id, name) ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onSelect(id) }.padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = id == selectedId, onClick = { onSelect(id) })
                        Text(name, Modifier.padding(start = 4.dp))
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** Customer chooser: every known user, filtered by name or organisation. */
@Composable
internal fun TicketCustomerSearchDialog(vm: TicketViewModel, onSelect: (Int) -> Unit, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val users = vm.allUsers
    val organizations = vm.organizations
    val filtered = remember(query, users, organizations) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) users else users.filter { user ->
            user.fullname.lowercase().contains(q) ||
                vm.organizationName(user.organization_id)?.lowercase()?.contains(q) == true
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.select_customer)) },
        text = {
            Column {
                OutlinedTextField(
                    value = query, onValueChange = { query = it }, singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Search, null) },
                    placeholder = { Text(stringResource(R.string.search)) },
                    modifier = Modifier.fillMaxWidth(),
                )
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp).padding(top = 8.dp)) {
                    items(filtered, key = { it.id }) { user ->
                        Text(vm.userName(user.id),
                            Modifier.fillMaxWidth().clickable { onSelect(user.id) }.padding(vertical = 12.dp))
                    }
                    if (filtered.isEmpty()) {
                        item {
                            Text(stringResource(R.string.no_search_results), Modifier.padding(vertical = 12.dp),
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

/** Date first, then time: the pending time Zammad wants for "pending" states. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TicketPendingTimeDialog(onConfirm: (Instant) -> Unit, onDismiss: () -> Unit) {
    val now = remember { LocalDateTime.now() }
    var pickedDate by remember { mutableStateOf<LocalDate?>(null) }
    val date = pickedDate

    if (date == null) {
        val dateState = rememberDatePickerState(
            initialSelectedDateMillis = now.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = onDismiss,
            confirmButton = {
                TextButton(
                    enabled = dateState.selectedDateMillis != null,
                    onClick = {
                        // The picker reports the chosen day as UTC midnight.
                        dateState.selectedDateMillis?.let {
                            pickedDate = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                        }
                    },
                ) { Text(stringResource(R.string.ok)) }
            },
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        ) {
            DatePicker(state = dateState, title = {
                Text(stringResource(R.string.select_pending_time), Modifier.padding(start = 24.dp, end = 12.dp, top = 16.dp))
            })
        }
    } else {
        val timeState = rememberTimePickerState(initialHour = now.hour, initialMinute = now.minute)
        AlertDialog(
            onDismissRequest = onDismiss,
            title = { Text(stringResource(R.string.pending_time_title)) },
            text = { TimePicker(state = timeState) },
            confirmButton = {
                TextButton(onClick = {
                    val local = LocalDateTime.of(date, LocalTime.of(timeState.hour, timeState.minute))
                    onConfirm(local.atZone(ZoneId.systemDefault()).toInstant())
                }) { Text(stringResource(R.string.done)) }
            },
            dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
        )
    }
}
