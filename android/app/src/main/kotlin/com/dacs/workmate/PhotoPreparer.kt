package com.dacs.workmate

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import androidx.exifinterface.media.ExifInterface
import java.io.File

/** Longest edge and quality of a filed attendance photo (DACS Attendance PhotoStore). */
private const val MAX_EDGE_PX = 1600
private const val JPEG_QUALITY = 80

/**
 * Turns a fresh capture into the file that gets uploaded: upright, caption
 * burned in (it must survive export and download), compressed to ~300 KB,
 * app-private. Ported from DACS Attendance PhotoStore.prepare.
 */
object PhotoPreparer {

    fun prepare(source: File, target: File, caption: String, mirror: Boolean = false) {
        val decoded = decodeUpright(source)
        // The front camera is filed AS PREVIEWED (mirrored), as DACS Attendance
        // files it: the worker approves the mirror image, so the record matches it.
        val upright = if (mirror) mirrored(decoded) else decoded
        val scaled = scaleToBudget(upright)
        if (scaled !== upright) upright.recycle()
        drawCaption(scaled, caption)
        target.parentFile?.mkdirs()
        try {
            target.outputStream().use { out ->
                val ok = scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
                check(ok) { "JPEG encode failed" }
            }
        } catch (t: Throwable) {
            // Keep the raw source (the only evidence); never leave a partial file behind.
            target.delete()
            throw t
        } finally {
            scaled.recycle()
        }
        // The raw capture has no caption and must never be the thing that is sent.
        source.delete()
    }

    /** EXIF rotation AND mirror (front camera), sampled so the full-size bitmap never exists. */
    private fun decodeUpright(source: File): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, bounds)
        val bitmap = BitmapFactory.decodeFile(
            source.absolutePath,
            BitmapFactory.Options().apply {
                inMutable = true
                inSampleSize = photoSampleSize(bounds.outWidth, bounds.outHeight, MAX_EDGE_PX)
            }
        ) ?: error("Could not decode captured photo")

        val exif = ExifInterface(source.absolutePath)
        val degrees = exif.rotationDegrees
        val flipped = exif.isFlipped
        if (degrees == 0 && !flipped) return bitmap

        // Flip FIRST, then rotate: the order rotationDegrees assumes.
        val matrix = Matrix().apply {
            if (flipped) postScale(-1f, 1f)
            postRotate(degrees.toFloat())
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    /** Flips an already-upright bitmap left to right. */
    private fun mirrored(bitmap: Bitmap): Bitmap {
        val flipped = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, Matrix().apply { postScale(-1f, 1f) }, true)
        if (flipped !== bitmap) bitmap.recycle()
        return flipped
    }

    private fun scaleToBudget(bitmap: Bitmap): Bitmap {
        val longest = maxOf(bitmap.width, bitmap.height)
        if (longest <= MAX_EDGE_PX) return bitmap
        val factor = MAX_EDGE_PX.toFloat() / longest
        return Bitmap.createScaledBitmap(bitmap, (bitmap.width * factor).toInt(), (bitmap.height * factor).toInt(), true)
    }

    /** Bottom gradient + monospaced bold text, shrunk until the WHOLE caption fits. */
    private fun drawCaption(bitmap: Bitmap, caption: String) {
        val canvas = Canvas(bitmap)
        val bandHeight = bitmap.height * 0.14f
        val top = bitmap.height - bandHeight
        canvas.drawRect(
            0f, top, bitmap.width.toFloat(), bitmap.height.toFloat(),
            Paint().apply {
                shader = LinearGradient(
                    0f, top, 0f, bitmap.height.toFloat(),
                    Color.TRANSPARENT, Color.argb(190, 0, 0, 0), Shader.TileMode.CLAMP
                )
            }
        )
        val margin = bitmap.width * 0.04f
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            setShadowLayer(bitmap.width * 0.006f, 0f, 0f, Color.BLACK)
        }
        text.textSize = fitTextSize(
            preferred = bitmap.width * 0.038f,
            maxWidth = bitmap.width - margin * 2,
            measure = { size ->
                text.textSize = size
                text.measureText(caption)
            }
        )
        canvas.drawText(caption, margin, bitmap.height - bandHeight * 0.32f, text)
    }
}
