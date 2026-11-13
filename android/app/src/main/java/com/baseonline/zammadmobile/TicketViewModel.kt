package com.baseonline.zammadmobile

import android.app.Application
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.baseonline.zammadmobile.chat.ChatService
import com.baseonline.zammadmobile.data.ApiException
import com.baseonline.zammadmobile.data.ArticleCreationPayload
import com.baseonline.zammadmobile.data.Attachment
import com.baseonline.zammadmobile.data.AttachmentDraft
import com.baseonline.zammadmobile.data.Organization
import com.baseonline.zammadmobile.data.Role
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.data.TicketCreationPayload
import com.baseonline.zammadmobile.data.TicketGroup
import com.baseonline.zammadmobile.data.TicketPriority
import com.baseonline.zammadmobile.data.TicketState
import com.baseonline.zammadmobile.data.TicketUpdatePayload
import com.baseonline.zammadmobile.data.TimeAccountingPayload
import com.baseonline.zammadmobile.data.TimeAccountingType
import com.baseonline.zammadmobile.data.User
import com.baseonline.zammadmobile.data.ZammadApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit

/** Which tickets the list shows. */
sealed class TicketFilter {
    data object MyTickets : TicketFilter()
    data object Unassigned : TicketFilter()
    data object AllOpen : TicketFilter()
    /** Open tickets whose SLA deadline has passed, longest overdue first. */
    data object Escalated : TicketFilter()
    data class ByStatus(val id: Int, val name: String) : TicketFilter()

    /** String resource for the fixed filters; null for [ByStatus] (use its name). */
    val labelRes: Int? get() = when (this) {
        MyTickets -> R.string.my_assigned_tickets
        Unassigned -> R.string.unassigned_tickets
        AllOpen -> R.string.all_open_tickets
        Escalated -> R.string.filter_escalated
        is ByStatus -> null
    }
}

/**
 * Owns ticket state and filters, the counterpart of the iOS `TicketViewModel`.
 * All state is Compose state and is only touched on the main thread; the
 * suspend functions are safe to call from `rememberCoroutineScope()`.
 */
class TicketViewModel(app: Application) : AndroidViewModel(app) {
    var currentTickets by mutableStateOf<List<Ticket>>(emptyList()); private set
    var searchedTickets by mutableStateOf<List<Ticket>?>(null); private set
    var ticketStates by mutableStateOf<List<TicketState>>(emptyList()); private set
    var ticketPriorities by mutableStateOf<List<TicketPriority>>(emptyList()); private set
    var currentUser by mutableStateOf<User?>(null); private set
    var allUsers by mutableStateOf<List<User>>(emptyList()); private set
    var roles by mutableStateOf<List<Role>>(emptyList()); private set
    var groups by mutableStateOf<List<TicketGroup>>(emptyList()); private set
    var organizations by mutableStateOf<List<Organization>>(emptyList()); private set
    var timeAccountingTypes by mutableStateOf<List<TimeAccountingType>>(emptyList()); private set
    var isTimeAccountingEnabled by mutableStateOf(false); private set
    var isLoading by mutableStateOf(false); private set
    var errorMessage by mutableStateOf<String?>(null)
    var activeFilter by mutableStateOf<TicketFilter>(TicketFilter.MyTickets); private set
    /** Open tickets past their SLA deadline; badge on the filter button (Premium). */
    var escalatedCount by mutableIntStateOf(0); private set

    private var loadingJob: Job? = null
    private val ctx get() = getApplication<Application>()

    val displayTickets: List<Ticket> get() = searchedTickets ?: currentTickets

    val agentUsers: List<User>
        get() {
            val agentRole = roles.firstOrNull { it.name == "Agent" }?.id
            if (agentRole != null) return allUsers.filter { it.role_ids?.contains(agentRole) == true && it.active }
            // Roles endpoint forbidden: treat any active user with an e-mail as a potential agent.
            return allUsers.filter { it.active && it.email.isNotEmpty() }
        }

    private fun describe(e: Throwable): String = e.message ?: e.toString()

    // --- Loading ---

    suspend fun applyFilter(filter: TicketFilter) = loadData(filter, false)
    suspend fun refreshAllData() = loadData(activeFilter, true)

    suspend fun performSearch(query: String) {
        if (query.isBlank()) { clearSearch(); return }
        isLoading = true
        errorMessage = null
        try {
            searchedTickets = ZammadApi.searchTickets(query)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = describe(e)
        }
        isLoading = false
    }

    fun clearSearch() { searchedTickets = null }

    /** Drops everything loaded from the server (disconnect). */
    fun reset() {
        loadingJob?.cancel()
        currentTickets = emptyList(); searchedTickets = null
        ticketStates = emptyList(); ticketPriorities = emptyList()
        currentUser = null; allUsers = emptyList(); roles = emptyList(); groups = emptyList()
        organizations = emptyList(); timeAccountingTypes = emptyList()
        isTimeAccountingEnabled = false; isLoading = false; errorMessage = null
        activeFilter = TicketFilter.MyTickets; escalatedCount = 0
    }

    private suspend fun loadData(filter: TicketFilter, isFullRefresh: Boolean) {
        loadingJob?.cancel()
        val job = viewModelScope.launch {
            if (isFullRefresh || currentUser == null) isLoading = true
            activeFilter = filter
            try {
                if (isFullRefresh || currentUser == null) loadMetadata()
                coroutineScope {
                    val tickets = async { fetchTickets(filter) }
                    val escalated = async { fetchEscalatedCount() }
                    val loaded = tickets.await()
                    currentTickets = loaded
                    escalatedCount = if (filter == TicketFilter.Escalated) loaded.size else escalated.await()
                    errorMessage = null
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("TicketViewModel", "Failed to load data: $e")
                errorMessage = describe(e)
            }
        }
        loadingJob = job
        job.join()
        // Also when the job was cancelled by a newer load: the newest one owns
        // the flag, so only the job that is still current may clear it.
        if (loadingJob === job) isLoading = false
    }

    private suspend fun loadMetadata() = coroutineScope {
        val states = async { ZammadApi.fetchTicketStates() }
        val priorities = async { ZammadApi.fetchTicketPriorities() }
        val user = async { ZammadApi.fetchCurrentUser() }
        val users = async { ZammadApi.gracefully(emptyList()) { ZammadApi.fetchAllUsers() } }
        val loadedRoles = async { ZammadApi.gracefully(emptyList()) { ZammadApi.fetchRoles() } }
        val loadedGroups = async { ZammadApi.gracefully(emptyList()) { ZammadApi.fetchGroups() } }
        val orgs = async { ZammadApi.gracefully(emptyList()) { ZammadApi.fetchOrganizations() } }
        val types = async { ZammadApi.gracefully(emptyList()) { ZammadApi.fetchTimeAccountingTypes() } }

        ticketStates = states.await()
        ticketPriorities = priorities.await()
        val me = user.await()
        currentUser = me
        // Register in the chat directory so colleagues can find us without us
        // opening the chat screen first. Fire-and-forget.
        viewModelScope.launch { try { ChatService.register(me); ChatService.refreshUnreadCount() } catch (e: Exception) { } }
        allUsers = users.await()
        roles = loadedRoles.await()
        groups = loadedGroups.await()
        organizations = orgs.await()
        timeAccountingTypes = types.await().filter { it.active }
        isTimeAccountingEnabled = timeAccountingTypes.isNotEmpty()
    }

    /** Search clause selecting every non-closed state, or null before states loaded. */
    private val openStatesQuery: String?
        get() {
            val ids = ticketStates.filter { it.name.lowercase() !in listOf("closed", "gesloten") }.map { it.id }
            return if (ids.isEmpty()) null else "state_id:(${ids.joinToString(" OR ")})"
        }

    /** Open tickets whose nearest SLA deadline has passed. */
    private val escalatedQuery: String? get() = openStatesQuery?.let { "escalation_at:[* TO now] AND $it" }

    /** Count only; a failure (old Zammad, no permission) simply shows no badge. */
    private suspend fun fetchEscalatedCount(): Int {
        val query = escalatedQuery ?: return 0
        return try { ZammadApi.countTickets(query) } catch (e: CancellationException) { throw e } catch (e: Exception) { 0 }
    }

    private suspend fun fetchTickets(filter: TicketFilter): List<Ticket> {
        val open = openStatesQuery ?: return emptyList()
        return when (filter) {
            TicketFilter.MyTickets -> {
                val userId = currentUser?.id ?: throw ApiException.UserNotFound()
                ZammadApi.searchTickets("owner_id:$userId AND $open")
            }
            TicketFilter.Unassigned -> ZammadApi.searchTickets("owner_id:1 AND $open")
            TicketFilter.AllOpen -> ZammadApi.searchTickets(open)
            TicketFilter.Escalated -> ZammadApi.searchTickets(escalatedQuery!!)
                .sortedBy { it.escalation_at ?: Instant.MAX }
            is TicketFilter.ByStatus -> ZammadApi.fetchTicketsByStatus(filter.id)
        }
    }

    /** A ticket by id from what is loaded, without a network call. */
    fun cachedTicket(id: Int): Ticket? =
        currentTickets.firstOrNull { it.id == id } ?: searchedTickets?.firstOrNull { it.id == id }

    /**
     * Resolves a notification's number to a ticket: a database id first, then a
     * ticket *number* (webhook titles carry the number, not the id).
     */
    suspend fun handleDeepLink(ticketID: Int): Ticket? {
        cachedTicket(ticketID)?.let { return it }
        if (currentUser == null) refreshAllData()
        try {
            return ZammadApi.fetchTicket(ticketID)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) { }
        try {
            ZammadApi.searchTickets("number:$ticketID").firstOrNull()?.let { return it }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) { }
        errorMessage = "Ticket #$ticketID"
        return null
    }

    // --- Update & reply ---

    /**
     * Saves owner/state/priority/customer. Returns true when Zammad refuses
     * because the chosen state needs a pending time; the caller then asks for
     * one and calls again with [pendingTime].
     */
    suspend fun updateTicket(ticket: Ticket, pendingTime: Instant? = null): Boolean {
        val payload = TicketUpdatePayload(
            ticket.owner_id, ticket.state_id, ticket.priority_id, ticket.customer_id,
            pendingTime?.truncatedTo(ChronoUnit.SECONDS)?.toString(),
        )
        try {
            ZammadApi.updateTicket(ticket.id, payload)
            refreshAllData()
            return false
        } catch (e: ApiException.Server) {
            if (e.statusCode == 422 && e.serverError?.contains("pending_time") == true) return true
            throw e
        }
    }

    class NoClosedStateException : Exception()

    /** "closed" by name first, by state type (5 on every Zammad install) as fallback. */
    private val closedState: TicketState?
        get() = ticketStates.firstOrNull { it.name.lowercase() in listOf("closed", "gesloten", "geschlossen", "fermé") }
            ?: ticketStates.firstOrNull { it.state_type_id == 5 }

    /**
     * Mirrors Zammad's "Close & Tag as Spam" macro: tag first, so a ticket that
     * cannot be closed still carries the spam marker. Throws
     * [NoClosedStateException] (show `close_as_spam_no_closed_state`).
     */
    suspend fun closeAsSpam(ticket: Ticket) {
        val closed = closedState ?: throw NoClosedStateException()
        ZammadApi.addTag(ticket.id, "spam")
        ZammadApi.updateTicket(ticket.id,
            TicketUpdatePayload(ticket.owner_id, closed.id, ticket.priority_id, ticket.customer_id))
        refreshAllData()
    }

    suspend fun sendReply(ticket: Ticket, body: String, subject: String, recipient: String,
                          attachments: List<AttachmentDraft> = emptyList()) {
        ZammadApi.createArticle(ArticleCreationPayload(
            ticket.id, body, recipient, subject, false, "email",
            attachments.takeIf { it.isNotEmpty() }?.map { it.uploadPayload }))
    }

    suspend fun addInternalNote(ticket: Ticket, body: String, attachments: List<AttachmentDraft> = emptyList()) {
        ZammadApi.createArticle(ArticleCreationPayload(
            ticket.id, body, "", ticket.title, true, "note",
            attachments.takeIf { it.isNotEmpty() }?.map { it.uploadPayload }))
    }

    suspend fun createTicket(title: String, groupId: Int, customerId: Int, stateId: Int, priorityId: Int,
                             ownerId: Int?, tags: String?, articleBody: String, articleType: String) {
        ZammadApi.createTicket(TicketCreationPayload(
            title, groupId, customerId, stateId, priorityId, ownerId, tags,
            TicketCreationPayload.ArticlePayload(articleBody, articleType, false)))
        refreshAllData()
    }

    suspend fun downloadAttachment(attachment: Attachment, articleId: Int, ticketId: Int): File =
        ZammadApi.downloadAttachment(ctx, ticketId, articleId, attachment)

    suspend fun addSpentTime(ticket: Ticket, time: String, typeId: Int) {
        ZammadApi.createTimeAccounting(ticket.id, TimeAccountingPayload(time, typeId))
        refreshAllData()
    }

    // --- Names & formatting ---

    fun stateName(id: Int): String = ticketStates.firstOrNull { it.id == id }?.name ?: ctx.getString(R.string.unknown)
    fun priorityName(id: Int): String = ticketPriorities.firstOrNull { it.id == id }?.name ?: ctx.getString(R.string.unknown)

    fun userName(id: Int): String {
        val user = allUsers.firstOrNull { it.id == id } ?: return ctx.getString(R.string.unassigned)
        return organizationName(user.organization_id)?.let { "${user.fullname} ($it)" } ?: user.fullname
    }

    fun userEmail(id: Int): String? = allUsers.firstOrNull { it.id == id }?.email
    fun organizationName(id: Int?): String? = id?.let { oid -> organizations.firstOrNull { it.id == oid }?.name }

    private fun capitalized(name: String) = name.replaceFirstChar { it.uppercase() }

    fun localizedStatusName(statusName: String): String = when (statusName.lowercase()) {
        "new" -> ctx.getString(R.string.status_new)
        "pending reminder" -> ctx.getString(R.string.status_pending_reminder)
        "closed" -> ctx.getString(R.string.status_closed)
        "merged" -> ctx.getString(R.string.status_merged)
        "pending close" -> ctx.getString(R.string.status_pending_close)
        else -> capitalized(statusName)
    }

    fun localizedPriorityName(priorityName: String): String = when (priorityName.lowercase()) {
        "1 low" -> ctx.getString(R.string.priority_low)
        "2 normal" -> ctx.getString(R.string.priority_normal)
        "3 high" -> ctx.getString(R.string.priority_high)
        else -> capitalized(priorityName)
    }

    fun colorForStatus(name: String): Color = when (name.lowercase()) {
        "new" -> Color(0xFF34C759)
        "open", "in behandeling" -> Color(0xFFE6B800)
        "pending reminder", "pending close" -> Color(0xFFFF9500)
        "merged" -> Color(0xFFFF2D55)
        "closed" -> Color(0xFF8E8E93)
        else -> Color(0xFF8E8E93)
    }

    fun colorForPriority(name: String): Color = when (name.lowercase()) {
        "1 low" -> Color(0xFF34C759)
        "2 normal" -> Color(0xFF007AFF)
        "3 high" -> Color(0xFFFF3B30)
        else -> Color(0xFF8E8E93)
    }
}
