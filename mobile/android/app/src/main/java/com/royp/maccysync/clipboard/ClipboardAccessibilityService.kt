package com.royp.maccysync.clipboard

import android.accessibilityservice.AccessibilityService
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import com.royp.maccysync.MaccyApp

// An active AccessibilityService is permitted to read the clipboard in the
// background on Android 10+. The OnPrimaryClipChangedListener is unreliable for
// background apps on newer Android/OEMs, so we ALSO poll the clipboard (debounced)
// on accessibility events — the technique real clipboard-history apps use.
class ClipboardAccessibilityService : AccessibilityService() {
  private var clipboard: ClipboardManager? = null
  private val listener = ClipboardManager.OnPrimaryClipChangedListener {
    Log.i(TAG, "primaryClipChanged")
    capture()
  }
  private var lastSeen: String? = null
  private var lastCheck = 0L

  override fun onServiceConnected() {
    super.onServiceConnected()
    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.addPrimaryClipChangedListener(listener)
    clipboard = cm
    Log.i(TAG, "service connected, listener registered")
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    val now = System.currentTimeMillis()
    if (now - lastCheck < 400) return
    lastCheck = now
    capture()
  }

  override fun onInterrupt() {}

  override fun onDestroy() {
    clipboard?.removePrimaryClipChangedListener(listener)
    super.onDestroy()
  }

  private fun capture() {
    // On some OEMs/Android versions the OS returns null to a background service
    // (no clipboard access) — that's expected; the share target is the fallback.
    val text = ClipboardCapture.currentText(this) ?: return
    if (text == lastSeen) return
    if (ClipboardWriter.wasJustWritten(text)) { lastSeen = text; return }
    lastSeen = text
    Log.i(TAG, "captured len=${text.length}")
    MaccyApp.from(this).controller.captureLocal(ClipboardCapture.metaFor(text))
  }

  private companion object { const val TAG = "MaccyCap" }
}
