import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/entegrasyonlar.dart';
import 'package:yonetim/ekranlar/platform_ayarlari.dart';
import 'package:yonetim/ekranlar/sunucular.dart';
import 'package:yonetim/ekranlar/yoneticiler.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

const _genis = Size(1500, 1000);
const _telefon = Size(400, 860);

Map<String, Object?> _kullanicilar() => {
  'GET /api/v1/users': {
    'items': [
      {
        'id': 'u1',
        'email': 'yonetici@ornek.test',
        'display_name': 'Deneme Yönetici',
        'role': 'super_admin',
        'status': 'active',
        'mfa_enabled': true,
        'permissions': null,
        'last_login_at': '2026-11-19T10:00:00Z',
        'created_at': '2026-01-01T10:00:00Z',
        'phone': '',
        'title': '',
        'note': '',
      },
      {
        'id': 'u2',
        'email': 'destek@musteri.test',
        'display_name': 'Ayşe Destek',
        'role': 'org_admin',
        'organization_id': 'o1',
        'organization_name': 'Örnek Firma',
        'status': 'suspended',
        'mfa_enabled': false,
        'permissions': ['mailboxes.manage', 'tracking.view', 'spam.manage', 'quarantine.view'],
        'last_login_at': null,
        'created_at': '2026-02-01T10:00:00Z',
        'phone': '',
        'title': 'Destek',
        'note': '',
      },
    ],
  },
  'GET /api/v1/catalog': {
    'permissions': [
      {'key': 'mailboxes.manage', 'name': 'Posta kutularını yönet'},
      {'key': 'tracking.view', 'name': 'Posta takibi ve kuyruk'},
    ],
    'role_templates': {
      'full': null,
      'support': ['mailboxes.manage', 'tracking.view', 'spam.manage', 'quarantine.view'],
    },
  },
  'GET /api/v1/security/mfa-policy': {'required_roles': <String>[], 'editable': true},
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => kullaniciAyarla());

  testWidgets('Sunucular: düğüm bilgisi ve dinleyiciler', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/system': {
        'nodes': [
          {
            'hostname': 'dugum-1',
            'role': 'all-in-one',
            'version': '1.2.3',
            'go_version': 'go1.25',
            'os': 'linux/amd64',
            'cpus': 8,
            'process_uptime': 3700,
            'host_uptime': 90000,
            'load_avg': [0.5, 0.4, 0.3],
            'mem_total': 8 << 30,
            'mem_available': 4 << 30,
            'process_rss': 200 << 20,
            'heap_alloc': 100 << 20,
            'goroutines': 120,
            'queue_depth': 3,
            'db_pool': {'total': 4, 'idle': 2, 'acquired': 2, 'max': 20},
            'disks': {
              'store': {'total_bytes': 100 << 30, 'used_bytes': 40 << 30, 'free_bytes': 60 << 30},
              'spool': null,
            },
            'listeners': [
              {'name': 'smtp-inbound', 'addr': ':25', 'status': 'ok'},
              {'name': 'smtp-submission', 'addr': '', 'status': 'disabled'},
            ],
          },
        ],
        'note': 'Tek düğüm kurulumu.',
      },
    });
    await t.pumpWidget(testUygulamasi(const SunucularEkrani()));
    await t.pumpAndSettle();
    expect(find.text('dugum-1'), findsOneWidget);
    expect(find.text('8 çekirdek'), findsOneWidget);
    expect(find.text('1 sa 1 dk'), findsOneWidget);
    expect(find.text('smtp-inbound'), findsOneWidget);
    expect(find.text('kapalı'), findsOneWidget);
    expect(find.text('60,0 GB boş'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Yöneticiler: geniş tabloda kullanıcılar ve şablon', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi(_kullanicilar());
    await t.pumpWidget(testUygulamasi(const YoneticilerEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Deneme Yönetici'), findsOneWidget);
    expect(find.text('Ayşe Destek'), findsOneWidget);
    expect(find.text('Destek'), findsWidgets);
    expect(find.text('Tam yetki'), findsOneWidget);
    expect(find.text('Askıda'), findsOneWidget);
    expect(find.text('Yeni yönetici'), findsOneWidget);
    // Yönet menüsü: kendisi olmayan kullanıcıda yetki/şifre/etkinleştir eylemleri.
    await t.tap(find.text('Ayşe Destek'));
    await t.pumpAndSettle();
    expect(find.text('Şifre sıfırla'), findsOneWidget);
    expect(find.text('Etkinleştir'), findsOneWidget);
  });

  testWidgets('Yöneticiler: telefonda kart; müşteri görünümünde yazma yok', (t) async {
    ekranBoyutu(t, _telefon);
    kullaniciAyarla(rol: 'org_admin', taklit: {'organization_id': 'o1', 'organization_name': 'Örnek Firma'});
    Uyg.api = SahteApi(_kullanicilar());
    await t.pumpWidget(testUygulamasi(const YoneticilerEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Ayşe Destek'), findsOneWidget);
    expect(find.text('KULLANICI'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('Entegrasyonlar: anahtar listesi', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/api-keys': {
        'items': [
          {
            'id': 'k1',
            'name': 'WHMCS',
            'prefix': 'bmk_1234abcd',
            'scope': 'provisioning',
            'allowed_ips': ['203.0.113.10'],
            'created_at': '2026-10-01T10:00:00Z',
            'last_used_at': null,
            'last_used_ip': null,
            'revoked_at': null,
            'linked_accounts': 7,
          },
        ],
        'base_url': 'https://panel.ornek.test',
      },
    });
    await t.pumpWidget(testUygulamasi(const EntegrasyonlarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('WHMCS'), findsOneWidget);
    expect(find.text('203.0.113.10'), findsOneWidget);
    expect(find.text('Kullanılmadı'), findsOneWidget);
    expect(find.text('Etkin'), findsOneWidget);
    expect(find.textContaining('panel.ornek.test'), findsOneWidget);
  });

  testWidgets('Platform ayarları: spam, limitler ve sistem', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/settings': {
        'spam': {'enabled': true, 'junk_threshold': 5, 'reject_threshold': 15},
        'system': {
          'smtp_hostname': 'mx.ornek.test',
          'smtp_addr': ':25',
          'submission_addr': '',
          'outbound_mode': 'direct',
          'public_ips': ['203.0.113.5'],
          'max_message_bytes': 50 << 20,
          'event_retention_days': 30,
          'cookie_secure': true,
        },
      },
      'GET /api/v1/activesync/settings': {
        'enabled': false,
        'url': 'https://panel.ornek.test/Microsoft-Server-ActiveSync',
        'path': '/Microsoft-Server-ActiveSync',
        'license_note': 'Ticari kullanım için Microsoft EAS lisansı gerekebilir',
        'can_edit': true,
        'max_devices': 10,
        'eas16': false,
      },
      'GET /api/v1/settings/limits': {
        'limits': {'max_message_bytes': 25 << 20, 'max_attachment_bytes': 18 << 20, 'max_signature_bytes': 256 << 10, 'max_avatar_bytes': 512 << 10},
        'bounds': {
          'max_message_bytes': [1 << 20, 100 << 20],
          'max_attachment_bytes': [1 << 20, 75 << 20],
          'max_signature_bytes': [8 << 10, 2 << 20],
          'max_avatar_bytes': [16 << 10, 1 << 20],
        },
        'smtp_hard_max_bytes': 50 << 20,
      },
    });
    await t.pumpWidget(testUygulamasi(const PlatformAyarlariEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Spam filtresi'), findsOneWidget);
    expect(find.text('mx.ornek.test'), findsOneWidget);
    expect(find.text('direct'), findsOneWidget);
    expect(find.text('Exchange ActiveSync (mobil eşitleme)'), findsOneWidget);
    expect(find.text('Boyut limitleri (platform varsayılanı)'), findsOneWidget);
    expect(find.widgetWithText(TextField, '25'), findsOneWidget);
    expect(find.widgetWithText(TextField, '256'), findsOneWidget);
  });
}
