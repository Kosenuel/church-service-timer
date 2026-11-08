package org.kosenuel.churchservicetimer

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Opt-in local credential storage. Never exported in app backups or diagnostics. */
class DisplayCredentialVault(context: Context, store: String = "display-vault",
    private val alias: String = "church-timer-display-v1", private val maxLength: Int = 128) {
    private val prefs = context.getSharedPreferences(store, Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).setRandomizedEncryptionRequired(true).build())
            generateKey()
        }
    }
    fun save(id: String, password: String) {
        require(id.isNotBlank() && id.length <= 200 && password.isNotEmpty() && password.length <= maxLength)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()); updateAAD(id.toByteArray(Charsets.UTF_8)) }
        val raw = password.toByteArray(Charsets.UTF_8)
        try {
            val encrypted = cipher.doFinal(raw)
            check(prefs.edit().putString(id, Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP)).commit())
        } finally { raw.fill(0) }
    }
    fun contains(id: String): Boolean = prefs.contains(id)
    fun read(id: String): String? {
        val value = prefs.getString(id, null) ?: return null
        try {
            val data = Base64.decode(value, Base64.NO_WRAP)
            require(data.size >= 28)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0,12)))
                updateAAD(id.toByteArray(Charsets.UTF_8))
            }
            val raw = cipher.doFinal(data.copyOfRange(12,data.size))
            return try { raw.toString(Charsets.UTF_8) } finally { raw.fill(0) }
        } catch(e: Exception) { throw IllegalStateException("Saved credential unavailable. Forget it and enter the password again.") }
    }
    fun forget(id: String) { check(prefs.edit().remove(id).commit()) }
}
