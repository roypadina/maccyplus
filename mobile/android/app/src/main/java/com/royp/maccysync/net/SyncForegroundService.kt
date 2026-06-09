package com.royp.maccysync.net

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.R
import com.royp.maccysync.notify.SyncNowActivity
import com.royp.maccysync.ui.MainActivity

// Keeps the sync connection (and mDNS discovery) alive in the background.
class SyncForegroundService : Service() {
  private var discovery: NsdDiscovery? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    startForegroundCompat()
    val app = MaccyApp.from(this)
    app.controller.start()
    if (discovery == null) {
      discovery = NsdDiscovery(this) { host, port ->
        app.controller.onDiscovered(host, port)
      }.also { it.start() }
    }
    return START_STICKY
  }

  override fun onDestroy() {
    discovery?.stop()
    discovery = null
    MaccyApp.from(this).controller.stop()
    super.onDestroy()
  }

  private fun startForegroundCompat() {
    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val channel = NotificationChannel(
        CHANNEL_ID, getString(R.string.fgs_channel), NotificationManager.IMPORTANCE_LOW)
      manager.createNotificationChannel(channel)
    }
    val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    // Tap the notification body → SyncNowActivity: a focused activity that can read
    // the clipboard (a background broadcast cannot), captures the just-copied clip,
    // then syncs ALL phone clips to the Mac so the new value is included.
    val syncAll = PendingIntent.getActivity(
      this, 4, Intent(this, SyncNowActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags)
    // Action button: open the app.
    val open = PendingIntent.getActivity(
      this, 2, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), flags)

    val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
      .setContentTitle(getString(R.string.fgs_title))
      .setContentText(getString(R.string.fgs_text))
      .setSmallIcon(R.drawable.ic_tile)
      .setOngoing(true)
      .setContentIntent(syncAll)
      .addAction(0, getString(R.string.fgs_open), open)
      .build()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }
  }

  companion object {
    private const val CHANNEL_ID = "sync"
    private const val NOTIFICATION_ID = 1

    fun start(context: Context) {
      ContextCompat.startForegroundService(context, Intent(context, SyncForegroundService::class.java))
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, SyncForegroundService::class.java))
    }
  }
}
