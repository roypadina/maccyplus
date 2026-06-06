package com.royp.maccysync.notify

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.clipboard.ClipboardCapture
import com.royp.maccysync.net.SyncForegroundService

// Launched by tapping the ongoing notification. Because we briefly become the
// focused app, we CAN read the live clipboard here (the OS blocks that for a
// background service). We send it to the Mac, then finish without showing UI.
// If the read comes back empty, SyncController falls back to the latest stored clip.
class SendLatestActivity : ComponentActivity() {
  private var done = false

  override fun onResume() {
    super.onResume()
    if (done) return
    done = true
    val app = MaccyApp.from(this)
    if (!app.prefs.isPaired) {
      Toast.makeText(this, "Pair with a Mac first", Toast.LENGTH_SHORT).show()
      finish(); return
    }
    SyncForegroundService.start(this)
    val live = ClipboardCapture.currentText(this)
    app.controller.sendLatestToMac(live) { ok ->
      Toast.makeText(this, if (ok) "Sent latest to Mac" else "Nothing to send", Toast.LENGTH_SHORT).show()
      finish()
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    overridePendingTransition(0, 0)
  }
}
