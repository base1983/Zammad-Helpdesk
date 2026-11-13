package com.baseonline.zammadmobile.managers

import androidx.compose.ui.graphics.Color
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.Ticket
import java.time.Duration
import java.time.Instant
import kotlin.math.max
import kotlin.math.roundToLong

/** Where a ticket stands against an SLA deadline. */
sealed class SLAStatus(val color: Color) {
    class Escalated(val overdue: Duration) : SLAStatus(Color(0xFFE53935))
    class DueSoon(val remaining: Duration) : SLAStatus(Color(0xFFFB8C00))
    class OnTrack(val remaining: Duration) : SLAStatus(Color(0xFF43A047))

    val isEscalated get() = this is Escalated

    /** Resource + argument for "%s left" / "%s overdue". */
    val textRes: Int get() = if (this is Escalated) R.string.sla_time_overdue else R.string.sla_time_left

    val shortText: String get() = SLAFormatter.duration(
        when (this) {
            is Escalated -> overdue
            is DueSoon -> remaining
            is OnTrack -> remaining
        }
    )

    companion object {
        private val DUE_SOON = Duration.ofHours(1)
        fun of(deadline: Instant, now: Instant = Instant.now()): SLAStatus {
            val remaining = Duration.between(now, deadline)
            return when {
                remaining.isZero || remaining.isNegative -> Escalated(remaining.negated())
                remaining < DUE_SOON -> DueSoon(remaining)
                else -> OnTrack(remaining)
            }
        }
    }
}

data class SLADeadline(val kind: Kind, val deadline: Instant?, val completedAt: Instant?) {
    enum class Kind(val titleRes: Int) {
        FIRST_RESPONSE(R.string.sla_first_response), UPDATE(R.string.sla_update), SOLUTION(R.string.sla_solution)
    }
    val isMet: Boolean get() = completedAt != null
    fun status(now: Instant = Instant.now()): SLAStatus? =
        if (isMet || deadline == null) null else SLAStatus.of(deadline, now)
}

val Ticket.hasSLA: Boolean
    get() = escalation_at != null || first_response_escalation_at != null || update_escalation_at != null ||
        close_escalation_at != null || (first_response_at != null && first_response_in_min != null)

/** Status against the nearest deadline (Zammad's own `escalation_at`). */
fun Ticket.slaStatus(now: Instant = Instant.now()): SLAStatus? = escalation_at?.let { SLAStatus.of(it, now) }

val Ticket.slaDeadlines: List<SLADeadline>
    get() = listOf(
        SLADeadline(SLADeadline.Kind.FIRST_RESPONSE, first_response_escalation_at, first_response_at),
        SLADeadline(SLADeadline.Kind.UPDATE, update_escalation_at, null),
        SLADeadline(SLADeadline.Kind.SOLUTION, close_escalation_at, close_at),
    ).filter { it.deadline != null || it.isMet }

object SLAFormatter {
    /** Two largest units, e.g. "2d 3h", "4h 10m", "12m"; never below one minute. */
    fun duration(value: Duration): String {
        val minutes = max(1L, (value.seconds / 60.0).roundToLong())
        val d = minutes / 1440
        val h = (minutes % 1440) / 60
        val m = minutes % 60
        return when {
            d > 0 -> if (h > 0) "${d}d ${h}h" else "${d}d"
            h > 0 -> if (m > 0) "${h}h ${m}m" else "${h}h"
            else -> "${m}m"
        }
    }
}
