package com.royp.maccysync.clipboard

import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import java.io.File

// Saves received image/file payloads via MediaStore (scoped storage, no runtime
// permission needed on API 29+).
object FileSaver {
  fun saveImage(context: Context, name: String, bytes: ByteArray): Boolean =
    write(context, MediaStore.Images.Media.EXTERNAL_CONTENT_URI, name, "image/png",
          Environment.DIRECTORY_PICTURES + "/MaccySync", bytes)

  fun saveDownload(context: Context, name: String, mime: String?, bytes: ByteArray): Boolean =
    write(context, MediaStore.Downloads.EXTERNAL_CONTENT_URI, name,
          mime ?: "application/octet-stream", Environment.DIRECTORY_DOWNLOADS + "/MaccySync", bytes)

  // Stream a (possibly large) already-on-disk file into Downloads without loading
  // it whole into RAM. Used for the 256 MiB file-download path.
  fun saveDownloadStreamed(context: Context, name: String, mime: String?, src: File): Boolean {
    val resolver = context.contentResolver
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, name)
      put(MediaStore.MediaColumns.MIME_TYPE, mime ?: "application/octet-stream")
      put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/MaccySync")
    }
    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return false
    return runCatching {
      resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } } ?: return false
      true
    }.getOrDefault(false)
  }

  private fun write(
    context: Context,
    collection: android.net.Uri,
    name: String,
    mime: String,
    relativePath: String,
    bytes: ByteArray
  ): Boolean {
    val resolver = context.contentResolver
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, name)
      put(MediaStore.MediaColumns.MIME_TYPE, mime)
      put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
    }
    val uri = resolver.insert(collection, values) ?: return false
    return runCatching {
      resolver.openOutputStream(uri)?.use { it.write(bytes) } ?: return false
      true
    }.getOrDefault(false)
  }
}
