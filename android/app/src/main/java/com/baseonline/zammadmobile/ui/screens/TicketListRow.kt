package com.baseonline.zammadmobile.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.TicketViewModel
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.Ticket
import com.baseonline.zammadmobile.managers.DraftManager
import com.baseonline.zammadmobile.managers.ReadStatusManager
import com.baseonline.zammadmobile.managers.SLAStatus
import com.baseonline.zammadmobile.managers.slaStatus
import com.baseonline.zammadmobile.ui.components.glassColor

/**
 * One ticket in the list, the counterpart of the iOS `TicketRowView`: unread
 * dot, title, draft marker, number, customer, and state / priority / SLA chips.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun TicketListRow(
    ticket: Ticket,
    vm: TicketViewModel,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Read so the row recomposes when a ticket is marked read or unread.
    @Suppress("UNUSED_VARIABLE")
    val readVersion = ReadStatusManager.version
    val isUnread = ReadStatusManager.isUnread(ticket, vm.currentUser)
    val hasDraft = DraftManager.hasDraft(ticket.id)
    val rawState = vm.stateName(ticket.state_id)
    val rawPriority = vm.priorityName(ticket.priority_id)
    // SLA information is a Premium feature, as on iOS.
    val sla = if (SettingsManager.isPremium) ticket.slaStatus() else null
    val shape = RoundedCornerShape(12.dp)

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick),
        shape = shape,
        color = glassColor(),
        contentColor = MaterialTheme.colorScheme.onSurface,
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isUnread) {
                    Box(Modifier.size(8.dp).background(Color(0xFF007AFF), CircleShape))
                }
                Text(
                    ticket.title,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = if (isUnread) FontWeight.Bold else FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (hasDraft) {
                    Icon(
                        Icons.Outlined.EditNote,
                        contentDescription = stringResource(R.string.draft_indicator),
                        modifier = Modifier.size(18.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                Text(
                    "#${ticket.number}",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                )
            }

            Text(
                vm.userName(ticket.customer_id),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )

            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Solid colour with black text, as on iOS.
                TicketListChip(vm.localizedStatusName(rawState), vm.colorForStatus(rawState), Color.Black)
                TicketListChip(rawPriority, vm.colorForPriority(rawPriority), Color.Black)
                if (sla != null) {
                    val description = stringResource(sla.textRes, sla.shortText)
                    TicketListChip(
                        sla.shortText, sla.color, Color.White,
                        icon = if (sla is SLAStatus.Escalated) Icons.Filled.Warning else Icons.Outlined.Schedule,
                        modifier = Modifier.clearAndSetSemantics { contentDescription = description },
                    )
                }
            }
        }
    }
}

@Composable
private fun TicketListChip(
    text: String,
    background: Color,
    foreground: Color,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
) {
    Row(
        modifier
            .background(background, RoundedCornerShape(50))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, modifier = Modifier.size(13.dp), tint = foreground)
        Text(text, color = foreground, style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium, maxLines = 1)
    }
}
