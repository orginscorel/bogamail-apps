import 'simge.dart';

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'ortak.dart';
import 'tema.dart';

/// Sunucudaki en yeni derleme (GET /api/v1/app/release).
class SurumBilgisi {
  SurumBilgisi({required this.derleme, required this.surum, required this.notlar, this.boyut, this.sha256, this.indir, this.dosya});
  final int derleme;
  final String surum;
  final String notlar;
  final int? boyut;
  final String? sha256;
  final String? indir;
  final String? dosya;
  String get etiket => '$surum ($derleme)';
}

/// Uzaktan güncelleme. Android ve Windows kurulum dosyasını BogaMail sunucusundan indirir (SHA-256 doğrulanır) ve
/// kurulumu başlatır; iPhone/Mac'te yeni derleme TestFlight'tan alınır. Sunucu "en düşük derleme" bildirirse eski
/// sürümler zorunlu güncelleme ekranı görür.
class Guncelleme {
  Guncelleme._();

  /// App Store Connect uygulama kimlikleri (TestFlight bağlantısı).
  static const _appleKimlik = {'posta': '6837349277', 'yonetim': '6837349292'};

  /// Yüklü sürüm: "1.1.0", derleme numarası.
  static String surum = '';
  static int derleme = 0;

  /// Daha yeni derleme varsa dolu; arayüzler bunu dinler.
  static final yeni = ValueNotifier<SurumBilgisi?>(null);

  /// Yüklü derleme sunucunun desteklediği en düşük derlemenin altında.
  static final zorunlu = ValueNotifier<bool>(false);

  /// İndirme ilerlemesi (0..1); null = indirme yok.
  static final ilerleme = ValueNotifier<double?>(null);

  static DateTime? _son;

  static String get platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem;
  }

  static bool get magazadan => platform == 'ios' || platform == 'macos';

  static String get platformAdi => switch (platform) {
    'ios' => 'iPhone / iPad',
    'macos' => 'Mac',
    'android' => 'Android',
    'windows' => 'Windows',
    _ => platform,
  };

  /// Kullanıcıya gösterilecek sürüm metni: "Sürüm 1.1.0 (12)".
  static String get surumMetni => surum.isEmpty ? '' : 'Sürüm $surum ($derleme)';

  static Future<void> _surumuOku() async {
    if (surum.isNotEmpty) return;
    try {
      final p = await PackageInfo.fromPlatform();
      surum = p.version;
      derleme = int.tryParse(p.buildNumber) ?? 0;
    } catch (_) {}
  }

  /// Sunucuya sorar. [sessiz]: hata bildirmez (açılışta, arka planda). En sık 10 dakikada bir ağa çıkar.
  static Future<SurumBilgisi?> denetle(BogaApi api, {bool sessiz = true, bool zorla = false}) async {
    await _surumuOku();
    if (!zorla && _son != null && DateTime.now().difference(_son!) < const Duration(minutes: 10)) return yeni.value;
    if (!const {'ios', 'macos', 'android', 'windows'}.contains(platform)) return null;
    try {
      final v = await api.get('/api/v1/app/release', q: {'app': api.uygulama, 'platform': platform});
      _son = DateTime.now();
      if (v is! Map) return null;
      final enDusuk = (v['min_build'] as num?)?.toInt() ?? 0;
      zorunlu.value = derleme > 0 && enDusuk > derleme;
      if (v['available'] != true) {
        yeni.value = null;
        return null;
      }
      final b = SurumBilgisi(
        derleme: (v['build'] as num).toInt(),
        surum: '${v['version'] ?? ''}',
        notlar: '${v['notes'] ?? ''}',
        boyut: (v['size'] as num?)?.toInt(),
        sha256: (v['sha256'] as String?)?.toLowerCase(),
        indir: v['download'] as String?,
        dosya: v['file_name'] as String?,
      );
      yeni.value = b.derleme > derleme ? b : null;
      return yeni.value;
    } catch (e) {
      if (!sessiz) bildir('Güncelleme denetlenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      return null;
    }
  }

  /// Güncellemeyi uygular: Android/Windows indirip kurar, iPhone/Mac TestFlight'ı açar.
  static Future<void> kur(BogaApi api, SurumBilgisi b) async {
    if (magazadan) {
      final id = _appleKimlik[api.uygulama];
      final uyg = Uri.parse('itms-beta://beta.itunes.apple.com/v1/app/$id');
      if (!await launchUrl(uyg, mode: LaunchMode.externalApplication)) {
        await launchUrl(Uri.parse('https://beta.itunes.apple.com/v1/app/$id'), mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (b.indir == null || ilerleme.value != null) return;
    ilerleme.value = 0;
    try {
      final dizin = await getTemporaryDirectory();
      final dosya = File('${dizin.path}/${b.dosya ?? 'BogaMail-guncelleme${platform == 'windows' ? '.exe' : '.apk'}'}');
      if (await dosya.exists()) await dosya.delete();
      final c = await api.dio.download(
        b.indir!,
        dosya.path,
        onReceiveProgress: (al, top) {
          final t = top > 0 ? top : (b.boyut ?? 0);
          if (t > 0) ilerleme.value = (al / t).clamp(0, 1).toDouble();
        },
      );
      if ((c.statusCode ?? 0) >= 400) throw ApiHata(c.statusCode, 'Güncelleme indirilemedi (HTTP ${c.statusCode}).');
      if (b.sha256 != null && b.sha256!.isNotEmpty) {
        final ozet = await sha256.bind(dosya.openRead()).first;
        if (ozet.toString() != b.sha256) {
          await dosya.delete();
          throw ApiHata(0, 'İndirilen dosya doğrulanamadı. Tekrar deneyin.');
        }
      }
      if (platform == 'android') {
        final s = await OpenFilex.open(dosya.path, type: 'application/vnd.android.package-archive');
        if (s.type != ResultType.done) {
          throw ApiHata(
            0,
            s.type == ResultType.permissionDenied
                ? 'Kurulum izni verilmedi. Ayarlar → Bilinmeyen uygulamaları yükle bölümünden izin verin.'
                : 'Kurulum başlatılamadı: ${s.message}',
          );
        }
      } else if (platform == 'windows') {
        await Process.start(dosya.path, ['/SILENT', '/SP-', '/NOCANCEL', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'], mode: ProcessStartMode.detached);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        exit(0);
      }
    } catch (e) {
      bildir('Güncelleme yapılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      ilerleme.value = null;
    }
  }
}

/// Küçük sürüm yazısı: "Sürüm 1.1.0 (12)". Ayarlar altı, yan menü altı, giriş ekranı.
class SurumEtiketi extends StatelessWidget {
  const SurumEtiketi({super.key, this.renk, this.ortala = false});
  final Color? renk;
  final bool ortala;
  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: Guncelleme._surumuOku(),
    builder: (_, _) => Text(
      Guncelleme.surumMetni,
      textAlign: ortala ? TextAlign.center : null,
      style: TextStyle(fontSize: 11.5, color: renk ?? context.r.silik, fontWeight: FontWeight.w600, letterSpacing: .2),
    ),
  );
}

/// Yeni sürüm varken ekranın üstünde ince şerit; dokununca güncellemeyi başlatır. Yoksa yer kaplamaz.
class GuncellemeBandi extends StatelessWidget {
  const GuncellemeBandi({super.key, required this.api});
  final BogaApi api;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<SurumBilgisi?>(
    valueListenable: Guncelleme.yeni,
    builder: (context, b, _) {
      if (b == null) return const SizedBox.shrink();
      final r = context.r;
      return Material(
        color: r.vurguYumusak,
        child: InkWell(
          onTap: () => Guncelleme.kur(api, b),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: ValueListenableBuilder<double?>(
              valueListenable: Guncelleme.ilerleme,
              builder: (_, p, _) => Row(
                children: [
                  Icon(Simge.guncelleme, size: 18, color: r.vurgu),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p != null
                          ? 'Güncelleme indiriliyor… %${(p * 100).round()}'
                          : 'Yeni sürüm hazır: ${b.etiket}${Guncelleme.magazadan ? ' — TestFlight\'tan güncelleyin' : ''}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.metin),
                    ),
                  ),
                  Text(
                    p != null ? '' : 'Güncelle',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.vurgu),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Ayarlar'daki "Uygulama sürümü ve güncelleme" kartı.
class GuncellemeKarti extends StatefulWidget {
  const GuncellemeKarti({super.key, required this.api});
  final BogaApi api;
  @override
  State<GuncellemeKarti> createState() => _GuncellemeKartiState();
}

class _GuncellemeKartiState extends State<GuncellemeKarti> {
  bool _bakiyor = false;
  bool _bakildi = false;

  @override
  void initState() {
    super.initState();
    Guncelleme._surumuOku().then((_) => mounted ? setState(() {}) : null);
  }

  Future<void> _denetle() async {
    setState(() => _bakiyor = true);
    await Guncelleme.denetle(widget.api, sessiz: false, zorla: true);
    if (mounted) {
      setState(() {
        _bakiyor = false;
        _bakildi = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ValueListenableBuilder<SurumBilgisi?>(
      valueListenable: Guncelleme.yeni,
      builder: (context, b, _) => Container(
        decoration: BoxDecoration(
          color: r.kart,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: r.kenar),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const Icon(Simge.dogrulanmis, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kimlik == Kimlik.posta ? 'BogaMail' : 'BogaMail Yönetim',
                        style: gosterim(16, agirlik: FontWeight.w600, renk: r.metin),
                      ),
                      const SizedBox(height: 2),
                      Text('${Guncelleme.surumMetni} · ${Guncelleme.platformAdi}', style: TextStyle(fontSize: 13, color: r.soluk)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (b != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: r.vurguYumusak, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Yeni sürüm: ${b.etiket}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: r.metin),
                    ),
                    if (b.notlar.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        b.notlar,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: r.soluk),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<double?>(
                valueListenable: Guncelleme.ilerleme,
                builder: (_, p, _) => p != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: p, borderRadius: BorderRadius.circular(4), color: r.vurgu, backgroundColor: r.ic),
                          const SizedBox(height: 6),
                          Text('İndiriliyor… %${(p * 100).round()}', style: TextStyle(fontSize: 12.5, color: r.soluk)),
                        ],
                      )
                    : SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Guncelleme.kur(widget.api, b),
                          icon: const Icon(Simge.guncelleme),
                          label: Text(Guncelleme.magazadan ? 'TestFlight\'ta güncelle' : 'İndir ve kur'),
                        ),
                      ),
              ),
            ] else
              Row(
                children: [
                  Icon(_bakildi ? Simge.basari : Simge.bilgi, size: 18, color: _bakildi ? Marka.zumrut : r.silik),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bakildi ? 'En güncel sürümü kullanıyorsunuz.' : 'Güncellemeler otomatik denetlenir.',
                      style: TextStyle(fontSize: 13, color: r.soluk),
                    ),
                  ),
                  TextButton(
                    onPressed: _bakiyor ? null : _denetle,
                    child: _bakiyor ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Denetle'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Zorunlu güncelleme ekranı (yüklü derleme artık desteklenmiyor).
class ZorunluGuncellemeEkrani extends StatelessWidget {
  const ZorunluGuncellemeEkrani({super.key, required this.api});
  final BogaApi api;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Simge.guncelleme, size: 56, color: r.vurgu),
                  const SizedBox(height: 18),
                  Text('Güncelleme gerekli', style: gosterim(24, renk: r.metin)),
                  const SizedBox(height: 10),
                  Text(
                    'Bu sürüm (${Guncelleme.surumMetni}) artık desteklenmiyor. Devam etmek için uygulamayı güncelleyin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: r.soluk, height: 1.45),
                  ),
                  const SizedBox(height: 24),
                  ValueListenableBuilder<SurumBilgisi?>(
                    valueListenable: Guncelleme.yeni,
                    builder: (_, b, _) => SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: b == null ? () => Guncelleme.denetle(api, sessiz: false, zorla: true) : () => Guncelleme.kur(api, b),
                        icon: const Icon(Simge.indir),
                        label: Text(b == null ? 'Yeniden denetle' : 'Güncelle (${b.etiket})'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<double?>(
                    valueListenable: Guncelleme.ilerleme,
                    builder: (_, p, _) => p == null ? const SizedBox.shrink() : LinearProgressIndicator(value: p, color: r.vurgu),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
