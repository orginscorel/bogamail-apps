// Canlı güncellemeler: GET /api/v1/mail/stream (Server-Sent Events). Uygulama öndeyken bağlı kalır, arka plana
// geçince kapanır; kopmalarda artan beklemeyle yeniden bağlanır. Olay içerikleri hiçbir yere yazılmaz.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../oturum.dart';
import 'modeller.dart';

enum CanliTur { bagli, baglaniyor, yok, kapali }

/// Eşitleme göstergesi için bağlantı durumu. [sonrakiDeneme]: bağlantı yokken bir sonraki deneme zamanı.
@immutable
class CanliDurumu {
  const CanliDurumu(this.tur, {this.sonrakiDeneme});
  final CanliTur tur;
  final DateTime? sonrakiDeneme;
}

class Canli {
  Canli._();
  static final ben = Canli._();

  final _olaylar = StreamController<CanliOlay>.broadcast();
  Stream<CanliOlay> get olaylar => _olaylar.stream;

  /// Bağlantı durumu (arayüzde küçük gösterge için).
  final bagli = ValueNotifier<bool>(false);

  /// Ayrıntılı durum (Canlı / Bağlanıyor… / Bağlantı yok — N sn sonra).
  final durum = ValueNotifier<CanliDurumu>(const CanliDurumu(CanliTur.kapali));

  /// Sunucudan son olay ya da başarılı bağlantı zamanı.
  final sonOlay = ValueNotifier<DateTime?>(null);

  CancelToken? _iptal;
  Timer? _tekrar;
  int _deneme = 0;
  bool _istenen = false;

  void baslat() {
    if (_istenen) return;
    _istenen = true;
    _deneme = 0;
    _baglan();
  }

  /// "Şimdi eşitle": bekleyen yeniden denemeyi beklemeden hemen bağlanır (bağlıysa dokunmaz).
  void simdiBaglan() {
    if (!_istenen) return baslat();
    if (_iptal != null) return;
    _tekrar?.cancel();
    _tekrar = null;
    _deneme = 0;
    _baglan();
  }

  void durdur() {
    _istenen = false;
    _tekrar?.cancel();
    _tekrar = null;
    _iptal?.cancel();
    _iptal = null;
    bagli.value = false;
    durum.value = const CanliDurumu(CanliTur.kapali);
  }

  Future<void> _baglan() async {
    if (!_istenen || _iptal != null) return;
    final iptal = CancelToken();
    _iptal = iptal;
    durum.value = const CanliDurumu(CanliTur.baglaniyor);
    try {
      final c = await Uyg.api.dio.get<ResponseBody>(
        '/api/v1/mail/stream',
        cancelToken: iptal,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
          // Sunucu 25 sn'de bir "ping" gönderir; bu süre içinde hiç veri gelmezse bağlantı ölü sayılır.
          receiveTimeout: const Duration(seconds: 75),
        ),
      );
      final d = c.statusCode ?? 0;
      if (d == 401) {
        _istenen = false;
        Uyg.oturumDustu();
        return;
      }
      if (d != 200 || c.data == null) throw StateError('akış açılamadı');
      bagli.value = true;
      durum.value = const CanliDurumu(CanliTur.bagli);
      sonOlay.value = DateTime.now();
      _deneme = 0;
      String olay = 'message';
      final veri = StringBuffer();
      await for (final satir in c.data!.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter())) {
        if (satir.isEmpty) {
          _isle(olay, veri.toString());
          olay = 'message';
          veri.clear();
        } else if (satir.startsWith(':')) {
          // yorum / ping: bağlantı canlı
          sonOlay.value = DateTime.now();
        } else if (satir.startsWith('event:')) {
          olay = satir.substring(6).trim();
        } else if (satir.startsWith('data:')) {
          if (veri.isNotEmpty) veri.write('\n');
          veri.write(satir.substring(5).trimLeft());
        }
      }
    } catch (_) {
      // ağ hatası / iptal: aşağıda yeniden denenir
    }
    bagli.value = false;
    if (identical(_iptal, iptal)) _iptal = null;
    if (!_istenen || iptal.isCancelled) return;
    _deneme++;
    final bekle = Duration(milliseconds: min(60000, 1000 * pow(2, min(_deneme, 6)).toInt()) + Random().nextInt(1000));
    _tekrar?.cancel();
    durum.value = CanliDurumu(CanliTur.yok, sonrakiDeneme: DateTime.now().add(bekle));
    _tekrar = Timer(bekle, _baglan);
  }

  void _isle(String olay, String veri) {
    sonOlay.value = DateTime.now();
    if (olay == 'logout') {
      durdur();
      Uyg.oturumDustu();
      return;
    }
    if (olay == 'hello') {
      // Yeniden bağlanınca kaçırılmış olabilecek değişiklikleri almak için tazele.
      _olaylar.add(CanliOlay('changed', const {}));
      return;
    }
    if (olay != 'mail' || veri.isEmpty) return;
    try {
      _olaylar.add(CanliOlay.json(jsonDecode(veri)));
    } catch (_) {}
  }
}
