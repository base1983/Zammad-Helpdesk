package com.baseonline.zammadmobile

import android.content.Intent
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.baseonline.zammadmobile.data.SettingsManager
import com.baseonline.zammadmobile.managers.AdConsentManager
import com.baseonline.zammadmobile.managers.AppOpenAdManager
import com.baseonline.zammadmobile.managers.AuthenticationManager
import com.baseonline.zammadmobile.managers.DeepLinkManager
import com.baseonline.zammadmobile.managers.StoreManager
import com.baseonline.zammadmobile.push.HelpdeskMessagingService
import com.baseonline.zammadmobile.ui.AppRoot
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/** Single activity; everything else is Compose (see ui/AppRoot.kt). */
class MainActivity : FragmentActivity() {
    private val appLifecycle = object : DefaultLifecycleObserver {
        override fun onStart(owner: LifecycleOwner) {
            // App came to the foreground.
            if (!SettingsManager.isSetupComplete) return
            MainScope().launch { StoreManager.checkEntitlements() }
            if (!AuthenticationManager.isUnlocked) {
                AuthenticationManager.authenticate(this@MainActivity)
            } else {
                AppOpenAdManager.presentIfReady(this@MainActivity) {
                    SettingsManager.isSetupComplete && AuthenticationManager.isUnlocked &&
                        DeepLinkManager.pendingTicketID == null
                }
            }
        }
        override fun onStop(owner: LifecycleOwner) = AuthenticationManager.lock()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        AdConsentManager.start(this)
        ProcessLifecycleOwner.get().lifecycle.addObserver(appLifecycle)
        setContent { AppRoot() }
    }

    override fun onDestroy() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(appLifecycle)
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    /** Notification taps carry the routing keys as extras; links come as data. */
    private fun handleIntent(intent: Intent?) {
        intent ?: return
        val extras = intent.extras
        val payload = HelpdeskMessagingService.ROUTING_KEYS
            .mapNotNull { key -> extras?.get(key)?.toString()?.let { key to it } }.toMap()
        if (payload.isNotEmpty()) {
            DeepLinkManager.handlePayload(payload)
            payload.keys.forEach { intent.removeExtra(it) }
        } else if (intent.action == Intent.ACTION_VIEW) {
            intent.dataString?.let { DeepLinkManager.handleUrl(it) }
        }
    }
}
