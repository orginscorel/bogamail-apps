import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/depolama.dart';
import 'package:yonetim/ekranlar/ip_yonetimi.dart';
import 'package:yonetim/ekranlar/itibar.dart';
import 'package:yonetim/ekranlar/izleme.dart';
import 'package:yonetim/ekranlar/kiraci.dart';
import 'package:yonetim/ekranlar/yedekleme.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

const _genis = Size(1500, 1000);
const _telefon = Size(400, 860);

final _simdi = DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _butunluk({String durum = 'problems'}) => {
  'schedule': {'enabled': true, 'weekday': 0, 'time': '04:00', 'timezone': 'Europe/Istanbul', 'read_mb_per_sec': 50},
  'next_run_at': _simdi,
  'running': null,
  'last': {
    'id': 's1',
    'trigger': 'scheduled',
    'status': durum,
    'started_at': _simdi,
    'finished_at': _simdi,
    'requested_by': '',
    'messages_checked': 1200,
    'bytes_checked': 1048576,
    'blob_files': 1201,
    'missing_blobs': 2,
    'hash_mismatches': 0,
    'size_mismatches': 0,
    'orphan_blobs': 1,
    'manifest_run': '',
    'manifest_status': 'ok',
    'manifest_files': 4,
    'manifest_problems': 0,
    'problems': [
      {'kind': 'missing_blob', 'path': 'ab/cd/ef.zst', 'message_id': 'm1'},
    ],
    'problems_truncated': false,
    'error': '',
    'duration_seconds': 12.4,
  },
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => kullaniciAyarla());

  testWidgets('İzleme: bileşenler, uyarılar ve bütünlük uyarısı', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/health': {
        'components': [
          {'name': 'postgresql', 'status': 'ok', 'latency_ms': 1.25},
          {'name': 'redis', 'status': 'down', 'detail': 'unreachable'},
        ],
        'checked_at': _simdi,
      },
      'GET /api/v1/stats/overview': {'messages_received_today': 42, 'delivered_today': 40, 'rejected_messages': 1, 'failed_today': 0},
      'GET /api/v1/stats/traffic': {'items': []},
      'GET /api/v1/monitor/alerts': {
        'items': [
          {'id': 1, 'at': _simdi, 'target': 'ornek.com', 'label': 'MX kaydı', 'prev_status': 'ok', 'status': 'fail', 'current_status': 'fail', 'detail': 'MX yok'},
        ],
      },
      'GET /api/v1/gateway/alerts': {'items': []},
      'GET /api/v1/backup/integrity': _butunluk(),
    });
    await t.pumpWidget(testUygulamasi(const IzlemeEkrani()));
    await t.pumpAndSettle();
    expect(find.textContaining('Sorunlu bileşen: Önbellek (Redis)'), findsOneWidget);
    expect(find.text('Veritabanı (PostgreSQL)'), findsOneWidget);
    expect(find.text('1,3 ms'), findsOneWidget);
    expect(find.text('MX kaydı'), findsOneWidget);
    expect(find.textContaining('Bütünlük taraması sorun buldu'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('Yedekleme: zamanlama, çalıştırmalar ve bütünlük taraması', (t) async {
    ekranBoyutu(t, _genis);
    final api = SahteApi({
      'GET /api/v1/backup/status': {
        'database': {'name': 'bogamail', 'size_bytes': 52428800, 'version': '16.2'},
        'store': {'messages': 1200, 'bytes': 104857600, 'mailboxes': 12},
        'paths': {'store': null, 'spool': null, 'quarantine': null},
        'store_dir': '/var/lib/bogamail/store',
        'spool_dir': '/var/spool/bogamail',
        'quarantine_dir': '/var/lib/bogamail/q',
        'last_export_at': null,
        'scheduled_backup': true,
        'backup': {
          'schedule': {'enabled': true, 'time': '03:00', 'timezone': 'Europe/Istanbul', 'retention_days': 7},
          'next_run_at': _simdi,
          'last_run': null,
          'last_success': null,
          'running': false,
          'dir': '/var/backups/bogamail',
          'kept_runs': 3,
          'kept_bytes': 314572800,
          'disk_total_bytes': 0,
          'disk_free_bytes': 0,
          'disk_stat_ok': false,
          'snapshot_mailboxes': 4,
        },
      },
      'GET /api/v1/backup/runs': {
        'items': [
          {
            'id': 'r1',
            'trigger': 'manual',
            'status': 'ok',
            'started_at': _simdi,
            'finished_at': _simdi,
            'db_bytes': 1024,
            'store_bytes': 2048,
            'mailbox_bytes': 0,
            'total_bytes': 3072,
            'mailboxes': 0,
            'messages': 5,
            'error': '',
            'requested_by': 'yonetici@ornek.test',
            'duration_seconds': 3,
          },
        ],
      },
      'GET /api/v1/backup/integrity': _butunluk(),
      'POST /api/v1/backup/integrity/scan': {'id': 's2'},
    });
    Uyg.api = api;
    await t.pumpWidget(testUygulamasi(const YedeklemeEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Zamanlama'), findsOneWidget);
    expect(find.text('Şimdi yedekle'), findsOneWidget);
    expect(find.text('Başarılı'), findsOneWidget);
    expect(find.text('Bütünlük taraması'), findsOneWidget);
    expect(find.text('ab/cd/ef.zst'), findsOneWidget);
    expect(find.text('Veritabanı (PostgreSQL)'), findsOneWidget);
    await t.tap(find.text('Şimdi tara'));
    await t.pumpAndSettle();
    expect(api.istendi('POST', '/api/v1/backup/integrity/scan'), isTrue);
  });

  testWidgets('Depolama: kullanım, verimlilik ve otomatik temizleme', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/storage': {
        'totals': {'mailboxes': 12, 'messages': 3400, 'used_bytes': 1073741824, 'allocated_bytes': 10737418240, 'over_quota': 1, 'above_90_percent': 2},
        'top_mailboxes': [
          {'id': 'm1', 'address': 'ali@ornek.com', 'organization_name': 'Örnek AŞ', 'used_bytes': 1048576, 'quota_bytes': 2097152, 'messages': 30},
        ],
        'organizations': [
          {'id': 'o1', 'name': 'Örnek AŞ', 'used_bytes': 1048576, 'allocated_bytes': 2097152, 'plan_quota_bytes': null},
        ],
        'disks': {'store': null, 'spool': null},
      },
      'GET /api/v1/storage/retention': {
        'platform': {'trash_days': 30, 'junk_days': 30},
        'organizations': [
          {'id': 'o1', 'name': 'Örnek AŞ', 'trash_days': 7, 'junk_days': null},
        ],
        'can_edit_platform': true,
        'enabled': true,
      },
      'GET /api/v1/storage/efficiency': {
        'config': {'Compress': true, 'Dedup': true, 'Migrate': true, 'MigrateRate': 10, 'Retention': true},
        'measuring': false,
        'latest': null,
        'history': [],
        'growth': [],
        'formats': {'legacy': 0, 'compressed': 10, 'plain': 2},
        'disk_alert_threshold': 90,
        'cleanup_runs': [],
      },
    });
    await t.pumpWidget(testUygulamasi(const DepolamaEkrani()));
    await t.pumpAndSettle();
    expect(find.text('Kotası dolu'), findsOneWidget);
    expect(find.text('ali@ornek.com'), findsOneWidget);
    expect(find.text('Depolama verimliliği'), findsOneWidget);
    expect(find.text('Otomatik temizleme'), findsOneWidget);
    expect(find.text('Çöp 7 gün · Spam 30 gün (platform)'), findsOneWidget);
  });

  Map<String, dynamic> kiraciYanitlari() => {
    'GET /api/v1/tenants/isolation': {
      'items': [
        {
          'id': 'o1',
          'name': 'Örnek AŞ',
          'status': 'active',
          'plan_name': 'Business',
          'settings': {'queue_weight': 1, 'ip_pool': null, 'paused': true, 'paused_reason': 'spam', 'auto_throttle': true},
          'effective': {'msgs_per_minute': 120, 'rcpts_per_hour': 3000, 'max_concurrent': 4, 'queue_weight': 1, 'paused': true, 'throttled': false},
          'finished_24h': 10,
          'hard_24h': 0,
          'bounce_rate': 0,
          'risk': 12,
          'sent_last_hour': 3,
          'queued': 5,
          'held': 0,
          'running': 0,
          'dedicated_ips': 0,
        },
      ],
      'defaults': {
        'msgs_per_minute': 120,
        'rcpts_per_hour': 3000,
        'max_concurrent': 4,
        'throttle_bounce_rate': 10,
        'throttle_risk': 75,
        'throttle_minutes': 60,
        'throttle_factor': 0.2,
        'min_finished': 50,
      },
      'queue_enabled': true,
    },
  };

  testWidgets('Kiracı izolasyonu: geniş tablo', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi(kiraciYanitlari());
    await t.pumpWidget(testUygulamasi(const KiraciIzolasyonuEkrani()));
    await t.pumpAndSettle();
    expect(find.text('MÜŞTERİ'), findsOneWidget);
    expect(find.text('Örnek AŞ'), findsOneWidget);
    expect(find.text('Durduruldu'), findsOneWidget);
    expect(find.text('120/dk · 4 bağ. · pay 1'), findsOneWidget);
  });

  testWidgets('Kiracı izolasyonu: telefonda kart', (t) async {
    ekranBoyutu(t, _telefon);
    Uyg.api = SahteApi(kiraciYanitlari());
    await t.pumpWidget(testUygulamasi(const KiraciIzolasyonuEkrani()));
    await t.pumpAndSettle();
    expect(find.text('MÜŞTERİ'), findsNothing);
    expect(find.text('Örnek AŞ'), findsOneWidget);
    expect(find.text('Business'), findsOneWidget);
  });

  testWidgets('IP yönetimi: envanter ve SPF', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/ips/inventory': {
        'items': [
          {
            'id': 'i1',
            'address': '203.0.113.10',
            'role': 'both',
            'pool': 'default',
            'note': '',
            'enabled': true,
            'helo_name': 'posta.ornek.com',
            'warmup_enabled': true,
            'sent_today': 12,
            'usage': 'shared',
            'present': true,
            'warmup_day': 2,
            'warmup_cap': 200,
            'ptr': ['posta.ornek.com'],
            'fcrdns': true,
            'ptr_matches_helo': true,
            'listed': 0,
            'checked_at': _simdi,
            'reputation_score': 92,
          },
        ],
        'local_addresses': ['203.0.113.10'],
        'pools': ['default'],
        'warmup_schedule': [50, 100, 200],
        'mx_host': 'posta.ornek.com',
      },
      'GET /api/v1/platform/spf': {
        'include': '_spf.ornek.com',
        'configured': true,
        'customer_value': 'v=spf1 mx include:_spf.ornek.com -all',
        'expected': 'v=spf1 ip4:203.0.113.10 -all',
        'direct_value': '',
        'found': ['v=spf1 ip4:203.0.113.10 -all'],
        'ok': true,
        'ips': [
          {'ip': '203.0.113.10', 'result': 'pass', 'ok': true},
        ],
      },
    });
    await t.pumpWidget(testUygulamasi(const IpYonetimiEkrani()));
    await t.pumpAndSettle();
    expect(find.text('203.0.113.10'), findsOneWidget);
    expect(find.text('3. gün · 12/200'), findsOneWidget);
    expect(find.text('92/100'), findsOneWidget);
    expect(find.text('IP ekle'), findsOneWidget);
    await t.tap(find.text('Platform SPF'));
    await t.pumpAndSettle();
    expect(find.text('Tüm IP\'ler yetkili'), findsOneWidget);
    expect(find.text('v=spf1 mx include:_spf.ornek.com -all'), findsOneWidget);
  });

  testWidgets('İtibar: IP puanı, öneriler ve teslim sekmesi', (t) async {
    ekranBoyutu(t, _genis);
    Uyg.api = SahteApi({
      'GET /api/v1/reputation/overview': {
        'generated_at': _simdi,
        'outbound_mode': 'direct',
        'helo_host': 'posta.ornek.com',
        'policy': {'daily_limit': 500, 'per_domain_per_minute': 30, 'bounce_pause_rate': 10},
        'ips': [
          {
            'id': 'i1',
            'address': '203.0.113.10',
            'role': 'both',
            'pool': 'default',
            'enabled': true,
            'report': null,
            'checked_at': null,
            'sent_today': 5,
            'sent_7d': 40,
            'daily_limit': 500,
            'score': {
              'total': 88,
              'grade': 'iyi',
              'coverage': 80,
              'factors': [
                {'id': 'ptr', 'label': 'PTR kaydı', 'weight': 10, 'points': 10, 'status': 'ok', 'value': 'var', 'rule': 'PTR olmalı'},
              ],
            },
            'history': [],
            'zones': {},
            'attribution': '',
            'helo_name': 'posta.ornek.com',
            'usage': 'shared',
            'is_default': true,
            'per_ip': false,
          },
        ],
        'recommendations': [
          {'severity': 'warning', 'title': 'DMARC eksik', 'detail': 'ayrıntı', 'fix': 'DMARC ekleyin'},
        ],
        'score_window': '7d',
        'min_sample': 50,
      },
      'GET /api/v1/reputation/delivery': {
        'range': '7d',
        'bucket_seconds': 86400,
        'totals': {'queued': 100, 'delivered': 95, 'hard_bounces': 2, 'soft_bounces': 1, 'deferred_rcpts': 3, 'deferrals': 4, 'refused': 0, 'refused_messages': 0, 'bulk_refused': 0},
        'rates': {'delivery_rate': 95.0, 'hard_bounce_rate': 2.0},
        'series': [],
        'refusal_rules': [],
        'signals': {'complaints': 0, 'hard_bounce_suppressions': 1, 'unsubscribes': 0, 'fbl': 'FBL bağlı değil'},
      },
    });
    await t.pumpWidget(testUygulamasi(const ItibarEkrani()));
    await t.pumpAndSettle();
    expect(find.text('88'), findsOneWidget);
    expect(find.text('PTR kaydı'), findsOneWidget);
    expect(find.text('DMARC eksik'), findsOneWidget);
    expect(find.text('Denetle'), findsOneWidget);
    await t.tap(find.text('Teslim'));
    await t.pumpAndSettle();
    expect(find.text('Teslim edilen'), findsOneWidget);
    expect(find.text('teslim oranı %95'), findsOneWidget);
  });
}
