package org.kosenuel.cuekeeper

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Locally imported font only: neither font bytes nor raster data ship in the APK. */
class TimesFont(context: Context) {
    private val app = context.applicationContext
    private val storage = AtomicFile(File(app.filesDir, "times-new-roman.ttf"))
    private var installedFace: Typeface? = null

    @Synchronized
    fun available(): Boolean = try {
        loadFace()
        true
    } catch (_: Exception) {
        false
    }

    /** Validate and render before replacing a previously working import. */
    @Synchronized
    fun install(bytes: ByteArray): Boolean {
        validateRegularTimes(bytes)
        val candidate = File.createTempFile("cuekeeper-times-", ".ttf", app.cacheDir)
        try {
            candidate.outputStream().use { it.write(bytes) }
            val face = Typeface.createFromFile(candidate)
            require(!face.isBold && !face.isItalic) { "Choose the regular Times New Roman font." }
            for (bold in listOf(false, true)) {
                for (italic in listOf(false, true)) {
                    render(face, "AgjpQ TIME 0123456789", 14, bold, italic)
                    render(face, "AgjpQ TIME 0123456789", 7, bold, italic)
                }
            }
            var output: FileOutputStream? = null
            try {
                output = storage.startWrite()
                output.write(bytes)
                storage.finishWrite(output)
            } catch (error: Exception) {
                storage.failWrite(output)
                throw error
            }
            // Keep the validated face; Android may cache a Typeface by its source path.
            installedFace = face
            return true
        } finally {
            candidate.delete()
        }
    }

    @Synchronized
    fun rasterize(text: String, height: Int, bold: Boolean, italic: Boolean): Map<String, Any> {
        return render(loadFace(), text, height, bold, italic)
    }

    private fun loadFace(): Typeface {
        installedFace?.let { return it }
        require(storage.baseFile.exists() || File(storage.baseFile.path + ".bak").exists()) {
            "Import a licensed regular Times New Roman TTF first."
        }
        val bytes = storage.openRead().use(::readBounded)
        validateRegularTimes(bytes)
        val face = Typeface.createFromFile(storage.baseFile)
        require(!face.isBold && !face.isItalic) { "The imported Times New Roman font is not regular." }
        render(face, "AgjpQ TIME 0123456789", 14, false, false)
        installedFace = face
        return face
    }

    private fun readBounded(input: InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) return output.toByteArray()
            require(output.size() + count <= MAX_FILE_BYTES) { "Font exceeds 4 MiB." }
            output.write(buffer, 0, count)
        }
    }

    private fun render(face: Typeface, text: String, height: Int, bold: Boolean, italic: Boolean): Map<String, Any> {
        require(height == 7 || height == 14) { "Display font height must be 7 or 14 rows." }
        require(text.isNotBlank() && text.codePointCount(0, text.length) <= 160) {
            "Display text must contain 1–160 characters and cannot be blank."
        }
        var offset = 0
        while (offset < text.length) {
            val char = text[offset]
            require(!Character.isISOControl(char) && char != '\u2028' && char != '\u2029') {
                "Display text must be a single line without control characters."
            }
            if (Character.isHighSurrogate(char)) {
                require(offset + 1 < text.length && Character.isLowSurrogate(text[offset + 1])) {
                    "Display text contains an invalid Unicode character."
                }
                offset += 2
            } else {
                require(!Character.isLowSurrogate(char)) { "Display text contains an invalid Unicode character." }
                offset++
            }
        }
        val paint = Paint().apply {
            typeface = face
            color = Color.WHITE
            style = Paint.Style.FILL
            isAntiAlias = false
            isSubpixelText = false
            hinting = Paint.HINTING_ON
            isFakeBoldText = bold && !face.isBold
            textSkewX = if (italic && !face.isItalic) -0.25f else 0f
        }
        // Fit actual whole-string ink, without resizing or thresholding an AA image.
        for (size in 40 downTo 1) {
            paint.textSize = size.toFloat()
            val bitmap = drawCandidate(paint, text, size) ?: continue
            try {
                val pixels = IntArray(bitmap.width * bitmap.height)
                bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                var top = bitmap.height
                var bottom = -1
                for (y in 0 until bitmap.height) {
                    for (x in 0 until bitmap.width) {
                        if (pixels[y * bitmap.width + x] ushr 24 != 0) {
                            top = min(top, y)
                            bottom = max(bottom, y)
                        }
                    }
                }
                val inkHeight = bottom - top + 1
                if (inkHeight !in 1..height) continue
                // Horizontal bounds retain leading/trailing advances and italic overhang.
                val bounds = Rect()
                paint.getTextBounds(text, 0, text.length, bounds)
                val left = min(0, bounds.left)
                val right = max(ceil(paint.measureText(text).toDouble()).toInt(), bounds.right)
                val padding = max(8, size)
                val startX = padding
                var endX = startX + right - left
                var firstX = startX
                for (y in top..bottom) {
                    for (x in 0 until bitmap.width) {
                        if (pixels[y * bitmap.width + x] ushr 24 != 0) {
                            firstX = min(firstX, x)
                            endX = max(endX, x + 1)
                        }
                    }
                }
                val width = endX - firstX
                if (width !in 1..MAX_WIDTH) continue
                val rows = (top..bottom).map { y ->
                    buildString(width) {
                        for (x in firstX until endX) {
                            append(if (pixels[y * bitmap.width + x] ushr 24 != 0) '1' else '0')
                        }
                    }
                }
                return mapOf("width" to width, "height" to inkHeight, "rows" to rows)
            } finally {
                bitmap.recycle()
            }
        }
        throw IllegalArgumentException("The text could not be rendered within the display bounds.")
    }

    private fun drawCandidate(paint: Paint, text: String, size: Int): Bitmap? {
        val advance = paint.measureText(text)
        if (!advance.isFinite() || advance < 0 || advance > MAX_WIDTH) return null
        val bounds = Rect()
        paint.getTextBounds(text, 0, text.length, bounds)
        val metrics = paint.fontMetrics
        if (!metrics.top.isFinite() || !metrics.bottom.isFinite() ||
            metrics.top !in -16384f..16384f || metrics.bottom !in -16384f..16384f) return null
        val left = min(0, bounds.left)
        val right = max(ceil(advance.toDouble()).toInt(), bounds.right)
        val top = min(kotlin.math.floor(metrics.top.toDouble()).toInt(), bounds.top)
        val bottom = max(ceil(metrics.bottom.toDouble()).toInt(), bounds.bottom)
        val padding = max(8, size)
        val width = right.toLong() - left + padding * 2L
        val height = bottom.toLong() - top + padding * 2L
        if (width !in 1..(MAX_WIDTH + padding * 2).toLong() || height !in 1..512L) return null
        val bitmap = Bitmap.createBitmap(width.toInt(), height.toInt(), Bitmap.Config.ARGB_8888)
        try {
            Canvas(bitmap).drawText(text, (padding - left).toFloat(), (padding - top).toFloat(), paint)
            return bitmap
        } catch (error: Exception) {
            bitmap.recycle()
            throw error
        }
    }

    companion object {
        private const val MAX_FILE_BYTES = 4 * 1024 * 1024
        private const val MAX_WIDTH = 8192

        /** Read only bounded SFNT metadata; Android performs the font's actual decoding. */
        private fun validateRegularTimes(bytes: ByteArray) {
            require(bytes.size in 12..MAX_FILE_BYTES) { "Choose a valid TTF font no larger than 4 MiB." }
            val data = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            fun u16(at: Int): Int {
                require(at >= 0 && at <= bytes.size - 2) { "The font contains truncated metadata." }
                return data.getShort(at).toInt() and 0xffff
            }
            fun u32(at: Int): Long {
                require(at >= 0 && at <= bytes.size - 4) { "The font contains truncated metadata." }
                return data.getInt(at).toLong() and 0xffffffffL
            }
            require(u32(0) == 0x00010000L || u32(0) == 0x74727565L) {
                "Choose a single TrueType .ttf file, not a font collection or other format."
            }
            val count = u16(4)
            require(count in 1..128 && 12L + count * 16L <= bytes.size) { "Invalid font table directory." }
            val tables = mutableMapOf<String, Pair<Int, Int>>()
            for (index in 0 until count) {
                val record = 12 + index * 16
                val tag = String(bytes, record, 4, Charsets.ISO_8859_1)
                val start = u32(record + 8)
                val length = u32(record + 12)
                require(start <= bytes.size && length <= bytes.size && start + length <= bytes.size) {
                    "A font table points outside the selected file."
                }
                require(!tables.containsKey(tag)) { "The font contains a duplicate table." }
                tables[tag] = start.toInt() to length.toInt()
            }
            require(listOf("name", "head", "cmap", "maxp", "hhea", "hmtx", "glyf", "loca").all { it in tables }) {
                "The selected file is missing required TrueType tables."
            }
            require("fvar" !in tables) { "Choose the static regular Times New Roman TTF." }
            val (head, headLength) = tables.getValue("head")
            require(headLength >= 54 && u32(head + 12) == 0x5f0f3cf5L && u16(head + 18) in 16..16384) {
                "Invalid TrueType font header."
            }
            require(u16(head + 44) and 3 == 0) { "Choose regular Times New Roman, not Bold or Italic." }
            tables["OS/2"]?.let { (start, length) ->
                require(length >= 64) { "Invalid TrueType style metadata." }
                require(u16(start + 4) == 400 && u16(start + 62) and 0x21 == 0) {
                    "Choose regular Times New Roman, not a different weight or style."
                }
            }
            val (name, nameLength) = tables.getValue("name")
            require(nameLength >= 6 && u16(name) in 0..1) { "Invalid font name table." }
            val records = u16(name + 2)
            val storageOffset = u16(name + 4)
            require(records in 1..1024 && 6L + records * 12L <= nameLength &&
                storageOffset >= 6 + records * 12 && storageOffset <= nameLength) { "Invalid font name records." }
            val labels = mutableMapOf<Int, MutableList<String>>()
            for (index in 0 until records) {
                val record = name + 6 + index * 12
                val platform = u16(record)
                val encoding = u16(record + 2)
                val id = u16(record + 6)
                val length = u16(record + 8)
                val offset = u16(record + 10)
                require(storageOffset.toLong() + offset + length <= nameLength) { "A font name points outside its table." }
                if (id !in listOf(1, 2, 16, 17) || length == 0) continue
                require(length <= 2048) { "A font name is too long." }
                val charset = when {
                    platform == 0 || (platform == 3 && encoding in listOf(0, 1, 10)) -> Charsets.UTF_16BE
                    platform == 1 && encoding == 0 -> Charsets.ISO_8859_1
                    else -> continue
                }
                val value = charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes, name + storageOffset + offset, length)).toString()
                    .trim().lowercase(Locale.ROOT).replace(" ", "")
                labels.getOrPut(id) { mutableListOf() }.add(value)
            }
            val families = labels[16] ?: labels[1].orEmpty()
            require("timesnewroman" in families) { "The selected font is not Times New Roman." }
            val styles = labels[17] ?: labels[2].orEmpty()
            require(styles.any { it in listOf("regular", "roman", "normal") } &&
                styles.none { value -> listOf("bold", "italic", "oblique", "light", "black", "medium").any(value::contains) }) {
                "Choose the regular Times New Roman TTF; bold and italic are applied in Church Service Timer."
            }
        }
    }
}
