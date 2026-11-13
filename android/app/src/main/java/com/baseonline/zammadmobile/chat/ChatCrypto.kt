package com.baseonline.zammadmobile.chat

import android.util.Base64
import com.baseonline.zammadmobile.data.SecureStore
import java.util.UUID

/**
 * End-to-end encryption for chat, the Android twin of `ChatCrypto` in
 * ChatService.swift. This device holds one Curve25519 key pair (private key in
 * [SecureStore], public key published per device in the chat directory).
 * Bodies and attachments are sealed with a content key (random per direct
 * message, long-lived per group) and that key is wrapped per recipient device
 * with the pairwise ECDH+HKDF key. The relay only ever stores ciphertext.
 */
object ChatCrypto {
    private const val PRIVATE_KEY = "chat_e2e_private_key"
    private const val DEVICE_ID = "chat_device_id"
    const val PREFIX = "enc1:"

    private fun b64(data: ByteArray): String = Base64.encodeToString(data, Base64.NO_WRAP)
    private fun unb64(text: String): ByteArray? = try { Base64.decode(text, Base64.DEFAULT) } catch (e: Exception) { null }

    /** Stable per install; kept next to the private key so the two travel together. */
    val deviceId: String
        @Synchronized get() {
            SecureStore.load(DEVICE_ID)?.takeIf { it.isNotEmpty() }?.let { return it }
            return UUID.randomUUID().toString().uppercase().also { SecureStore.save(it, DEVICE_ID) }
        }

    @Synchronized
    private fun privateKey(): ByteArray {
        SecureStore.load(PRIVATE_KEY)?.let(::unb64)?.takeIf { it.size == 32 }?.let { return it }
        return ChatCryptoCore.generatePrivateKey().also { SecureStore.save(b64(it), PRIVATE_KEY) }
    }

    val publicKeyBase64: String get() = b64(ChatCryptoCore.publicKey(privateKey()))

    /** Drops this device's identity; messages wrapped for the old one stay sealed. */
    fun resetIdentity() {
        SecureStore.delete(PRIVATE_KEY)
        SecureStore.delete(DEVICE_ID)
    }

    fun isEncrypted(body: String) = body.startsWith(PREFIX)

    private fun pairwiseKey(partnerPublicKeyBase64: String): ByteArray {
        val partner = unb64(partnerPublicKeyBase64) ?: throw IllegalArgumentException("bad public key")
        return ChatCryptoCore.pairwiseKey(privateKey(), partner)
    }

    fun generateContentKey(): ByteArray = ChatCryptoCore.randomKey()

    /** Wraps a content key for one device, using our pairwise key with it. */
    fun wrapKey(contentKey: ByteArray, devicePublicKey: String): String =
        b64(ChatCryptoCore.seal(contentKey, pairwiseKey(devicePublicKey)))

    /** Unwraps our copy of a content key against the device that wrapped it. */
    fun unwrapKey(wrapped: String, wrapperPublicKey: String): ByteArray? = try {
        ChatCryptoCore.open(unb64(wrapped)!!, pairwiseKey(wrapperPublicKey))
    } catch (e: Exception) { null }

    fun encrypt(plaintext: String, contentKey: ByteArray): String =
        PREFIX + b64(ChatCryptoCore.seal(plaintext.toByteArray(Charsets.UTF_8), contentKey))

    /**
     * Plaintext for encrypted bodies, the body unchanged when it is not
     * encrypted, or null when this device holds no key for it (the caller shows
     * the "encrypted message" placeholder).
     */
    fun decrypt(body: String, contentKey: ByteArray?): String? {
        if (!body.startsWith(PREFIX)) return body
        if (contentKey == null) return null
        return try {
            String(ChatCryptoCore.open(unb64(body.substring(PREFIX.length))!!, contentKey), Charsets.UTF_8)
        } catch (e: Exception) { null }
    }

    fun encryptData(data: ByteArray, contentKey: ByteArray): ByteArray = ChatCryptoCore.seal(data, contentKey)
    fun decryptData(data: ByteArray, contentKey: ByteArray): ByteArray = ChatCryptoCore.open(data, contentKey)
}
