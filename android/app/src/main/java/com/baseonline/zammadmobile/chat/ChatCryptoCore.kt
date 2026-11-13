package com.baseonline.zammadmobile.chat

import org.bouncycastle.crypto.agreement.X25519Agreement
import org.bouncycastle.crypto.digests.SHA256Digest
import org.bouncycastle.crypto.generators.HKDFBytesGenerator
import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.HKDFParameters
import org.bouncycastle.crypto.params.KeyParameter
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters
import java.security.SecureRandom

/**
 * The byte-level primitives of the chat's end-to-end encryption, free of any
 * Android dependency so they can be unit-tested on the JVM against vectors
 * produced by the iOS app's CryptoKit code (see ChatCryptoInteropTest).
 *
 * Must stay bit-compatible with `ChatCrypto` in ChatService.swift:
 *  - key agreement  X25519 (raw 32-byte keys)
 *  - pairwise key   HKDF-SHA256(ikm = shared secret, salt = "zammad-helpdesk-chat-v1",
 *                   info = empty, 32 bytes)
 *  - sealing        ChaCha20-Poly1305, "combined" layout: nonce(12) ‖ ciphertext ‖ tag(16)
 */
object ChatCryptoCore {
    private val SALT = "zammad-helpdesk-chat-v1".toByteArray(Charsets.UTF_8)
    private const val NONCE_SIZE = 12
    private const val TAG_BITS = 128
    private val random = SecureRandom()

    fun generatePrivateKey(): ByteArray = X25519PrivateKeyParameters(random).encoded

    fun publicKey(privateKey: ByteArray): ByteArray =
        X25519PrivateKeyParameters(privateKey, 0).generatePublicKey().encoded

    fun randomKey(): ByteArray = ByteArray(32).also { random.nextBytes(it) }

    /** The symmetric key two devices share; symmetric in its arguments' owners. */
    fun pairwiseKey(privateKey: ByteArray, partnerPublicKey: ByteArray): ByteArray {
        require(partnerPublicKey.size == 32) { "X25519 public keys are 32 bytes" }
        val agreement = X25519Agreement()
        agreement.init(X25519PrivateKeyParameters(privateKey, 0))
        val secret = ByteArray(agreement.agreementSize)
        agreement.calculateAgreement(X25519PublicKeyParameters(partnerPublicKey, 0), secret, 0)
        val hkdf = HKDFBytesGenerator(SHA256Digest())
        hkdf.init(HKDFParameters(secret, SALT, ByteArray(0)))
        return ByteArray(32).also { hkdf.generateBytes(it, 0, 32) }
    }

    /** ChaChaPoly.seal(...).combined */
    fun seal(plaintext: ByteArray, key: ByteArray, nonce: ByteArray = ByteArray(NONCE_SIZE).also { random.nextBytes(it) }): ByteArray {
        val cipher = ChaCha20Poly1305()
        cipher.init(true, AEADParameters(KeyParameter(key), TAG_BITS, nonce))
        val out = ByteArray(cipher.getOutputSize(plaintext.size))
        val written = cipher.processBytes(plaintext, 0, plaintext.size, out, 0)
        cipher.doFinal(out, written)
        return nonce + out
    }

    /** ChaChaPoly.open(SealedBox(combined:)); throws when the key or data is wrong. */
    fun open(combined: ByteArray, key: ByteArray): ByteArray {
        require(combined.size >= NONCE_SIZE + TAG_BITS / 8) { "sealed box too short" }
        val cipher = ChaCha20Poly1305()
        cipher.init(false, AEADParameters(KeyParameter(key), TAG_BITS, combined.copyOfRange(0, NONCE_SIZE)))
        val length = combined.size - NONCE_SIZE
        val out = ByteArray(cipher.getOutputSize(length))
        val written = cipher.processBytes(combined, NONCE_SIZE, length, out, 0)
        val total = written + cipher.doFinal(out, written)
        return if (total == out.size) out else out.copyOf(total)
    }
}
