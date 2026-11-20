import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/simgeler.dart';
import 'modeller.dart';
import 'onyukleme.dart';
import 'posta_servisi.dart';
import 'yardimci.dart';

enum KonumTur { klasor, gorunum, etiket, birlesik }

/// Listede gösterilen yer: bir klasör, bir görünüm (yıldızlı, önemli, okunmamış) veya bir etiket.
@immutable
class Konum {
  const Konum(this.tur, this.id);
  const Konum.klasor(String id) : this(KonumTur.klasor, id);
  const Konum.gorunum(String gorunum) : this(KonumTur.gorunum, gorunum);
  const Konum.etiket(String id) : this(KonumTur.etiket, id);

  /// "Tüm hesaplar" birleşik gelen kutusu.
  const Konum.birlesik() : this(KonumTur.birlesik, 'tum');

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

  /// Son tazelemeye yol açan değişikliğin ileti kimliği (null: genel / toplu değişiklik). Okuyucu yalnız kendi
  /// iletisi değiştiyse yeniden yükler.
  String? sonDegisen;

  /// Uygulamanın kendi yaptığı (iyimser) değişiklikler: listeler satırı yerinde günceller, ağa gitmez.
  final _yerel = StreamController<(String, Map<String, dynamic>)>.broadcast();
  Stream<(String, Map<String, dynamic>)> get yerelDegisiklikler => _yerel.stream;

  /// Kendi değişikliğimizin sunucudan geri gelen "changed" yankısını tanımak için (kimlik → zaman).
  final _yankilar = <String, DateTime>{};

  /// İletiyi okundu olarak işaretler: önbellek ve listeler hemen, sunucu arkada. Okuyucuyu bekletmez, ileti
  /// yeniden indirilmez.
  void okunduIsaretle(String id, {bool okundu = true}) {
    _yankilar[id] = DateTime.now();
    _yerel.add((id, {'seen': okundu}));
    unawaited(Posta.iletiYerelGuncelle(id, {'seen': okundu}));
    unawaited(() async {
      try {
        await Posta.guncelle(id, {'seen': okundu});
      } catch (_) {}
      sayilariYenile(listeler: false);
    }());
  }

  /// Yerel bayrak değişikliği (yıldız, önemli...): önbellek + listeler.
  void yerelGuncelle(String id, Map<String, dynamic> alanlar) {
    _yankilar[id] = DateTime.now();
    _yerel.add((id, alanlar));
    unawaited(Posta.iletiYerelGuncelle(id, alanlar));
  }

  /// SSE olayı: sayıları tazeler; kendi değişikliğimizin yankısıysa listeleri/okuyucuyu yeniden yüklemez; yeni
  /// postanın gövdesini hemen önbelleğe alır.
  void canliOlay(CanliOlay o) {
    if (o.tur != 'new_mail' && o.tur != 'changed' && o.tur != 'scheduled') return;
    final id = '${o.veri['message_id'] ?? ''}';
    if (o.tur == 'new_mail' && id.isNotEmpty) Onyukleme.ben.hemen(id);
    if (o.tur == 'changed' && id.isNotEmpty) {
      final y = _yankilar[id];
      _yankilar.removeWhere((_, t) => DateTime.now().difference(t) > const Duration(seconds: 10));
      if (y != null && DateTime.now().difference(y) < const Duration(seconds: 10)) {
        sayilariYenile(listeler: false);
        return;
      }
      // Başka oturumda değişti: önbellekteki ayrıntı eskidi.
      Onyukleme.ben.eskit(id);
    }
    // degisen: '' = açık okuyucuyu ilgilendirmez (yeni posta), kimlik = o ileti, null = genel/toplu.
    sayilariYenile(degisen: o.tur == 'new_mail' ? '' : (o.tur == 'changed' && id.isNotEmpty ? id : null));
  }

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

  /// Konumun simgesi ve rengi (kenar menüsü, liste başlığı; web ile aynı eşleme).
  (IconData, Color?) gorsel(Konum k) => switch (k.tur) {
    KonumTur.klasor => (klasorSimgesi(klasor(k.id)?.rol), klasorRengi(klasor(k.id)?.rol)),
    KonumTur.gorunum => (gorunumSimgesi(k.id), gorunumRengi(k.id)),
    KonumTur.etiket => (Simge.etiket, etiketRengi(etiket(k.id)?.renk ?? 'gray')),
    KonumTur.birlesik => (gorunumSimgesi('unified'), null),
  };

  Klasor? get seciliKlasor => konum?.tur == KonumTur.klasor ? klasor(konum!.id) : null;

  String baslik(Konum? k) {
    if (k == null) return 'BogaMail';
    return switch (k.tur) {
      KonumTur.klasor => klasor(k.id)?.gorunenAd ?? 'Klasör',
      KonumTur.gorunum => gorunumAdlari[k.id] ?? 'İletiler',
      KonumTur.etiket => etiket(k.id)?.ad ?? 'Etiket',
      KonumTur.birlesik => 'Tüm hesaplar',
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
    if (!yuklendi) {
      // Önce önbellek: kenar menüsü ve gelen kutusu ağ beklenmeden çizilir.
      final o = await Posta.klasorlerOnbellek().catchError((_) => null);
      if (o != null && !yuklendi && o.$1.isNotEmpty) {
        klasorler = o.$1;
        etiketler = o.$2;
        yuklendi = true;
        konum ??= _baslangicKonumu();
        notifyListeners();
      }
    }
    try {
      final r = await Future.wait([Posta.klasorler(), Posta.etiketler().catchError((_) => <Etiket>[])]);
      klasorler = r[0] as List<Klasor>;
      etiketler = r[1] as List<Etiket>;
      yuklendi = true;
      konum ??= _baslangicKonumu();
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
  bool _bekleyenListeler = false;

  /// Sayıları tazeler (canlı olaylar art arda gelirse birleştirilir).
  void sayilariYenile({bool listeler = true, String? degisen}) {
    if (_gecikme?.isActive ?? false) {
      // Birleştirilen olaylardan biri genel ise genel kalır.
      if (_bekleyenListeler && sonDegisen != degisen) degisen = null;
      listeler = listeler || _bekleyenListeler;
    }
    _bekleyenListeler = listeler;
    sonDegisen = degisen;
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
      _bekleyenListeler = false;
      if (listeler) surum.value++;
      unawaited(Posta.kutuYenile());
    });
  }

  void _rozet() => Push.rozet(rolu('inbox')?.okunmamis ?? 0);

  /// Hesap geçişinde korunacak yer: klasör rolü (inbox→inbox) ya da görünüm/birleşik. İlk konum seçilirken tüketilir.
  String? gecisRolu;
  Konum? gecisKonumu;

  Konum? _baslangicKonumu() {
    final g = gecisKonumu;
    final rl = gecisRolu;
    gecisKonumu = null;
    gecisRolu = null;
    if (g != null) return g;
    final k = (rl != null ? rolu(rl) : null) ?? rolu('inbox');
    return k != null ? Konum.klasor(k.id) : null;
  }

  void git(Konum k) {
    if (konum == k) return;
    konum = k;
    notifyListeners();
  }

  void sifirla() {
    _gecikme?.cancel();
    _yankilar.clear();
    sonDegisen = null;
    Onyukleme.ben.iptal();
    klasorler = [];
    etiketler = [];
    ayarlar = null;
    konum = null;
    yuklendi = false;
  }
}
