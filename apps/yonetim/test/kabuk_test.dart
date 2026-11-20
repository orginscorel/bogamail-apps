import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:yonetim/ekranlar/bolumler.dart';
import 'package:yonetim/ekranlar/kabuk.dart';
import 'package:yonetim/ekranlar/ozet.dart';
import 'package:yonetim/oturum.dart';
import 'package:yonetim/veri/operasyon.dart';

import 'sahte_api.dart';

Map<String, Object?> _yanitlar() {
  final simdi = DateTime.now().toUtc();
  return {
    'GET /api/v1/stats/overview': {
      'organizations': 12,
      'domains': 30,
      'domains_pending': 2,
      'gateway_domains': 1,
      'mailboxes': 410,
      'active_mailboxes': 400,
      'allocated_bytes': 1 << 40,
      'used_bytes': 1 << 38,
      'messages_received_today': 1500,
      'delivered_today': 1480,
      'failed_today': 3,
      'queue_depth': 7,
      'delivery_success_rate': 99.2,
      'unavailable': {},
    },
    'GET /api/v1/stats/traffic': {
      'items': [
        for (var i = 0; i < 48; i++)
          {'hour': simdi.subtract(Duration(hours: 47 - i)).toIso8601String(), 'accepted': i < 24 ? 10 : 20, 'delivered': 9, 'rejected': 1, 'failed': 0, 'deferred': 0},
      ],
    },
    'GET /api/v1/alerts/active': {
      'items': [
        {'rule_id': 'r1', 'name': 'Kuyruk birikti', 'severity': 'critical', 'label': 'platform', 'value': 900, 'threshold': 500},
      ],
    },
    'GET /api/v1/alerts/history': {'items': []},
    'GET /api/v1/health': {
      'components': [
        {'name': 'database', 'status': 'ok', 'latency_ms': 1.2},
      ],
    },
    'GET /api/v1/quarantine': {
      'items': [],
      'summary': {'held': 4, 'virus_7d': 1, 'blocked_7d': 2},
    },
    'GET /api/v1/audit-logs': {'items': [], 'total': 0},
  };
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  setUp(() {
    Uyg.api = SahteApi(_yanitlar());
    kullaniciAyarla();
    bolumRozetleri.value = const {};
  });

  testWidgets('geniş ekran: gruplu yan menü, rozetler, gösterge kartları', (t) async {
    ekranBoyutu(t, const Size(1600, 1000));
    await t.pumpWidget(testUygulamasi(const Kabuk()));
    await t.pumpAndSettle();
    expect(find.text('HİZMET'), findsOneWidget);
    await t.scrollUntilVisible(find.text('GÜVENLİK'), 200,
        scrollable: find.descendant(of: find.byType(YanMenu), matching: find.byType(Scrollable)).first);
    expect(find.text('GÜVENLİK'), findsOneWidget);
    expect(find.text('Müşteriler'), findsWidgets);
    expect(find.text('Posta kutuları'), findsWidgets);
    expect(find.text('Dikkat gerektirenler'), findsOneWidget);
    expect(find.textContaining('Kuyruk birikti'), findsOneWidget);
    expect(bolumRozetleri.value[Bolum.alarmlar], 1);
    expect(bolumRozetleri.value[Bolum.karantina], 4);
    // Alınan: son 24 saat 480, önceki 240 → %100 artış.
    expect(find.text('%100'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('telefon: alt çubuk ve gruplu Daha fazla ekranı', (t) async {
    ekranBoyutu(t, const Size(400, 860));
    await t.pumpWidget(testUygulamasi(const Kabuk()));
    await t.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Daha fazla'), findsOneWidget);
    await t.tap(find.text('Daha fazla'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('GÜVENLİK'), 200,
        scrollable: find.descendant(of: find.byType(DahaFazlaEkrani), matching: find.byType(Scrollable)).first);
    expect(find.text('GÜVENLİK'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('müşteri yöneticisi platform bölümlerini görmez, paket özelliklerine göre süzülür', (t) async {
    kullaniciAyarla(rol: 'org_admin', baglam: {
      'organization': {'name': 'Örnek AŞ', 'plan_kind': 'gateway', 'features': {'gateway': true}},
    });
    expect(Bolum.musteriler.gorunur, isFalse);
    expect(Bolum.sunucu.gorunur, isFalse);
    expect(Bolum.kutular.gorunur, isFalse);
    expect(Bolum.gateway.gorunur, isTrue);
    expect(Bolum.paketim.gorunur, isTrue);
    expect(Bolum.dmarc.gorunur, isFalse);
    kullaniciAyarla(rol: 'reseller_admin', izinler: ['mailboxes.manage']);
    expect(Bolum.kuyruk.gorunur, isFalse);
    expect(Bolum.musteriler.gorunur, isTrue);
    expect(Bolum.bayiler.gorunur, isFalse);
  });

  test('özet değişimi: son 24 saat ile önceki 24 saat', () {
    final t0 = DateTime(2026);
    final l = [for (var i = 0; i < 4; i++) TrafikDilimi(t0.add(Duration(hours: i)), i < 2 ? 5 : 10, 0, 0, 0, 0)];
    expect(ozetDegisimi(l, (d) => d.kabul), 100);
    expect(ozetDegisimi(const [], (d) => d.kabul), isNull);
  });
}
