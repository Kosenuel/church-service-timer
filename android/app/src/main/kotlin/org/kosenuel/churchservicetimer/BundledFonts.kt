package org.kosenuel.churchservicetimer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Typeface
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/** Four unmodified Tinos faces bundled under SIL OFL 1.1. No external font access. */
class BundledFonts(context: Context) {
    private val app = context.applicationContext
    private val faces = mutableMapOf<String, Typeface>()
    private fun face(bold: Boolean, italic: Boolean): Typeface {
        val style = if (bold && italic) "BoldItalic" else if (bold) "Bold" else if (italic) "Italic" else "Regular"
        return faces.getOrPut(style) { Typeface.createFromAsset(app.assets, "display_fonts/tinos/Tinos-$style.ttf") }
    }
    @Synchronized fun available(): Boolean = try {
        for (b in listOf(false, true)) for (i in listOf(false, true)) face(b, i)
        true
    } catch (_: Exception) { false }
    @Synchronized fun rasterize(text: String, height: Int, bold: Boolean, italic: Boolean): Map<String, Any> =
        render(face(bold, italic), text, height)

    private fun render(face: Typeface, text: String, height: Int): Map<String, Any> {
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
            isFakeBoldText = false
            textSkewX = 0f
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

    companion object { private const val MAX_WIDTH = 8192 }
}
