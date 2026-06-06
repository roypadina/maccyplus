package com.royp.maccysync.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.widget.Toast
import com.royp.maccysync.MaccyApp

// Handles the notification's "Sync all" action button. Sync-all reads only the
// local DB (no clipboard access needed), so a receiver is enough — the network
// push runs on the controller's own IO scope.
class ClipActionReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != ACTION_SYNC_ALL) return
    val app = MaccyApp.from(context)
    app.controller.syncAllToMac { n ->
      val msg = when {
        n < 0 -> "Not connected to Mac"
        n == 0 -> "Nothing to sync"
        else -> "Synced $n clip${if (n == 1) "" else "s"} to Mac"
      }
      Toast.makeText(context, msg, Toast.LENGTH_SHORT).show()
    }
  }

  companion object {
    const val ACTION_SYNC_ALL = "com.royp.maccysync.action.SYNC_ALL"
  }
}
