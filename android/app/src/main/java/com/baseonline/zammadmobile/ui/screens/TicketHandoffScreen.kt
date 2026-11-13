package com.baseonline.zammadmobile.ui.screens

import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.chat.ChatDirectory
import com.baseonline.zammadmobile.chat.ChatException
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.chat.ChatTarget
import com.baseonline.zammadmobile.data.ZammadApi
import com.baseonline.zammadmobile.ui.Nav
import com.baseonline.zammadmobile.ui.components.AppScaffold
import com.baseonline.zammadmobile.ui.components.CenteredLoading
import com.baseonline.zammadmobile.ui.components.StyledSection
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Hand a ticket off to a colleague: pick an engineer, send them a message
 * (an encrypted chat message with the ticket reference, or an internal note
 * plus mention when they are not registered for chat) and optionally assign
 * the ticket in the same step.
 */
@Composable
fun TicketHandoffScreen(vm: TicketViewModel, nav: Nav, ticketId: Int) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var ticket by remember { mutableStateOf(vm.cachedTicket(ticketId)) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var selectedAgentId by rememberSaveable { mutableStateOf<Int?>(null) }
    var message by rememberSaveable { mutableStateOf("") }
    var assignImmediately by rememberSaveable { mutableStateOf(true) }
    var isSending by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var isPickingAgent by remember { mutableStateOf(false) }

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

    // Agents that can take the ticket: everyone but the current user and
    // Zammad's built-in "nobody" user (id 1).
    val agents = vm.agentUsers
    val currentUserId = vm.currentUser?.id
    val availableAgents = remember(agents, currentUserId) {
        agents.filter { it.id != currentUserId && it.id != 1 && it.active }
            .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.fullname })
    }

    fun send() {
        val current = ticket ?: return
        val agentId = selectedAgentId ?: return
        if (isSending) return
        isSending = true
        errorMessage = null

        scope.launch {
            try {
                // 1. Prefer a direct chat message (with ticket reference) via the
                //    relay. Falls back to an internal note + mention when the
                //    colleague isn't registered for chat.
                var sentViaChat = false
                val currentUser = vm.currentUser
                if (currentUser != null) {
                    try {
                        ChatService.register(currentUser)
                        ChatDirectory.refresh()
                        val partner = ChatDirectory.engineerForZammadUser(agentId)
                        if (partner != null) {
                            ChatService.send(ChatTarget.Direct(partner), message, current)
                            sentViaChat = true
                        }
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        Log.i("TicketHandoff", "Chat handoff unavailable, falling back to internal note: $e")
                    }
                }

                if (!sentViaChat) {
                    val agentName = vm.userName(agentId)
                    val senderName = currentUser?.fullname.orEmpty()
                    vm.addInternalNote(current, "@$agentName\n$message\n\n— $senderName")
                    ZammadApi.gracefully(Unit) { ZammadApi.createMention(current.id, agentId) }
                }

                // 2. Assign, which also triggers Zammad's "assigned to you" notification.
                if (assignImmediately) {
                    val needsPendingTime = vm.updateTicket(current.copy(owner_id = agentId))
                    if (needsPendingTime) {
                        errorMessage = context.getString(R.string.handoff_error_pending_time)
                        return@launch
                    }
                }

                nav.back()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = (e as? ChatException)?.localized(context) ?: e.message ?: e.toString()
            } finally {
                isSending = false
            }
        }
    }

    AppScaffold(title = stringResource(R.string.handoff_ticket), subtitle = ticket?.let { "#${it.number}" },
        onBack = { nav.back() }) { padding ->
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
            StyledSection(stringResource(R.string.handoff_engineer)) {
                TicketPickerRow(
                    stringResource(R.string.handoff_select_engineer),
                    availableAgents.firstOrNull { it.id == selectedAgentId }?.fullname.orEmpty(),
                    enabled = !isSending,
                ) { isPickingAgent = true }
            }

            StyledSection(stringResource(R.string.handoff_message)) {
                OutlinedTextField(
                    value = message,
                    onValueChange = { message = it },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp).padding(8.dp),
                    enabled = !isSending,
                    placeholder = { Text(stringResource(R.string.handoff_message_placeholder)) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                )
            }

            StyledSection(footer = stringResource(R.string.handoff_assign_footer)) {
                Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.handoff_assign_immediately), Modifier.weight(1f))
                    Switch(checked = assignImmediately, onCheckedChange = { assignImmediately = it }, enabled = !isSending)
                }
            }

            errorMessage?.let { TicketMessageCard(it) }

            Button(
                onClick = { send() },
                enabled = !isSending && selectedAgentId != null && message.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (isSending) {
                    CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = LocalContentColor.current)
                    Spacer(Modifier.width(8.dp))
                }
                Text(stringResource(R.string.handoff_send))
            }
        }

        if (isPickingAgent) {
            TicketOptionPickerDialog(
                stringResource(R.string.handoff_select_engineer),
                availableAgents.map { it.id to it.fullname },
                selectedAgentId,
                onSelect = { selectedAgentId = it; isPickingAgent = false },
                onDismiss = { isPickingAgent = false },
            )
        }
    }
}
