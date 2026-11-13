package com.baseonline.zammadmobile.managers

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.baseonline.zammadmobile.R
import com.baseonline.zammadmobile.data.SettingsManager
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

/** App lock with fingerprint/face or the device PIN, like the iOS Face ID lock. */
object AuthenticationManager {
    var isUnlocked by mutableStateOf(false); private set
    private var isPrompting = false

    fun authenticate(activity: FragmentActivity) {
        if (!SettingsManager.isLockEnabled) { isUnlocked = true; return }
        if (isUnlocked || isPrompting) return
        val authenticators = BIOMETRIC_WEAK or DEVICE_CREDENTIAL
        // A device without any screen lock cannot be asked: let the user in
        // rather than lock them out of their own app.
        if (BiometricManager.from(activity).canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
            isUnlocked = true; return
        }
        isPrompting = true
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    isPrompting = false; isUnlocked = true
                }
                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    isPrompting = false; isUnlocked = false
                }
            })
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(activity.getString(R.string.app_locked))
                .setSubtitle(activity.getString(R.string.unlock_reason))
                .setAllowedAuthenticators(authenticators)
                .build()
        )
    }

    /** True when the device has a screen lock the app lock can lean on. */
    fun canLock(context: Context): Boolean =
        BiometricManager.from(context).canAuthenticate(BIOMETRIC_WEAK or DEVICE_CREDENTIAL) == BiometricManager.BIOMETRIC_SUCCESS

    fun lock() { if (SettingsManager.isLockEnabled && !isPrompting) isUnlocked = false }
}

/**
 * Shares the server URL and API token with the Wear OS companion over the
 * Wearable Data Layer (the counterpart of WatchConnectivity on iOS). The watch
 * app talks to Zammad directly with them. Contract with the `wear` module:
 * data item `/zammad/credentials` with string keys `server_url` and `token`.
 */
object WearSync {
    const val PATH = "/zammad/credentials"

    fun push(context: Context) {
        val token = SettingsManager.loadToken()
        val url = SettingsManager.loadServerURL()
        try {
            val client = Wearable.getDataClient(context.applicationContext)
            if (token == null || url.isEmpty() || !SettingsManager.isSetupComplete) {
                client.deleteDataItems(Uri.parse("wear://*$PATH"))
                return
            }
            val request = PutDataMapRequest.create(PATH).apply {
                dataMap.putString("server_url", url)
                dataMap.putString("token", token)
                dataMap.putLong("updated", System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            client.putDataItem(request)
        } catch (e: Exception) {
            // No Play services / no watch paired: nothing to sync to.
            Log.i("WearSync", "Skipped: ${e.message}")
        }
    }
}
