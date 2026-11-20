// Tasarım görüntüleri: TASARIM_CIKTI=<klasör/önek> ortam değişkeni verilirse özet, posta kutuları tablosu ve
// ayarlar ekranlarını 390×844 ve 1280×800 boyutlarında gerçek yazı tipleriyle PNG olarak yazar. Normal test
// koşusunda atlanır.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:yonetim/ekranlar/ayarlar.dart';
import 'package:yonetim/ekranlar/bolumler.dart';
import 'package:yonetim/ekranlar/hesap_blogu.dart';
import 'package:yonetim/ekranlar/kabuk.dart';
import 'package:yonetim/ekranlar/posta_kutulari.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

final _cikti = Platform.environment['TASARIM_CIKTI'];

Future<void> _yaziTipi(String aile, List<String> dosyalar) async {
  final y = FontLoader(aile);
  for (final d in dosyalar) {
    final f = File(d);
    if (f.existsSync()) y.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await y.load();
}

Future<void> _yaziTipleri() async {
  const ortak = '../../packages/boga_ortak/assets/fonts';
  await _yaziTipi('packages/boga_ortak/Poppins', [
    for (final k in ['Regular', 'Medium', 'SemiBold', 'Bold']) '$ortak/Poppins-$k.ttf',
  ]);
  await _yaziTipi('packages/boga_ortak/Jakarta', ['$ortak/PlusJakartaSans.ttf']);
  await _yaziTipi('MaterialIcons', ['/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  // Phosphor simge yazı tipleri (uygulamayla gelen).
  for (final st in ['Light', 'Regular', 'Fill']) {
    await _yaziTipi('Phosphor$st', ['assets/fonts/phosphor/Phosphor-$st.ttf']);
  }
}

Map<String, Object?> _yanitlar() {
  final simdi = DateTime.now().toUtc();
  final saat = [for (var i = 0; i < 168; i++) 40 + (i * 37 % 90) + (i % 24 > 8 && i % 24 < 19 ? 120 : 0)];
  return {
    'GET /api/v1/stats/overview': {
      'organizations': 48,
      'domains': 132,
      'domains_pending': 3,
      'gateway_domains': 6,
      'mailboxes': 2410,
      'active_mailboxes': 2380,
      'allocated_bytes': 6 << 40,
      'used_bytes': 2 << 40,
      'messages_received_today': 18420,
      'delivered_today': 18190,
      'failed_today': 14,
      'queue_depth': 23,
      'delivery_success_rate': 99.4,
      'unavailable': {},
    },
    'GET /api/v1/stats/traffic': (Object? _, Map<String, dynamic>? q) {
      final n = int.tryParse('${q?['hours'] ?? 24}') ?? 24;
      return {
        'items': [
          for (var i = 0; i < n; i++)
            {
              'hour': simdi.subtract(Duration(hours: n - 1 - i)).toIso8601String(),
              'accepted': saat[i % saat.length] * 6,
              'delivered': saat[i % saat.length] * 6 - 8,
              'rejected': 12,
              'failed': 1,
              'deferred': 3,
            },
        ],
      };
    },
    'GET /api/v1/alerts/active': {
      'items': [
        {'rule_id': 'r1', 'name': 'Kuyruk birikti', 'severity': 'warning', 'label': 'platform', 'value': 23, 'threshold': 20},
      ],
    },
    'GET /api/v1/alerts/history': {'items': []},
    'GET /api/v1/health': {
      'components': [
        {'name': 'database', 'status': 'ok', 'latency_ms': 1.2},
        {'name': 'redis', 'status': 'ok', 'latency_ms': 0.4},
        {'name': 'smtp', 'status': 'ok', 'latency_ms': 3.1},
      ],
    },
    'GET /api/v1/quarantine': {
      'items': [],
      'summary': {'held': 4, 'virus_7d': 1, 'blocked_7d': 2},
    },
    'GET /api/v1/audit-logs': {
      'items': [
        for (final (i, a) in ['mailbox.create', 'domain.verify', 'organization.update', 'mailbox.password_reset'].indexed)
          {'id': 'a$i', 'at': simdi.subtract(Duration(minutes: 7 * i + 3)).toIso8601String(), 'actor_email': 'yonetici@bogahost.test', 'action': a, 'target_type': 'mailbox', 'target_label': 'ali@ornek.com.tr'},
      ],
      'total': 4,
    },
    'GET /api/v1/mailboxes': {
      'items': [
        for (final (i, k) in [
          ('ali.yilmaz', 'Ali Yılmaz', 0.82),
          ('ayse.demir', 'Ayşe Demir', 0.35),
          ('muhasebe', 'Muhasebe', 0.96),
          ('info', 'Bilgi', 0.12),
          ('satis', 'Satış Ekibi', 0.58),
          ('destek', 'Destek', 0.44),
          ('mehmet.kaya', 'Mehmet Kaya', 0.07),
          ('ik', 'İnsan Kaynakları', 0.66),
        ].indexed)
          {
            'id': 'm$i',
            'address': '${k.$1}@ornek.com.tr',
            'display_name': k.$2,
            'domain_id': 'd1',
            'domain_name': 'ornek.com.tr',
            'organization_id': 'o1',
            'organization_name': 'Örnek Teknoloji A.Ş.',
            'quota_bytes': 10 << 30,
            'used_bytes': ((10 << 30) * k.$3).round(),
            'status': i == 3 ? 'suspended' : 'active',
            'last_login_at': simdi.subtract(Duration(hours: i * 5 + 1)).toIso8601String(),
            'created_at': simdi.subtract(Duration(days: 30 + i * 11)).toIso8601String(),
          },
      ],
      'total': 8,
    },
    'GET /api/v1/auth/mfa': {'enabled': true},
    'GET /api/v1/auth/sessions': {
      'items': [
        {'id': 's1', 'ip': '192.0.2.10', 'user_agent': 'BogaMail-Yonetim/1.1.0 (macOS)', 'created_at': simdi.subtract(const Duration(days: 2)).toIso8601String(), 'last_seen_at': simdi.toIso8601String(), 'current': true},
        {'id': 's2', 'ip': '198.51.100.4', 'user_agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/131', 'created_at': simdi.subtract(const Duration(days: 5)).toIso8601String(), 'last_seen_at': simdi.subtract(const Duration(hours: 3)).toIso8601String(), 'current': false},
      ],
    },
  };
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
    if (_cikti != null) await _yaziTipleri();
  });

  // Hesap menüsü: geniş ekranda yan menüdeki bloktan yukarı açılır kutu; telefonda "Daha fazla" → blok → alt sayfa.
  Future<void> hesapMenusu(WidgetTester t) async {
    if (find.text('Daha fazla').evaluate().isNotEmpty) {
      await t.tap(find.text('Daha fazla'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byType(HesapBlogu), 300,
          scrollable: find.descendant(of: find.byType(DahaFazlaEkrani), matching: find.byType(Scrollable)).first);
      await t.pumpAndSettle();
    }
    await t.tap(find.byType(HesapBlogu).first);
    await t.pumpAndSettle();
  }

  final ekranlar = <(String, Widget Function(), Future<void> Function(WidgetTester)?)>[
    ('ozet', () => const Kabuk(), null),
    ('tablo', () => const PostaKutulariEkrani(), null),
    ('ayarlar', () => const AyarlarEkrani(), null),
    ('hesap', () => const Kabuk(), hesapMenusu),
  ];
  for (final (ad, kur, adim) in ekranlar) {
    for (final boy in const [Size(390, 844), Size(1280, 800)]) {
      testWidgets('görüntü $ad ${boy.width.toInt()}x${boy.height.toInt()}', skip: _cikti == null, (t) async {
        ekranBoyutu(t, boy);
        Uyg.api = SahteApi(_yanitlar());
        kullaniciAyarla();
        bolumRozetleri.value = const {};
        final anahtar = GlobalKey();
        await t.pumpWidget(RepaintBoundary(key: anahtar, child: testUygulamasi(kur())));
        await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        if (adim != null) await adim(t);
        await t.runAsync(() async {
          final ro = anahtar.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await ro.toImage(pixelRatio: 2);
          final b = await img.toByteData(format: ui.ImageByteFormat.png);
          final f = File('$_cikti-$ad-${boy.width.toInt()}x${boy.height.toInt()}.png');
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(b!.buffer.asUint8List());
        });
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
