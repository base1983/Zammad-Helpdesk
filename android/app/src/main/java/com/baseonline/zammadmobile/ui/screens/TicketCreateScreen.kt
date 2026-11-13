package com.baseonline.zammadmobile.ui.screens

import com.baseonline.zammadmobile.App

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.AlertDialog
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
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.User
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.StyledSection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val ARTICLE_TYPES = listOf("note", "email")

/**
 * New ticket form, the counterpart of the iOS `TicketCreateView`: title,
 * customer, group, owner, first article (note or e-mail), state, priority and
 * tags. Create is enabled once every required field is filled.
 */
@Composable
fun TicketCreateScreen(vm: TicketViewModel, nav: Nav) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var title by rememberSaveable { mutableStateOf("") }
    var customerId by rememberSaveable { mutableStateOf<Int?>(null) }
    // Name of a customer picked from a server search, who may not be in vm.allUsers.
    var pickedCustomerName by rememberSaveable { mutableStateOf<String?>(null) }
    var articleBody by rememberSaveable { mutableStateOf("Hi there,\n\n") }
    var groupId by rememberSaveable { mutableStateOf<Int?>(null) }
    var ownerId by rememberSaveable { mutableStateOf<Int?>(null) }
    var stateId by rememberSaveable { mutableStateOf<Int?>(null) }
    var priorityId by rememberSaveable { mutableStateOf<Int?>(null) }
    var tags by rememberSaveable { mutableStateOf("") }
    var articleType by rememberSaveable { mutableStateOf(ARTICLE_TYPES.first()) }
    var didApplyCustomerDefault by rememberSaveable { mutableStateOf(false) }

    var alertMessage by remember { mutableStateOf<String?>(null) }
    var isShowingCustomerSearch by remember { mutableStateOf(false) }
    var isSubmitting by remember { mutableStateOf(false) }

    // Defaults from the loaded metadata, as on iOS: first group, state "new",
    // priority "2 normal", the current user as customer. Keyed on the data so
    // they also land when the metadata arrives after the screen opened.
    LaunchedEffect(vm.groups, vm.ticketStates, vm.ticketPriorities, vm.currentUser) {
        if (groupId == null) groupId = vm.groups.firstOrNull()?.id
        if (stateId == null) {
            stateId = (vm.ticketStates.firstOrNull { it.name.lowercase() == "new" } ?: vm.ticketStates.firstOrNull())?.id
        }
        if (priorityId == null) {
            priorityId = (vm.ticketPriorities.firstOrNull { it.name.lowercase() == "2 normal" }
                ?: vm.ticketPriorities.firstOrNull())?.id
        }
        val me = vm.currentUser
        if (!didApplyCustomerDefault && me != null) {
            didApplyCustomerDefault = true
            if (customerId == null) customerId = me.id
        }
    }

    val isFormValid = title.isNotEmpty() && customerId != null && articleBody.isNotEmpty() &&
        groupId != null && stateId != null && priorityId != null

    fun submit() {
        val customer = customerId
        val group = groupId
        val state = stateId
        val priority = priorityId
        if (customer == null || group == null || state == null || priority == null) {
            alertMessage = context.getString(R.string.please_fill_all_required_fields)
            return
        }
        isSubmitting = true
        scope.launch {
            try {
                vm.createTicket(
                    title = title, groupId = group, customerId = customer, stateId = state, priorityId = priority,
                    ownerId = ownerId, tags = tags.ifEmpty { null }, articleBody = articleBody, articleType = articleType,
                )
                nav.back()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                alertMessage = context.getString(R.string.failed_to_create_ticket) + ": " + (e.message ?: e.toString())
            } finally {
                isSubmitting = false
            }
        }
    }

    val customerName = customerId?.let { id ->
        if (vm.allUsers.any { it.id == id }) vm.userName(id)
        else pickedCustomerName ?: vm.currentUser?.takeIf { it.id == id }?.fullname ?: vm.userName(id)
    }

    AppScaffold(
        title = stringResource(R.string.new_ticket),
        onBack = { nav.back() },
        actions = {
            if (isSubmitting) {
                CircularProgressIndicator(Modifier.padding(end = 16.dp).size(22.dp), strokeWidth = 2.dp)
            } else {
                TextButton(onClick = { submit() }, enabled = isFormValid) { Text(stringResource(R.string.create)) }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize().imePadding(), contentAlignment = Alignment.TopCenter) {
            Column(
                Modifier.widthIn(max = 720.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                StyledSection(stringResource(R.string.details)) {
                    OutlinedTextField(
                        value = title,
                        onValueChange = { title = it },
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        label = { Text(stringResource(R.string.title)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    )
                    HorizontalDivider()
                    ValueRow(
                        label = stringResource(R.string.customer),
                        value = customerName ?: stringResource(R.string.select_customer),
                        isPlaceholder = customerName == null,
                        onClick = { isShowingCustomerSearch = true },
                    )
                    HorizontalDivider()
                    PickerRow(
                        label = stringResource(R.string.group),
                        selected = groupId,
                        options = vm.groups.map { it.id to it.name },
                        onSelect = { groupId = it },
                    )
                    HorizontalDivider()
                    PickerRow(
                        label = stringResource(R.string.owner),
                        selected = ownerId,
                        options = listOf<Pair<Int?, String>>(null to stringResource(R.string.unassigned)) +
                            vm.agentUsers.map { it.id to it.fullname },
                        onSelect = { ownerId = it },
                    )
                }

                StyledSection(stringResource(R.string.article)) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 12.dp)) {
                        ARTICLE_TYPES.forEachIndexed { index, type ->
                            SegmentedButton(
                                selected = articleType == type,
                                onClick = { articleType = type },
                                shape = SegmentedButtonDefaults.itemShape(index, ARTICLE_TYPES.size),
                            ) { Text(articleTypeLabel(type)) }
                        }
                    }
                    OutlinedTextField(
                        value = articleBody,
                        onValueChange = { articleBody = it },
                        modifier = Modifier.fillMaxWidth().padding(12.dp).heightIn(min = 200.dp),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    )
                }

                StyledSection(stringResource(R.string.classification)) {
                    PickerRow(
                        label = stringResource(R.string.status),
                        selected = stateId,
                        options = vm.ticketStates.map { it.id to vm.localizedStatusName(it.name) },
                        onSelect = { stateId = it },
                    )
                    HorizontalDivider()
                    PickerRow(
                        label = stringResource(R.string.priority),
                        selected = priorityId,
                        options = vm.ticketPriorities.map { it.id to vm.localizedPriorityName(it.name) },
                        onSelect = { priorityId = it },
                    )
                    HorizontalDivider()
                    OutlinedTextField(
                        value = tags,
                        onValueChange = { tags = it },
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                        label = { Text(stringResource(R.string.tags)) },
                        singleLine = true,
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                    )
                }
            }
        }
    }

    if (isShowingCustomerSearch) {
        CustomerSearchSheet(
            vm = vm,
            selectedId = customerId,
            onSelect = { user ->
                customerId = user.id
                pickedCustomerName = user.fullname.ifEmpty { user.email.ifEmpty { user.login } }
                isShowingCustomerSearch = false
            },
            onDismiss = { isShowingCustomerSearch = false },
        )
    }

    alertMessage?.let { message ->
        AlertDialog(
            onDismissRequest = { alertMessage = null },
            title = { Text(stringResource(R.string.error)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { alertMessage = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** iOS shows the raw type names; there are no resource keys for them. */
private fun articleTypeLabel(type: String) = App.ctx.getString(if (type == "email") R.string.article_type_email else R.string.article_type_note)

/** A form row: label on the left, current value on the right, tap to change. */
@Composable
private fun ValueRow(label: String, value: String, isPlaceholder: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, color = MaterialTheme.colorScheme.onSurface)
        Text(
            value,
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.End,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            color = if (isPlaceholder) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        )
        Icon(Icons.Filled.UnfoldMore, contentDescription = null, modifier = Modifier.size(18.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

/** A [ValueRow] that opens a menu of [options] (id to label). */
@Composable
private fun PickerRow(label: String, selected: Int?, options: List<Pair<Int?, String>>, onSelect: (Int?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ValueRow(
            label = label,
            value = options.firstOrNull { it.first == selected }?.second ?: "",
            onClick = { expanded = true },
        )
        Box(Modifier.align(Alignment.CenterEnd)) {
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                options.forEach { (id, name) ->
                    DropdownMenuItem(
                        text = { Text(name) },
                        trailingIcon = if (id == selected) {
                            { Icon(Icons.Filled.Check, contentDescription = null) }
                        } else null,
                        onClick = { expanded = false; onSelect(id) },
                    )
                }
            }
        }
    }
}

/**
 * Customer picker, the counterpart of the iOS `CustomerSearchView`: the loaded
 * users filtered by name or organisation, plus a server search so customers
 * beyond the loaded set (or on servers where the user list is forbidden) can
 * be found too.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CustomerSearchSheet(vm: TicketViewModel, selectedId: Int?, onSelect: (User) -> Unit, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var remote by remember { mutableStateOf<List<User>>(emptyList()) }
    var isSearching by remember { mutableStateOf(false) }

    LaunchedEffect(query) {
        val trimmed = query.trim()
        if (trimmed.length < 2) { remote = emptyList(); isSearching = false; return@LaunchedEffect }
        delay(350)
        isSearching = true
        remote = try {
            ZammadApi.searchUsers(trimmed)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
        isSearching = false
    }

    val local = remember(query, vm.allUsers, vm.organizations) {
        val q = query.trim().lowercase()
        if (q.isEmpty()) vm.allUsers
        else vm.allUsers.filter {
            it.fullname.lowercase().contains(q) ||
                vm.organizationName(it.organization_id)?.lowercase()?.contains(q) == true
        }
    }
    val results = remember(local, remote) { (local + remote).distinctBy { it.id } }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.9f).imePadding()) {
            Text(stringResource(R.string.select_customer), style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp))
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                placeholder = { Text(stringResource(R.string.search)) },
                leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
                trailingIcon = {
                    when {
                        isSearching -> CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        query.isNotEmpty() -> IconButton(onClick = { query = "" }) {
                            Icon(Icons.Filled.Cancel, contentDescription = null)
                        }
                    }
                },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
            LazyColumn(Modifier.fillMaxWidth().weight(1f)) {
                items(results, key = { it.id }) { user ->
                    val organization = vm.organizationName(user.organization_id)
                    val name = user.fullname.ifEmpty { user.email.ifEmpty { user.login } }
                    Row(
                        Modifier.fillMaxWidth().clickable { onSelect(user) }.padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(if (organization != null) "$name ($organization)" else name,
                            modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (user.id == selectedId) Icon(Icons.Filled.Check, contentDescription = null)
                    }
                    HorizontalDivider()
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.CenterHorizontally).padding(8.dp)) {
                Text(stringResource(R.string.cancel))
            }
        }
    }
}
