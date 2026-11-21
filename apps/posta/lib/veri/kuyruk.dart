// Çevrimdışı çalışma: bekleyen değişiklikler (okundu, yıldız, arşiv, silme, taşıma...) ve Giden Kutusu.
//
// Değişiklikler arayüzde ve yerel önbellekte hemen uygulanır (iyimser); sunucuya ulaşılamazsa sırayla kalıcı bir
// kuyruğa yazılır ve bağlantı gelince aynı sırayla gönderilir. Çakışma güvenliği: 404/409/410/422 gibi istemci
// hataları (ileti başka yerde silinmiş / taşınmış) sessizce düşürülür; sunucu hatası ya da bağlantı yoksa kuyruk
// durur ve sonra yeniden denenir.
//
// Giden Kutusu (Outlook gibi): çevrimdışıyken gönderilen iletiler ekleriyle birlikte yerelde saklanır, kenar
// menüsünde görünür; her öğenin durumu (Bekliyor / Gönderiliyor… / Hata) vardır, açılıp düzenlenebilir ya da
// silinebilir. Bağlantı gelince sırayla gönderilir ve sunucu Gönderilenler'e koyar.
//
// Kalıcılık: hesap başına önbellek dizininde "kalici:" anahtarları (boyut sınırında silinmez; hesap kaldırılınca /
// çıkışta silinir). İçerik loglanmaz.

import 'dart:async';
import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';

import '../oturum.dart';
import 'hesap_servisi.dart';
import 'onbellek.dart';
import 'posta_servisi.dart';
import 'yardimci.dart';

/// Sunucuya gönderilmeyi bekleyen bir değişiklik.
@immutable
class BekleyenIslem {
  const BekleyenIslem({required this.id, required this.yontem, required this.yol, this.govde, required this.aciklama, required this.zaman});
  final String id;
  final String yontem;
  final String yol;
  final Map<String, dynamic>? govde;

  /// Arayüzde gösterilen kısa açıklama ("Arşivle (2 ileti)").
  final String aciklama;
  final DateTime zaman;

  Map<String, dynamic> get json => {'id': id, 'yontem': yontem, 'yol': yol, 'govde': govde, 'aciklama': aciklama, 'zaman': zaman.millisecondsSinceEpoch};

  static BekleyenIslem? json_(Object? v) {
    if (v is! Map) return null;
    final g = v['govde'];
    return BekleyenIslem(
      id: '${v['id'] ?? ''}',
      yontem: '${v['yontem'] ?? ''}',
      yol: '${v['yol'] ?? ''}',
      govde: g is Map ? Map<String, dynamic>.from(g) : null,
      aciklama: '${v['aciklama'] ?? ''}',
      zaman: DateTime.fromMillisecondsSinceEpoch((v['zaman'] as num?)?.toInt() ?? 0),
    );
  }
}

String yeniKimlik() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${r.nextInt(1 << 30).toRadixString(36)}';
}

/// İstemci hatası: değişiklik artık uygulanamaz (ileti yok / taşınmış / geçersiz) → kuyruktan düşürülür.
bool _dusurulur(int? d) => d != null && d >= 400 && d < 500 && d != 401 && d != 408 && d != 429;

class IslemKuyrugu {
  IslemKuyrugu._();
  static final ben = IslemKuyrugu._();
  static const _anahtar = 'kalici:kuyruk';

  final ogeler = ValueNotifier<List<BekleyenIslem>>(const []);
  bool get bos => ogeler.value.isEmpty;

  Future<void>? _oynatma;
  String _hesap = '';

  Future<void> yukle() async {
    _hesap = Onbellek.ben.hesap ?? '';
    final v = await Onbellek.ben.oku(_anahtar);
    if (_hesap != (Onbellek.ben.hesap ?? '')) return;
    ogeler.value = v is List ? v.map(BekleyenIslem.json_).whereType<BekleyenIslem>().toList() : const [];
  }

  Future<void> _kaydet() => Onbellek.ben.yaz(_anahtar, ogeler.value.map((e) => e.json).toList());

  Future<void> ekle(String yontem, String yol, Map<String, dynamic>? govde, String aciklama) async {
    ogeler.value = [...ogeler.value, BekleyenIslem(id: yeniKimlik(), yontem: yontem, yol: yol, govde: govde, aciklama: aciklama, zaman: DateTime.now())];
    await _kaydet();
  }

  /// Bekleyen değişiklikleri sırayla gönderir. Eşzamanlı çağrılar aynı oynatmayı bekler.
  Future<void> oynat() => _oynatma ??= _oynat().whenComplete(() => _oynatma = null);

  Future<void> _oynat() async {
    final hesap = _hesap;
    while (ogeler.value.isNotEmpty && hesap == _hesap) {
      final i = ogeler.value.first;
      try {
        await istekGonder(i.yontem, i.yol, i.govde);
      } on ApiHata catch (e) {
        if (e.baglantiYok || !_dusurulur(e.durum)) return; // sonra yeniden denenir
      } catch (_) {
        return;
      }
      if (hesap != _hesap) return;
      ogeler.value = ogeler.value.where((x) => x.id != i.id).toList();
      await _kaydet();
    }
  }

  static Future<dynamic> istekGonder(String yontem, String yol, Map<String, dynamic>? govde) {
    final a = Uyg.api;
    return switch (yontem) {
      'PATCH' => a.patch(yol, govde),
      'POST' => a.post(yol, govde),
      'PUT' => a.put(yol, govde),
      'DELETE' => a.delete(yol, govde: govde),
      _ => a.get(yol),
    };
  }

  void sifirla() {
    _hesap = '';
    ogeler.value = const [];
  }
}

enum GidenDurum { bekliyor, gonderiliyor, hata }

@immutable
class GidenOge {
  const GidenOge({
    required this.id,
    required this.konu,
    required this.kime,
    required this.zaman,
    this.durum = GidenDurum.bekliyor,
    this.hata,
    this.boyut = 0,
    this.ekSayisi = 0,
  });
  final String id;
  final String konu;
  final String kime;
  final DateTime zaman;
  final GidenDurum durum;
  final String? hata;
  final int boyut;
  final int ekSayisi;

  GidenOge kopya({GidenDurum? durum, String? hata, bool hataSil = false}) => GidenOge(
    id: id,
    konu: konu,
    kime: kime,
    zaman: zaman,
    durum: durum ?? this.durum,
    hata: hataSil ? null : (hata ?? this.hata),
    boyut: boyut,
    ekSayisi: ekSayisi,
  );

  Map<String, dynamic> get json => {
    'id': id,
    'konu': konu,
    'kime': kime,
    'zaman': zaman.millisecondsSinceEpoch,
    'durum': durum.name,
    'hata': hata,
    'boyut': boyut,
    'ek': ekSayisi,
  };

  static GidenOge? json_(Object? v) {
    if (v is! Map) return null;
    final d = GidenDurum.values.where((x) => x.name == v['durum']).firstOrNull ?? GidenDurum.bekliyor;
    return GidenOge(
      id: '${v['id'] ?? ''}',
      konu: '${v['konu'] ?? ''}',
      kime: '${v['kime'] ?? ''}',
      zaman: DateTime.fromMillisecondsSinceEpoch((v['zaman'] as num?)?.toInt() ?? 0),
      // Uygulama gönderim sırasında kapandıysa: yeniden bekliyor.
      durum: d == GidenDurum.gonderiliyor ? GidenDurum.bekliyor : d,
      hata: v['hata'] as String?,
      boyut: (v['boyut'] as num?)?.toInt() ?? 0,
      ekSayisi: (v['ek'] as num?)?.toInt() ?? 0,
    );
  }
}

class GidenKutusu {
  GidenKutusu._();
  static final ben = GidenKutusu._();
  static const _anahtar = 'kalici:giden';
  static String _icerik(String id) => 'kalici:giden:$id';

  final ogeler = ValueNotifier<List<GidenOge>>(const []);

  /// Bekleyen (hata olmayan) iletiler.
  int get bekleyen => ogeler.value.where((o) => o.durum != GidenDurum.hata).length;

  /// Sunucu kuyruğu (GET /mail/scheduled): geri alma süresindeki, planlanmış ve gönderilemeyen iletiler.
  final sunucu = ValueNotifier<List<Planli>>(const []);

  /// Kenar menüsündeki sayı: yerel + sunucu.
  int get toplam => ogeler.value.length + sunucu.value.length;

  /// Hata durumunda öğe var (kenar menüsünde kırmızı).
  bool get hataVar => ogeler.value.any((o) => o.durum == GidenDurum.hata) || sunucu.value.any((p) => p.durum == 'failed');

  /// Sunucu kuyruğunu tazeler (önce yerel kopya; çevrimdışında son bilinen liste kalır).
  Future<void> sunucuTazele() async {
    final hesap = _hesap;
    try {
      final l = await yerelOnce(
        'giden:sunucu',
        () async => {'items': (await Hesap.planlananlar()).where((p) => p.giden).map((p) => p.json).toList()},
        (v) => ((v is Map ? v['items'] : null) as List? ?? const []).map(Planli.json).where((p) => p.giden).toList(),
        yerel: (l) {
          if (hesap == _hesap && sunucu.value.isEmpty) sunucu.value = l;
        },
      );
      if (hesap == _hesap) sunucu.value = l;
    } catch (_) {}
  }

  /// Düzenlenmek üzere açık öğeler gönderilmez.
  final _duzenleniyor = <String>{};
  Future<void>? _gonderim;
  String _hesap = '';

  /// Başarılı gönderimden sonra (sayılar / Gönderilenler tazelenir).
  static void Function()? gonderildi;

  Future<void> yukle() async {
    _hesap = Onbellek.ben.hesap ?? '';
    final v = await Onbellek.ben.oku(_anahtar);
    if (_hesap != (Onbellek.ben.hesap ?? '')) return;
    ogeler.value = v is List ? v.map(GidenOge.json_).whereType<GidenOge>().toList() : const [];
    final sv = await Onbellek.ben.oku('giden:sunucu');
    if (_hesap != (Onbellek.ben.hesap ?? '')) return;
    sunucu.value = ((sv is Map ? sv['items'] : null) as List? ?? const []).map(Planli.json).where((p) => p.giden).toList();
  }

  Future<void> _kaydet() => Onbellek.ben.yaz(_anahtar, ogeler.value.map((e) => e.json).toList());

  void _guncelle(String id, GidenOge Function(GidenOge) f) {
    ogeler.value = [for (final o in ogeler.value) o.id == id ? f(o) : o];
  }

  /// Gönderim isteğini (ekler base64 içinde) Giden Kutusu'na koyar. [eskiId]: düzenlenen öğenin yerine.
  Future<String> ekle(Map<String, dynamic> istek, {Map<String, dynamic>? ek, String? eskiId}) async {
    final id = yeniKimlik();
    final kime = [
      for (final a in ['to', 'cc', 'bcc']) ...((istek[a] as List?) ?? const []),
    ].map((e) => '$e').join(', ');
    final ekler = (istek['attachments'] as List?) ?? const [];
    final boyut = ekler.fold<int>(0, (t, e) => t + (e is Map ? ('${e['data'] ?? ''}'.length * 3 ~/ 4) : 0));
    await Onbellek.ben.yaz(_icerik(id), {'istek': istek, 'ek': ?ek});
    final o = GidenOge(
      id: id,
      konu: '${istek['subject'] ?? ''}',
      kime: kime,
      zaman: DateTime.now(),
      boyut: boyut,
      ekSayisi: ekler.length + ((istek['include_parts'] as List?)?.length ?? 0),
    );
    final l = [...ogeler.value];
    final i = eskiId == null ? -1 : l.indexWhere((x) => x.id == eskiId);
    if (i >= 0) {
      l[i] = o;
    } else {
      l.add(o);
    }
    ogeler.value = l;
    if (eskiId != null) {
      _duzenleniyor.remove(eskiId);
      await Onbellek.ben.sil(_icerik(eskiId));
    }
    await _kaydet();
    return id;
  }

  /// Kayıtlı gönderim isteği ve ek bilgiler (düzenleme için).
  Future<(Map<String, dynamic>, Map<String, dynamic>)?> icerik(String id) async {
    final v = await Onbellek.ben.oku(_icerik(id));
    if (v is! Map || v['istek'] is! Map) return null;
    return (Map<String, dynamic>.from(v['istek'] as Map), v['ek'] is Map ? Map<String, dynamic>.from(v['ek'] as Map) : <String, dynamic>{});
  }

  Future<void> sil(String id) async {
    _duzenleniyor.remove(id);
    ogeler.value = ogeler.value.where((o) => o.id != id).toList();
    await Onbellek.ben.sil(_icerik(id));
    await _kaydet();
  }

  void duzenlemeBasla(String id) => _duzenleniyor.add(id);
  void duzenlemeBitti(String id) {
    if (_duzenleniyor.remove(id)) unawaited(gonder());
  }

  bool duzenleniyor(String id) => _duzenleniyor.contains(id);

  Future<void> tekrarDene(String id) async {
    _guncelle(id, (o) => o.kopya(durum: GidenDurum.bekliyor, hataSil: true));
    await _kaydet();
    await gonder();
  }

  /// Bekleyenleri sırayla gönderir. Bağlantı yoksa durur (öğeler bekliyor kalır); sunucu reddederse öğe "Hata"
  /// olur ve sıradakine geçilir.
  Future<void> gonder() => _gonderim ??= _gonder().whenComplete(() => _gonderim = null);

  Future<void> _gonder() async {
    final hesap = _hesap;
    while (hesap == _hesap) {
      final o = ogeler.value.where((x) => x.durum == GidenDurum.bekliyor && !_duzenleniyor.contains(x.id)).firstOrNull;
      if (o == null) return;
      final c = await icerik(o.id);
      if (c == null) {
        await sil(o.id);
        continue;
      }
      // Eski (anahtarsız) öğeler: ilk denemeden önce kalıcı anahtar verilir; sonraki denemeler aynı anahtarla.
      if (c.$1['_idem'] is! String) {
        c.$1['_idem'] = gonderimAnahtari();
        await Onbellek.ben.yaz(_icerik(o.id), {'istek': c.$1, if (c.$2.isNotEmpty) 'ek': c.$2});
      }
      _guncelle(o.id, (x) => x.kopya(durum: GidenDurum.gonderiliyor, hataSil: true));
      try {
        await Posta.gonder(c.$1);
      } on GonderimHatasi catch (e) {
        if (hesap != _hesap) return;
        if (e.baglantiYok) {
          _guncelle(o.id, (x) => x.kopya(durum: GidenDurum.bekliyor));
          return;
        }
        final m = e.dlp != null ? 'Hassas veri uyarısı: açıp onaylayarak gönderin' : e.mesaj;
        _guncelle(o.id, (x) => x.kopya(durum: GidenDurum.hata, hata: m));
        await _kaydet();
        continue;
      } catch (e) {
        if (hesap != _hesap) return;
        _guncelle(o.id, (x) => x.kopya(durum: GidenDurum.hata, hata: hataMetni(e)));
        await _kaydet();
        continue;
      }
      if (hesap != _hesap) return;
      await sil(o.id);
      gonderildi?.call();
    }
  }

  void sifirla() {
    _hesap = '';
    _duzenleniyor.clear();
    ogeler.value = const [];
    sunucu.value = const [];
  }
}
