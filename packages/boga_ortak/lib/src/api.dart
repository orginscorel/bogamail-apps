import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// API hatası. [durum] null ise sunucuya hiç ulaşılamadı.
class ApiHata implements Exception {
  ApiHata(this.durum, this.mesaj, {this.kod = '', this.alan});
  final int? durum;
  final String mesaj;
  final String kod;
  final String? alan;
  bool get baglantiYok => durum == null;
  @override
  String toString() => mesaj;
}

/// Sunucunun İngilizce döndürdüğü yaygın hataların Türkçesi (kod → mesaj).
const _hataMetni = {
  'invalid_credentials': 'E-posta adresi veya şifre hatalı.',
  'rate_limited': 'Çok fazla deneme yapıldı. Biraz bekleyip tekrar deneyin.',
  'unauthorized': 'Oturumunuz sona erdi. Yeniden giriş yapın.',
  'forbidden': 'Bu işlem için yetkiniz yok.',
  'not_found': 'Kayıt bulunamadı.',
  'csrf_failed': 'Oturum doğrulanamadı. Yeniden giriş yapın.',
  'bad_origin': 'İstek reddedildi.',
  'unavailable': 'Sunucu şu an yanıt veremiyor. Biraz sonra tekrar deneyin.',
  'invalid_code': 'Doğrulama kodu hatalı.',
  'mfa_invalid': 'Doğrulama kodu hatalı.',
  'mfa_expired': 'Doğrulama süresi doldu. Yeniden giriş yapın.',
  'internal': 'Sunucuda bir hata oluştu. Tekrar deneyin.',
};

/// BogaMail API istemcisi. Web paneliyle aynı oturum modelini kullanır: oturum çerezi (cihazda kalıcı, şifreli
/// depolanmaz ama uygulama alanındadır) + değişiklik isteklerinde X-CSRF-Token. Oturum sunucuda 30 gün kayar,
/// yani uygulama kullanıldıkça kullanıcı oturumdan atılmaz.
class BogaApi {
  BogaApi({required this.uygulama, required this.csrfCerezi});

  /// 'posta' | 'yonetim' — çerez deposu ve ayarlar uygulamaya göre ayrılır.
  final String uygulama;

  /// CSRF çerezinin adı: posta → bm_mail_csrf, yönetim → bm_csrf.
  final String csrfCerezi;

  static const varsayilanSunucu = 'https://posta.bogahost.com';

  String sunucu = varsayilanSunucu;
  late final Dio dio;
  late final PersistCookieJar _jar;
  String surum = '';

  /// 401 geldiğinde (giriş istekleri hariç) çağrılır: uygulama giriş ekranına döner.
  VoidCallback? oturumDustu;

  /// Her istekten sonra sunucuya ulaşılıp ulaşılamadığını bildirir (çevrimdışı göstergesi, kuyruk yeniden oynatma).
  /// Yalnız posta uygulaması kullanır; null ise hiçbir şey yapılmaz.
  void Function(bool ulasildi)? ulasilabilirlik;

  Future<void> baslat() async {
    final prefs = await SharedPreferences.getInstance();
    sunucu = prefs.getString('$uygulama.sunucu') ?? varsayilanSunucu;
    final dizin = await getApplicationSupportDirectory();
    _jar = PersistCookieJar(storage: FileStorage('${dizin.path}/cerezler_$uygulama/'), ignoreExpires: false);
    try {
      final p = await PackageInfo.fromPlatform();
      surum = '${p.version} (${p.buildNumber})';
    } catch (_) {}
    final platform = kIsWeb
        ? 'Web'
        : Platform.isIOS
        ? 'iOS'
        : Platform.isMacOS
        ? 'macOS'
        : Platform.isAndroid
        ? 'Android'
        : Platform.isWindows
        ? 'Windows'
        : Platform.operatingSystem;
    dio = Dio(
      BaseOptions(
        baseUrl: sunucu,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 120),
        headers: {'User-Agent': 'BogaMail-${uygulama == 'posta' ? 'Posta' : 'Yonetim'}/$surum ($platform)', 'Accept': 'application/json'},
        validateStatus: (_) => true,
      ),
    );
    // HTTP/2 (sunucu h2 sunar): paralel istekler (liste, ileti, önyükleme, görseller) tek bağlantıda çoğullanır,
    // her istek için yeni TLS el sıkışması yapılmaz. ALPN ile h2 yoksa HTTP/1.1 bağdaştırıcısına düşülür.
    if (!kIsWeb) {
      dio.httpClientAdapter = Http2Adapter(ConnectionManager(idleTimeout: const Duration(seconds: 45)), fallbackAdapter: IOHttpClientAdapter());
    }
    dio.interceptors.add(CookieManager(_jar));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          if (o.method != 'GET' && o.method != 'HEAD') {
            final csrf = await _csrf();
            if (csrf != null) o.headers['X-CSRF-Token'] = csrf;
          }
          h.next(o);
        },
      ),
    );
  }

  Future<String?> _csrf() async {
    final c = await _jar.loadForRequest(Uri.parse('$sunucu/api/v1/mail/x'));
    for (final k in c) {
      if (k.name == csrfCerezi) return k.value;
    }
    return null;
  }

  /// Oturum çerezi var mı (ağa çıkmadan; geçerliliği sunucu söyler).
  Future<bool> oturumVar() async {
    final c = await _jar.loadForRequest(Uri.parse('$sunucu/api/v1/mail/x'));
    return c.any((k) => k.name == (uygulama == 'posta' ? 'bm_mail_session' : 'bm_session') || k.name == csrfCerezi);
  }

  Future<void> sunucuAyarla(String url) async {
    var u = url.trim();
    if (u.isEmpty) u = varsayilanSunucu;
    if (!u.startsWith('http')) u = 'https://$u';
    u = u.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$uygulama.sunucu', u);
    sunucu = u;
    dio.options.baseUrl = u;
  }

  Future<void> cerezleriTemizle() => _jar.deleteAll();

  Future<dynamic> get(String yol, {Map<String, dynamic>? q}) => _istek('GET', yol, q: q);
  Future<dynamic> post(String yol, [Object? govde]) => _istek('POST', yol, govde: govde ?? const <String, dynamic>{});
  Future<dynamic> put(String yol, [Object? govde]) => _istek('PUT', yol, govde: govde ?? const <String, dynamic>{});
  Future<dynamic> patch(String yol, [Object? govde]) => _istek('PATCH', yol, govde: govde ?? const <String, dynamic>{});
  Future<dynamic> delete(String yol, {Object? govde, Map<String, dynamic>? q}) => _istek('DELETE', yol, govde: govde, q: q);

  /// Ham bayt indirir (ek dosyaları, logolar).
  Future<Uint8List> indir(String yol, {Map<String, dynamic>? q, void Function(int, int)? ilerleme}) async {
    final Response<List<int>> c;
    try {
      c = await dio.get<List<int>>(
        yol,
        queryParameters: q,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: ilerleme,
      );
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) ulasilabilirlik?.call(false);
      throw _agHatasi(e);
    }
    ulasilabilirlik?.call(true);
    final d = c.statusCode ?? 0;
    if (d >= 400) {
      if (d == 401) oturumDustu?.call();
      throw ApiHata(d, d == 404 ? 'Dosya bulunamadı.' : 'Dosya indirilemedi (HTTP $d).');
    }
    return Uint8List.fromList(c.data ?? const []);
  }

  ApiHata _agHatasi(DioException e) {
    final zaman = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout;
    return ApiHata(null, zaman ? 'Sunucu zamanında yanıt vermedi. Bağlantınızı kontrol edin.' : 'Sunucuya ulaşılamıyor. İnternet bağlantınızı kontrol edin.');
  }

  Future<dynamic> _istek(String yontem, String yol, {Object? govde, Map<String, dynamic>? q}) async {
    final Response<dynamic> c;
    try {
      c = await dio.request<dynamic>(
        yol,
        data: govde,
        queryParameters: q,
        options: Options(method: yontem),
      );
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) ulasilabilirlik?.call(false);
      throw _agHatasi(e);
    }
    ulasilabilirlik?.call(true);
    final d = c.statusCode ?? 0;
    if (d >= 200 && d < 300) return c.data;
    var mesaj = 'İstek başarısız (HTTP $d).';
    var kod = '';
    String? alan;
    final v = c.data;
    if (v is Map && v['error'] is Map) {
      final e = v['error'] as Map;
      kod = '${e['code'] ?? ''}';
      alan = e['field'] as String?;
      final m = '${e['message'] ?? ''}'.trim();
      mesaj = _hataMetni[kod] ?? (m.isNotEmpty ? m : mesaj);
    } else if (d == 413) {
      mesaj = 'Gönderilen veri çok büyük.';
    } else if (d >= 500) {
      mesaj = _hataMetni['internal']!;
    }
    final girisIstegi = yol.contains('/auth/login');
    if (d == 401 && !girisIstegi) oturumDustu?.call();
    throw ApiHata(d, mesaj, kod: kod, alan: alan);
  }
}
