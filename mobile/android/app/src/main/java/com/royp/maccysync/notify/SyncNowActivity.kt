package com.royp.maccysync.notify

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.clipboard.ClipboardCapture
import com.royp.maccysync.net.SyncForegroundService

// Launched by tapping the ongoing notification. A broadcast can't read the
// clipboard (only a focused app can), so this translucent activity reads the clip
// the user just copied in another app — on WINDOW FOCUS, since onResume is too
// early and the OS denies the read there — and sends just that one clip to the Mac.
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
    app.controller.sendCurrentToMac(current) { ok ->
      Toast.makeText(this, if (ok) "Sent to Mac" else "Not connected to Mac", Toast.LENGTH_SHORT).show()
      finish()
    }
  }
}
