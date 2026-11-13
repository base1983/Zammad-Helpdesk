package com.baseonline.zammadmobile.managers

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.data.ZammadApi
import java.util.concurrent.TimeUnit

/**
 * Periodic check for tickets created since the last check, shown as a local
 * notification. The counterpart of the iOS BGAppRefreshTask; Android runs it
 * roughly every 15 minutes when there is a network connection.
 */
class BackgroundRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        if (!SettingsManager.isSetupComplete || SettingsManager.loadToken() == null) return Result.success()
        val lastFetch = SettingsManager.loadLastFetchMillis()
        if (lastFetch == 0L) {
            // First run: start counting from now instead of announcing every open ticket.
            SettingsManager.saveLastFetchMillis(System.currentTimeMillis())
            return Result.success()
        }
        return try {
            val openIds = ZammadApi.fetchTicketStates()
                .filter { it.name.lowercase() !in listOf("closed", "gesloten") }.map { it.id }
            if (openIds.isEmpty()) return Result.success()
            val tickets = ZammadApi.searchTickets("state_id:(${openIds.joinToString(" OR ")})")
            val fresh = tickets.filter { it.created_at.toEpochMilli() > lastFetch }
            if (fresh.isNotEmpty()) {
                val first = fresh.minBy { it.created_at }
                PushManager.notify(
                    applicationContext, PushManager.CHANNEL_TICKETS,
                    applicationContext.getString(R.string.new_tickets_notification_title, fresh.size),
                    fresh.joinToString("\n") { it.title },
                    mapOf("ticketID" to first.id.toString()),
                )
                SettingsManager.saveLastFetchMillis(fresh.maxOf { it.created_at.toEpochMilli() })
            }
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    companion object {
        private const val NAME = "ticket_refresh"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<BackgroundRefreshWorker>(15, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.KEEP, request)
        }

        fun cancel(context: Context) { WorkManager.getInstance(context).cancelUniqueWork(NAME) }
    }
}
