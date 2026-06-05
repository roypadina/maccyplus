package com.royp.maccysync.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.text.format.DateUtils
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Notes
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.royp.maccysync.MaccyApp
import com.royp.maccysync.clipboard.ClipboardAccessibilityService
import com.royp.maccysync.clipboard.ClipboardWriter
import com.royp.maccysync.data.ClipEntity
import com.royp.maccysync.net.SyncForegroundService
import com.royp.maccysync.pairing.PairingActivity
import com.royp.maccysync.sync.SyncController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    requestNotificationPermission()
    val app = application as MaccyApp
    if (app.prefs.syncEnabled && app.prefs.isPaired) SyncForegroundService.start(this)
    requestBatteryExemptionIfNeeded()
    setContent { MaccyTheme { App(app) } }
  }

  private fun requestNotificationPermission() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
      checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
      requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
    }
  }

  @SuppressLint("BatteryLife")
  private fun requestBatteryExemptionIfNeeded() {
    val pm = getSystemService(PowerManager::class.java) ?: return
    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
      runCatching {
        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
      }
    }
  }
}

@Composable
private fun App(app: MaccyApp) {
  var showSettings by remember { mutableStateOf(false) }
  val state by app.controller.state.collectAsStateWithLifecycle()
  val peerName by app.controller.peerName.collectAsStateWithLifecycle()

  Scaffold(
    containerColor = Ink.bg,
    topBar = { MaccyHeader(state, peerName, showSettings) { showSettings = !showSettings } }
  ) { pad ->
    Box(Modifier.fillMaxSize().padding(pad)) {
      if (showSettings) SettingsScreen(app) else ClipsScreen(app)
    }
  }
}

// MARK: header + connection pill

@Composable
private fun MaccyHeader(state: SyncController.ConnState, peerName: String, showSettings: Boolean, onToggle: () -> Unit) {
  Column(Modifier.background(Ink.bg)) {
    Row(
      Modifier.fillMaxWidth().padding(start = 18.dp, end = 8.dp, top = 14.dp, bottom = 12.dp),
      verticalAlignment = Alignment.CenterVertically
    ) {
      Box(Modifier.size(11.dp).clip(RoundedCornerShape(3.dp)).background(Ink.lime))
      Spacer(Modifier.width(9.dp))
      Text("maccy", color = Ink.text, style = MaterialTheme.typography.titleLarge)
      Text("·sync", color = Ink.muted, style = MaterialTheme.typography.titleLarge)
      Spacer(Modifier.weight(1f))
      ConnectionPill(state, peerName)
      Spacer(Modifier.width(4.dp))
      IconButton(onClick = onToggle) {
        Icon(
          if (showSettings) Icons.Filled.Close else Icons.Filled.Settings,
          contentDescription = "Settings",
          tint = if (showSettings) Ink.lime else Ink.muted
        )
      }
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(Ink.border))
  }
}

@Composable
private fun ConnectionPill(state: SyncController.ConnState, peerName: String) {
  val (label, color) = when (state) {
    SyncController.ConnState.Connected -> (if (peerName.isNotEmpty()) peerName.uppercase() else "LIVE") to Ink.lime
    SyncController.ConnState.Connecting -> "SYNC…" to Ink.amber
    SyncController.ConnState.Pairing -> "PAIRING" to Ink.amber
    SyncController.ConnState.Disconnected -> "OFFLINE" to Ink.faint
  }
  val live = state == SyncController.ConnState.Connected || state == SyncController.ConnState.Connecting
  Row(
    Modifier
      .clip(RoundedCornerShape(50))
      .background(Ink.surfaceHi)
      .border(1.dp, Ink.border, RoundedCornerShape(50))
      .padding(horizontal = 10.dp, vertical = 5.dp),
    verticalAlignment = Alignment.CenterVertically
  ) {
    PulseDot(color, live)
    Spacer(Modifier.width(7.dp))
    Text(label, color = color, style = MaterialTheme.typography.labelSmall, maxLines = 1)
  }
}

@Composable
private fun PulseDot(color: Color, pulsing: Boolean) {
  val alpha = if (pulsing) {
    val t = rememberInfiniteTransition(label = "pulse")
    t.animateFloat(
      initialValue = 0.35f, targetValue = 1f,
      animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "dot"
    ).value
  } else 1f
  Box(Modifier.size(7.dp).clip(CircleShape).background(color.copy(alpha = alpha)))
}

// MARK: clips screen with separated phone / mac tabs

@Composable
private fun ClipsScreen(app: MaccyApp) {
  val context = LocalContext.current
  val scope = rememberCoroutineScope()
  var tab by remember { mutableIntStateOf(0) }
  val phoneClips by app.repo.localClips().collectAsStateWithLifecycle(initialValue = emptyList())
  val macClips by app.repo.macClips().collectAsStateWithLifecycle(initialValue = emptyList())

  fun toast(m: String) = Toast.makeText(context, m, Toast.LENGTH_SHORT).show()

  Column(Modifier.fillMaxSize()) {
    SegmentedTabs(
      selected = tab,
      tabs = listOf("THIS PHONE" to Ink.lime, "FROM MAC" to Ink.amber),
      counts = listOf(phoneClips.size, macClips.size),
      onSelect = { tab = it }
    )
    if (tab == 0) {
      ClipList(
        items = phoneClips, accent = Ink.lime,
        empty = EmptyCopy("No copies yet", "Share text here, or copy on this phone."),
        onClick = { clip -> clip.text?.let { ClipboardWriter.setText(context, it); toast("Copied") } }
      )
    } else {
      ClipList(
        items = macClips, accent = Ink.amber,
        empty = EmptyCopy("Nothing from your Mac", "Copy something on the Mac — it lands here."),
        onClick = { clip ->
          scope.launch {
            val ok = withContext(Dispatchers.IO) { app.controller.applyMacClip(clip.toMeta()) }
            toast(if (ok) "Copied to clipboard" else "Couldn't fetch — connect the phone")
          }
        }
      )
    }
  }
}

private data class EmptyCopy(val title: String, val subtitle: String)

@Composable
private fun SegmentedTabs(
  selected: Int,
  tabs: List<Pair<String, Color>>,
  counts: List<Int>,
  onSelect: (Int) -> Unit
) {
  Row(
    Modifier
      .fillMaxWidth()
      .padding(16.dp)
      .clip(RoundedCornerShape(12.dp))
      .background(Ink.surfaceHi)
      .border(1.dp, Ink.border, RoundedCornerShape(12.dp))
      .padding(4.dp)
  ) {
    tabs.forEachIndexed { index, (label, accent) ->
      val active = index == selected
      val bg by animateColorAsState(if (active) accent.copy(alpha = 0.16f) else Color.Transparent, label = "segbg")
      val fg by animateColorAsState(if (active) accent else Ink.muted, label = "segfg")
      Row(
        Modifier
          .weight(1f)
          .clip(RoundedCornerShape(9.dp))
          .background(bg)
          .clickable { onSelect(index) }
          .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
      ) {
        Text(label, color = fg, style = MaterialTheme.typography.labelMedium)
        Spacer(Modifier.width(7.dp))
        Text(
          counts[index].toString(),
          color = if (active) accent else Ink.faint,
          style = MaterialTheme.typography.labelSmall,
          modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(if (active) accent.copy(alpha = 0.18f) else Ink.bg)
            .padding(horizontal = 6.dp, vertical = 2.dp)
        )
      }
    }
  }
}

@Composable
private fun ClipList(items: List<ClipEntity>, accent: Color, empty: EmptyCopy, onClick: (ClipEntity) -> Unit) {
  if (items.isEmpty()) {
    EmptyState(empty)
    return
  }
  LazyColumn(
    Modifier.fillMaxSize(),
    contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp)
  ) {
    items(items, key = { it.id }) { clip -> ClipCard(clip, accent, onClick) }
  }
}

@Composable
private fun ClipCard(clip: ClipEntity, accent: Color, onClick: (ClipEntity) -> Unit) {
  Row(
    Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(14.dp))
      .background(Ink.surface)
      .border(1.dp, Ink.border, RoundedCornerShape(14.dp))
      .clickable { onClick(clip) }
      .height(intrinsicSize = androidx.compose.foundation.layout.IntrinsicSize.Min),
    verticalAlignment = Alignment.CenterVertically
  ) {
    Box(Modifier.width(3.dp).fillMaxSize().background(accent))
    Box(
      Modifier.padding(start = 12.dp).size(34.dp).clip(RoundedCornerShape(9.dp)).background(accent.copy(alpha = 0.14f)),
      contentAlignment = Alignment.Center
    ) {
      Icon(kindIcon(clip.kind), contentDescription = null, tint = accent, modifier = Modifier.size(17.dp))
    }
    Column(Modifier.weight(1f).padding(horizontal = 12.dp, vertical = 12.dp)) {
      Text(
        clip.preview.ifBlank { clip.filename ?: "untitled" },
        color = Ink.text, style = MaterialTheme.typography.bodyMedium,
        maxLines = 2, overflow = TextOverflow.Ellipsis
      )
      Spacer(Modifier.height(4.dp))
      Text(subtitle(clip), color = Ink.muted, style = MaterialTheme.typography.labelSmall)
    }
    Icon(
      Icons.Outlined.ContentCopy, contentDescription = "copy", tint = Ink.faint,
      modifier = Modifier.padding(end = 14.dp).size(16.dp)
    )
  }
}

@Composable
private fun EmptyState(copy: EmptyCopy) {
  Column(
    Modifier.fillMaxSize().padding(32.dp),
    verticalArrangement = Arrangement.Center,
    horizontalAlignment = Alignment.CenterHorizontally
  ) {
    Text("[ ∅ ]", color = Ink.faint, style = MaterialTheme.typography.headlineSmall)
    Spacer(Modifier.height(14.dp))
    Text(copy.title, color = Ink.text, style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(6.dp))
    Text(
      copy.subtitle, color = Ink.muted, style = MaterialTheme.typography.bodySmall,
      modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center
    )
  }
}

// MARK: settings

@Composable
private fun SettingsScreen(app: MaccyApp) {
  val context = LocalContext.current
  var syncEnabled by remember { mutableStateOf(app.prefs.syncEnabled) }
  var sendText by remember { mutableStateOf(app.prefs.sendText) }
  var deviceName by remember { mutableStateOf(app.prefs.deviceName) }
  var paired by remember { mutableStateOf(app.prefs.isPaired) }
  val a11y = isAccessibilityEnabled(context)
  val exempt = isBatteryExempt(context)

  LazyColumn(
    Modifier.fillMaxSize(),
    contentPadding = PaddingValues(16.dp),
    verticalArrangement = Arrangement.spacedBy(14.dp)
  ) {
    item {
      SettingsCard("SYNC") {
        ToggleRow("Enable clipboard sync", syncEnabled) {
          syncEnabled = it; app.prefs.syncEnabled = it
          if (it) SyncForegroundService.start(context) else SyncForegroundService.stop(context)
        }
        FieldRow("This phone's name", deviceName) { deviceName = it; app.prefs.deviceName = it }
        ToggleRow("Send my copies to Mac", sendText) { sendText = it; app.prefs.sendText = it }
      }
    }
    item {
      SettingsCard("PAIRING") {
        if (paired) {
          Text("Paired with ${app.prefs.macName ?: "Mac"}", color = Ink.text, style = MaterialTheme.typography.bodyMedium)
          Spacer(Modifier.height(10.dp))
          Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GhostButton("RE-PAIR") { context.startActivity(Intent(context, PairingActivity::class.java)) }
            GhostButton("UNPAIR", Ink.coral) {
              app.controller.unpair(); SyncForegroundService.stop(context); paired = false
            }
          }
        } else {
          Text("Scan the QR shown in Maccy on your Mac.", color = Ink.muted, style = MaterialTheme.typography.bodySmall)
          Spacer(Modifier.height(10.dp))
          PrimaryButton("PAIR WITH MAC") { context.startActivity(Intent(context, PairingActivity::class.java)) }
        }
      }
    }
    item {
      SettingsCard("KEEP RUNNING") {
        StatusLine(exempt, if (exempt) "Battery unrestricted — stays connected." else "Samsung suspends it in the background.")
        if (!exempt) {
          Spacer(Modifier.height(10.dp))
          GhostButton("ALLOW UNRESTRICTED") {
            runCatching {
              context.startActivity(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
              )
            }
          }
        }
      }
    }
    item {
      SettingsCard("AUTO-CAPTURE") {
        StatusLine(a11y, if (a11y) "Accessibility on — copies captured where the OS allows." else "Optional: some devices block background clipboard reads.")
        Spacer(Modifier.height(6.dp))
        Text("Tip: phone→Mac always works via Share ▸ Maccy Sync.", color = Ink.muted, style = MaterialTheme.typography.bodySmall)
        Spacer(Modifier.height(10.dp))
        GhostButton(if (a11y) "ACCESSIBILITY SETTINGS" else "GRANT ACCESS") {
          context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }
      }
    }
  }
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
  Column(
    Modifier
      .fillMaxWidth()
      .clip(RoundedCornerShape(16.dp))
      .background(Ink.surface)
      .border(1.dp, Ink.border, RoundedCornerShape(16.dp))
      .padding(16.dp)
  ) {
    Text(title, color = Ink.muted, style = MaterialTheme.typography.titleSmall)
    Spacer(Modifier.height(14.dp))
    content()
  }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
  Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
    Text(label, color = Ink.text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
    Switch(
      checked = checked, onCheckedChange = onChange,
      colors = SwitchDefaults.colors(
        checkedThumbColor = Ink.onAccent, checkedTrackColor = Ink.lime,
        uncheckedThumbColor = Ink.muted, uncheckedTrackColor = Ink.surfaceHi, uncheckedBorderColor = Ink.border
      )
    )
  }
}

@Composable
private fun FieldRow(label: String, value: String, onChange: (String) -> Unit) {
  Column(Modifier.padding(vertical = 6.dp)) {
    Text(label, color = Ink.muted, style = MaterialTheme.typography.labelMedium)
    Spacer(Modifier.height(6.dp))
    TextField(
      value = value, onValueChange = onChange, singleLine = true,
      textStyle = MaterialTheme.typography.bodyLarge,
      modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)),
      colors = TextFieldDefaults.colors(
        focusedContainerColor = Ink.surfaceHi, unfocusedContainerColor = Ink.surfaceHi,
        focusedTextColor = Ink.text, unfocusedTextColor = Ink.text,
        focusedIndicatorColor = Ink.lime, unfocusedIndicatorColor = Color.Transparent,
        cursorColor = Ink.lime
      )
    )
  }
}

@Composable
private fun StatusLine(ok: Boolean, text: String) {
  Row(verticalAlignment = Alignment.CenterVertically) {
    Box(Modifier.size(7.dp).clip(CircleShape).background(if (ok) Ink.lime else Ink.amber))
    Spacer(Modifier.width(9.dp))
    Text(text, color = Ink.muted, style = MaterialTheme.typography.bodySmall, modifier = Modifier.weight(1f))
  }
}

@Composable
private fun PrimaryButton(label: String, onClick: () -> Unit) {
  Box(
    Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Ink.lime).clickable { onClick() }
      .padding(vertical = 12.dp),
    contentAlignment = Alignment.Center
  ) { Text(label, color = Ink.onAccent, style = MaterialTheme.typography.labelLarge) }
}

@Composable
private fun GhostButton(label: String, tint: Color = Ink.text, onClick: () -> Unit) {
  Box(
    Modifier.clip(RoundedCornerShape(10.dp)).border(1.dp, Ink.border, RoundedCornerShape(10.dp)).background(Ink.surfaceHi)
      .clickable { onClick() }.padding(horizontal = 16.dp, vertical = 11.dp),
    contentAlignment = Alignment.Center
  ) { Text(label, color = tint, style = MaterialTheme.typography.labelMedium) }
}

// MARK: helpers

private fun kindIcon(kind: String) = when (kind) {
  "image" -> Icons.Outlined.Image
  "file" -> Icons.Outlined.Description
  else -> Icons.Outlined.Notes
}

private fun subtitle(clip: ClipEntity): String {
  val rel = DateUtils.getRelativeTimeSpanString(
    clip.createdAt, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS
  ).toString().lowercase()
  return when (clip.kind) {
    "image" -> "image · $rel"
    "file" -> "${clip.filename ?: "file"} · $rel"
    else -> rel
  }
}

private fun isAccessibilityEnabled(context: Context): Boolean {
  val expected = ComponentName(context, ClipboardAccessibilityService::class.java).flattenToString()
  val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
  return enabled.split(':').any { it.equals(expected, ignoreCase = true) }
}

private fun isBatteryExempt(context: Context): Boolean {
  val pm = context.getSystemService(PowerManager::class.java) ?: return false
  return pm.isIgnoringBatteryOptimizations(context.packageName)
}
