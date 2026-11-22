package com.bogahost.posta

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.provider.CalendarContract
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
    // Görevi takvime ekle: takvim uygulamasının yeni etkinlik ekranı (kullanıcı onaylar). Dart: lib/veri/takvime_ekle.dart.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "boga/takvim").setMethodCallHandler { call, result ->
      if (call.method != "ekle") {
        result.notImplemented()
        return@setMethodCallHandler
      }
      val baslangic = (call.argument<Number>("baslangic") ?: 0).toLong()
      val bitis = (call.argument<Number>("bitis") ?: baslangic).toLong()
      val niyet = Intent(Intent.ACTION_INSERT)
        .setData(CalendarContract.Events.CONTENT_URI)
        .putExtra(CalendarContract.Events.TITLE, call.argument<String>("baslik") ?: "")
        .putExtra(CalendarContract.Events.DESCRIPTION, call.argument<String>("notlar") ?: "")
        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, baslangic)
        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, bitis)
      result.success(
        try {
          startActivity(niyet)
          true
        } catch (e: ActivityNotFoundException) {
          false
        }
      )
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
