// Arka planda ileti gövdesi önyükleme: liste yüklenince görünen ilk iletiler (önce okunmamışlar), canlı akıştan
// gelen yeni posta hemen. Eşzamanlı en çok [esZamanli] istek; klasör/konum değişince ya da kaydırınca kuyruk
// yenilenir (eski istekler sürerken yenileri bekletilmez, kuyruktan düşer). GET ileti sunucuda yan etkisizdir
// (okundu işareti ayrıca PATCH ile yapılır).

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';

import 'html_temizle.dart';
import 'modeller.dart';
import 'onbellek.dart';
import 'posta_servisi.dart';
import 'tercihler.dart';

class Onyukleme {
  Onyukleme._();
  static final ben = Onyukleme._();

  static int esZamanli = 3;
  static int azami = 20;

  /// Testlerde kapatılabilir.
  static bool etkin = true;

  final _kuyruk = <String>[];

  /// Arka plan eşitlemesinin düşük öncelikli kuyruğu (görünen liste boşaldıktan sonra işlenir).
  final _arka = <String>[];

  /// Arka plan önyüklemesi önbellek diskinin en çok bu oranını doldurur (kullanıcının gördüğü kayıtlar silinmesin).
  static double arkaDolulukSiniri = .6;
  final _suruyor = <String>{};
  final _eski = <String>{};
  int _calisan = 0;

  /// Kuyruğu bu listeye göre yeniler: okunmamışlar önce, en çok [azami] ileti.
  void iste(List<IletiOzet> ogeler, {int bas = 0}) {
    if (!etkin) return;
    final parca = ogeler.skip(bas).take(azami).toList();
    final sirali = [...parca.where((m) => !m.okundu), ...parca.where((m) => m.okundu)];
    _kuyruk
      ..clear()
      ..addAll(sirali.map((m) => m.id).where(_gerekli));
    _calis();
  }

  /// Yeni posta: kuyruğun başına.
  void hemen(String id) {
    if (!etkin || !_gerekli(id)) return;
    _kuyruk
      ..remove(id)
      ..insert(0, id);
    _calis();
  }

  /// Arka plan eşitlemesi: verilen iletilerin gövdelerini (sırayla, düşük öncelikle) önbelleğe alır.
  void arkaPlan(Iterable<String> idler) {
    if (!etkin) return;
    for (final id in idler) {
      if (!_arka.contains(id) && _gerekli(id)) _arka.add(id);
    }
    _calis();
  }

  int get arkaBekleyen => _arka.length;

  /// Başka oturumda değişti: önbellekteki kopya bir sonraki önyüklemede yenilenir (açılınca zaten tazelenir).
  void eskit(String id) => _eski.add(id);

  /// Uzak görseller de önyüklenir mi: kullanıcı "uzak görselleri otomatik göster"i açtıysa (okuyucuyla aynı kural).
  static bool Function() gorselIzni = () => Tercihler.uzakGorseller.value;

  /// İleti başına en çok bu kadar görsel önyüklenir.
  static int azamiGorsel = 12;

  /// Okuyucunun otomatik göstereceği görselleri yerel önbelleğe alır (gereksiz/tehditli iletilerde yapılmaz).
  void _gorselleriOnyukle(Object? ham) {
    if (!gorselIzni()) return;
    try {
      final d = IletiDetay.json(ham);
      if (d.ozet.klasorRolu == 'junk' || d.tehditler.isNotEmpty) return;
      final l = uzakGorseller(d.gorunum.html).take(azamiGorsel).toList();
      if (l.isEmpty) return;
      // İki işçi: görseller de HTTP/2 bağlantısında çoğullanır, okuyucunun isteklerini boğmaz.
      Future<void> isci() async {
        while (l.isNotEmpty) {
          await Posta.uzakGorselVeri(l.removeAt(0));
        }
      }

      unawaited(Future.wait([isci(), isci()]));
    } catch (_) {}
  }

  void iptal() {
    _kuyruk.clear();
    _arka.clear();
    _eski.clear();
  }

  bool _gerekli(String id) => id.isNotEmpty && !_suruyor.contains(id) && (_eski.contains(id) || !Onbellek.ben.var_('ileti:$id'));

  void _calis() {
    while (_calisan < esZamanli && (_kuyruk.isNotEmpty || _arka.isNotEmpty)) {
      if (_kuyruk.isEmpty && Onbellek.ben.doluluk > arkaDolulukSiniri) {
        _arka.clear();
        return;
      }
      final id = _kuyruk.isNotEmpty ? _kuyruk.removeAt(0) : _arka.removeAt(0);
      if (!_gerekli(id)) continue;
      _calisan++;
      _suruyor.add(id);
      _eski.remove(id);
      final s = Stopwatch()..start();
      unawaited(
        Posta.iletiHam(id)
            .then(
              (ham) {
                zamanLogu('önyükleme', s);
                _gorselleriOnyukle(ham);
              },
              onError: (Object e) {
                // Bağlantı yok: arka plan kuyruğu boşuna denenmez (sonraki eşitlemede yeniden kurulur).
                if (e is ApiHata && e.baglantiYok) _arka.clear();
              },
            )
            .whenComplete(() {
              _calisan--;
              _suruyor.remove(id);
              _calis();
            }),
      );
    }
  }
}
