// "Tüm hesaplar" birleşik gelen kutusu: /api/v1/mail/unified/* (internal/api/unified.go). Bu cihazda kayıtlı ve
// oturumu açık tüm hesapların iletileri tek listede; içerik hesap değiştirmeden okunur, temel işlemler yapılır.
// Yanıtla/ilet için önce o hesaba geçilir (gönderen o hesap olur).

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import 'canli.dart';
import 'modeller.dart';
import 'onbellek.dart';

class BirlesikHesap {
  const BirlesikHesap({required this.id, required this.adres, this.ad = '', required this.renk});
  final String id;
  final String adres;
  final String ad;
  final Color renk;

  factory BirlesikHesap.json(Object? v) {
    final m = v is Map ? v : const {};
    return BirlesikHesap(id: '${m['id'] ?? ''}', adres: '${m['address'] ?? ''}', ad: '${m['display_name'] ?? ''}', renk: renkCoz('${m['color'] ?? ''}'));
  }

  /// Listede kısa etiket: adresin @ öncesi.
  String get kisa => adres.contains('@') ? adres.substring(0, adres.indexOf('@')) : adres;
  String get gorunen => ad.trim().isNotEmpty ? ad.trim() : adres;

  /// "#2563eb" → Color (bozuksa mavi).
  static Color renkCoz(String s) {
    final h = s.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (h.length != 6 || v == null) return const Color(0xFF2563EB);
    return Color(0xFF000000 | v);
  }
}

class BirlesikOge {
  BirlesikOge(this.ozet, this.kutuId, this.hesap);
  final IletiOzet ozet;
  final String kutuId;
  final String hesap;

  /// Hesaplar arasında benzersiz anahtar.
  String get anahtar => '$kutuId/${ozet.id}';

  factory BirlesikOge.json(Object? v) {
    final m = v is Map ? v : const {};
    return BirlesikOge(IletiOzet.json(m), '${m['mailbox_id'] ?? ''}', '${m['account'] ?? ''}');
  }
}

class BirlesikSayfa {
  BirlesikSayfa(this.hesaplar, this.ogeler, this.sonraki);
  final List<BirlesikHesap> hesaplar;
  final List<BirlesikOge> ogeler;
  final String? sonraki;

  factory BirlesikSayfa.json(Object? v) {
    final m = v is Map ? v : const {};
    final h = m['accounts'] is List ? m['accounts'] as List : const [];
    final o = m['items'] is List ? m['items'] as List : const [];
    final s = m['next_before'];
    return BirlesikSayfa(
      h.map(BirlesikHesap.json).where((x) => x.id.isNotEmpty).toList(),
      o.map(BirlesikOge.json).where((x) => x.kutuId.isNotEmpty && x.ozet.id.isNotEmpty).toList(),
      s is String && s.isNotEmpty ? s : null,
    );
  }
}

/// Birleşik görünüm klasörleri (sunucudaki folder=).
const birlesikKlasorler = <(String, String, IconData)>[
  ('inbox', 'Gelen', Icons.inbox_outlined),
  ('unread', 'Okunmamış', Icons.mail_outline_rounded),
  ('flagged', 'Yıldızlı', Icons.star_rounded),
  ('sent', 'Gönderilen', Icons.send_outlined),
  ('all', 'Tümü', Icons.all_inbox_outlined),
];

class Birlesik {
  Birlesik._();
  static const _k = '/api/v1/mail/unified';

  static Future<BirlesikSayfa> liste({String klasor = 'inbox', String? once, String? arama, int boyut = 50}) async {
    final v = await Uyg.api.get(
      '$_k/messages',
      q: {'folder': klasor, 'limit': boyut, 'before': ?once, if (arama != null && arama.trim().isNotEmpty) 'q': arama.trim()},
    );
    if (once == null && (arama == null || arama.trim().isEmpty)) unawaited(Onbellek.ben.yaz('birlesik:$klasor', v));
    return BirlesikSayfa.json(v);
  }

  static Future<BirlesikSayfa?> listeOnbellek(String klasor) async {
    final v = await Onbellek.ben.oku('birlesik:$klasor');
    return v == null ? null : BirlesikSayfa.json(v);
  }

  static Future<IletiDetay> ileti(String kutuId, String id) async {
    final v = await Uyg.api.get('$_k/messages/$kutuId/$id');
    unawaited(Onbellek.ben.yaz('birlesik-ileti:$kutuId/$id', v));
    return IletiDetay.json(v);
  }

  static IletiDetay? iletiHemen(String kutuId, String id) {
    final v = Onbellek.ben.hemen('birlesik-ileti:$kutuId/$id');
    return v == null ? null : IletiDetay.json(v);
  }

  static Future<Uint8List> ekIndir(String kutuId, String id, int sira, {void Function(int, int)? ilerleme}) =>
      Uyg.api.indir('$_k/messages/$kutuId/$id/attachments/$sira', ilerleme: ilerleme);

  /// action: seen | unseen | flag | unflag | archive | trash | spam
  static Future<int> eylem(List<BirlesikOge> ogeler, String eylem) async {
    final v = await Uyg.api.post('$_k/actions', {
      'items': [
        for (final o in ogeler) {'mailbox_id': o.kutuId, 'message_id': o.ozet.id},
      ],
      'action': eylem,
    });
    return v is Map && v['done'] is num ? (v['done'] as num).toInt() : 0;
  }

  static Future<(int, Map<String, int>)> sayilar() async {
    final v = await Uyg.api.get('$_k/counts');
    final m = v is Map ? v : const {};
    final l = m['accounts'] is List ? m['accounts'] as List : const [];
    return (
      m['total_unread'] is num ? (m['total_unread'] as num).toInt() : 0,
      {
        for (final a in l)
          if (a is Map) '${a['id']}': a['unread'] is num ? (a['unread'] as num).toInt() : 0,
      },
    );
  }
}

/// Birleşik görünümün uygulama geneli durumu: kaç hesap var (giriş noktası yalnız >1 hesapta görünür), toplam
/// okunmamış rozeti, yeni posta olayları. Sayılar canlı "unified_new" olayıyla, yoksa 60 sn'de bir tazelenir.
class BirlesikDurum extends ChangeNotifier {
  BirlesikDurum._();
  static final ben = BirlesikDurum._();

  /// Oturumu açık kayıtlı hesap sayısı (bu cihazda).
  int hesapSayisi = 0;
  int toplamOkunmamis = 0;
  Map<String, int> hesapOkunmamis = const {};

  bool get kullanilabilir => hesapSayisi > 1;

  final _yeni = StreamController<Map<String, dynamic>>.broadcast();

  /// Başka hesaba gelen yeni posta (canlı unified_new).
  Stream<Map<String, dynamic>> get yeniPosta => _yeni.stream;

  final _yerel = StreamController<String>.broadcast();

  /// Okuyucuda yapılan değişiklik (anahtar = kutu/ileti): liste satırı yeniden çizilir.
  Stream<String> get yerelDegisiklikler => _yerel.stream;
  void yerelDegisti(String anahtar) => _yerel.add(anahtar);

  StreamSubscription<CanliOlay>? _abone;
  Timer? _yokla;
  Timer? _gecikme;

  static Duration yoklamaAraligi = const Duration(seconds: 60);

  Future<void> baslat() async {
    _abone ??= Canli.ben.olaylar.listen(_canli);
    await hesaplariYenile();
  }

  Future<void> hesaplariYenile() async {
    try {
      final l = await Uyg.hesaplar();
      hesapSayisi = l.where((h) => !h.cikisYapti).length;
    } catch (_) {}
    _yoklamayiKur();
    notifyListeners();
    if (kullanilabilir) await sayilariYenile();
  }

  void _yoklamayiKur() {
    _yokla?.cancel();
    _yokla = kullanilabilir ? Timer.periodic(yoklamaAraligi, (_) => sayilariYenile()) : null;
  }

  Future<void> sayilariYenile() async {
    if (!kullanilabilir) return;
    try {
      final (t, m) = await Birlesik.sayilar();
      if (t == toplamOkunmamis && mapEquals(m, hesapOkunmamis)) return;
      toplamOkunmamis = t;
      hesapOkunmamis = m;
      notifyListeners();
    } on ApiHata catch (e) {
      // 403/404: sunucu birleşik görünümü desteklemiyor ya da bu oturumda kapalı.
      if (e.durum == 403 || e.durum == 404) {
        hesapSayisi = 0;
        _yoklamayiKur();
        notifyListeners();
      }
    } on DioException catch (_) {
    } catch (_) {}
  }

  void _canli(CanliOlay o) {
    if (o.tur == 'unified_new') {
      _yeni.add(o.veri);
    } else if (o.tur != 'new_mail' && o.tur != 'changed') {
      return;
    }
    if (!kullanilabilir) return;
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 400), sayilariYenile);
  }

  void durdur() {
    _abone?.cancel();
    _abone = null;
    _yokla?.cancel();
    _yokla = null;
    _gecikme?.cancel();
    _gecikme = null;
  }

  void sifirla() {
    durdur();
    hesapSayisi = 0;
    toplamOkunmamis = 0;
    hesapOkunmamis = const {};
  }
}
