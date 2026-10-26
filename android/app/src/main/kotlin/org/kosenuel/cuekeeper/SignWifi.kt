package org.kosenuel.cuekeeper

import android.content.Context
import android.net.ConnectivityManager
import android.net.MacAddress
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

/** User-initiated, exact-SSID local-only requests. No process-wide binding:
 * only W2 sockets use the returned Network; pairing/internet keep their route.
 * The request remains registered to let Android recover a transient loss.
 * Call cancel on explicit disconnect, destination switch and engine shutdown.
 */
class SignWifi(private val context: Context, private val vault: DisplayCredentialVault,
               private val selected: (Network?) -> Unit) {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val prefs = context.getSharedPreferences("sign-wifi", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var pending: MethodChannel.Result? = null
    private var epoch = 0
    private var activeNetwork: Network? = null

    fun info(id: String): Map<String, Any> {
        val raw = prefs.getString(id, null)
        val j = if (raw == null) JSONObject() else JSONObject(raw)
        return mapOf("ssid" to j.optString("ssid"), "security" to j.optString("security", "wpa2"),
            "bssid" to j.optString("bssid"), "passwordSaved" to vault.contains("wifi:$id"),
            "supported" to (Build.VERSION.SDK_INT >= 29), "wifiEnabled" to wifi.isWifiEnabled)
    }
    fun save(id: String, ssid: String, security: String, password: String?, bssid: String) {
        require(id.isNotBlank()) { "Select a remembered display first." }
        require(ssid.isNotBlank() && ssid.toByteArray(Charsets.UTF_8).size <= 32 && !ssid.any { it < ' ' }) { "Enter a Wi-Fi name of 1–32 bytes." }
        require(security in setOf("open", "wpa2", "wpa3")) { "Choose Open, WPA2 or WPA3." }
        if (bssid.isNotEmpty()) MacAddress.fromString(bssid)
        val previous = info(id)
        if (security != "open") {
            val value = password ?: if ((previous["ssid"] == ssid || previous["ssid"] == "") && previous["security"] == security) vault.read("wifi:$id") else null
            require(value != null && value.length in 8..63 && value.all { it.code in 32..126 }) { "Enter the sign's Wi-Fi password (8–63 characters)." }
            vault.save("wifi:$id", value)
        } else vault.forget("wifi:$id")
        check(prefs.edit().putString(id, JSONObject().put("ssid", ssid).put("security", security).put("bssid", bssid).toString()).commit())
    }
    fun forget(id: String) {
        check(prefs.edit().remove(id).commit())
        vault.forget("wifi:$id")
    }
    fun cancel() {
        epoch++
        pending?.error("CANCELLED", "Wi-Fi connection cancelled.", null)
        pending = null
        callback?.let { try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        callback = null
        activeNetwork = null
        selected(null)
    }
    fun request(id: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) { result.error("WIFI_SETTINGS", "Use Android Wi-Fi settings on this phone, then retry.", null); return }
        if (!wifi.isWifiEnabled) { result.error("WIFI_OFF", "Turn on Wi-Fi, then reconnect.", null); return }
        try {
            val profile = info(id)
            val ssid = profile["ssid"] as String
            require(ssid.isNotEmpty()) { "Save the sign's Wi-Fi details first." }
            val spec = WifiNetworkSpecifier.Builder().setSsid(ssid)
            val bssid = profile["bssid"] as String
            if (bssid.isNotEmpty()) spec.setBssid(MacAddress.fromString(bssid))
            when (profile["security"]) {
                "wpa2" -> spec.setWpa2Passphrase(vault.read("wifi:$id") ?: error("Enter the saved Wi-Fi password again."))
                "wpa3" -> spec.setWpa3Passphrase(vault.read("wifi:$id") ?: error("Enter the saved Wi-Fi password again."))
            }
            val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).setNetworkSpecifier(spec.build()).build()
            cancel()
            pending = result
            val token = epoch
            val listener = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) { main.post {
                    if (token != epoch) return@post
                    activeNetwork = network
                    selected(network)
                    pending?.success(true); pending = null
                } }
                override fun onLost(network: Network) { main.post { if (token == epoch && network == activeNetwork) { activeNetwork = null; selected(null) } } }
                override fun onUnavailable() { main.post {
                    if (token != epoch) return@post
                    pending?.error("WIFI_UNAVAILABLE", "Wi-Fi was not joined. Check the sign is powered on, its password, and Android's connection approval.", null)
                    pending = null
                    cancel()
                } }
            }
            callback = listener
            cm.requestNetwork(request, listener, 30000)
        } catch (_: SecurityException) {
            pending = null
            cancel()
            result.error("WIFI_PERMISSION", "Allow nearby Wi-Fi access (or Location on older Android), then retry.", null)
        } catch (e: Exception) {
            // Never return the request object or supplied password in errors.
            val ownsResult = pending === result
            if (ownsResult) pending = null
            cancel()
            result.error("WIFI", "Could not join the saved Wi-Fi. Review its name, security and password in Wi-Fi reconnect details.", null)
        }
    }
}
