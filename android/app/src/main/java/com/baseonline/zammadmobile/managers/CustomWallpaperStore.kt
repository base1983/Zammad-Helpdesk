package com.baseonline.zammadmobile.managers

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import com.baseonline.zammadmobile.App
import com.baseonline.zammadmobile.data.WallpaperMode
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** The user's own background photo, one per appearance mode, kept in app storage. */
object CustomWallpaperStore {
    /** Bumped when a photo changes, so the background recomposes and reloads. */
    var version by mutableIntStateOf(0); private set

    private fun directory() = File(App.ctx.filesDir, "wallpapers").apply { mkdirs() }

    /** The stored photo for [mode], or null when none was chosen. Reads [version]. */
    fun file(mode: WallpaperMode): File? {
        val v = version
        return directory().listFiles()?.firstOrNull { it.name.startsWith("custom_${mode.name.lowercase()}_") }
            .also { if (v < 0) Unit }
    }

    fun hasImage(mode: WallpaperMode) = file(mode) != null

    /** Imports a picked image, downscaled to at most 2160 px on the long side. */
    suspend fun save(context: Context, uri: Uri, mode: WallpaperMode): Boolean = withContext(Dispatchers.IO) {
        try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 4320) sample *= 2
            val bitmap = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            } ?: return@withContext false
            val scale = 2160f / maxOf(bitmap.width, bitmap.height)
            val scaled = if (scale < 1f) Bitmap.createScaledBitmap(
                bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
            remove(mode, notify = false)
            // A fresh file name per import, so image caches never show the old photo.
            File(directory(), "custom_${mode.name.lowercase()}_${System.currentTimeMillis()}.jpg").outputStream().use {
                scaled.compress(Bitmap.CompressFormat.JPEG, 85, it)
            }
            withContext(Dispatchers.Main) { version++ }
            true
        } catch (e: Exception) { false }
    }

    fun remove(mode: WallpaperMode, notify: Boolean = true) {
        directory().listFiles()?.filter { it.name.startsWith("custom_${mode.name.lowercase()}_") }?.forEach { it.delete() }
        if (notify) version++
    }
}
