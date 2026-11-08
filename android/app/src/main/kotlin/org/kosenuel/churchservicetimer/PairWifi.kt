package org.kosenuel.churchservicetimer

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Rejoins the one Wi-Fi network a paired phone joined its host on (church
 * Wi-Fi, the host's hotspot or the sign's Wi-Fi). Only that remembered network
 * is ever requested; other known networks are never tried. While joined, the
 * process is bound to it so the pairing socket uses that route. */
class PairWifi(context: Context, private val vault: DisplayCredentialVault) {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val prefs = context.getSharedPreferences("pair-wifi", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var pending: MethodChannel.Result? = null
    private var epoch = 0
    /** Passwords the user chose not to store: kept only while the app runs. */
    private val unsaved = mutableMapOf<String, String>()
    private fun password(host: String) = vault.read("pairwifi:$host") ?: unsaved[host]

    fun info(host: String): Map<String, Any> {
        val raw = prefs.getString(host, null)
        val j = if (raw == null) JSONObject() else JSONObject(raw)
        return mapOf("ssid" to j.optString("ssid"), "security" to j.optString("security", "wpa2"),
            "kind" to j.optString("kind", "church"), "passwordSaved" to vault.contains("pairwifi:$host"),
            "supported" to (Build.VERSION.SDK_INT >= 29), "wifiEnabled" to wifi.isWifiEnabled)
    }

    fun save(host: String, ssid: String, security: String, kind: String, password: String?, store: Boolean) {
        require(host.isNotBlank()) { "Join a host first." }
        require(ssid.isNotBlank() && ssid.toByteArray(Charsets.UTF_8).size <= 32 && !ssid.any { it < ' ' }) { "Enter a Wi-Fi name of 1–32 bytes." }
        require(security in setOf("open", "wpa2", "wpa3")) { "Choose Open, WPA2 or WPA3." }
        require(kind in setOf("church", "hotspot", "sign")) { "Choose how this phone joined." }
        unsaved.remove(host)
        if (security == "open") vault.forget("pairwifi:$host")
        else if (!password.isNullOrEmpty()) {
            require(password.length in 8..63 && password.all { it.code in 32..126 }) { "Enter the Wi-Fi password (8–63 characters)." }
            if (store) vault.save("pairwifi:$host", password)
            else { vault.forget("pairwifi:$host"); unsaved[host] = password }
        }
        check(prefs.edit().putString(host, JSONObject().put("ssid", ssid).put("security", security).put("kind", kind).toString()).commit())
    }

    fun forget(host: String) {
        cancel()
        check(prefs.edit().remove(host).commit())
        vault.forget("pairwifi:$host")
        unsaved.remove(host)
    }

    fun cancel() {
        epoch++
        pending?.error("CANCELLED", "Wi-Fi rejoin cancelled.", null)
        pending = null
        callback?.let { try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        callback = null
        try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
    }

    fun request(host: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) { result.error("WIFI_SETTINGS", "Rejoin from Android Wi-Fi settings on this phone.", null); return }
        if (!wifi.isWifiEnabled) { result.error("WIFI_OFF", "Turn on Wi-Fi to rejoin the host.", null); return }
        try {
            val profile = info(host)
            val ssid = profile["ssid"] as String
            require(ssid.isNotEmpty()) { "No network was remembered for this host." }
            val spec = WifiNetworkSpecifier.Builder().setSsid(ssid)
            when (profile["security"]) {
                "wpa2" -> spec.setWpa2Passphrase(password(host) ?: error("No saved password."))
                "wpa3" -> spec.setWpa3Passphrase(password(host) ?: error("No saved password."))
            }
            val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(spec.build()).build()
            cancel()
            pending = result
            val token = epoch
            val listener = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { main.post {
                    if (token != epoch) return@post
                    try { cm.bindProcessToNetwork(network) } catch (_: Exception) {}
                    pending?.success(true); pending = null
                } }
                override fun onLost(network: Network) { main.post {
                    if (token == epoch) try { cm.bindProcessToNetwork(null) } catch (_: Exception) {}
                } }
                override fun onUnavailable() { main.post {
                    if (token != epoch) return@post
                    pending?.error("WIFI_UNAVAILABLE", "Could not rejoin $ssid. Check it is in range.", null)
                    pending = null
                    cancel()
                } }
            }
            callback = listener
            cm.requestNetwork(request, listener, 30000)
        } catch (_: SecurityException) {
            pending = null
            cancel()
            result.error("WIFI_PERMISSION", "Allow nearby Wi-Fi access (or Location on older Android) to rejoin automatically.", null)
        } catch (_: Exception) {
            // Never return the request object or the stored password in errors.
            if (pending === result) pending = null
            cancel()
            result.error("WIFI", "Could not rejoin the remembered Wi-Fi.", null)
        }
    }
}
