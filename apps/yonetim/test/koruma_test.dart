import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/dmarc.dart';
import 'package:yonetim/ekranlar/greylist.dart';
import 'package:yonetim/ekranlar/saldiri_haritasi.dart';
import 'package:yonetim/ekranlar/sandbox.dart';
import 'package:yonetim/ekranlar/smtp_trafigi.dart';
import 'package:yonetim/ekranlar/spam.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  final simdi = DateTime.now().toUtc().toIso8601String();
  const genis = Size(1400, 1000), dar = Size(400, 860);

  Future<SahteApi> kur(WidgetTester t, Widget ekran, Map<String, Object?> yanitlar, {Size boyut = genis, String rol = 'super_admin'}) async {
    ekranBoyutu(t, boyut);
    kullaniciAyarla(rol: rol);
    final api = SahteApi(yanitlar);
    Uyg.api = api;
    await t.pumpWidget(testUygulamasi(ekran));
    await t.pumpAndSettle();
    return api;
  }

  final sandboxlar = {
    'items': [
      {
        'id': 's1',
        'organization_id': 'o1',
        'organization_name': 'Örnek AŞ',
        'name': 'Staging uygulaması',
        'smtp_username': 'sbx_ornek',
        'api_token_prefix': 'sbxt_ab',
        'retention_days': 7,
        'max_messages': 200,
        'quota_bytes': 52428800,
        'created_at': simdi,
        'last_message_at': simdi,
        'messages': 12,
        'used_bytes': 1048576,
        'feature': true,
      },
    ],
    'smtp': {
      'host': 'smtp.ornek.test',
      'ports': [
        {'port': 587, 'security': 'STARTTLS'},
        {'port': 465, 'security': 'TLS'},
      ],
    },
    'submission_enabled': true,
  };

  testWidgets('Test Sandbox: geniş tablo ve SMTP bilgisi', (t) async {
    await kur(t, const SandboxEkrani(), {'GET /api/v1/sandboxes': sandboxlar});
    expect(find.text('Staging uygulaması'), findsOneWidget);
    expect(find.text('Örnek AŞ'), findsOneWidget);
    expect(find.textContaining('smtp.ornek.test'), findsOneWidget);
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(find.text('Yeni sandbox'), findsOneWidget);
  });

  testWidgets('Test Sandbox: telefonda kart', (t) async {
    await kur(t, const SandboxEkrani(), {'GET /api/v1/sandboxes': sandboxlar}, boyut: dar);
    expect(find.text('Staging uygulaması'), findsOneWidget);
    expect(find.text('SANDBOX'), findsNothing);
    expect(find.text('12 / 200'), findsOneWidget);
  });

  testWidgets('Test Sandbox: ileti ayrıntısı', (t) async {
    final ileti = {
      'id': 'm1',
      'received_at': simdi,
      'mail_from': 'app@ornek.test',
      'rcpts': ['kisi@ornek.test'],
      'subject': 'Hoş geldiniz',
      'from_header': 'Uygulama <app@ornek.test>',
      'size_bytes': 2048,
      'tls': true,
      'remote_ip': '192.0.2.10',
      'attachments': 0,
      'analysis': {
        'size_bytes': 2048,
        'attachments': 0,
        'html': {'has_html': true, 'html_bytes': 1500, 'images': 1, 'links': 2},
        'dkim': {'signed': false},
        'spam': {'score': 1.5, 'threshold': 8, 'refused': false, 'findings': []},
        'issues': [
          {'level': 'warn', 'code': 'alt', 'text': 'Resimde alt metni yok'},
        ],
      },
    };
    await kur(t, SandboxIletileri(kutu: SandboxKutusu(Map<String, dynamic>.from((sandboxlar['items'] as List).first as Map))), {
      'GET /api/v1/sandboxes/s1/messages': {
        'items': [ileti],
        'total': 1,
      },
      'GET /api/v1/sandboxes/s1/messages/m1': {
        'message': ileti,
        'view': {'html': '<p>Merhaba dünya</p>', 'text': 'Merhaba dünya', 'attachments': []},
        'headers': [
          {'name': 'Subject', 'value': 'Hoş geldiniz'},
        ],
      },
    });
    expect(find.text('Hoş geldiniz'), findsOneWidget);
    await t.tap(find.text('Hoş geldiniz'));
    await t.pumpAndSettle();
    expect(find.text('Resimde alt metni yok'), findsOneWidget);
    expect(find.text('1.5 / 8'), findsOneWidget);
    expect(find.text('Merhaba dünya'), findsOneWidget);
  });

  testWidgets('DMARC Merkezi: alan adları ve ayrıntı', (t) async {
    await kur(t, const DmarcEkrani(), {
      'GET /api/v1/dmarc/domains': {
        'items': [
          {
            'id': 'd1',
            'name': 'ornek.com',
            'mode': 'hosting',
            'organization_name': 'Örnek AŞ',
            'feature_enabled': true,
            'messages_30d': 1200,
            'pass_rate_30d': 98.5,
            'last_report_at': simdi,
            'score': 92,
          },
        ],
      },
      'GET /api/v1/dmarc/domains/d1': {
        'domain': {'id': 'd1', 'name': 'ornek.com', 'organization_name': 'Örnek AŞ'},
        'totals': {'messages': 100, 'pass': 95, 'dkim_aligned': 95, 'spf_aligned': 90, 'quarantined': 1, 'rejected': 0},
        'pass_rate': 95,
        'series': [
          {'day': '2026-11-19', 'messages': 50, 'pass': 48},
          {'day': '2026-11-20', 'messages': 50, 'pass': 47},
        ],
        'sources': [
          {
            'ip': '198.51.100.7',
            'ptr': ['mail.saglayici.test'],
            'ptr_resolved': true,
            'class': 'unknown',
            'verdict': 'unauthorized',
            'messages': 5,
            'pass': 0,
            'pass_rate': 0,
          },
        ],
        'reporters': [],
        'reports': [],
        'unauthorized_sources': 1,
        'unauthorized_messages': 5,
        'rua_address': 'dmarc+abc@ornek.test',
        'rua_published': true,
        'recommendation': {'current': 'none', 'next': 'quarantine', 'ready': false, 'reason': 'Daha fazla veri gerekli', 'steps': []},
        'score': null,
        'score_checked_at': simdi,
        'smtp_listening': true,
      },
      'GET /api/v1/dmarc/senders': {'items': []},
    });
    expect(find.text('ornek.com'), findsOneWidget);
    expect(find.text('%98,5'), findsOneWidget);
    expect(find.text('92/100'), findsOneWidget);
    await t.tap(find.text('ornek.com'));
    await t.pumpAndSettle();
    expect(find.text('198.51.100.7'), findsOneWidget);
    expect(find.text('Yetkisiz gönderici'), findsWidgets);
    expect(find.text('Politika yol haritası'), findsOneWidget);
  });

  testWidgets('SMTP Trafiği: göstergeler ve listeler', (t) async {
    await kur(t, const SmtpTrafigiEkrani(), {
      'GET /api/v1/smtp-traffic': {
        'hours': 24,
        'bucket_minutes': 24,
        'series': [
          {'t': '2026-11-20T10:00:00Z', 'mx': 48, 'submission': 24, 'tls': 40, 'auth_fail': 2},
          {'t': '2026-11-20T10:24:00Z', 'mx': 72, 'submission': 24, 'tls': 50, 'auth_fail': 0},
        ],
        'listeners': [
          {'listener': 'mx', 'connections': 1000, 'tls': 900, 'auth_ok': 0, 'auth_fail': 0, 'no_mail': 50, 'peak_per_minute': 12},
          {'listener': 'submission', 'connections': 200, 'tls': 200, 'auth_ok': 190, 'auth_fail': 10, 'no_mail': 0, 'peak_per_minute': 4},
        ],
        'inbound_messages': 800,
        'inbound_tls_messages': 760,
        'top_helo': [
          {'key': 'mx.google.com', 'count': 300},
        ],
        'top_ip': [],
        'top_asn': [
          {'key': '15169', 'label': 'GOOGLE', 'count': 300},
        ],
        'our_classes': [],
        'our_codes': [
          {'key': '550', 'label': 'Kullanıcı yok', 'count': 7},
        ],
        'remote_codes': [],
        'remote_hosts': [],
      },
    });
    expect(find.text('1.200'), findsOneWidget);
    expect(find.text('%92'), findsOneWidget);
    expect(find.text('MX (25)'), findsOneWidget);
    expect(find.text('mx.google.com'), findsOneWidget);
    expect(find.text('550'), findsOneWidget);
  });

  testWidgets('SMTP Trafiği: müşteriye kapalı', (t) async {
    await kur(t, const SmtpTrafigiEkrani(), {}, rol: 'org_admin');
    expect(find.textContaining('yalnızca platform yöneticilerine'), findsOneWidget);
  });

  testWidgets('Spam Güvenliği: özet ve listeler (telefon)', (t) async {
    await kur(t, const SpamEkrani(), {
      'GET /api/v1/spam/summary': {
        'scanned_today': 5400,
        'junked_today': 40,
        'rejected_today': 12,
        'blocked_by_list_today': 3,
        'top_rules': [
          {'rule': 'DNSBL_SPAMHAUS', 'count': 9},
        ],
        'recent': [
          {
            'id': 1,
            'at': simdi,
            'mail_from': 'kotu@spam.test',
            'rcpt': 'kisi@ornek.com',
            'spam_score': 12.5,
            'spam_action': 'reject',
            'spam_rules': ['DNSBL_SPAMHAUS'],
          },
        ],
      },
      'GET /api/v1/spam/lists': {
        'items': [
          {
            'id': 'l1',
            'organization_id': null,
            'organization_name': null,
            'kind': 'block',
            'type': 'domain',
            'value': 'spam.test',
            'created_by': 'yonetici@ornek.test',
            'created_at': simdi,
          },
        ],
      },
    }, boyut: dar);
    expect(find.text('5.400'), findsOneWidget);
    expect(find.text('Ret 12.5'), findsOneWidget);
    await t.tap(find.text('İzin ve engel listeleri'));
    await t.pumpAndSettle();
    expect(find.text('spam.test'), findsOneWidget);
    expect(find.text('Engel'), findsWidgets);
  });

  testWidgets('Greylisting: istatistikler ve platform ayarı', (t) async {
    final ayar = {
      'enabled': true,
      'mode': 'suspicious',
      'score': 4,
      'delay_seconds': 300,
      'pass_hours': 12,
      'whitelist_after': 3,
      'whitelist_days': 30,
      'provider_ptr': ['google.com'],
      'provider_asn': [15169],
    };
    await kur(t, const GreylistEkrani(), {
      'GET /api/v1/greylist/stats': {
        'hours': 24,
        'delayed': 320,
        'passed': 210,
        'never_retried': 90,
        'pending': 20,
        'median_delay_s': 420,
        'timeline': [
          {'hour': '2026-11-20T10:00:00Z', 'delayed': 20, 'passed': 12},
        ],
        'top_never_retried': [
          {'net': '203.0.113.0/24', 'country': 'CN', 'count': 40},
        ],
        'settings': ayar,
      },
      'GET /api/v1/security2/settings': {'greylist': ayar},
    });
    expect(find.text('320'), findsOneWidget);
    expect(find.text('ortanca bekleme 7 dk'), findsOneWidget);
    expect(find.text('203.0.113.0/24  CN'), findsOneWidget);
    expect(find.text('Platform ayarı'), findsOneWidget);
    expect(find.text('Greylisting açık'), findsOneWidget);
  });

  testWidgets('Saldırı Haritası: ülke ızgarası ve sıralamalar', (t) async {
    await kur(t, const SaldiriHaritasiEkrani(), {
      'GET /api/v1/attacks': {
        'hours': 24,
        'total': 150,
        'by_country': [
          {'key': 'CN', 'count': 90},
          {'key': 'RU', 'count': 60},
        ],
        'by_kind': [
          {'key': 'spam', 'count': 100},
          {'key': 'phishing', 'count': 50},
        ],
        'top_asn': [
          {'key': '4134', 'label': 'CHINANET', 'count': 80},
        ],
        'top_ip': [],
        'top_target': [
          {'key': 'kisi@ornek.com', 'count': 30},
        ],
        'timeline': [
          {
            'hour': simdi,
            'total': 10,
            'kinds': {'spam': 7, 'phishing': 3},
          },
        ],
        'recent': [
          {'at': simdi, 'kind': 'phishing', 'ip': '203.0.113.9', 'asn': 4134, 'as_name': 'CHINANET', 'country': 'CN', 'target': 'kisi@ornek.com'},
        ],
      },
    });
    expect(find.text('CN · Çin'), findsOneWidget);
    expect(find.text('Rusya'), findsNothing);
    expect(find.text('RU · Rusya'), findsOneWidget);
    expect(find.text('AS4134'), findsNothing);
    expect(find.textContaining('CHINANET'), findsWidgets);
    expect(find.text('203.0.113.9 · Çin'), findsOneWidget);
  });
}
