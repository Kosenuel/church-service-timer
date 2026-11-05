package org.kosenuel.cuekeeper

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.lang.ref.WeakReference
import io.flutter.embedding.engine.FlutterEngineCache
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.content.Intent
import android.content.ActivityNotFoundException
import android.os.SystemClock
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.AtomicFile
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    companion object { var bridge: DeviceBridge? = null }
    override fun provideFlutterEngine(context: Context): FlutterEngine? = FlutterEngineCache.getInstance().get("service-timer")
    override fun shouldDestroyEngineWithHost() = false
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("service-timer", flutterEngine)
        if (bridge == null) bridge = DeviceBridge(applicationContext, flutterEngine)
        bridge!!.attach(this)
    }
    override fun onDestroy() { bridge?.detach(this); super.onDestroy() }
    @Deprecated("Activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        bridge?.onActivityResult(requestCode, resultCode, data)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}

/** Engine-owned bridge: no Activity is retained while the screen is closed. */
class DeviceBridge(private val context: Context, engine: FlutterEngine) {
    private var host = WeakReference<MainActivity>(null)
    private var keepAwake = true
    fun attach(activity: MainActivity) {
        host = WeakReference(activity)
        if (keepAwake) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    fun detach(activity: MainActivity) { if (host.get() === activity) host.clear() }
    private fun activity(): MainActivity = host.get() ?: error("Open the app to perform this action")
    private val main = Handler(Looper.getMainLooper())
    private fun runOnUiThread(block: () -> Unit) { main.post(block) }
    private val filesDir get() = context.filesDir
    private val contentResolver get() = context.contentResolver
    private val packageManager get() = context.packageManager
    private val packageName get() = context.packageName
    private val window get() = activity().window
    private fun startActivity(intent: Intent) = activity().startActivity(intent)
    private fun startActivityForResult(intent: Intent, code: Int) = activity().startActivityForResult(intent, code)
    private fun checkSelfPermission(permission: String) = context.checkSelfPermission(permission)
    private fun requestPermissions(permissions: Array<String>, code: Int) = activity().requestPermissions(permissions, code)
    val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "church.timer/device")
    fun pulse() { channel.invokeMethod("backgroundTick", null) }
    /** Forwards a Pause or Next tap from the active-service notification. */
    fun notificationAction(action: String) { channel.invokeMethod("notificationAction", action) }
    fun closeDisplay() { displayIo.execute { w2.disconnect() } }

    private val io = Executors.newSingleThreadExecutor()
    private val displayIo = Executors.newSingleThreadExecutor()
    private val w2 by lazy { W2Display(context) }
    private var pending: MethodChannel.Result? = null
    private var exportContent: String? = null
    private var importLimit = 1048576
    private var notificationRequest: MethodChannel.Result? = null
    private var networkRequest: MethodChannel.Result? = null
    private val bundledFonts by lazy { BundledFonts(context) }
    private val vault by lazy { DisplayCredentialVault(context) }
    private val pairingVault by lazy { DisplayCredentialVault(context, "pairing-vault", "church-timer-pairing-v1", 65536) }
    private val signWifi by lazy { SignWifi(context, vault) { w2.preferredNetwork = it } }
    private val pairWifi by lazy { PairWifi(context, vault) }
    private val pickerFeedback by lazy { PickerFeedback(context) }
    private var wifiPermissionResult: MethodChannel.Result? = null
    private var wifiPermissionId: String? = null
    private fun cancelSignWifi() {
        wifiPermissionResult?.error("CANCELLED", "Wi-Fi connection cancelled.", null)
        wifiPermissionResult = null; wifiPermissionId = null
        signWifi.cancel()
    }
    private val printer by lazy { ServiceSheetPrinter() }
    private val stateFile get() = AtomicFile(File(filesDir, "service-state.json"))

    init {
        WarningNotifications.ensureChannel(context)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickerTick" -> { host.get()?.window?.decorView?.let { pickerFeedback.tick(it, call.arguments as? String ?: "off") }; result.success(null) }
                "signWifiProfile" -> background(result) { signWifi.info(call.arguments as String) }
                "saveSignWifiProfile" -> background(result) {
                    signWifi.save(call.argument<String>("id")!!, call.argument<String>("ssid")!!,
                        call.argument<String>("security") ?: "wpa2", call.argument<String>("password"), call.argument<String>("bssid") ?: "")
                    null
                }
                "cancelSignWifi" -> { cancelSignWifi(); result.success(null) }
                "pairWifiProfile" -> background(result) { pairWifi.info(call.arguments as String) }
                "savePairWifi" -> background(result) {
                    pairWifi.save(call.argument<String>("host")!!, call.argument<String>("ssid")!!,
                        call.argument<String>("security") ?: "wpa2", call.argument<String>("kind") ?: "church",
                        call.argument<String>("password"), call.argument<Boolean>("store") != false)
                    null
                }
                "forgetPairWifi" -> background(result) { pairWifi.forget(call.arguments as String); null }
                "cancelPairWifi" -> { pairWifi.cancel(); result.success(null) }
                "joinPairWifi" -> pairWifi.request(call.arguments as String, result)
                "joinSignWifi" -> {
                    val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
                    if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) {
                        if (wifiPermissionResult != null) result.error("BUSY", "A Wi-Fi permission request is already open.", null)
                        else {
                            wifiPermissionResult = result; wifiPermissionId = call.arguments as String
                            try { requestPermissions(if (Build.VERSION.SDK_INT >= 33) arrayOf(permission) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 46) }
                            catch (_: Exception) { wifiPermissionResult = null; wifiPermissionId = null; result.error("WIFI", "Open the app to reconnect to Wi-Fi.", null) }
                        }
                    } else signWifi.request(call.arguments as String, result)
                }
                "loadPairing" -> background(result) { pairingVault.read("registry") }
                "savePairing" -> background(result) { pairingVault.save("registry", call.arguments as String); null }
                "printSheet" -> try { printer.print(activity(), call.argument<String>("name")!!, call.argument<String>("html")!!); result.success(null) } catch(e: Exception) { result.error("PRINT", "Could not open the print screen", null) }
                "localAddress" -> background(result) {
                    val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
                    val net = cm.allNetworks.firstOrNull { cm.getNetworkCapabilities(it)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true } ?: error("Connect both devices to the same Wi-Fi first")
                    cm.getLinkProperties(net)?.linkAddresses?.firstOrNull { it.address is java.net.Inet4Address }?.address?.hostAddress ?: error("No Wi-Fi IPv4 address")
                }
                "saveDisplayPassword" -> background(result) { vault.save(call.argument<String>("id")!!, call.argument<String>("password")!!); null }
                "savedDisplayPassword" -> background(result) { vault.read(call.arguments as String) }
                "forgetDisplayPassword" -> background(result) { vault.forget(call.arguments as String); null }
                "forgetDisplay" -> { cancelSignWifi(); displayBackground(result) { val id = w2.preferences()["id"] as String; vault.forget(id); signWifi.forget(id); w2.forget(); null } }

                "activeServiceRunning" -> result.success(ActiveService.running)
                "serviceNotification" -> {
                    ServiceCard.update(context, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    result.success(null)
                }
                "activeService" -> {
                    if (call.arguments == true) {
                        try {
                            activity() // Start only from a visible, user-initiated session.
                            ActiveService.start(context, result)
                        } catch (e: Exception) { result.error("SERVICE", e.message, null) }
                    } else { ActiveService.stop(context); result.success(false) }
                }
                "w2Preferences" -> displayBackground(result) { w2.preferences() }
                "w2AutoReconnect" -> { if (call.arguments != true) cancelSignWifi(); displayBackground(result) { w2.autoReconnect(call.arguments == true); null } }
                "w2NetworkInfo" -> {
                    if (call.arguments == true && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                        if (networkRequest != null) result.error("BUSY", "A permission request is open", null)
                        else {
                            networkRequest = result
                            try { requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 45) }
                            catch (_: Exception) { networkRequest = null; result.error("WIFI", "Open the app to read its Wi-Fi name", null) }
                        }
                    } else background(result) { networkInfo() }
                }
                "w2Discover" -> displayBackground(result) { w2.discover() }
                "w2Connect" -> displayBackground(result) {
                    w2.connect(call.argument<String>("id") ?: "", (call.argument<String>("password") ?: "").toCharArray())
                }
                "w2Disconnect" -> displayBackground(result) { w2.disconnect(); null }
                "w2Simulator" -> displayBackground(result) { w2.simulator(); null }
                "w2Status" -> displayBackground(result) { w2.status() }
                "w2Admin" -> displayBackground(result) {
                    val saved = stateFile.openRead().use { org.json.JSONObject(String(it.readBytes(), Charsets.UTF_8)) }
                    check(saved.getJSONObject("session").getString("phase") != "active") { "End the service before changing device settings." }
                    val kind = call.argument<String>("kind") ?: ""
                    val id = w2.preferences()["id"] as String
                    val outcome = w2.administer(kind, (call.argument<String>("value") ?: "").toCharArray(), call.argument<Int>("generation") ?: -1)
                    if (kind == "devicePassword") vault.forget(id)
                    if (kind == "wifiPassword" || kind == "ssid") signWifi.forget(id)
                    outcome
                }
                "w2Send" -> displayBackground(result) {
                    w2.send(call.argument<ByteArray>("bytes") ?: error("Missing program"),
                        call.argument<Number>("deadline")?.toLong(), call.argument<Int>("generation") ?: -1)
                }
                "wifiSettings" -> { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)); result.success(null) }
                "batteryUnrestricted" -> {
                    val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(power.isIgnoringBatteryOptimizations(packageName))
                }
                "batterySettings" -> {
                    // The system list avoids the restricted direct-request permission.
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                    } catch (_: ActivityNotFoundException) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                "composeFeedback" -> {
                    try {
                        val subject = call.argument<String>("subject") ?: ""
                        val body = call.argument<String>("body") ?: ""
                        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse(FeedbackEmail.uri(subject, body)))
                        intent.putExtra(Intent.EXTRA_EMAIL, arrayOf(FeedbackEmail.RECIPIENT))
                        intent.putExtra(Intent.EXTRA_SUBJECT, subject)
                        intent.putExtra(Intent.EXTRA_TEXT, body)
                        startActivity(intent)
                        result.success(true)
                    } catch (_: ActivityNotFoundException) {
                        result.success(false)
                    } catch (e: Exception) { result.error("EMAIL", e.message, null) }
                }
                "appVersion" -> {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                    result.success("${info.versionName} ($code)")
                }
                "keepScreenAwake" -> {
                    keepAwake = call.arguments == true
                    if (call.arguments == true) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "hasTinosFont" -> background(result) { bundledFonts.available() }
                "rasterizeTinos" -> background(result) {
                    bundledFonts.rasterize(call.argument<String>("text") ?: "", (call.argument<Int>("height") ?: 2) * 7,
                        call.argument<Boolean>("bold") ?: false, call.argument<Boolean>("italic") ?: false)
                }
                "pickChurchBanner" -> {
                    if (pending != null) result.error("BUSY", "A document picker is already open", null)
                    else {
                        pending = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "image/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
                            }, 45)
                        } catch (e: Exception) { pending = null; result.error("IMAGE", e.message, null) }
                    }
                }
                "notificationStatus" -> result.success(WarningNotifications.status(context))
                "enableNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (notificationRequest != null) result.error("BUSY", "Notification permission request already open", null)
                        else {
                            notificationRequest = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 44)
                        }
                    } else result.success(null)
                }
                "notificationSettings" -> {
                    if (Build.VERSION.SDK_INT >= 26) startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                    else startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "exactWarnings" -> {
                    if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                    result.success(null)
                }
                "syncWarnings" -> {
                    try { WarningNotifications.sync(context, call.arguments as Map<*, *>); result.success(null) }
                    catch (e: Exception) { result.error("NOTIFICATION", e.message, null) }
                }
                "testNotification" -> {
                    try { WarningNotifications.test(context); result.success(null) }
                    catch (e: Exception) { result.error("NOTIFICATION", e.message, null) }
                }
                "clock" -> result.success(mapOf(
                    "mono" to SystemClock.elapsedRealtime(),
                    "wall" to System.currentTimeMillis(),
                    "boot" to Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT, -1).toString()
                ))
                "load" -> background(result) {
                    val f = stateFile
                    if (!f.baseFile.exists() && !File(f.baseFile.path + ".bak").exists()) null
                    else f.readFully().toString(Charsets.UTF_8)
                }
                "save" -> {
                    val value = call.arguments as? String
                    if (value == null) result.error("STATE", "State must be JSON text", null)
                    else background(result) {
                        val f = stateFile
                        var stream: FileOutputStream? = null
                        try {
                            stream = f.startWrite()
                            stream.write(value.toByteArray(Charsets.UTF_8))
                            f.finishWrite(stream)
                        } catch (e: Exception) {
                            f.failWrite(stream)
                            throw e
                        }
                        null
                    }
                }
                "pick" -> {
                    if (pending != null) result.error("BUSY", "A document picker is already open", null)
                    else {
                        pending = result
                        importLimit = if (call.argument<Int>("maxBytes") == 16 * 1024 * 1024) 16 * 1024 * 1024 else 1048576
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("text/csv", "text/comma-separated-values", "application/json", "text/plain", "application/octet-stream"))
                            }, 41)
                        } catch (e: Exception) { pending = null; result.error("PICKER", e.message, null) }
                    }
                }
                "export" -> {
                    if (pending != null) result.error("BUSY", "A document picker is already open", null)
                    else {
                        pending = result
                        exportContent = call.argument<String>("content")
                        val name = call.argument<String>("name") ?: "template.json"
                        try {
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = if (name.endsWith(".json")) "application/json" else "text/csv"
                                putExtra(Intent.EXTRA_TITLE, name)
                            }, 42)
                        } catch (e: Exception) { pending = null; exportContent = null; result.error("PICKER", e.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try { val value = block(); runOnUiThread { result.success(value) } }
            catch (e: Exception) { runOnUiThread { result.error("IO", e.message ?: e.javaClass.simpleName, null) } }
        }
    }

    private fun displayBackground(result: MethodChannel.Result, block: () -> Any?) {
        displayIo.execute {
            try { val value = block(); runOnUiThread { result.success(value) } }
            catch (e: Exception) { runOnUiThread { result.error("DISPLAY", e.message ?: "Display request failed", null) } }
        }
    }

    @Deprecated("Activity result bridge for Flutter's method channel")
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != 41 && requestCode != 42 && requestCode != 45) return
        val result = pending ?: return
        val maxBytes = importLimit
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            exportContent = null
            result.success(null)
            return
        }
        if (requestCode == 45) {
            background(result) { ChurchBanner.read(context, uri) }
            return
        }
        if (requestCode == 42) {
            val text = exportContent ?: ""
            exportContent = null
            background(result) {
                val stream = contentResolver.openOutputStream(uri, "wt") ?: error("Cannot open destination")
                stream.use { it.write(text.toByteArray(Charsets.UTF_8)); it.flush() }
                null
            }
        } else background(result) {
            var name = "template.json"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val ni = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val si = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (ni >= 0) name = cursor.getString(ni)
                    if (si >= 0 && !cursor.isNull(si) && cursor.getLong(si) > maxBytes.toLong()) error("Import exceeds ${maxBytes / 1048576} MiB")
                }
            }
            if (!name.endsWith(".csv", true) && !name.endsWith(".json", true)) error("Choose CSV or JSON. Export Excel as CSV first.")
            val bytes = ByteArrayOutputStream()
            val stream = contentResolver.openInputStream(uri) ?: error("Cannot open selected file")
            stream.use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (bytes.size() + count > maxBytes) error("Import exceeds ${maxBytes / 1048576} MiB")
                    bytes.write(buffer, 0, count)
                }
            }
            val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            mapOf("name" to name, "content" to decoder.decode(ByteBuffer.wrap(bytes.toByteArray())).toString())
        }
    }

    @Suppress("DEPRECATION")
    private fun networkInfo(): Map<String, Any> {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as android.net.ConnectivityManager
        val net = cm.allNetworks.firstOrNull { cm.getNetworkCapabilities(it)?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true }
        val manager = context.getSystemService(Context.WIFI_SERVICE) as android.net.wifi.WifiManager
        val ssid = if (net != null && checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED)
            manager.connectionInfo?.ssid?.removeSurrounding("\"")?.takeUnless { it == "<unknown ssid>" } else null
        return mapOf("wifiConnected" to (net != null), "ssid" to (ssid ?: ""))
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == 46) {
            val result = wifiPermissionResult; val id = wifiPermissionId
            wifiPermissionResult = null; wifiPermissionId = null
            if (result != null && id != null) {
                val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
                if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) signWifi.request(id, result)
                else result.error("WIFI_PERMISSION", "Wi-Fi permission was not granted. Open Wi-Fi settings to connect manually.", null)
            }
        }
        if (requestCode == 45) {
            val result = networkRequest
            networkRequest = null
            if (result != null) background(result) { networkInfo() }
        }
        if (requestCode == 44) {
            notificationRequest?.success(null)
            notificationRequest = null
        }
    }
}
