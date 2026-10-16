package org.kosenuel.cuekeeper

import android.app.Activity
import android.content.Intent
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
    private var pending: MethodChannel.Result? = null
    private var exportContent: String? = null
    private val stateFile get() = AtomicFile(File(filesDir, "service-state.json"))

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "church.timer/device").setMethodCallHandler { call, result ->
            when (call.method) {
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

    @Deprecated("Activity result bridge for Flutter's method channel")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 41 && requestCode != 42) return
        val result = pending ?: return
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            exportContent = null
            result.success(null)
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
                    if (si >= 0 && !cursor.isNull(si) && cursor.getLong(si) > 1048576L) error("Import exceeds 1 MiB")
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
                    if (bytes.size() + count > 1048576) error("Import exceeds 1 MiB")
                    bytes.write(buffer, 0, count)
                }
            }
            val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
            mapOf("name" to name, "content" to decoder.decode(ByteBuffer.wrap(bytes.toByteArray())).toString())
        }
    }
}
