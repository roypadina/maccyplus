package com.royp.maccysync

import android.app.Application
import android.content.Context
import com.royp.maccysync.data.ClipRepository
import com.royp.maccysync.sync.SyncController

class MaccyApp : Application() {
  lateinit var prefs: Prefs
    private set
  lateinit var repo: ClipRepository
    private set
  lateinit var controller: SyncController
    private set

  override fun onCreate() {
    super.onCreate()
    prefs = Prefs(this)
    repo = ClipRepository(this)
    controller = SyncController(this, prefs, repo)
    // NOTE: do NOT start the foreground service here — Android 12+ forbids
    // starting an FGS from Application.onCreate (background start). MainActivity
    // starts it from its foreground context instead.
  }

  companion object {
    fun from(context: Context): MaccyApp = context.applicationContext as MaccyApp
  }
}
