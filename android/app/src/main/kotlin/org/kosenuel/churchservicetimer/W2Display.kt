package org.kosenuel.churchservicetimer

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import org.kosenuel.churchservicetimer.w2.Hd7Auth
import org.kosenuel.churchservicetimer.w2.W2Discovery
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.security.GeneralSecurityException
import java.security.SecureRandom
import java.util.TimeZone
import java.util.UUID

/** All operations run on a dedicated serial executor. No password is persisted. */
class W2Display(context: Context) {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val prefs = context.getSharedPreferences("w2-display", Context.MODE_PRIVATE)
    private val random = SecureRandom()
    @Volatile var preferredNetwork: Network? = null
    private var network: Network? = null
    private var socket: DatagramSocket? = null
    private var session: Hd7Auth.Session? = null
    private var device: Map<String, Any>? = null
    private var generation = 0
    private val candidates = mutableMapOf<String, Pair<Network, Map<String, Any>>>()

    fun preferences(): Map<String, Any> = mapOf(
        "hardware" to prefs.getBoolean("hardware", false),
        "id" to (prefs.getString("id", "") ?: ""),
        "autoReconnect" to prefs.getBoolean("autoReconnect", true),
        "name" to (prefs.getString("name", "") ?: "")
    )
    fun autoReconnect(enabled: Boolean) { check(prefs.edit().putBoolean("autoReconnect", enabled).commit()) }
    fun forget() { disconnect(); check(prefs.edit().remove("id").remove("name").putBoolean("hardware", false).commit()) }
    fun simulator() {
        disconnect()
        check(prefs.edit().putBoolean("hardware", false).commit()) { "Could not save output preference" }
    }
    fun disconnect() {
        generation++
        socket?.close(); socket = null
        session?.close(); session = null
        device = null; network = null
    }
    private fun wifi(): Network = preferredNetwork?.takeIf { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true } ?: cm.allNetworks.firstOrNull {
        cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
    } ?: error("Connect the phone to the sign's Wi-Fi, then scan again.")
    private fun open(net: Network): DatagramSocket = DatagramSocket().apply {
        try { net.bindSocket(this); soTimeout = 1000 }
        catch (e: Exception) { close(); throw e }
    }
    private fun scan(net: Network, address: String, timeout: Long): List<Map<String, Any>> {
        val found = linkedMapOf<String, Map<String, Any>>()
        open(net).use { s ->
            s.broadcast = true
            val sequence = random.nextInt()
            val query = W2Discovery.query(sequence)
            s.send(DatagramPacket(query, query.size, InetAddress.getByName(address), W2Discovery.PORT))
            val until = SystemClock.elapsedRealtime() + timeout
            while (SystemClock.elapsedRealtime() < until) {
                s.soTimeout = (until - SystemClock.elapsedRealtime()).coerceIn(1, 1000).toInt()
                val reply = DatagramPacket(ByteArray(4096), 4096)
                try { s.receive(reply) } catch (_: SocketTimeoutException) { continue }
                if (reply.port != W2Discovery.PORT) continue
                try {
                    val d = W2Discovery.decode(reply.data.copyOf(reply.length), sequence, reply.address.hostAddress)
                    found[d["id"] as String] = d
                    if (address != "255.255.255.255") return found.values.toList()
                } catch (_: IllegalArgumentException) { /* Unknown controllers are never written to. */ }
            }
        }
        return found.values.toList()
    }
    fun discover(): List<Map<String, Any>> {
        val net = wifi()
        candidates.clear()
        val found = scan(net, "255.255.255.255", 2200)
        found.forEach { candidates[it["id"] as String] = net to it }
        return found
    }
    fun connect(id: String, password: CharArray): Map<String, Any> {
        try {
            disconnect()
            val (net, selected) = candidates[id] ?: error("Scan again and select the display.")
            val current = scan(net, selected["address"] as String, 1200).firstOrNull { it["id"] == id }
                ?: error("Selected display is no longer reachable. Scan again.")
            check(current["supported"] == true) { "This milestone supports W2 V6.02.232, 32 × 16 red monochrome only." }
            val s = open(net)
            socket = s
            network = net
            s.connect(InetAddress.getByName(current["address"] as String), W2Discovery.PORT)
            val installId = prefs.getString("installation", null) ?: UUID.randomUUID().toString().replace("-", "")
            Hd7Auth.login(password, installId, "ChurchServiceTimer_Android").use { request ->
                exchange(request).use { session = it.loginSession() }
            }
            device = current
            check(prefs.edit().putString("installation", installId).putString("id", id)
                .putString("name", current["name"] as String).putBoolean("hardware", true).commit()) {
                "Could not save display selection"
            }
            return current + mapOf("generation" to generation)
        } catch (e: Exception) { disconnect(); throw e }
        finally { password.fill('\u0000') }
    }
    private fun exchange(request: Hd7Auth.Request, attempts: Int = 2): Hd7Auth.Reply {
        val s = socket ?: error("Display disconnected")
        val wire = request.bytes()
        try {
            // A retry is exactly the same authenticated request, including salt and ID.
            repeat(attempts) {
                s.send(DatagramPacket(wire, wire.size))
                val until = SystemClock.elapsedRealtime() + 1200
                while (SystemClock.elapsedRealtime() < until) {
                    s.soTimeout = (until - SystemClock.elapsedRealtime()).coerceIn(1, 1200).toInt()
                    val packet = DatagramPacket(ByteArray(8192), 8192)
                    try { s.receive(packet) } catch (_: SocketTimeoutException) { break }
                    val reply = try { Hd7Auth.decode(request, packet.data.copyOf(packet.length), 8192) }
                        catch (_: GeneralSecurityException) { continue }
                    if (reply.status != 0) {
                        val status = reply.status
                        reply.close()
                        error(if (status == -125) "Display password was rejected." else "Controller rejected the request ($status). Reconnect before retrying.")
                    }
                    return reply
                }
            }
            error("No acknowledgement from the display. Its last accepted output may still be showing.")
        } finally { wire.fill(0) }
    }
    private fun command(code: Int, body: ByteArray) {
        (session ?: error("Reconnect to the display.")).command(code, body).use { request ->
            exchange(request).close()
        }
    }
    /** Administration never retries: a lost ACK may still mean the setting changed. */
    fun administer(kind: String, value: CharArray, expectedGeneration: Int): Map<String, Any> {
        var body: ByteArray? = null
        try {
            check(expectedGeneration == generation && session != null) { "Reconnect before changing device settings." }
            check(W2Administration.supported(device ?: emptyMap())) { "Administration is not verified for this display." }
            val code = if (kind == "devicePassword") W2Administration.DEVICE_PASSWORD_COMMAND else W2Administration.WIFI_COMMAND
            body = when(kind) {
                "ssid" -> W2Administration.ssidBody(String(value))
                "wifiPassword" -> W2Administration.wifiPasswordBody(value)
                "devicePassword" -> W2Administration.devicePasswordBody(value)
                else -> error("Unknown device setting")
            }
            val accepted = try {
                session!!.command(code, body).use { request -> exchange(request, 1).close() }
                true
            } catch (_: Exception) { false }
            disconnect()
            return mapOf("acknowledged" to accepted)
        } finally { value.fill('\u0000'); body?.fill(0) }
    }
    fun status(): Map<String, Any> {
        val d = device ?: return mapOf("connected" to false)
        return try {
            val net = network ?: error("Wi-Fi disconnected")
            check(cm.getNetworkCapabilities(net)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true)
            val current = scan(net, d["address"] as String, 1000).firstOrNull { it["id"] == d["id"] }
            check(current != null && current["supported"] == true)
            mapOf("connected" to true, "generation" to generation)
        } catch (_: Exception) {
            // A missed discovery reply is not proof that the authenticated session died.
            // Dart applies a grace period before closing and re-authenticating it.
            mapOf("connected" to false, "generation" to generation,
                "reason" to "Controller health reply missing")
        }
    }
    private fun calibrateRtc(now: Long) {
        val localSeconds = (now + TimeZone.getDefault().getOffset(now)) / 1000
        check(localSeconds in 0..0xffffffffL) { "Phone time is outside the controller range." }
        command(20, ByteBuffer.allocate(14).put(14.toByte()).putInt(localSeconds.toInt())
            .put(0.toByte()).putInt(0).putInt(0).array())
    }
    /** Only the compact numeric clock layouts produced by W2Program.clock. */
    private fun validateClock(bytes: ByteArray) {
        check(bytes.size == 444 || bytes.size == 500) { "Invalid clock program length" }
        val twelve = bytes[148] == 6.toByte()
        check(bytes[148] == 1.toByte() || twelve) { "Invalid clock time format" }
        val suffixBytes = if (twelve) 56 else 0
        check(bytes.size == 444 + suffixBytes) { "Invalid clock glyph data" }
        val header = ByteBuffer.allocate(94)
        header.putShort(0, 94.toShort())
        header.put(2, 0x32.toByte())
        header.put(6, 0xff.toByte()); header.put(7, 0xff.toByte())
        header.put(8, if (twelve) 6.toByte() else 1.toByte())
        header.putShort(29, 14.toShort())
        header.putShort(31, (if (twelve) 4 else 6).toShort())
        header.putInt(35, 135); header.putInt(41, 135)
        header.putShort(47, (if (twelve) 12 else 0).toShort())
        header.putInt(49, 135); header.putInt(53, 1)
        header.putInt(65, 135 + suffixBytes)
        header.putInt(69, bytes.size - 99); header.putInt(73, bytes.size - 99)
        header.putInt(86, 1)
        check(bytes.copyOfRange(140, 234).contentEquals(header.array())) { "Invalid clock layout" }
        val data = ByteBuffer.wrap(bytes)
        check(data.getInt(19) == 0 && data.getInt(27) == 31 &&
            bytes[99] == 'H'.code.toByte() && bytes[100] == 'A'.code.toByte() &&
            data.getShort(107).toInt() == 32 && data.getShort(109).toInt() == 16 &&
            data.getShort(111).toInt() == 1 && data.getInt(136) == 41) { "Invalid clock display area" }
    }
    fun send(bytes: ByteArray, targetWall: Long?, expectedGeneration: Int): Map<String, Any> {
        check(expectedGeneration == generation && session != null) { "Connection changed. Reconnect before sending." }
        check(bytes.size in 233..135335 && bytes[0] == 'H'.code.toByte() && bytes[1] == 'C'.code.toByte()) { "Unsupported display program" }
        try {
            check(cm.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true) { "Wi-Fi disconnected" }
            val now = System.currentTimeMillis()
            if (targetWall != null) {
                check(bytes.size == 393 && bytes[142] == 0x34.toByte()) { "Invalid timer program" }
                check(targetWall - now in 1..3_599_000) { "Remaining time must be between 00:01 and 59:59." }
                val offset = TimeZone.getDefault().getOffset(now)
                calibrateRtc(now)
                // The countdown deadline stays fixed even if an acknowledgement is retried.
                ByteBuffer.wrap(bytes).putInt(144, ((targetWall + offset) / 1000).toInt())
            } else if (bytes[142] == 0x32.toByte()) {
                validateClock(bytes)
                // This program reads the RTC locally; no per-second/minute uploads.
                calibrateRtc(now)
            } else {
                val frames = ByteBuffer.wrap(bytes).getShort(143).toInt() and 0xffff
                check(bytes[142] == 0x30.toByte() && frames in 1..2048 && bytes.size == 167 + 66 * frames &&
                    ByteBuffer.wrap(bytes).getInt(155) == 27 + 2 * frames) { "Invalid display frame sequence" }
            }
            val transfer = random.nextInt(65536).toShort()
            val packets = (bytes.size + 4095) / 4096
            command(2, ByteBuffer.allocate(5).put(5.toByte()).putShort(transfer).putShort(packets.toShort()).array())
            repeat(packets) { index ->
                val offset = index * 4096
                val length = minOf(4096, bytes.size - offset)
                command(3, ByteBuffer.allocate(5 + length).put(5.toByte()).putShort(transfer).putShort(index.toShort()).put(bytes, offset, length).array())
            }
            command(4, ByteBuffer.allocate(3).put(3.toByte()).putShort(transfer).array())
            return mapOf("accepted" to true, "generation" to generation, "acceptedAt" to System.currentTimeMillis())
        } catch (e: Exception) { disconnect(); throw e }
    }
}
