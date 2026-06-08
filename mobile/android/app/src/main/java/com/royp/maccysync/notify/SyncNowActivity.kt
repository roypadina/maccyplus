package com.royp.maccysync.notify

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.clipboard.ClipboardCapture
import com.royp.maccysync.net.SyncForegroundService

// Launched by tapping the ongoing notification ("Sync all"). A broadcast can't do
// this: the clipboard is only readable while an app holds WINDOW FOCUS, so we use
// a translucent activity. On focus we read the clip the user just copied in another
// app, capture it, then sync every phone clip to the Mac — so the new value is
// included and lands first. (onResume is too early; the OS denies the read there.)
class SyncNowActivity : ComponentActivity() {
  private var done = false

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    overridePendingTransition(0, 0)
  }

  override fun onWindowFocusChanged(hasFocus: Boolean) {
    super.onWindowFocusChanged(hasFocus)
    if (!hasFocus || done) return
    done = true
    val app = MaccyApp.from(this)
    if (!app.prefs.isPaired) {
      Toast.makeText(this, "Pair with a Mac first", Toast.LENGTH_SHORT).show()
      finish(); return
    }
    SyncForegroundService.start(this)
    val current = ClipboardCapture.currentText(this)
    app.controller.syncAllIncludingCurrent(current) { n ->
      val msg = when {
        n < 0 -> "Not connected to Mac"
        n == 0 -> "Nothing to sync"
        else -> "Synced $n clip${if (n == 1) "" else "s"} to Mac"
      }
      Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
      finish()
    }
  }
}
