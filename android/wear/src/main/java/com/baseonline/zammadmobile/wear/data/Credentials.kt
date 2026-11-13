package com.baseonline.zammadmobile.wear.data

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.tasks.await

data class Credentials(val serverUrl: String, val token: String)

/**
 * The credentials the phone app hands over through the Wearable Data Layer:
 * a data item at [PATH] with string keys `server_url` and `token`. The phone
 * deletes the item when the user disconnects, and the watch then drops its copy.
 */
object CredentialStore {
    const val PATH = "/zammad/credentials"
    private const val KEY_URL = "server_url"
    private const val KEY_TOKEN = "token"
    private const val TAG = "CredentialStore"

    private var store: SecureStore? = null
    private val _state = MutableStateFlow<Credentials?>(null)
    val state: StateFlow<Credentials?> = _state

    @Synchronized
    fun init(context: Context) {
        if (store != null) return
        val s = SecureStore(context)
        store = s
        val url = s.load(KEY_URL)
        val token = s.load(KEY_TOKEN)
        _state.value = if (!url.isNullOrEmpty() && !token.isNullOrEmpty()) Credentials(url, token) else null
    }

    @Synchronized
    private fun save(url: String, token: String) {
        val s = store ?: return
        val new = Credentials(url, token)
        if (_state.value == new) return
        s.save(url, KEY_URL)
        s.save(token, KEY_TOKEN)
        _state.value = new
    }

    @Synchronized
    private fun clear() {
        val s = store ?: return
        s.delete(KEY_URL)
        s.delete(KEY_TOKEN)
        _state.value = null
    }

    private fun apply(item: DataItem) {
        val map = DataMapItem.fromDataItem(item).dataMap
        val url = map.getString(KEY_URL).orEmpty()
        val token = map.getString(KEY_TOKEN).orEmpty()
        if (url.isEmpty() || token.isEmpty()) clear() else save(url, token)
    }

    /**
     * Reads the current data item. No item means the phone is signed out (or
     * has never synced), so the local copy goes too; a failing Data Layer call
     * leaves the local copy alone.
     */
    suspend fun refresh(context: Context) {
        init(context)
        try {
            val items = Wearable.getDataClient(context.applicationContext).dataItems.await()
            try {
                val item = items.firstOrNull { it.uri.path == PATH }
                if (item != null) apply(item) else clear()
            } finally {
                items.release()
            }
        } catch (e: Exception) {
            Log.i(TAG, "Data Layer unavailable: ${e.message}")
        }
    }

    fun onDataChanged(context: Context, events: DataEventBuffer) {
        init(context)
        for (event in events) {
            if (event.dataItem.uri.path != PATH) continue
            when (event.type) {
                DataEvent.TYPE_CHANGED -> apply(event.dataItem)
                DataEvent.TYPE_DELETED -> clear()
            }
        }
    }
}

/** Receives credential changes while the watch app is not running. */
class CredentialListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        CredentialStore.onDataChanged(applicationContext, events)
    }
}
