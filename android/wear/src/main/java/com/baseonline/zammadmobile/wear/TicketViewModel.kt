package com.baseonline.zammadmobile.wear

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.baseonline.zammadmobile.wear.data.ApiException
import com.baseonline.zammadmobile.wear.data.Role
import com.baseonline.zammadmobile.wear.data.Ticket
import com.baseonline.zammadmobile.wear.data.TicketPriority
import com.baseonline.zammadmobile.wear.data.TicketState
import com.baseonline.zammadmobile.wear.data.User
import com.baseonline.zammadmobile.wear.data.ZammadApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.temporal.ChronoUnit

sealed interface TicketFilter {
    data object MyTickets : TicketFilter
    data object Unassigned : TicketFilter
    data object AllOpen : TicketFilter
    data class ByStatus(val id: Int, val name: String) : TicketFilter
}

/** Counterpart of the watchOS `WatchTicketViewModel`. */
class TicketViewModel(app: Application) : AndroidViewModel(app) {
    var tickets by mutableStateOf<List<Ticket>>(emptyList()); private set
    var ticketStates by mutableStateOf<List<TicketState>>(emptyList()); private set
    var ticketPriorities by mutableStateOf<List<TicketPriority>>(emptyList()); private set
    var allUsers by mutableStateOf<List<User>>(emptyList()); private set
    var roles by mutableStateOf<List<Role>>(emptyList()); private set
    var currentUser by mutableStateOf<User?>(null); private set
    var isLoading by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null); private set
    var filter by mutableStateOf<TicketFilter>(TicketFilter.MyTickets); private set

    // Ticket detail
    var detailTicket by mutableStateOf<Ticket?>(null); private set
    var detailLoading by mutableStateOf(false); private set

    private var loadJob: Job? = null
    private var detailJob: Job? = null

    val agentUsers: List<User>
        get() {
            val agentRoleId = roles.firstOrNull { it.name == "Agent" }?.id ?: return emptyList()
            return allUsers.filter { agentRoleId in it.role_ids }
        }

    /** Credentials changed or went away: forget everything tied to the old account. */
    fun reset() {
        loadJob?.cancel()
        detailJob?.cancel()
        tickets = emptyList()
        ticketStates = emptyList()
        ticketPriorities = emptyList()
        allUsers = emptyList()
        roles = emptyList()
        currentUser = null
        isLoading = false
        errorMessage = null
        filter = TicketFilter.MyTickets
        detailTicket = null
        detailLoading = false
    }

    fun selectFilter(newFilter: TicketFilter) {
        filter = newFilter
        loadTickets()
    }

    fun loadTickets() {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            isLoading = true
            errorMessage = null
            try {
                if (currentUser == null) loadMetadata()
                tickets = fetchTickets(filter)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                errorMessage = describe(e)
            }
            isLoading = false
        }
    }

    private suspend fun loadMetadata() = coroutineScope {
        val user = async { ZammadApi.fetchCurrentUser() }
        val states = async { ZammadApi.fetchTicketStates() }
        val priorities = async { ZammadApi.fetchTicketPriorities() }
        val users = async { ZammadApi.fetchAllUsers() }
        val roleList = async { ZammadApi.fetchRoles() }
        val me = user.await()
        ticketStates = states.await()
        ticketPriorities = priorities.await()
        allUsers = users.await()
        roles = roleList.await()
        currentUser = me
    }

    private suspend fun fetchTickets(filter: TicketFilter): List<Ticket> {
        val me = currentUser ?: return emptyList()
        return when (filter) {
            TicketFilter.MyTickets -> ZammadApi.searchTickets("owner_id:${me.id} AND state.name:(new OR open)")
            TicketFilter.Unassigned -> ZammadApi.searchTickets("owner_id:1 AND state.name:(new OR open)")
            TicketFilter.AllOpen -> ZammadApi.searchTickets("state.name:(new OR open)")
            is TicketFilter.ByStatus -> ZammadApi.searchTickets("state_id:${filter.id}")
        }
    }

    // Ticket detail

    fun openTicket(id: Int) {
        detailTicket = null
        loadDetail(id)
    }

    private fun loadDetail(id: Int, before: (suspend () -> Unit)? = null) {
        detailJob?.cancel()
        detailJob = viewModelScope.launch {
            detailLoading = true
            try {
                before?.invoke()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Same as watchOS: a failed save is not surfaced; the reload
                // below shows what the server actually holds.
            }
            try {
                val fresh = ZammadApi.fetchTicket(id)
                detailTicket = fresh
                tickets = tickets.map { if (it.id == fresh.id) fresh else it }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (before == null) detailTicket = null
            }
            detailLoading = false
        }
    }

    /** Applies [change] to the open ticket, saves it and reloads the detail. */
    fun updateDetail(change: (Ticket) -> Ticket) {
        val changed = change(detailTicket ?: return)
        detailTicket = changed
        loadDetail(changed.id) {
            // A pending state needs a pending_time; like watchOS, default to
            // one hour from now when the ticket has none.
            val pending = stateName(changed.state_id).lowercase().contains("pending") && changed.pending_time == null
            val pendingTime = if (pending) Instant.now().plus(1, ChronoUnit.HOURS).truncatedTo(ChronoUnit.SECONDS).toString() else null
            ZammadApi.updateTicket(changed, pendingTime)
        }
    }

    // Helpers

    private fun string(id: Int, vararg args: Any) = getApplication<Application>().getString(id, *args)

    private fun describe(e: Exception): String = when (e) {
        is ApiException.AuthenticationFailed, is ApiException.NoCredentials -> string(R.string.error_auth)
        is ApiException.InvalidUrl -> string(R.string.error_invalid_url)
        is ApiException.Decoding -> string(R.string.error_decoding)
        is ApiException.Server -> e.serverMessage ?: string(R.string.error_server, e.code)
        else -> string(R.string.error_network)
    }

    fun userName(userId: Int): String {
        if (userId == 1) return string(R.string.unassigned)
        return allUsers.firstOrNull { it.id == userId }?.fullname ?: string(R.string.unknown)
    }

    private fun stateName(stateId: Int): String = ticketStates.firstOrNull { it.id == stateId }?.name.orEmpty()

    fun localizedStateName(stateId: Int): String =
        ticketStates.firstOrNull { it.id == stateId }?.let { localizedStatusName(it.name) } ?: string(R.string.unknown)

    fun localizedStatusName(name: String): String = when (name.replace(" ", "_").lowercase()) {
        "new" -> string(R.string.status_new)
        "open" -> string(R.string.status_open)
        "pending_reminder" -> string(R.string.status_pending_reminder)
        "closed" -> string(R.string.status_closed)
        "merged" -> string(R.string.status_merged)
        "pending_close" -> string(R.string.status_pending_close)
        else -> name
    }

    fun priorityName(priorityId: Int): String =
        ticketPriorities.firstOrNull { it.id == priorityId }?.name ?: string(R.string.unknown)

    fun statusColor(stateId: Int): Color {
        val name = stateName(stateId).lowercase()
        return when {
            "new" in name -> Color(0xFF4A9DFF)
            "open" in name -> Color(0xFF34C759)
            "pending" in name -> Color(0xFFFF9F0A)
            else -> Color(0xFF8E8E93)
        }
    }
}
