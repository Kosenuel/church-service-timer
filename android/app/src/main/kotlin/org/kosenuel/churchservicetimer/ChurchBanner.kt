package org.kosenuel.churchservicetimer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.ExifInterface
import android.net.Uri
import android.util.Base64
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/** Imports a private, metadata-free 3:1 copy. The selected original is untouched. */
object ChurchBanner {
    fun read(context: Context, uri: Uri): String {
        val bytes = ByteArrayOutputStream()
        (context.contentResolver.openInputStream(uri) ?: error("Cannot open selected image")).use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                require(bytes.size() + n <= 5_000_000) { "Choose an image no larger than 5 MB." }
                bytes.write(buffer, 0, n)
            }
        }
        val raw = bytes.toByteArray()
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        require(bounds.outMimeType in setOf("image/jpeg", "image/png", "image/webp")) { "Choose a JPEG, PNG or WebP image." }
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 40_000_000) { "Choose an image up to 40 megapixels." }
        val orientation = try {
            ExifInterface(ByteArrayInputStream(raw)).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } catch (_: Exception) { ExifInterface.ORIENTATION_NORMAL }
        val options = BitmapFactory.Options().apply {
            inSampleSize = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / inSampleSize > 2400) inSampleSize *= 2
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeByteArray(raw, 0, raw.size, options) ?: error("This image could not be decoded.")
        val transform = Matrix().apply {
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
            }
        }
        var upright: Bitmap? = null
        var output: Bitmap? = null
        try {
            val image = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, transform, true)
            upright = image
            val result = Bitmap.createBitmap(600, 200, Bitmap.Config.ARGB_8888)
            output = result
            val frame = bannerFrame(image.width, image.height)
            Canvas(result).drawBitmap(image, null, RectF(frame.left, frame.top, frame.right, frame.bottom), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            val encoded = ByteArrayOutputStream()
            check(result.compress(Bitmap.CompressFormat.PNG, 100, encoded)) { "Could not prepare banner." }
            require(encoded.size() <= 500_000) { "Image could not be reduced to the banner size." }
            return Base64.encodeToString(encoded.toByteArray(), Base64.NO_WRAP)
        } finally {
            output?.recycle()
            if (upright !== decoded) upright?.recycle()
            decoded.recycle()
        }
    }
}
