package com.baseonline.zammadmobile.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small secrets (the Zammad API token, the chat private key and device id),
 * the counterpart of the iOS `KeychainHelper`. Values are sealed with an
 * AES-256-GCM key that lives in the Android Keystore and never leaves it; only
 * the ciphertext is written to a private SharedPreferences file. The file is
 * excluded from backups (see the manifest), because the Keystore key does not
 * travel with a restore and the ciphertext would be useless on another device.
 */
object SecureStore {
    private const val KEY_ALIAS = "zammad_helpdesk_secure_store_v1"
    private const val PREFS = "secure_store"
    private lateinit var appContext: Context

    fun init(context: Context) { appContext = context.applicationContext }

    private val prefs get() = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    @Synchronized
    fun save(value: String, forKey: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        prefs.edit().putString(forKey, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
    }

    @Synchronized
    fun load(forKey: String): String? {
        val stored = prefs.getString(forKey, null) ?: return null
        return try {
            val data = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data, 0, 12))
            String(cipher.doFinal(data, 12, data.size - 12), Charsets.UTF_8)
        } catch (e: Exception) {
            // Keystore key gone (restore onto a new device, or cleared credentials):
            // the value is unrecoverable, so behave as if it was never stored.
            null
        }
    }

    @Synchronized
    fun delete(forKey: String) { prefs.edit().remove(forKey).apply() }
}
