import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/ekip_calismasi.dart';
import 'package:yonetim/ekranlar/gateway.dart';
import 'package:yonetim/ekranlar/mobil_cihazlar.dart';
import 'package:yonetim/ekranlar/toplu_gonderim.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

const _genis = Size(1500, 900);

Map<String, dynamic> _cihaz() => {
  'id': 'd1',
  'device_id': 'ABC123',
  'device_type': 'iPhone',
  'model': 'iPhone 15',
  'friendly_name': 'Ayşe telefonu',
  'os': 'iOS 18',
  'protocol_version': '16.1',
  'status': 'allowed',
  'provisioned': true,
  'last_sync_at': '2026-11-19T10:00:00Z',
  'mailbox': 'ayse@ornek.test',
  'organization': 'Örnek Yazılım',
};

Future<void> _bitir(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  SahteApi cihazApi() => SahteApi({
    'GET /api/v1/activesync/devices': {
      'items': [_cihaz()],
      'total': 1,
    },
    'GET /api/v1/activesync/settings': {'enabled': true, 'max_devices': 10, 'eas16': true, 'can_edit': true},
  });

  testWidgets('mobil cihazlar: geniş ekranda tablo', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = cihazApi();
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const MobilCihazlarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Mobil Cihazlar'), findsWidgets);
    expect(find.text('Ayşe telefonu'), findsOneWidget);
    expect(find.text('İzinli'), findsWidgets);
    await _bitir(t);
  });

  testWidgets('mobil cihazlar: telefonda kart görünümü', (t) async {
    ekranBoyutu(t, const Size(400, 800));
    Uyg.api = cihazApi();
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const MobilCihazlarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Ayşe telefonu'), findsOneWidget);
    expect(find.text('POSTA KUTUSU'), findsNothing);
    await _bitir(t);
  });

  testWidgets('ekip çalışması: müşteri paneli sekmeleri', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/workplace': {
        'can_manage': true,
        'signature_mode': 'default',
        'departments': ['Satış'],
        'features': {'tasks': true},
        'counts': {'open_tasks': 3, 'org_rules': 1, 'profiles_filled': 2, 'mailboxes': 5},
      },
      'GET /api/v1/workplace/signature': {'mode': 'default', 'template_html': '<p>{{ad}}</p>', 'company': 'Örnek', 'web': '', 'profile_user_editable': true},
    });
    kullaniciAyarla(
      rol: 'org_admin',
      baglam: {
        'organization': {'id': 'o1', 'name': 'Örnek'},
      },
    );
    await t.pumpWidget(testUygulamasi(const EkipCalismasiEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Ekip Çalışması'), findsWidgets);
    expect(find.text('İmza şablonu'), findsWidgets);
    expect(find.text('Görevler'), findsOneWidget);
    expect(find.text('Açık görev'), findsOneWidget);
    await _bitir(t);
  });

  testWidgets('gateway: alan kartı ve uyarılar', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/gateway/domains': {
        'outbound_mode': 'direct',
        'items': [
          {
            'id': 'g1',
            'name': 'ornek.test',
            'status': 'active',
            'organization_name': 'Örnek Yazılım',
            'health': 'healthy',
            'targets': [
              {'id': 't1', 'host': 'mx.ornek.test', 'port': 25, 'priority': 10, 'tls_policy': 'opportunistic', 'enabled': true, 'state': 'closed'},
            ],
          },
        ],
      },
      'GET /api/v1/gateway/alerts': {'items': []},
    });
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const GatewayEkrani()));
    await t.pumpAndSettle();
    expect(find.text('ornek.test'), findsWidgets);
    expect(find.textContaining('mx.ornek.test'), findsWidgets);
    await _bitir(t);
  });

  testWidgets('toplu gönderim: müşteri kampanya listesi', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/campaigns/overview': {
        'organization': {'id': 'o1', 'name': 'Örnek Yazılım', 'feature_enabled': true},
        'limits': {'max_contacts': 1000, 'contacts': 10, 'max_campaign_sends_monthly': 5000, 'sent_this_month': 100, 'reserved_pending': 0},
        'settings': {'approval': 'default', 'effective_company': 'Örnek', 'effective_address': 'İstanbul'},
        'senders': [],
        'merge_tags': [],
        'active_campaigns': 1,
        'suppressed': 0,
      },
      'GET /api/v1/campaigns': {
        'items': [
          {
            'id': 'c1',
            'name': 'Kasım bülteni',
            'subject': 'Merhaba',
            'kind': 'informational',
            'status': 'completed',
            'started_at': '2026-11-10T10:00:00Z',
            'stats': {'total': 10, 'pending': 0, 'delivered': 9, 'bounced_hard': 1, 'queued': 10},
          },
        ],
      },
    });
    kullaniciAyarla(
      rol: 'org_admin',
      baglam: {
        'organization': {'id': 'o1', 'name': 'Örnek Yazılım'},
      },
    );
    await t.pumpWidget(testUygulamasi(const TopluGonderimEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kasım bülteni'), findsOneWidget);
    expect(find.text('Tamamlandı'), findsOneWidget);
    expect(find.text('Kişi listeleri'), findsOneWidget);
    await _bitir(t);
  });
}
