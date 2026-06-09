package com.royp.maccysync.share

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.net.SyncForegroundService

// Receives "Share ▸ Maccy Sync" intents. Text is pushed straight to the Mac;
// a shared file is copied into the phone's list and uploaded (the share itself
// is the explicit send). Reads the payload from the intent, so it needs no
// clipboard access — the reliable phone→Mac path on locked-down devices.
class ShareReceiverActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    if (!handleSend(intent)) finish()
  }

  private fun handleSend(intent: Intent?): Boolean {
    if (intent?.action != Intent.ACTION_SEND) return false
    val app = MaccyApp.from(this)
    if (!app.prefs.isPaired) {
      Toast.makeText(this, "Pair with a Mac first", Toast.LENGTH_SHORT).show()
      return false
    }
    // Make sure the connection is up so it pushes promptly (else it syncs on the
    // next reconnect — or, for files, when the user taps Upload).
    SyncForegroundService.start(this)

    // A shared file (EXTRA_STREAM) takes priority over any text label.
    @Suppress("DEPRECATION")
    val stream: Uri? = intent.getParcelableExtra(Intent.EXTRA_STREAM)
    if (stream != null) {
      Toast.makeText(this, "Sending file to Mac…", Toast.LENGTH_SHORT).show()
      // Keep the activity alive until the copy finishes — the URI read grant is
      // tied to this activity's lifetime.
      app.controller.importFile(stream, upload = true) { ok ->
        Toast.makeText(this, if (ok) "File queued for Mac" else "Couldn't read file", Toast.LENGTH_SHORT).show()
        finish()
      }
      return true
    }

    val text = intent.getStringExtra(Intent.EXTRA_TEXT)
    if (text.isNullOrBlank()) return false
    app.controller.onLocalText(text, auto = false)
    Toast.makeText(this, "Sent to Mac", Toast.LENGTH_SHORT).show()
    finish()
    return true
  }
}
