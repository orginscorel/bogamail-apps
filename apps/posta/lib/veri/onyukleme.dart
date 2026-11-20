// Arka planda ileti gövdesi önyükleme: liste yüklenince görünen ilk iletiler (önce okunmamışlar), canlı akıştan
// gelen yeni posta hemen. Eşzamanlı en çok [esZamanli] istek; klasör/konum değişince ya da kaydırınca kuyruk
// yenilenir (eski istekler sürerken yenileri bekletilmez, kuyruktan düşer). GET ileti sunucuda yan etkisizdir
// (okundu işareti ayrıca PATCH ile yapılır).

import 'dart:async';

import 'modeller.dart';
import 'onbellek.dart';
import 'posta_servisi.dart';

class Onyukleme {
  Onyukleme._();
  static final ben = Onyukleme._();

  static int esZamanli = 3;
  static int azami = 20;

  /// Testlerde kapatılabilir.
  static bool etkin = true;

  final _kuyruk = <String>[];
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

  /// Başka oturumda değişti: önbellekteki kopya bir sonraki önyüklemede yenilenir (açılınca zaten tazelenir).
  void eskit(String id) => _eski.add(id);

  void iptal() {
    _kuyruk.clear();
    _eski.clear();
  }

  bool _gerekli(String id) => id.isNotEmpty && !_suruyor.contains(id) && (_eski.contains(id) || !Onbellek.ben.var_('ileti:$id'));

  void _calis() {
    while (_calisan < esZamanli && _kuyruk.isNotEmpty) {
      final id = _kuyruk.removeAt(0);
      if (!_gerekli(id)) continue;
      _calisan++;
      _suruyor.add(id);
      _eski.remove(id);
      final s = Stopwatch()..start();
      unawaited(
        Posta.iletiHam(id).then((_) => zamanLogu('önyükleme', s), onError: (_) {}).whenComplete(() {
          _calisan--;
          _suruyor.remove(id);
          _calis();
        }),
      );
    }
  }
}
