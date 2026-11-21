// Arka plan eşitlemesi (önce yerel, sonra ağ): açılışta, canlı olaylarda (yeni posta, bayrak, taşıma...),
// bağlantı geri gelince ve belirli aralıklarla çalışır.
//
// 1. Bekleyen değişiklikleri ve Giden Kutusu'nu sırayla gönderir.
// 2. Klasör listesini ve sayıları tazeler (önbelleğe yazılır).
// 3. Gelen Kutusu'nun en yeni [gelenSayisi] iletisini listeler; listenin ilk sayfası önbelleğe yazılır, gövdeler
//    düşük öncelikle önyüklenir (görseller kullanıcı izin verdiyse görsel önbelleğine).
// 4. Gönderilenler, Taslaklar, Arşiv'in ilk sayfası ve en yeni [digerSayisi] iletisi.
//
// Sunucuda ucuz bir değişiklik (delta/modseq) uç noktası yok: klasör başına ilk sayfa yeniden alınır; gövdeler
// yalnız önbellekte yoksa indirilir. Önyükleme disk sınırının [Onyukleme.arkaDolulukSiniri] oranında durur.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'baglanti.dart';
import 'durum.dart';
import 'kuyruk.dart';
import 'onbellek.dart';
import 'onyukleme.dart';
import 'posta_servisi.dart';

class Esitleyici {
  Esitleyici._();
  static final ben = Esitleyici._();

  /// Testlerde (FLUTTER_TEST) zamanlayıcılar ve ağ eşitlemesi kendiliğinden başlamaz.
  static bool etkin = kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  static Duration aralik = const Duration(minutes: 5);
  static int gelenSayisi = 200;
  static int digerSayisi = 25;
  static const digerRoller = ['sent', 'drafts', 'archive'];

  Timer? _zaman;
  Timer? _gecikme;
  Future<void>? _suren;
  bool _yeniden = false;

  /// Hesabın yerel verisini açar: önbellek, son eşitleme zamanı, bekleyen değişiklikler, Giden Kutusu.
  Future<void> hesapAc(String id) async {
    if (id.isEmpty) return;
    await Onbellek.ben.hesapAc(id);
    await Future.wait([Baglanti.ben.hesapAc(id), IslemKuyrugu.ben.yukle(), GidenKutusu.ben.yukle()]);
  }

  /// Hesabın tüm yerel verisini siler (çıkış / hesabı unut).
  Future<void> hesabiSil(String id) async {
    if (Onbellek.ben.hesap == id) {
      IslemKuyrugu.ben.sifirla();
      GidenKutusu.ben.sifirla();
    }
    await Onbellek.ben.hesabiSil(id);
    await Baglanti.ben.hesabiSil(id);
  }

  void baslat() {
    Baglanti.ben.geriGelince(_geriGeldi);
    if (!etkin) return;
    _zaman?.cancel();
    _zaman = Timer.periodic(aralik, (_) => tetikle(hemen: true));
    tetikle(hemen: true);
  }

  void durdur() {
    _zaman?.cancel();
    _zaman = null;
    _gecikme?.cancel();
    _gecikme = null;
  }

  void _geriGeldi() {
    // Bağlantı geldi: önce bekleyenler (testlerde de), sonra eşitleme.
    unawaited(IslemKuyrugu.ben.oynat());
    unawaited(GidenKutusu.ben.gonder());
    if (etkin) tetikle();
  }

  /// Eşitlemeyi ister; canlı olaylar art arda gelirse birleştirilir.
  void tetikle({bool hemen = false}) {
    if (!etkin) return;
    _gecikme?.cancel();
    _gecikme = Timer(hemen ? Duration.zero : const Duration(seconds: 2), () => unawaited(esitle()));
  }

  /// Tam eşitleme (sürerken çağrılırsa bittiğinde bir kez daha).
  Future<void> esitle() {
    if (_suren != null) {
      _yeniden = true;
      return _suren!;
    }
    return _suren = _esitle().whenComplete(() {
      _suren = null;
      if (_yeniden) {
        _yeniden = false;
        unawaited(esitle());
      }
    });
  }

  Future<void> _esitle() async {
    final hesap = Onbellek.ben.hesap;
    if (hesap == null) return;
    final s = Stopwatch()..start();
    try {
      await IslemKuyrugu.ben.oynat();
      await GidenKutusu.ben.gonder();
      final d = PostaDurum.ben;
      await d.klasorleriTazele();
      if (Onbellek.ben.hesap != hesap) return;
      final gelen = d.rolu('inbox');
      if (gelen != null) {
        final sayfa = d.ayarlar?.sayfaBoyutu ?? 50;
        final l = await Posta.liste(klasorId: gelen.id, boyut: gelenSayisi, onbellekBoyut: sayfa);
        if (Onbellek.ben.hesap != hesap) return;
        Onyukleme.ben.arkaPlan(l.ogeler.map((m) => m.id));
      }
      for (final rol in digerRoller) {
        final k = d.rolu(rol);
        if (k == null) continue;
        final l = await Posta.liste(klasorId: k.id, boyut: d.ayarlar?.sayfaBoyutu ?? 50);
        if (Onbellek.ben.hesap != hesap) return;
        Onyukleme.ben.arkaPlan(l.ogeler.take(digerSayisi).map((m) => m.id));
      }
      await Baglanti.ben.esitlendi();
      zamanLogu('eşitleme', s);
    } catch (_) {
      // çevrimdışı / sunucu hatası: sonraki tetiklemede yeniden
    }
  }
}
