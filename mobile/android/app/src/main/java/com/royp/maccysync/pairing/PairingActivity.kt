package com.royp.maccysync.pairing

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.net.SyncForegroundService
import java.util.concurrent.atomic.AtomicBoolean

// Uses Google's built-in code scanner (Play services), which owns the camera,
// focus, and QR detection — far more reliable than a hand-rolled CameraX +
// ML Kit analyzer, and needs no camera permission.
class PairingActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // Camera-free path: pair from a payload passed via intent (adb / share).
    val injected = intent?.getStringExtra("payload")
    if (injected != null) {
      pairWithPayload(injected)
      setContent { MaterialTheme { PairingStatus("Pairing…") } }
      return
    }
    setContent { MaterialTheme { PairingScreen(onDone = { finish() }) } }
  }

  private fun pairWithPayload(raw: String) {
    val payload = QrParser.parse(raw)
    if (payload == null) {
      android.util.Log.e("MaccyPair", "invalid payload")
      finish()
      return
    }
    android.util.Log.i("MaccyPair", "pairing with ${payload.name} @ ${payload.host}:${payload.port}")
    MaccyApp.from(this).controller.startPairing(payload) { ok, err ->
      android.util.Log.i("MaccyPair", "pair result ok=$ok err=$err")
      if (ok) SyncForegroundService.start(this)
      runOnUiThread { finish() }
    }
  }
}

@Composable
private fun PairingStatus(text: String) {
  Column(modifier = Modifier.fillMaxSize().padding(24.dp)) { Text(text) }
}

@Composable
private fun PairingScreen(onDone: () -> Unit) {
  val context = LocalContext.current
  val activity = context as ComponentActivity
  var status by remember { mutableStateOf("Opening scanner…") }
  val handled = remember { AtomicBoolean(false) }

  fun handleQr(raw: String) {
    if (!handled.compareAndSet(false, true)) return
    val payload = QrParser.parse(raw)
    if (payload == null) {
      handled.set(false)
      status = "That isn't a Maccy pairing code. Try again."
      return
    }
    status = "Pairing with ${payload.name}…"
    MaccyApp.from(context).controller.startPairing(payload) { success, error ->
      activity.runOnUiThread {
        if (success) {
          SyncForegroundService.start(context)
          status = "Paired!"
          onDone()
        } else {
          handled.set(false)
          status = "Pairing failed: ${error ?: "unknown"}"
        }
      }
    }
  }

  fun launchScan() {
    handled.set(false)
    status = "Point at the QR in Maccy ▸ Settings ▸ Sync ▸ Pair"
    val options = GmsBarcodeScannerOptions.Builder()
      .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
      .build()
    GmsBarcodeScanning.getClient(context, options).startScan()
      .addOnSuccessListener { barcode -> barcode.rawValue?.let { handleQr(it) } }
      .addOnCanceledListener { status = "Scan cancelled" }
      .addOnFailureListener { e -> status = "Scanner error: ${e.message}" }
  }

  LaunchedEffect(Unit) { launchScan() }

  Column(
    modifier = Modifier.fillMaxSize().padding(24.dp),
    verticalArrangement = Arrangement.spacedBy(16.dp)
  ) {
    Text("Pair with Mac", style = MaterialTheme.typography.headlineSmall)
    Text(status)
    Button(onClick = { launchScan() }) { Text("Scan QR code") }
    OutlinedButton(onClick = onDone) { Text("Cancel") }
  }
}
