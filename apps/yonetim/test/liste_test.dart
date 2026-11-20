import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/alan_adlari.dart';
import 'package:yonetim/ekranlar/alarmlar.dart';
import 'package:yonetim/ekranlar/denetim_kayitlari.dart';
import 'package:yonetim/ekranlar/karantina.dart';
import 'package:yonetim/ekranlar/kuyruk.dart';
import 'package:yonetim/ekranlar/sunucu_erisimi.dart';
import 'package:yonetim/ekranlar/takma_adlar.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

final _simdi = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _alan(String id, String ad, {String mod = 'hosting', String durum = 'active'}) => {
  'id': id,
  'name': ad,
  'unicode_name': ad,
  'mode': mod,
  'status': durum,
  'organization_id': 'o1',
  'organization_name': 'Örnek Ticaret',
  'verification_txt': 'bogamail-verify=abc',
  'mailbox_count': 4,
  'created_at': _simdi,
  'dns_check': 'ok',
};

/// Ekranı söker (zamanlayıcılar ve yükleyiciler kapanır).
Future<void> _kapat(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('Alan adları: sıralanabilir tablo ve telefon kartları', (t) async {
    final api = SahteApi({
      'GET /api/v1/domains': {
        'items': [_alan('d1', 'ornek.com.tr'), _alan('d2', 'gecit.test', mod: 'gateway', durum: 'pending')],
        'total': 2,
      },
    });
    Uyg.api = api;
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 900));
    await t.pumpWidget(testUygulamasi(const AlanAdlariEkrani()));
    await t.pumpAndSettle();
    expect(find.text('ALAN ADI'), findsOneWidget);
    expect(find.text('ornek.com.tr'), findsOneWidget);
    expect(find.text('Örnek Ticaret'), findsWidgets);
    expect(find.text('Alan adı ekle'), findsOneWidget);
    await t.tap(find.text('ALAN ADI'));
    await t.pumpAndSettle();
    expect(api.istekler.last.$4?['sort'], 'name');
    expect(api.istekler.last.$4?['order'], 'asc');

    ekranBoyutu(t, const Size(400, 850));
    await t.pumpWidget(testUygulamasi(const AlanAdlariEkrani(key: ValueKey('tel'))));
    await t.pumpAndSettle();
    expect(find.text('gecit.test'), findsOneWidget);
    expect(find.text('ALAN ADI'), findsNothing);
    await _kapat(t);
  });

  testWidgets('Takma adlar: tablo ve sekmeler', (t) async {
    Uyg.api = SahteApi({
      'GET /api/v1/aliases': {
        'items': [
          {
            'id': 'a1',
            'address': 'info@ornek.test',
            'domain_id': 'd1',
            'organization_name': 'Örnek Ticaret',
            'kind': 'alias',
            'name': '',
            'destinations': ['ali@ornek.test', 'ayse@ornek.test'],
            'send_policy': 'anyone',
            'enabled': true,
          },
        ],
        'external_forwarding': false,
      },
    });
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 900));
    await t.pumpWidget(testUygulamasi(const TakmaAdlarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('info@ornek.test'), findsOneWidget);
    expect(find.text('ali@ornek.test, ayse@ornek.test'), findsOneWidget);
    expect(find.text('Catch-all'), findsOneWidget);
    expect(find.textContaining('Dış adreslere yönlendirme kapalı'), findsOneWidget);
    await _kapat(t);
  });

  testWidgets('Kuyruk: özet kutuları ve kayıtlar', (t) async {
    Uyg.api = SahteApi({
      'GET /api/v1/queue/manager': {
        'enabled': true,
        'scoped': false,
        'can_manage': true,
        'matched': 1,
        'stats': {'total': 1, 'bytes': 2048, 'pending': 0, 'deferred': 1, 'held': 0, 'inbound': 0, 'outbound': 1, 'oldest_age_seconds': 600, 'error_classes': []},
        'error_class_labels': [
          {'key': 'greylist', 'label': 'Gri liste'},
        ],
        'groups': [],
        'items': [
          {
            'queue_id': 'Q123',
            'direction': 'outbound',
            'from': 'gonderen@ornek.test',
            'recipients': ['alici@uzak.test'],
            'received_at': _simdi,
            'size_bytes': 2048,
            'status': 'deferred',
            'attempts': 2,
            'last_error': '451 tekrar deneyin',
            'error_class': 'greylist',
            'age_seconds': 600,
          },
        ],
      },
    });
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 1000));
    await t.pumpWidget(testUygulamasi(const KuyrukEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kuyrukta'), findsOneWidget);
    expect(find.text('gonderen@ornek.test'), findsOneWidget);
    expect(find.text('Gri liste: 451 tekrar deneyin'), findsOneWidget);
    expect(find.text('Bekletilenler'), findsOneWidget);
    await _kapat(t);
  });

  testWidgets('Karantina: tablo', (t) async {
    Uyg.api = SahteApi({
      'GET /api/v1/quarantine': {
        'items': [
          {
            'id': 'k1',
            'queue_id': 'Q1',
            'direction': 'inbound',
            'organization_name': 'Örnek Ticaret',
            'mail_from': 'kotu@uzak.test',
            'header_from': 'Kötü <kotu@uzak.test>',
            'recipients': ['ali@ornek.test'],
            'subject': 'Fatura ektedir',
            'reason': 'virus',
            'status': 'held',
            'size_bytes': 1000,
            'findings': [
              {'kind': 'virus', 'name': 'Eicar-Test-Signature'},
            ],
            'created_at': _simdi,
          },
        ],
        'summary': {'held': 1, 'virus_7d': 1, 'blocked_7d': 0},
        'scanner': {'configured': true, 'status': 'ok'},
      },
    });
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 900));
    await t.pumpWidget(testUygulamasi(const KarantinaEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Fatura ektedir'), findsOneWidget);
    expect(find.text('Çalışıyor'), findsOneWidget);
    expect(find.text('KONU / GÖNDEREN'), findsOneWidget);
    await _kapat(t);
  });

  testWidgets('Uyarılar: etkin uyarılar ve kurallar sekmesi', (t) async {
    Uyg.api = SahteApi({
      'GET /api/v1/alerts/kinds': {
        'items': [
          {'key': 'queue_size', 'label': 'Kuyruk boyutu', 'unit': 'ileti', 'default_threshold': 500, 'below': false, 'org_scoped': true, 'hint': ''},
        ],
        'outbound_mode': 'direct',
        'external_email': true,
      },
      'GET /api/v1/alerts/active': {
        'items': [
          {'rule_id': 'r1', 'name': 'Kuyruk şişti', 'kind': 'queue_size', 'severity': 'critical', 'subject': '', 'label': '', 'value': 900, 'threshold': 500, 'since': _simdi},
        ],
      },
      'GET /api/v1/alerts/history': {'items': []},
      'GET /api/v1/alerts/channels': {
        'items': [
          {'id': 'c1', 'organization_id': null, 'organization_name': '', 'kind': 'panel', 'name': 'Panel zili', 'config': {}, 'enabled': true},
        ],
      },
      'GET /api/v1/alerts/rules': {
        'items': [
          {
            'id': 'r1',
            'organization_id': null,
            'organization_name': '',
            'kind': 'queue_size',
            'name': 'Büyük kuyruk',
            'threshold': 500,
            'severity': 'critical',
            'cooldown_minutes': 60,
            'notify_resolved': true,
            'channel_ids': ['c1'],
            'enabled': true,
            'firing': 1,
          },
        ],
      },
    });
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 900));
    await t.pumpWidget(testUygulamasi(const AlarmlarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kuyruk şişti'), findsOneWidget);
    await t.tap(find.text('Kurallar'));
    await t.pumpAndSettle();
    expect(find.text('Büyük kuyruk'), findsOneWidget);
    expect(find.text('≥ 500 ileti'), findsOneWidget);
    expect(find.text('Yeni kural'), findsOneWidget);
    await _kapat(t);
  });

  testWidgets('Denetim kayıtları: tablo ve zaman sıralaması', (t) async {
    final api = SahteApi({
      'GET /api/v1/audit-logs': {
        'items': [
          {'id': 1, 'at': _simdi, 'actor_email': 'yonetici@ornek.test', 'action': 'domain.create', 'target_type': 'domain', 'target_id': 'd1', 'organization_name': 'Örnek Ticaret', 'ip': '203.0.113.5', 'details': {'name': 'ornek.test'}},
        ],
        'total': 1,
      },
    });
    Uyg.api = api;
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 900));
    await t.pumpWidget(testUygulamasi(const DenetimKayitlariEkrani()));
    await t.pumpAndSettle();
    expect(find.text('yonetici@ornek.test'), findsOneWidget);
    expect(find.text('203.0.113.5'), findsOneWidget);
    expect(api.istekler.last.$4?['order'], 'desc');
    await t.tap(find.text('ZAMAN'));
    await t.pumpAndSettle();
    expect(api.istekler.last.$4?['order'], 'asc');
    await _kapat(t);
  });

  testWidgets('Sunucu erişimi: genel bakış ve SSH denemeleri tablosu', (t) async {
    Uyg.api = SahteApi({
      'GET /api/v1/host-security': {
        'my_ip': '198.51.100.7',
        'my_ip_ssh_allowed': true,
        'ssh_allow': [
          {'ip': '198.51.100.7'},
        ],
        'bans': [
          {'ip': '203.0.113.9', 'reason': 'SSH kaba kuvvet', 'auto': true, 'managed': true, 'created_at': _simdi},
        ],
        'drop_log': true,
        'autoban': {'enabled': true, 'threshold': 20, 'window_minutes': 10, 'ban_hours': 24},
        'sources': [
          {'ip': '192.0.2.44', 'dropped': 30, 'failed': 5, 'invalid_user': 2, 'accepted': 0, 'users': ['root'], 'last_seen': _simdi},
        ],
        'totals': {'accepted': 3, 'failed': 5, 'invalid_user': 2, 'dropped': 30},
        'window_days': 7,
      },
    });
    kullaniciAyarla();
    ekranBoyutu(t, const Size(1400, 1600));
    await t.pumpWidget(testUygulamasi(const SunucuErisimiEkrani()));
    await t.pumpAndSettle();
    expect(find.text('SSH izinli adres'), findsOneWidget);
    expect(find.text('203.0.113.9'), findsOneWidget);
    await t.tap(find.text('SSH denemeleri (1)'));
    await t.pumpAndSettle();
    expect(find.text('IP ADRESİ'), findsOneWidget);
    expect(find.text('root'), findsOneWidget);
    await _kapat(t);
  });
}
