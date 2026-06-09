package com.royp.maccysync.clipboard

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.royp.maccysync.core.ItemMeta
import com.royp.maccysync.core.Protocol
import java.io.File
import java.util.UUID

// Brings a picked / shared file INTO the phone's "This Phone" list as a file clip.
// SAF gives us a content:// URI whose permission grant can die later (reboot, app
// death), so we copy the bytes into app storage at import time — the clip then
// survives in the list and can be uploaded whenever the Mac is connected.
object FileImport {
  data class Imported(val meta: ItemMeta, val contentPath: String)

  fun fromUri(context: Context, uri: Uri): Imported? {
    val resolver = context.contentResolver
    var name = "file"
    var size = 0L
    runCatching {
      resolver.query(uri, null, null, null, null)?.use { c ->
        val nameIdx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        val sizeIdx = c.getColumnIndex(OpenableColumns.SIZE)
        if (c.moveToFirst()) {
          if (nameIdx >= 0) c.getString(nameIdx)?.let { name = it }
          if (sizeIdx >= 0 && !c.isNull(sizeIdx)) size = c.getLong(sizeIdx)
        }
      }
    }
    val mime = resolver.getType(uri) ?: "application/octet-stream"
    val id = UUID.randomUUID().toString()
    val dir = File(context.filesDir, "local-files").apply { mkdirs() }
    val dest = File(dir, "$id-${name.replace('/', '_')}")
    val copied = runCatching {
      resolver.openInputStream(uri)?.use { input ->
        dest.outputStream().use { input.copyTo(it) }
      } != null
    }.getOrDefault(false)
    if (!copied) { dest.delete(); return null }

    if (size <= 0L) size = dest.length()
    if (size > Protocol.MAX_CONTENT) { dest.delete(); return null }  // over the 256 MiB cap

    val meta = ItemMeta(
      id = id, kind = "file", createdAt = System.currentTimeMillis(),
      size = size.toInt(), mime = mime, preview = name, text = null,
      filename = name, thumb = null, path = null
    )
    return Imported(meta, dest.absolutePath)
  }
}
