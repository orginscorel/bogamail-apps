import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/dlp.dart';
import 'package:yonetim/ekranlar/kotuye_kullanim.dart';
import 'package:yonetim/ekranlar/kurulum.dart';
import 'package:yonetim/ekranlar/oltalama.dart';
import 'package:yonetim/ekranlar/tehdit.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  final simdi = DateTime.now().toUtc().toIso8601String();

  Map<String, Object?> tehditYanitlari() => {
    'GET /api/v1/threat/summary': {
      'today': {'spoof': 2},
      'week': {'spoof': 7, 'dmarc': 3},
      'rejected_week': 1,
    },
    'GET /api/v1/threat/detections': {
      'items': [
        {
          'id': 1,
          'at': simdi,
          'queue_id': 'Q1',
          'organization_id': 'o1',
          'organization_name': 'Örnek AŞ',
          'kind': 'spoof',
          'rule': 'own_domain_spoof',
          'score': 6.0,
          'action': 'junk',
          'detail': 'Kendi alan adını taklit',
          'banner': '',
          'mail_from': 'kotu@ornek.test',
          'header_from': 'patron@ornek.test',
          'remote_ip': '192.0.2.1',
        },
      ],
      'total': 1,
    },
  };

  testWidgets('Tehdit Koruması: tespitler geniş ekranda tablo olarak', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    kullaniciAyarla();
    Uyg.api = SahteApi(tehditYanitlari());
    await t.pumpWidget(testUygulamasi(const TehditEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Tehdit Koruması'), findsOneWidget);
    expect(find.text('own_domain_spoof'), findsOneWidget);
    expect(find.text('patron@ornek.test'), findsOneWidget);
    expect(find.text('IP / ASN itibarı'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('Tehdit Koruması: telefonda kart, müşteri yöneticisi için süper sekmeler yok', (t) async {
    ekranBoyutu(t, const Size(400, 850));
    kullaniciAyarla(rol: 'org_admin');
    Uyg.api = SahteApi(tehditYanitlari());
    await t.pumpWidget(testUygulamasi(const TehditEkrani()));
    await t.pumpAndSettle();
    expect(find.text('own_domain_spoof'), findsOneWidget);
    expect(find.text('ZAMAN'), findsNothing);
    expect(find.text('Ayarlar'), findsNothing);
  });

  testWidgets('DLP: politikalar ve şablonlar', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/dlp/meta': {
        'detectors': [
          {'key': 'tckn', 'name': 'T.C. kimlik no', 'check': 'sağlama'},
        ],
        'templates': [
          {'key': 'kvkk', 'name': 'KVKK', 'description': 'T.C. kimlik numaraları', 'detectors': ['tckn'], 'threshold': 1, 'action': 'warn'},
        ],
        'limits': {'pdf': 'PDF sınırı'},
      },
      'GET /api/v1/dlp/policies': {
        'items': [
          {
            'id': 'p1',
            'name': 'Kimlik koruması',
            'template': 'kvkk',
            'enabled': true,
            'detectors': ['tckn'],
            'custom_rules': [],
            'email_list_min': 20,
            'scope': 'external',
            'threshold': 2,
            'action': 'block',
            'except_senders': [],
            'except_domains': [],
            'updated_at': simdi,
          },
        ],
      },
    });
    await t.pumpWidget(testUygulamasi(const DlpEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kimlik koruması'), findsOneWidget);
    expect(find.text('Şablondan ekle'), findsOneWidget);
    expect(find.text('Engelle'), findsOneWidget);
    expect(find.text('Yeni politika'), findsOneWidget);
  });

  testWidgets('Kötüye kullanım: özet ve olaylar', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/abuse/summary': {'open': 4, 'notify': 1, 'blocked_mailboxes': 2, 'held': 9, 'dlp_held': 0},
      'GET /api/v1/abuse/incidents': {
        'items': [
          {
            'id': 'i1',
            'organization_name': 'Örnek AŞ',
            'mailbox_id': 'm1',
            'mailbox': 'ali@ornek.test',
            'score': 80,
            'signals': [],
            'actions': ['log', 'block'],
            'status': 'open',
            'messages': 120,
            'created_at': simdi,
            'updated_at': simdi,
            'send_blocked': true,
            'password_reset_required': false,
            'held': 3,
          },
        ],
        'can_manage': true,
      },
    });
    await t.pumpWidget(testUygulamasi(const KotuyeKullanimEkrani()));
    await t.pumpAndSettle();
    expect(find.text('ali@ornek.test'), findsOneWidget);
    expect(find.text('Gönderim durduruldu'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('1 tanesi bildirim eşiğinde'), findsOneWidget);
  });

  testWidgets('Oltalama: müşteri yöneticisi kampanyaları görür', (t) async {
    ekranBoyutu(t, const Size(1400, 900));
    kullaniciAyarla(rol: 'org_admin');
    Uyg.ben.value = {...?Uyg.ben.value, 'organization_id': 'o1'};
    Uyg.api = SahteApi({
      'GET /api/v1/phishing/overview': {
        'organization': {'id': 'o1', 'name': 'Örnek AŞ', 'feature_enabled': true},
        'campaigns': 1,
        'active_campaigns': 1,
        'active_mailboxes': 12,
        'new_user_reports': 2,
        'placeholders': [],
      },
      'GET /api/v1/phishing/campaigns': {
        'items': [
          {
            'id': 'c1',
            'name': 'Kasım tatbikatı',
            'template_name': 'Şifre süresi doluyor',
            'landing': 'login',
            'track_opens': false,
            'target_mode': 'all',
            'start_at': simdi,
            'spread_hours': 0,
            'status': 'running',
            'funnel': {'targets': 10, 'delivered': 10, 'clicked': 3, 'submitted': 1, 'reported': 2},
          },
        ],
      },
    });
    await t.pumpWidget(testUygulamasi(const OltalamaEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kasım tatbikatı'), findsOneWidget);
    expect(find.text('Sürüyor'), findsOneWidget);
    expect(find.text('3 (%30)'), findsOneWidget);
    expect(find.text('Yeni kampanya'), findsOneWidget);
  });

  testWidgets('Kurulum: ilerleme, adımlar ve kontrol listesi', (t) async {
    ekranBoyutu(t, const Size(1400, 1000));
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/platform-setup': {
        'hostname': 'mx.ornek.test',
        'ips': ['192.0.2.10'],
        'domain': 'ornek.test',
        'domain_configured': true,
        'domain_default': 'ornek.test',
        'mta_sts_mode': 'testing',
        'dmarc_report': 'dmarc@ornek.test',
        'tls_rpt_report': 'tls@ornek.test',
        'dkim': {'key': null, 'hosted_domain': false, 'can_generate': true},
        'run': {
          'id': 5,
          'checked_at': simdi,
          'trigger': 'manual',
          'ok': 1,
          'total': 2,
          'checks': [
            {'id': 'mx', 'step': 1, 'label': 'MX kaydı', 'status': 'ok', 'detail': 'Doğru'},
            {
              'id': 'spf',
              'step': 1,
              'label': 'SPF kaydı',
              'status': 'missing',
              'detail': 'Bulunamadı',
              'records': [
                {'host': 'ornek.test', 'type': 'TXT', 'value': 'v=spf1 mx -all', 'provider': 'dns'},
              ],
            },
          ],
        },
        'steps': [
          {'step': 1, 'title': 'Temel DNS', 'ok': 1, 'total': 2, 'status': 'missing'},
        ],
        'checklist': [
          {'id': 'B1', 'title': 'Yedekleme denendi', 'status': 'info', 'manual': true, 'done': false},
        ],
        'checklist_doc': 'docs/guvenlik.md',
        'changes': [],
        'schedule': 'Saatte bir otomatik',
        'dns_note': 'DNS değişiklikleri yayılabilir.',
        'notes': [],
      },
    });
    await t.pumpWidget(testUygulamasi(const KurulumEkrani()));
    await t.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Temel DNS'), findsOneWidget);
    expect(find.text('SPF kaydı'), findsOneWidget);
    expect(find.text('v=spf1 mx -all'), findsOneWidget);
    expect(find.textContaining('Yedekleme denendi'), findsOneWidget);
    expect(find.text('Tümünü doğrula'), findsOneWidget);
  });
}
