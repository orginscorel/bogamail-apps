import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yonetim/ekranlar/bildirim_izni.dart';
import 'package:yonetim/ekranlar/bolumler.dart';
import 'package:yonetim/ekranlar/kabuk.dart';
import 'package:yonetim/oturum.dart';
import 'package:yonetim/veri/alarm_izleyici.dart';
import 'package:yonetim/veri/arkaplan.dart';
import 'package:yonetim/veri/bildirim.dart';

import 'sahte_api.dart';

Map<String, dynamic> _alarm(String kural, String since, {String severity = 'critical'}) => {
  'rule_id': kural,
  'name': 'Kuyruk birikti',
  'kind': 'queue_depth',
  'severity': severity,
  'subject': 'platform',
  'label': 'platform',
  'value': 900,
  'threshold': 500,
  'detail': 'Kuyrukta 900 ileti',
  'since': since,
};

Map<String, Object?> _yanitlar(List<Map<String, dynamic>> Function() etkin) => {
  'GET /api/v1/stats/overview': {'queue_depth': 0, 'unavailable': {}},
  'GET /api/v1/stats/traffic': {'items': []},
  'GET /api/v1/alerts/active': (Object? _, Map<String, dynamic>? _) => {'items': etkin()},
  'GET /api/v1/alerts/history': {'items': []},
  'GET /api/v1/health': {'components': []},
  'GET /api/v1/quarantine': {'items': [], 'summary': {'held': 0}},
  'GET /api/v1/audit-logs': {'items': [], 'total': 0},
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    Intl.defaultLocale = 'tr_TR';
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Uyg.api = SahteApi(_yanitlar(() => []));
    kullaniciAyarla();
    bildirimTanitimiSifirla();
    bolumRozetleri.value = const {};
    Arkaplan.surekliBagli.value = true;
    Arkaplan.giristeBaslat.value = true;
  });

  test('alarm izleyici: yeni alarm bir kez bildirilir, kapanıp yeniden başlayan tekrar bildirilir', () async {
    var etkin = [_alarm('r1', '2026-11-20T10:00:00Z'), _alarm('r2', '2026-11-20T10:05:00Z', severity: 'warning')];
    final iz = AlarmIzleyici(() async => {'items': etkin});
    var y = await iz.yokla();
    expect(y.yeni.map((a) => a.kuralId), ['r1', 'r2']);
    expect(y.yeni.first.bildirimBasligi, 'Kritik alarm: Kuyruk birikti');
    expect(y.yeni.last.bildirimBasligi, 'Alarm: Kuyruk birikti');
    expect(y.yeni.first.bildirimMetni, 'platform — Kuyrukta 900 ileti');

    y = await iz.yokla();
    expect(y.yeni, isEmpty);
    expect(y.etkin, hasLength(2));

    // r1 kapandı, sonra yeniden başladı (yeni "since"): tekrar bildirilir.
    etkin = [etkin[1]];
    expect((await iz.yokla()).yeni, isEmpty);
    etkin = [etkin[0], _alarm('r1', '2026-11-20T11:00:00Z')];
    y = await iz.yokla();
    expect(y.yeni.map((a) => a.kuralId), ['r1']);

    // Başka bir isolate (Android hizmeti) aynı depoyu görür: aynı alarmı yeniden bildirmez.
    expect((await AlarmIzleyici(() async => {'items': etkin}).yokla()).yeni, isEmpty);
  });

  test('uygulama içi yoklama yerel bildirim gösterir; Android\'de hizmet çalışıyorsa uygulama yoklamaz', () async {
    final b = SahteBildirimPlatformu(yerelMi: true);
    Bildirim.platform = b;
    final ap = SahteArkaplanPlatformu(androidMi: true)..hizmet = true;
    Arkaplan.platform = ap;
    final etkin = [_alarm('r9', '2026-11-20T09:00:00Z')];
    final iz = UygulamaIzleyici(izleyici: AlarmIzleyici(() async => {'items': etkin}));
    await iz.yokla();
    expect(b.gosterilen, isEmpty, reason: 'hizmet yokluyor');
    ap.hizmet = false;
    await iz.yokla();
    expect(b.gosterilen, hasLength(1));
    expect(b.gosterilen.single.$2, 'Kritik alarm: Kuyruk birikti');
    expect(b.gosterilen.single.$4, '${alarmYukOneki}r9');
    expect(baglantiMetni(0), contains('Etkin alarm yok'));
    expect(baglantiMetni(3), '3 etkin alarm');
  });

  testWidgets('girişten sonra izin tanıtımı → sistem izni; Android\'de pil muafiyeti; hizmet başlar', (t) async {
    ekranBoyutu(t, const Size(390, 844));
    final b = SahteBildirimPlatformu(izin: IzinDurumu.sorulmadi, muaf: false);
    Bildirim.platform = b;
    final ap = SahteArkaplanPlatformu(androidMi: true);
    Arkaplan.platform = ap;
    await t.pumpWidget(testUygulamasi(const Kabuk()));
    await t.pumpAndSettle();
    expect(find.text('Bildirimleri açın'), findsOneWidget);
    await t.tap(find.text('Bildirimlere izin ver'));
    await t.pumpAndSettle();
    expect(b.izinIstendi, 1);
    expect(find.text('Arka planda bağlı kalın'), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Muaf tut')));
    await t.pumpAndSettle();
    expect(b.pilIstendi, 1);
    expect(ap.hizmetBaslatildi, 1);
    expect(find.textContaining('Pil kısıtlaması açık'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('izin reddedildiyse bant "Ayarları aç" gösterir; tanıtım tekrar sormaz', (t) async {
    ekranBoyutu(t, const Size(1280, 800));
    final b = SahteBildirimPlatformu(izin: IzinDurumu.reddedildi);
    Bildirim.platform = b;
    await t.pumpWidget(testUygulamasi(const Kabuk()));
    await t.pumpAndSettle();
    expect(find.text('Bildirimleri açın'), findsNothing);
    expect(find.text('Bildirimler kapalı: alarmları kaçırabilirsiniz.'), findsOneWidget);
    await t.tap(find.text('Ayarları aç'));
    await t.pumpAndSettle();
    expect(b.ayarlarAcildi, 1);
    // Kullanıcı ayarlardan açıp uygulamaya dönünce bant kalkar.
    b.izin = IzinDurumu.verildi;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Bildirimler kapalı: alarmları kaçırabilirsiniz.'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Android: pil kısıtlıysa bant "Muaf tut"; ayarlarda sürekli bağlı kal kapatılınca hizmet durur', (t) async {
    ekranBoyutu(t, const Size(390, 844));
    final b = SahteBildirimPlatformu(izin: IzinDurumu.verildi, muaf: false);
    Bildirim.platform = b;
    final ap = SahteArkaplanPlatformu(androidMi: true);
    Arkaplan.platform = ap;
    SharedPreferences.setMockInitialValues({'yonetim.pil.soruldu': true});
    await t.pumpWidget(testUygulamasi(const Scaffold(body: Column(children: [BildirimBandi(), Expanded(child: SingleChildScrollView(child: ArkaplanKarti()))]))));
    await t.pumpAndSettle();
    expect(find.text('Pil kısıtlaması açık: arka planda alarmlar gecikebilir.'), findsOneWidget);
    expect(find.text('Sürekli bağlı kal'), findsOneWidget);
    expect(find.text('Oturum açıldığında başlat'), findsNothing);
    await t.tap(find.text('Sürekli bağlı kal'));
    await t.pumpAndSettle();
    expect(ap.hizmetDurdu, 1);
    expect(Arkaplan.surekliBagli.value, isFalse);
    // Sürekli bağlı kapalıyken pil bandı gösterilmez.
    expect(find.text('Pil kısıtlaması açık: arka planda alarmlar gecikebilir.'), findsNothing);
    await t.tap(find.text('Muaf tut'));
    await t.pumpAndSettle();
    expect(b.pilIstendi, 1);
    expect(find.text('Pil kısıtlamasından muaf'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Windows: oturum açıldığında başlat varsayılan açık, kapatılabilir', (t) async {
    ekranBoyutu(t, const Size(1280, 800));
    final ap = SahteArkaplanPlatformu(windowsMi: true);
    Arkaplan.platform = ap;
    await Arkaplan.oturumAcildi();
    expect(ap.girisAcik, isTrue);
    expect(ap.hizmetBaslatildi, 0);
    await t.pumpWidget(testUygulamasi(const Scaffold(body: SingleChildScrollView(child: ArkaplanKarti()))));
    await t.pumpAndSettle();
    expect(find.textContaining('sistem tepsisinde başlar'), findsOneWidget);
    await t.tap(find.text('Oturum açıldığında başlat'));
    await t.pumpAndSettle();
    expect(ap.girisAcik, isFalse);
    expect((await SharedPreferences.getInstance()).getBool('yonetim.giriste_baslat'), isFalse);
    await t.pumpWidget(const SizedBox());
  });
}
