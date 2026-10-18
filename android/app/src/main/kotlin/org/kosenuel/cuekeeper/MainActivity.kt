package org.kosenuel.cuekeeper

import android.app.Activity
import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
    private val io = Executors.newSingleThreadExecutor()
    private val displayIo = Executors.newSingleThreadExecutor()
    private val w2 by lazy { W2Display(this) }
    private var pending: MethodChannel.Result? = null
    private var exportContent: String? = null
    private var importLimit = 1048576
    private var notificationRequest: MethodChannel.Result? = null
    private val bundledFonts by lazy { BundledFonts(this) }
    private val stateFile get() = AtomicFile(File(filesDir, "service-state.json"))

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WarningNotifications.ensureChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "church.timer/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "w2Preferences" -> displayBackground(result) { w2.preferences() }
                "w2Discover" -> displayBackground(result) { w2.discover() }
                "w2Connect" -> displayBackground(result) {
                    w2.connect(call.argument<String>("id") ?: "", (call.argument<String>("password") ?: "").toCharArray())
                }
                "w2Disconnect" -> displayBackground(result) { w2.disconnect(); null }
                "w2Simulator" -> displayBackground(result) { w2.simulator(); null }
                "w2Status" -> displayBackground(result) { w2.status() }
                "w2Send" -> displayBackground(result) {
                    w2.send(call.argument<ByteArray>("bytes") ?: error("Missing program"),
                        call.argument<Number>("deadline")?.toLong(), call.argument<Int>("generation") ?: -1)
                }
                "wifiSettings" -> { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)); result.success(null) }
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
                "notificationStatus" -> result.success(WarningNotifications.status(this))
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
                    try { WarningNotifications.sync(this, call.arguments as Map<*, *>); result.success(null) }
                    catch (e: Exception) { result.error("NOTIFICATION", e.message, null) }
                }
                "testNotification" -> {
                    try { WarningNotifications.test(this); result.success(null) }
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

    override fun onDestroy() {
        displayIo.execute { w2.disconnect() }
        displayIo.shutdown()
        io.shutdown()
        super.onDestroy()
    }

    @Deprecated("Activity result bridge for Flutter's method channel")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
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
            background(result) { ChurchBanner.read(this, uri) }
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

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 44) {
            notificationRequest?.success(null)
            notificationRequest = null
        }
    }
}
