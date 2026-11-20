import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/bayiler.dart';
import 'package:yonetim/ekranlar/dahili.dart';
import 'package:yonetim/ekranlar/itibar_merkezim.dart';
import 'package:yonetim/ekranlar/marka.dart';
import 'package:yonetim/ekranlar/paketim.dart';
import 'package:yonetim/ekranlar/paketler.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

const _katalog = {
  'features': [
    {'key': 'webmail', 'name': 'Webmail', 'group': 'Temel', 'available': true},
    {'key': 'bulk_sending', 'name': 'Toplu Gönderim', 'group': 'Gönderim', 'available': true},
    {'key': 'archiving', 'name': 'Arşivleme', 'group': 'Uyumluluk', 'available': false, 'phase': 'Faz 7'},
  ],
};

Map<String, dynamic> _plan({String id = 'p1', String ad = 'Kurumsal Mail 5', String? bayi}) => {
  'id': id,
  'code': 'kurumsal-mail-5',
  'name': ad,
  'kind': 'hosting',
  'description': 'Küçük ofisler için',
  'status': 'active',
  'reseller_id': bayi,
  'price_monthly': 149.9,
  'price_yearly': 1499,
  'currency': 'TRY',
  'sort_order': 100,
  'max_domains': 3,
  'max_mailboxes': 5,
  'total_quota_bytes': 50 << 30,
  'default_mailbox_quota_bytes': 10 << 30,
  'max_mailbox_quota_bytes': 20 << 30,
  'max_aliases': null,
  'send_limit_per_hour': 300,
  'daily_send_limit': 2000,
  'max_recipients_per_message': 100,
  'max_message_bytes': 25 << 20,
  'max_attachment_bytes': null,
  'max_signature_bytes': null,
  'features': {'webmail': true, 'bulk_sending': true},
  'organization_count': 4,
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  for (final genislik in [1400.0, 390.0]) {
    testWidgets('Paketim: paket, kullanım, gönderim sınırları ve dışa aktarma ($genislik)', (t) async {
      ekranBoyutu(t, Size(genislik, 2600));
      Uyg.api = SahteApi({
        'GET /api/v1/organizations/o1/entitlements': {
          'plan': _plan(),
          'effective': {
            'limits': {'max_mailboxes': 5, 'max_domains': 3, 'total_quota_bytes': 50 << 30, 'send_limit_per_hour': 300},
            'features': {'webmail': true, 'bulk_sending': true, 'archiving': true},
          },
          'usage': {
            'mailboxes': 4,
            'mailboxes_active': 3,
            'mailboxes_suspended': 1,
            'domains': 2,
            'domains_verified': 2,
            'sent_last_hour': 12,
            'sent_last_24h': 340,
          },
        },
        'GET /api/v1/catalog': _katalog,
        'GET /api/v1/settings/limits': {
          'limits': {'max_message_bytes': 26214400},
        },
        'GET /api/v1/tenants/o1/usage': {
          'effective': {
            'msgs_per_minute': 60,
            'rcpts_per_hour': 1000,
            'max_concurrent': 4,
            'paused': false,
            'throttled': true,
            'throttled_until': '2026-11-20T12:00:00Z',
            'reason': '',
          },
          'sent_last_hour': 120,
          'finished_24h': 300,
          'bounce_rate': 2.5,
          'queued': 3,
          'held': 1,
          'running': 1,
        },
        'GET /api/v1/organizations/o1/exports': {
          'items': [
            {
              'id': 'x1',
              'status': 'ready',
              'created_at': '2026-11-19T10:00:00Z',
              'mailboxes': 4,
              'messages': 1200,
              'contacts': 10,
              'events': 3,
              'size_bytes': 1 << 20,
            },
          ],
          'available': true,
        },
      });
      kullaniciAyarla(rol: 'org_admin');
      Uyg.ben.value = {...Uyg.ben.value!, 'organization_id': 'o1'};
      await t.pumpWidget(testUygulamasi(const PaketimEkrani()));
      await t.pumpAndSettle();
      expect(find.text('Kurumsal Mail 5'), findsOneWidget);
      expect(find.text('Posta kutusu'), findsWidgets);
      expect(find.text('3 aktif · 1 askıda'), findsOneWidget);
      expect(find.text('Toplu gönderim kişileri'), findsOneWidget);
      expect(find.text('Geçici olarak yavaşlatıldı'), findsOneWidget);
      expect(find.text('Pakette · Faz 7'), findsOneWidget);
      expect(find.text('Tümünü dışa aktar'), findsOneWidget);
      expect(find.text('Hazır'), findsOneWidget);
    });
  }

  for (final genislik in [1400.0, 390.0]) {
    testWidgets('İtibar Merkezim: göstergeler, nedenler, IP ve göndericiler ($genislik)', (t) async {
      ekranBoyutu(t, Size(genislik, 3000));
      final a = SahteApi({
        'GET /api/v1/reputation-center': {
          'organization': {'id': 'o1', 'name': 'Örnek'},
          'range': '7d',
          'totals': {
            'queued': 500,
            'delivered': 480,
            'hard_bounces': 6,
            'soft_bounces': 1,
            'deferred_rcpts': 4,
            'deferrals': 9,
            'refused': 2,
            'refused_messages': 2,
          },
          'rates': {'delivery_rate': 96, 'hard_bounce_rate': 1.2, 'soft_bounce_rate': 0.2},
          'series': [
            {'at': '2026-11-19T00:00:00Z', 'delivered': 200, 'hard_bounces': 2, 'soft_bounces': 0, 'deferred_rcpts': 1, 'refused': 0},
            {'at': '2026-11-20T00:00:00Z', 'delivered': 280, 'hard_bounces': 4, 'soft_bounces': 1, 'deferred_rcpts': 3, 'refused': 2},
          ],
          'bounce_reasons': [
            {
              'kind': 'hard',
              'enhanced_code': '5.1.1',
              'smtp_code': 550,
              'text': 'user unknown',
              'count': 6,
              'recipient_domains': ['ornek.test'],
              'last_at': '2026-11-20T08:00:00Z',
            },
          ],
          'complaints': {'suppressions': 0, 'fbl': 'FBL yok'},
          'ips': [
            {
              'address': '192.0.2.10',
              'dedicated': false,
              'ptr': ['mx.ornek.test'],
              'fcrdns': true,
              'helo_matches_ip': true,
              'listed': 0,
              'lists_checked': 12,
              'checked_at': '2026-11-20T06:00:00Z',
              'listings': [],
            },
          ],
          'senders': [
            {
              'address': 'satis@ornek.test',
              'delivered': 300,
              'hard_bounces': 5,
              'deferred_rcpts': 1,
              'rates': {'hard_bounce_rate': 1.6},
              'high_bounce': false,
              'over_pause_threshold': false,
            },
          ],
          'pause': {'rate': 10, 'min_sends': 50},
          'dmarc_center': true,
          'domains': [
            {'id': 'd1', 'name': 'ornek.test', 'score': 92, 'dmarc_messages_30d': 100, 'dmarc_pass_rate_30d': 99.0, 'dmarc_reports_30d': 4},
          ],
          'outbound_mode': 'direct',
        },
        'GET /api/v1/dedicated-ip/status': {'feature': false, 'mode': 'shared', 'warning': '', 'ips': []},
        'GET /api/v1/outbound/health': {
          'health': {
            'deferral_rate': 1,
            'unknown_user_rate': 0.5,
            'complaint_rate': 0,
            'deferred_24h': 1,
            'attempts_24h': 100,
            'unknown_user_24h': 1,
            'complaints_7d': 0,
            'delivered_7d': 400,
          },
          'brakes': [],
          'queued': 2,
          'held': 0,
          'held_by_brake': 0,
          'suppressed': 7,
          'thresholds': {'deferral_rate': 20, 'unknown_user_rate': 10, 'complaint_rate': 0.3, 'complaint_warn': 0.1},
        },
      });
      Uyg.api = a;
      kullaniciAyarla(rol: 'org_admin');
      Uyg.ben.value = {...Uyg.ben.value!, 'organization_id': 'o1'};
      await t.pumpWidget(testUygulamasi(const ItibarMerkezimEkrani()));
      await t.pumpAndSettle();
      expect(find.text('Teslim edilen'), findsOneWidget);
      expect(find.text('480'), findsOneWidget);
      expect(find.text('user unknown'), findsOneWidget);
      expect(find.text('192.0.2.10'), findsOneWidget);
      expect(find.text('satis@ornek.test'), findsOneWidget);
      expect(find.text('92/100'), findsOneWidget);
      expect(find.text('Gönderim sağlığı'), findsOneWidget);
      final q = a.istekler.firstWhere((i) => i.$2 == '/api/v1/reputation-center').$4!;
      expect(q['range'], '7d');
      expect(q.containsKey('organization_id'), isFalse);
    });
  }

  testWidgets('Yönetici Kurumları: kuruluşlar ve arşiv', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    final a = SahteApi({
      'GET /api/v1/organizations': {
        'items': [
          {
            'id': 'o9',
            'name': 'Bogahost İç',
            'status': 'active',
            'plan_name': 'Sınırsız',
            'domain_count': 2,
            'mailbox_count': 12,
            'allocated_bytes': 1 << 30,
            'internal': true,
          },
        ],
        'total': 1,
      },
      'GET /api/v1/internal/retained': {
        'items': [
          {
            'id': 'm1',
            'organization_name': 'Bogahost İç',
            'address': 'muhasebe@ic.test',
            'folder_name': 'INBOX',
            'subject': 'Fatura Ekim',
            'from': 'a@b.test',
            'size_bytes': 2048,
            'internal_date': '2026-11-01T10:00:00Z',
            'deleted_at': '2026-11-02T10:00:00Z',
          },
        ],
        'total': 1,
      },
      'POST /api/v1/internal/retained/m1/restore': {'ok': true},
    });
    Uyg.api = a;
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const DahiliKurumlarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Bogahost İç'), findsOneWidget);
    expect(a.istekler.firstWhere((i) => i.$2 == '/api/v1/organizations').$4!['internal'], '1');
    await t.tap(find.text('Silinen posta arşivi'));
    await t.pumpAndSettle();
    expect(find.text('Fatura Ekim'), findsOneWidget);
  });

  testWidgets('Bayiler: geniş tablo ve telefon kartları', (t) async {
    final yanit = {
      'GET /api/v1/resellers/summary': {
        'items': [
          {
            'id': 'r1',
            'name': 'Anadolu Bilişim',
            'status': 'active',
            'max_customers': 50,
            'max_mailboxes': null,
            'max_storage_bytes': 100 << 30,
            'contact_email': 'bayi@anadolu.test',
            'admin_count': 2,
            'usage': {'customers': 12, 'mailboxes': 140, 'allocated_bytes': 40 << 30, 'used_bytes': 10 << 30},
            'branding': {},
          },
        ],
      },
    };
    ekranBoyutu(t, const Size(1400, 900));
    Uyg.api = SahteApi(yanit);
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const BayilerEkrani()));
    await t.pumpAndSettle();
    expect(find.text('BAYİ'), findsOneWidget);
    expect(find.text('Anadolu Bilişim'), findsOneWidget);
    expect(find.text('12 / 50'), findsOneWidget);
    expect(find.text('Yeni bayi'), findsOneWidget);

    ekranBoyutu(t, const Size(400, 850));
    await t.pumpWidget(testUygulamasi(const BayilerEkrani(key: ValueKey('tel'))));
    await t.pumpAndSettle();
    expect(find.text('Anadolu Bilişim'), findsOneWidget);
    expect(find.text('BAYİ'), findsNothing);
  });

  testWidgets('Paketler: paket kartları ve düzenleme', (t) async {
    ekranBoyutu(t, const Size(1400, 1400));
    Uyg.api = SahteApi({
      'GET /api/v1/plans': {
        'items': [_plan(), _plan(id: 'p2', ad: 'Bayi Paketi', bayi: 'r1')],
      },
      'GET /api/v1/catalog': _katalog,
    });
    kullaniciAyarla();
    await t.pumpWidget(testUygulamasi(const PaketlerEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kurumsal Mail 5'), findsOneWidget);
    expect(find.text('Bayi paketi'), findsOneWidget);
    expect(find.text('Düzenle'), findsNWidgets(2));
    expect(find.text('Yeni paket'), findsOneWidget);
    await t.tap(find.text('Düzenle').first);
    await t.pumpAndSettle();
    expect(find.text('Kurumsal Mail 5 paketini düzenle'), findsOneWidget);
    expect(find.text('Sınırlar'), findsOneWidget);
  });

  for (final genislik in [1400.0, 390.0]) {
    testWidgets('Marka: ayarlar ve giriş adresi ($genislik)', (t) async {
      ekranBoyutu(t, Size(genislik, 2200));
      Uyg.api = SahteApi({
        'GET /api/v1/organizations/o1/branding': {
          'organization_id': 'o1',
          'enabled': true,
          'product_name': 'Örnek Posta',
          'primary_color': '#0f766e',
          'support_email': 'destek@ornek.test',
          'support_url': '',
          'footer_text': '',
          'has_logo': false,
          'has_logo_dark': false,
          'version': '1',
        },
        'GET /api/v1/organizations/o1/login-host': {
          'login_host': {
            'hostname': '',
            'status': '',
            'detail': '',
            'tls_status': '',
            'checked_at': null,
            'expected_cname': 'posta.ornek.test',
            'expected_ips': ['192.0.2.1'],
          },
          'branding_enabled': true,
        },
      });
      kullaniciAyarla(rol: 'org_admin');
      Uyg.ben.value = {...Uyg.ben.value!, 'organization_id': 'o1'};
      await t.pumpWidget(testUygulamasi(const MarkaEkrani()));
      await t.pumpAndSettle();
      expect(find.text('Örnek Posta'), findsWidgets);
      expect(find.text('Canlı önizleme'), findsOneWidget);
      expect(find.text('Kendi alan adınızla giriş'), findsOneWidget);
      expect(find.text('posta.ornek.test'), findsOneWidget);
    });
  }
}
