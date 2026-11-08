package org.kosenuel.churchservicetimer

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.security.MessageDigest

/** Pure codecs recovered from the supplied LedArt artifact. No transport or persistence.
 * See docs/DEVICE-ADMIN-0.13.md. Caller wipes passwords and returned bodies after use.
 * Administration setters have not been physically executed on the user's controller.
 */
object W2Administration {
    const val WIFI_COMMAND = 39
    const val DEVICE_PASSWORD_COMMAND = 49
    private const val KEY_SUFFIX = "64ACFEB8B6FE4EF082DB8F3CD428EB20"

    /** Deliberately limited to the exact firmware and capability physically read. */
    fun supported(device: Map<String, Any>): Boolean =
        device["supported"] == true && device["firmware"] == "HD_W2 V6.02.232" &&
            (device["pwdComplexity"] as? Number)?.toInt() == 1

    fun ssidBody(newSsid: String): ByteArray {
        require(newSsid.matches(Regex("[A-Za-z0-9_-]{4,16}"))) {
            "Use 4–16 letters, digits, underscores or hyphens for the Wi-Fi name."
        }
        val bytes = newSsid.toByteArray(Charsets.UTF_8)
        return try { wifiParameter(4, bytes) } finally { bytes.fill(0) }
    }

    fun wifiPasswordBody(password: CharArray): ByteArray {
        validateNewPassword(password)
        val encoded = Charsets.UTF_8.encode(CharBuffer.wrap(password))
        val bytes = ByteArray(encoded.remaining())
        return try {
            encoded.get(bytes)
            wifiParameter(5, bytes)
        } finally {
            bytes.fill(0)
            if (encoded.hasArray()) encoded.array().fill(0)
        }
    }

    fun devicePasswordBody(password: CharArray): ByteArray {
        validateNewPassword(password)
        val joined = CharArray(password.size + KEY_SUFFIX.length)
        password.copyInto(joined)
        KEY_SUFFIX.toCharArray().copyInto(joined, password.size)
        var encoded: ByteBuffer? = null
        var digest: ByteArray? = null
        return try {
            encoded = Charsets.UTF_8.encode(CharBuffer.wrap(joined))
            val md5 = MessageDigest.getInstance("MD5")
            md5.update(encoded)
            digest = md5.digest()
            ByteBuffer.allocate(20).put(4).put(2).putShort(16).put(digest).array()
        } finally {
            joined.fill('\u0000')
            digest?.fill(0)
            encoded?.let { if (it.hasArray()) it.array().fill(0) }
        }
    }

    /** Conservative subset of LedArt's 8–16 character validation. No disable-lock API. */
    fun validateNewPassword(password: CharArray) {
        require(password.size in 8..16 && password.all { it in '!'..'~' }) {
            "Use 8–16 visible English characters without spaces."
        }
        require(password.any { it != password[0] }) { "Use a varied password." }
        val step = password[1].code - password[0].code
        require((2 until password.size).any {
            password[it].code - password[it - 1].code != step
        }) { "Avoid a simple sequence of characters." }
    }

    private fun wifiParameter(parameter: Int, bytes: ByteArray): ByteArray =
        ByteBuffer.allocate(8 + bytes.size).put(8).put(0)
            .putShort(parameter.toShort()).putInt(bytes.size).put(bytes).array()
}
