package com.bogahost.posta

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // Bildirim sesi önizlemesi (Ayarlar › Bildirimler › Sesi dinle). Bildirimlerin kendisi sesi kanaldan
    // (posta_v2 / sohbet_v2) çalar. Dart: lib/veri/bildirim_sesi.dart ("boga/ses").
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boga/ses").setMethodCallHandler { call, result ->
      if (call.method != "cal") {
        result.notImplemented()
        return@setMethodCallHandler
      }
      val kaynak = if (call.arguments == "sohbet") R.raw.bogamail_sohbet else R.raw.bogamail_posta
      result.success(cal(applicationContext, kaynak))
    }
  }

  private fun cal(baglam: Context, kaynak: Int): Boolean = try {
    val nitelik = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_NOTIFICATION)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()
    val ses = baglam.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val oynatici = MediaPlayer.create(baglam, kaynak, nitelik, ses.generateAudioSessionId())
    if (oynatici == null) {
      false
    } else {
      oynatici.setOnCompletionListener { it.release() }
      oynatici.start()
      true
    }
  } catch (e: Exception) {
    false
  }
}
