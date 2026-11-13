package com.baseonline.zammadmobile

import android.app.Application
import android.content.Context
import com.baseonline.zammadmobile.chat.ChatBlockList
import com.baseonline.zammadmobile.chat.ChatHistoryStore
import com.baseonline.zammadmobile.data.SecureStore
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.managers.BackgroundRefreshWorker
import com.baseonline.zammadmobile.managers.DraftManager
import com.baseonline.zammadmobile.managers.PushManager
import com.baseonline.zammadmobile.managers.ReadStatusManager
import com.baseonline.zammadmobile.managers.StoreManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** Application-wide context for the singletons (stores, services). */
object App {
    lateinit var ctx: Context
        internal set
}

class HelpdeskApp : Application() {
    override fun onCreate() {
        super.onCreate()
        App.ctx = this
        SecureStore.init(this)
        SettingsManager.init(this)
        ReadStatusManager.init()
        DraftManager.init(this)
        ChatBlockList.init()
        ChatHistoryStore.init(this)
        PushManager.createChannels(this)
        StoreManager.init(this) // launch entitlement check: Premium comes from Play only
        CoroutineScope(Dispatchers.IO).launch { ChatHistoryStore.pruneAll() }
        if (SettingsManager.isSetupComplete) BackgroundRefreshWorker.schedule(this)
    }
}
