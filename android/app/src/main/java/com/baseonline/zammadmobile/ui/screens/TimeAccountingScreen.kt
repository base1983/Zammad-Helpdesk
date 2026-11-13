package com.baseonline.zammadmobile.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.StyledSection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Books time on a ticket: an activity type and the hours spent. */
@Composable
fun TimeAccountingScreen(vm: TicketViewModel, nav: Nav, ticketId: Int) {
    val scope = rememberCoroutineScope()

    var ticket by remember { mutableStateOf(vm.cachedTicket(ticketId)) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var time by rememberSaveable { mutableStateOf("") }
    var selectedTypeId by rememberSaveable { mutableStateOf<Int?>(null) }
    var isPickingType by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val types = vm.timeAccountingTypes

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
    // The types may arrive after the screen opened; preselect the first one then.
    LaunchedEffect(types) {
        if (selectedTypeId == null) selectedTypeId = types.firstOrNull()?.id
    }

    // Disabled without a time, and without an activity: the server needs a type id.
    val canSave = ticket != null && time.isNotBlank() && selectedTypeId != null && !isSaving

    fun save() {
        val current = ticket ?: return
        val typeId = selectedTypeId ?: return
        isSaving = true
        errorMessage = null
        // Decimal comma to dot, for the API.
        val formattedTime = time.trim().replace(",", ".")
        scope.launch {
            try {
                vm.addSpentTime(current, formattedTime, typeId)
                nav.back()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = e.message ?: e.toString()
            } finally {
                isSaving = false
            }
        }
    }

    AppScaffold(
        title = stringResource(R.string.add_spent_time),
        subtitle = ticket?.let { "#${it.number}" },
        onBack = { nav.back() },
        actions = {
            if (isSaving) {
                CircularProgressIndicator(Modifier.padding(horizontal = 12.dp).size(24.dp), strokeWidth = 2.dp)
            } else {
                TextButton(onClick = { save() }, enabled = canSave) { Text(stringResource(R.string.save)) }
            }
        },
    ) { padding ->
        if (ticket == null) {
            val error = loadError
            if (error != null) TicketMessageCard(error, Modifier.padding(padding).padding(16.dp))
            else CenteredLoading(Modifier.padding(padding), stringResource(R.string.loading_ticket))
            return@AppScaffold
        }

        Column(
            Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding).imePadding()
                .verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            StyledSection(stringResource(R.string.time_accounting)) {
                if (types.isEmpty()) {
                    if (vm.isLoading) {
                        Row(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(stringResource(R.string.loading_activities), Modifier.weight(1f))
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        }
                    } else {
                        Text(stringResource(R.string.no_activities_found_check_admin),
                            Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
                            color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                } else {
                    TicketPickerRow(
                        stringResource(R.string.activity),
                        types.firstOrNull { it.id == selectedTypeId }?.name ?: stringResource(R.string.select_activity),
                        enabled = !isSaving,
                    ) { isPickingType = true }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
                OutlinedTextField(
                    value = time,
                    onValueChange = { input -> time = input.filter { it.isDigit() || it == '.' || it == ',' } },
                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                    enabled = !isSaving,
                    singleLine = true,
                    label = { Text(stringResource(R.string.time_in_hours)) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
            }

            errorMessage?.let { TicketMessageCard(it) }
        }

        if (isPickingType) {
            TicketOptionPickerDialog(
                stringResource(R.string.activity),
                types.map { it.id to it.name },
                selectedTypeId,
                onSelect = { selectedTypeId = it; isPickingType = false },
                onDismiss = { isPickingType = false },
            )
        }
    }
}
