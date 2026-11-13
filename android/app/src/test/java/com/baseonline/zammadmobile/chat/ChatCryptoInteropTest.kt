package com.baseonline.zammadmobile.chat

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Base64

/**
 * Proves the Android primitives are bit-compatible with the iOS app. The
 * vectors below were produced by CryptoKit on macOS with the exact calls in
 * ChatService.swift (Curve25519.KeyAgreement, hkdfDerivedSymmetricKey with
 * salt "zammad-helpdesk-chat-v1", ChaChaPoly.seal(...).combined), using two
 * fixed throw-away private keys: bytes 1..32 (device A) and 101..132 (device B).
 */
class ChatCryptoInteropTest {
    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    private fun b64(s: String) = Base64.getDecoder().decode(s)

    private val aPriv = hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
    private val aPub = b64("B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=")
    private val bPriv = hex("65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384")
    private val bPub = b64("VxR2nRFr92Q2rnS8eT0sMK0ZA8WaxSc4BcfiaYtBDDY=")
    private val pairwise = hex("3208f1fec6cd797dbd2105283d5c9cc76adc84d1b60279f3979bc139cae147a0")
    private val wrapped = b64("ixrzMyVTkWf5P10D5iWCVs0XaiGTZz6kiATXxZrbiPjJiGQ6yKBP+kwVeHrCwmuy99hmpncTxpwdUve6")
    private val body = "+7iHf7Hog+3nowNt3wbWLGFGPuwXPb2QktWcJ4557zdbv4MSUIRaF+OJM0lU8YrhWaZzXf7hw3dlI5v1SHCw"
    private val contentKey = ByteArray(32) { (200 + it).toByte() }

    @Test fun publicKeysMatchCryptoKit() {
        assertArrayEquals(aPub, ChatCryptoCore.publicKey(aPriv))
        assertArrayEquals(bPub, ChatCryptoCore.publicKey(bPriv))
    }

    @Test fun pairwiseKeyMatchesCryptoKitFromBothSides() {
        assertArrayEquals(pairwise, ChatCryptoCore.pairwiseKey(aPriv, bPub))
        assertArrayEquals(pairwise, ChatCryptoCore.pairwiseKey(bPriv, aPub))
    }

    @Test fun opensKeyWrappedByIos() {
        // iOS device A wrapped the content key for device B.
        val key = ChatCryptoCore.open(wrapped, ChatCryptoCore.pairwiseKey(bPriv, aPub))
        assertArrayEquals(contentKey, key)
    }

    @Test fun opensBodySealedByIos() {
        val plain = String(ChatCryptoCore.open(b64(body), contentKey), Charsets.UTF_8)
        assertEquals("Hallo vanaf iOS — ünïcödé ✓", plain)
    }

    @Test fun sealOpenRoundTrip() {
        val data = ByteArray(100_000) { (it * 31).toByte() }
        assertArrayEquals(data, ChatCryptoCore.open(ChatCryptoCore.seal(data, contentKey), contentKey))
    }

    @Test(expected = Exception::class) fun rejectsTamperedCiphertext() {
        val sealed = ChatCryptoCore.seal("x".toByteArray(), contentKey)
        sealed[sealed.size - 1] = (sealed[sealed.size - 1] + 1).toByte()
        ChatCryptoCore.open(sealed, contentKey)
    }

    /** Prints a message from B to A for the reverse check with the Swift tool (see README). */
    @Test fun printAndroidToIosVector() {
        val key = ChatCryptoCore.randomKey()
        val w = Base64.getEncoder().encodeToString(ChatCryptoCore.seal(key, ChatCryptoCore.pairwiseKey(bPriv, aPub)))
        val wire = "enc1:" + Base64.getEncoder().encodeToString(
            ChatCryptoCore.seal("Hallo vanaf Android ✓".toByteArray(Charsets.UTF_8), key))
        println("ANDROID_VECTOR $w $wire")
    }
}
