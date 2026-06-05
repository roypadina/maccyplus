package com.royp.maccysync.share

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.clipboard.ClipboardCapture
import com.royp.maccysync.net.SyncForegroundService

// Receives "Share ▸ Maccy Sync" intents and pushes the shared text to the Mac.
// Reads the payload straight from the intent, so it needs no clipboard access —
// the reliable phone→Mac path on devices that block background clipboard reads.
class ShareReceiverActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    val sent = handleSend(intent)
    Toast.makeText(this, if (sent) "Sent to Mac" else "Nothing to send", Toast.LENGTH_SHORT).show()
    finish()
  }

  private fun handleSend(intent: Intent?): Boolean {
    if (intent?.action != Intent.ACTION_SEND) return false
    val app = MaccyApp.from(this)
    if (!app.prefs.isPaired) {
      Toast.makeText(this, "Pair with a Mac first", Toast.LENGTH_SHORT).show()
      return false
    }
    // Make sure the connection is up so it pushes promptly (else it syncs on the
    // next reconnect via history-sync).
    SyncForegroundService.start(this)

    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return false
    if (text.isBlank()) return false
    app.controller.captureLocal(ClipboardCapture.metaFor(text))
    return true
  }
}
