import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/musteri_detay.dart';
import 'package:yonetim/ekranlar/musteri_form.dart';
import 'package:yonetim/ekranlar/musteri_model.dart';
import 'package:yonetim/ekranlar/musteriler.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

Map<String, dynamic> _org({String id = 'o1', String ad = 'Örnek Yazılım', String durum = 'active', String? bayi}) => {
  'id': id,
  'name': ad,
  'status': durum,
  'reseller_id': bayi == null ? null : 'r1',
  'reseller_name': bayi,
  'plan_id': 'p1',
  'plan_name': 'Kurumsal Mail 2',
  'max_domains': 3,
  'max_mailboxes': 25,
  'total_quota_bytes': 50 << 30,
  'domain_count': 1,
  'mailbox_count': 7,
  'allocated_bytes': 10 << 30,
  'used_bytes': 2 << 30,
  'created_at': '2026-11-01T10:00:00Z',
  'internal': false,
  'profile': {'contact_name': 'Ayşe Demir', 'contact_phone': '0532 000 00 00', 'sector': 'bilisim', 'contact_email': 'ayse@ornek.test'},
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  SahteApi api() => SahteApi({
    'GET /api/v1/organizations': {
      'items': [_org(), _org(id: 'o2', ad: 'Deneme Ltd', durum: 'suspended', bayi: 'Bayi A')],
      'total': 2,
    },
    'GET /api/v1/organizations/o1': _org(),
    'GET /api/v1/organizations/o1/mfa-policy': {'panel': true, 'webmail': false},
    'GET /api/v1/plans': {
      'items': [
        {'id': 'p1', 'name': 'Kurumsal Mail 2', 'max_mailboxes': 25, 'total_quota_bytes': 50 << 30},
      ],
    },
    'GET /api/v1/resellers': {'items': []},
  });

  testWidgets('geniş ekranda müşteri tablosu', (t) async {
    ekranBoyutu(t, const Size(1500, 900));
    final a = api();
    Uyg.api = a;
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const MusterilerEkrani()));
    await t.pumpAndSettle();
    expect(find.text('MÜŞTERİ'), findsOneWidget);
    expect(find.text('Örnek Yazılım'), findsOneWidget);
    expect(find.text('Deneme Ltd'), findsOneWidget);
    expect(find.text('Askıda'), findsWidgets);
    expect(find.text('Yeni müşteri'), findsOneWidget);
    expect(find.text('Bayiler'), findsNothing);
    final q = a.istekler.firstWhere((i) => i.$2 == '/api/v1/organizations').$4!;
    expect(q['internal'], '0');
    expect(q['sort'], 'created_at');
  });

  testWidgets('telefonda müşteri kartları', (t) async {
    ekranBoyutu(t, const Size(400, 850));
    Uyg.api = api();
    kullaniciAyarla(rol: 'reseller_admin');
    await t.pumpWidget(testUygulamasi(const MusterilerEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Örnek Yazılım'), findsOneWidget);
    expect(find.text('MÜŞTERİ'), findsNothing);
    expect(find.text('1 / 3'), findsWidgets);
  });

  testWidgets('müşteri ayrıntısı', (t) async {
    ekranBoyutu(t, const Size(1200, 2400));
    Uyg.api = api();
    kullaniciAyarla();
    await t.pumpWidget(
      testUygulamasi(
        Scaffold(
          body: MusteriDetay(musteri: Musteri.coz(_org()), degisti: (_) {}),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('KART'), findsOneWidget);
    expect(find.text('ayse@ornek.test'), findsOneWidget);
    expect(find.text('Bayi yap'), findsOneWidget);
    expect(find.text('Çıkış IP\'si'), findsOneWidget);
    expect(find.text('Müşteri paneline gir'), findsWidgets);
    final s = t.widget<SwitchListTile>(find.byType(SwitchListTile).first);
    expect(s.value, isTrue);
  });

  testWidgets('yeni müşteri formu zorunlu alanları denetler', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    final a = api();
    Uyg.api = a;
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const MusteriFormu()));
    await t.pumpAndSettle();
    expect(find.text('Yeni müşteri'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Müşteri adı *'), 'Yeni Firma');
    await t.pump();
    await t.tap(find.text('Oluştur'));
    await t.pump();
    expect(find.text('Sektör seçin'), findsOneWidget);
    expect(a.istendi('POST', '/api/v1/organizations'), isFalse);
  });
}
