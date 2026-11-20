import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';

import 'modeller.dart';
import 'posta_servisi.dart';
import 'yardimci.dart';

enum KonumTur { klasor, gorunum, etiket }

/// Listede gösterilen yer: bir klasör, bir görünüm (yıldızlı, önemli, okunmamış) veya bir etiket.
@immutable
class Konum {
  const Konum(this.tur, this.id);
  const Konum.klasor(String id) : this(KonumTur.klasor, id);
  const Konum.gorunum(String gorunum) : this(KonumTur.gorunum, gorunum);
  const Konum.etiket(String id) : this(KonumTur.etiket, id);

  final KonumTur tur;
  final String id;

  @override
  bool operator ==(Object other) => other is Konum && other.tur == tur && other.id == id;
  @override
  int get hashCode => Object.hash(tur, id);
}

const gorunumAdlari = {
  'all': 'Tüm postalar',
  'starred': 'Yıldızlı',
  'important': 'Önemli',
  'unread': 'Okunmamışlar',
  'attachments': 'Ekli iletiler',
  'followup': 'Takip edilenler',
};

/// Uygulama genelindeki posta durumu: klasörler, etiketler, ayarlar, seçili konum.
class PostaDurum extends ChangeNotifier {
  PostaDurum._();
  static final ben = PostaDurum._();

  List<Klasor> klasorler = [];
  List<Etiket> etiketler = [];
  PostaAyarlari? ayarlar;
  Konum? konum;
  String? hata;
  bool yuklendi = false;

  /// Canlı değişikliklerde artar: açık listeler ve okuyucu sessizce tazelenir.
  final surum = ValueNotifier<int>(0);

  Klasor? rolu(String rol) {
    for (final k in klasorler) {
      if (k.rol == rol) return k;
    }
    return null;
  }

  Klasor? klasor(String? id) {
    for (final k in klasorler) {
      if (k.id == id) return k;
    }
    return null;
  }

  Etiket? etiket(String? id) {
    for (final e in etiketler) {
      if (e.id == id) return e;
    }
    return null;
  }

  Klasor? get seciliKlasor => konum?.tur == KonumTur.klasor ? klasor(konum!.id) : null;

  String baslik(Konum? k) {
    if (k == null) return 'BogaMail';
    return switch (k.tur) {
      KonumTur.klasor => klasor(k.id)?.gorunenAd ?? 'Klasör',
      KonumTur.gorunum => gorunumAdlari[k.id] ?? 'İletiler',
      KonumTur.etiket => etiket(k.id)?.ad ?? 'Etiket',
    };
  }

  /// Sistem klasörleri sabit sırada, ardından kullanıcı klasörleri (ada göre).
  List<Klasor> get sistemKlasorleri {
    final l = klasorler.where((k) => k.sistem).toList();
    l.sort((a, b) {
      final x = sistemSirasi.indexOf(a.rol!), y = sistemSirasi.indexOf(b.rol!);
      return (x < 0 ? 99 : x).compareTo(y < 0 ? 99 : y);
    });
    return l;
  }

  List<Klasor> get kullaniciKlasorleri {
    final l = klasorler.where((k) => !k.sistem).toList();
    l.sort((a, b) => a.ad.toLowerCase().compareTo(b.ad.toLowerCase()));
    return l;
  }

  /// Taşıma hedefleri (web ile aynı: kullanıcı klasörleri + Gelen + Arşiv).
  List<Klasor> tasimaHedefleri(String? haricId) => klasorler.where((k) => k.id != haricId && (!k.sistem || k.rol == 'inbox' || k.rol == 'archive')).toList();

  Future<void> yukle() async {
    hata = null;
    try {
      final r = await Future.wait([Posta.klasorler(), Posta.etiketler().catchError((_) => <Etiket>[])]);
      klasorler = r[0] as List<Klasor>;
      etiketler = r[1] as List<Etiket>;
      yuklendi = true;
      konum ??= rolu('inbox') != null ? Konum.klasor(rolu('inbox')!.id) : null;
      _rozet();
      notifyListeners();
    } catch (e) {
      hata = hataMetni(e);
      notifyListeners();
    }
    unawaited(ayarlariYukle());
  }

  Future<void> ayarlariYukle() async {
    try {
      ayarlar = await Posta.ayarlar();
      notifyListeners();
    } catch (_) {}
  }

  Timer? _gecikme;

  /// Sayıları tazeler (canlı olaylar art arda gelirse birleştirilir).
  void sayilariYenile({bool listeler = true}) {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Future.wait([Posta.klasorler(), Posta.etiketler().catchError((_) => etiketler)]);
        klasorler = r[0] as List<Klasor>;
        etiketler = r[1] as List<Etiket>;
        if (konum != null && konum!.tur == KonumTur.klasor && klasor(konum!.id) == null) {
          konum = rolu('inbox') != null ? Konum.klasor(rolu('inbox')!.id) : null;
        }
        _rozet();
        notifyListeners();
      } catch (_) {}
      if (listeler) surum.value++;
      unawaited(Posta.kutuYenile());
    });
  }

  void _rozet() => Push.rozet(rolu('inbox')?.okunmamis ?? 0);

  void git(Konum k) {
    if (konum == k) return;
    konum = k;
    notifyListeners();
  }

  void sifirla() {
    klasorler = [];
    etiketler = [];
    ayarlar = null;
    konum = null;
    yuklendi = false;
  }
}
