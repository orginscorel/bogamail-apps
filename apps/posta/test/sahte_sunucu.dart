// Testler için yol tabanlı sahte API: "GET /yol" → yanıt. Ağ yok; istekler gövdeleriyle kaydedilir.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:posta/oturum.dart';

class Istek {
  Istek(this.yontem, this.yol, this.sorgu, this.govde);
  final String yontem;
  final String yol;
  final Map<String, dynamic> sorgu;
  final Object? govde;
  Map<String, dynamic> get json => govde is Map ? Map<String, dynamic>.from(govde as Map) : <String, dynamic>{};
  @override
  String toString() => '$yontem $yol';
}

typedef Yanit = (int, Object?);

class YolSunucusu implements HttpClientAdapter {
  final istekler = <Istek>[];

  /// "GET /api/v1/mail/chat/rooms" → (durum, gövde) ya da istekten üreten işlev.
  final yollar = <String, Object>{};

  void kur() {
    Uyg.api.dio = Dio(BaseOptions(baseUrl: 'http://sahte.invalid', validateStatus: (_) => true))..httpClientAdapter = this;
  }

  Iterable<Istek> bul(String yontem, String yol) => istekler.where((i) => i.yontem == yontem && i.yol == yol);

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? govde, Future<void>? iptal) async {
    Object? g = o.data;
    if (g is String && g.isNotEmpty) {
      try {
        g = jsonDecode(g);
      } catch (_) {}
    }
    final ist = Istek(o.method, o.uri.path, o.queryParameters, g);
    istekler.add(ist);
    final h = yollar['${o.method} ${o.uri.path}'];
    final Yanit y = switch (h) {
      null => (
        404,
        {
          'error': {'code': 'not_found', 'message': 'Bulunamadı'},
        },
      ),
      final Yanit Function(Istek) f => f(ist),
      final Yanit v => v,
      _ => (500, null),
    };
    if (y.$2 == null) return ResponseBody.fromString('', y.$1);
    return ResponseBody.fromString(
      jsonEncode(y.$2),
      y.$1,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
