package com.baseonline.zammadmobile.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.lifecycleScope
import com.baseonline.zammadmobile.wear.data.CredentialStore
import com.baseonline.zammadmobile.wear.ui.WearApp
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val viewModel: TicketViewModel by viewModels()

    // Live updates while the app is open; CredentialListenerService covers the rest.
    private val dataListener = DataClient.OnDataChangedListener { events ->
        CredentialStore.onDataChanged(applicationContext, events)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        CredentialStore.init(this)
        setContent { WearApp(viewModel) }
    }

    override fun onResume() {
        super.onResume()
        try {
            Wearable.getDataClient(this).addListener(dataListener)
        } catch (e: Exception) {
            // No Play services: the stored copy is all there is.
        }
        lifecycleScope.launch { CredentialStore.refresh(applicationContext) }
    }

    override fun onPause() {
        super.onPause()
        try {
            Wearable.getDataClient(this).removeListener(dataListener)
        } catch (e: Exception) {
        }
    }
}
