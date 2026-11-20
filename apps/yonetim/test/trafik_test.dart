import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/bastirma.dart';
import 'package:yonetim/ekranlar/kampanya_izleme.dart';
import 'package:yonetim/ekranlar/mesaj_takibi.dart';
import 'package:yonetim/ekranlar/teslim_teshisi.dart';
import 'package:yonetim/ekranlar/teslimat_kontrol.dart';
import 'package:yonetim/ekranlar/teslimat_sorunlari.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

const _aciklama = {'status': 'delivered', 'label': 'Teslim edildi', 'tone': 'ok', 'summary': 'İleti posta kutusuna yazıldı.'};

final _olay = {
  'id': 1,
  'at': '2026-11-20T10:00:00Z',
  'queue_id': 'Q1ABC',
  'direction': 'inbound',
  'event': 'delivered',
  'stage': 'delivery',
  'remote_ip': '198.51.100.7',
  'mail_from': 'gonderen@ornek.test',
  'rcpt': 'alici@musteri.test',
  'organization_name': 'Örnek AŞ',
  'smtp_code': 250,
  'enhanced_code': '2.0.0',
  'reason': 'ok',
  'size_bytes': 2048,
  'spam_rules': <String>[],
  'bulk': false,
  'explain': _aciklama,
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<void> ac(WidgetTester t, Widget w, {Size boyut = const Size(1400, 900)}) async {
    ekranBoyutu(t, boyut);
    await t.pumpWidget(testUygulamasi(w));
    await t.pumpAndSettle();
  }

  testWidgets('Mesaj Takibi: olaylar, gecikmeler ve ileti yolculuğu', (t) async {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/mail-events': {
        'items': [_olay],
        'total': 1,
      },
      'GET /api/v1/mail-events/latency': {
        'hours': 24,
        'stages': [
          {'key': 'smtp', 'label': 'SMTP oturumu', 'count': 12, 'p50_ms': 420, 'p95_ms': 1800, 'max_ms': 2500},
        ],
      },
      'GET /api/v1/mail-events/explore/Q1ABC': {
        'timeline': {
          'queue_id': 'Q1ABC',
          'direction': 'inbound',
          'gateway': false,
          'start': '2026-11-20T10:00:00Z',
          'end': '2026-11-20T10:00:02Z',
          'total_ms': 2000,
          'stages': [
            {'key': 'smtp', 'label': 'SMTP oturumu', 'start': '2026-11-20T10:00:00Z', 'end': '2026-11-20T10:00:01Z', 'duration_ms': 1000, 'status': 'ok', 'details': null, 'slowest': true},
            {'key': 'delivery', 'label': 'Kutuya yazma', 'end': '2026-11-20T10:00:02Z', 'duration_ms': 30, 'status': 'ok', 'details': [{'k': 'Klasör', 'v': 'INBOX'}], 'slowest': false},
          ],
          'slowest': 0,
          'failures': 0,
          'recipients': [],
          'summary': _aciklama,
        },
        'slow_note': '',
        'events': [_olay],
      },
    });
    await ac(t, const MesajTakibiEkrani());
    expect(find.text('gonderen@ornek.test'), findsOneWidget);
    expect(find.text('Q1ABC'), findsOneWidget);
    expect(find.text('SMTP oturumu'), findsOneWidget);
    await t.tap(find.text('gonderen@ornek.test'));
    await t.pumpAndSettle();
    expect(find.text('İleti Yolculuğu'), findsOneWidget);
    expect(find.text('Kutuya yazma'), findsWidgets);
    expect(find.text('en yavaş'), findsOneWidget);
  });

  testWidgets('Mesaj Takibi telefonda kart', (t) async {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/mail-events': {
        'items': [_olay],
        'total': 1,
      },
      'GET /api/v1/mail-events/latency': {'hours': 24, 'stages': []},
    });
    await ac(t, const MesajTakibiEkrani(), boyut: const Size(400, 800));
    expect(find.text('→ alici@musteri.test'), findsOneWidget);
    expect(find.text('ZAMAN'), findsNothing);
  });

  testWidgets('Bastırma Listesi: sayaçlar, kayıt ve şikâyet sekmesi', (t) async {
    kullaniciAyarla();
    final api = SahteApi({
      'GET /api/v1/suppressions': {
        'items': [
          {
            'id': '00000000-0000-0000-0000-000000000001',
            'organization_id': 'o1',
            'organization_name': 'Örnek AŞ',
            'address': 'yok@uzak.test',
            'reason': 'hard_bounce',
            'source': 'dsn',
            'detail': '550 5.1.1',
            'hits': 3,
            'created_at': '2026-11-19T08:00:00Z',
            'expires_at': '2026-12-19T08:00:00Z',
          },
        ],
        'total': 1,
        'counts': {'hard_bounce': 1, 'complaint': 0, 'unsubscribe': 0, 'manual': 0},
      },
      'GET /api/v1/fbl/reports': {'items': []},
    });
    Uyg.api = api;
    await ac(t, const BastirmaListesiEkrani());
    expect(find.text('yok@uzak.test'), findsOneWidget);
    expect(find.text('Kalıcı geri dönüş'), findsWidgets);
    expect(find.text('Adres ekle'), findsOneWidget);
    await t.tap(find.byTooltip('İşlemler'));
    await t.pumpAndSettle();
    expect(find.text('Listeden çıkar'), findsOneWidget);
  });

  testWidgets('Toplu Gönderim İzleme: riskli kampanya ve onay sayısı', (t) async {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/admin/campaigns': {
        'items': [
          {
            'id': 'c1',
            'organization_name': 'Örnek AŞ',
            'name': 'Kasım bülteni',
            'kind': 'commercial',
            'status': 'pending_approval',
            'from_address': 'bulten@ornek.test',
            'total_recipients': 1200,
            'status_reason': '',
            'wait_reason': '',
            'stats': {'queued': 100, 'delivered': 90},
            'rates': {'bounce': 0.08, 'complaint': 0, 'unsubscribe': 0},
            'speed_per_hour': 600,
          },
        ],
        'total': 1,
        'pending_approval': 1,
      },
    });
    await ac(t, const KampanyaIzlemeEkrani());
    expect(find.text('Kasım bülteni'), findsOneWidget);
    expect(find.text('%8,0'), findsOneWidget);
    expect(find.text('Onay bekliyor'), findsOneWidget);
    await t.tap(find.byTooltip('İşlemler'));
    await t.pumpAndSettle();
    expect(find.text('Onayla'), findsOneWidget);
    expect(find.text('Reddet'), findsOneWidget);
  });

  testWidgets('Teslimat Sorunları: sayaçlar ve sorunlu alan adı', (t) async {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/monitor/issues': {
        'domains': [
          {
            'id': 'd1',
            'name': 'ornek.test',
            'mode': 'hosting',
            'status': 'active',
            'organization_name': 'Örnek AŞ',
            'worst': 'fail',
            'problems': 1,
            'checked_at': '2026-11-20T09:00:00Z',
            'checks': [
              {
                'id': 'spf',
                'label': 'SPF',
                'status': 'fail',
                'detail': 'SPF kaydı yok',
                'cause': 'Alıcılar postayı reddedebilir.',
                'fix': 'TXT kaydı ekleyin.',
                'checked_at': '2026-11-20T09:00:00Z',
                'changed_at': '2026-11-20T09:00:00Z',
              },
            ],
          },
        ],
        'platform': [],
        'settings': {'enabled': true, 'interval_minutes': 30, 'dbl_enabled': false},
        'last_run': null,
      },
    });
    await ac(t, const TeslimatSorunlariEkrani());
    expect(find.text('ornek.test'), findsOneWidget);
    expect(find.text('TXT kaydı ekleyin.'), findsOneWidget);
    expect(find.text('Şimdi denetle'), findsOneWidget);
    expect(find.text('Tümünü denetle'), findsOneWidget);
  });

  testWidgets('Teslim Teşhisi: geri dönme sınıfları', (t) async {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/deliverability/bounces': {
        'range': '7d',
        'total': 5,
        'hard': 4,
        'soft': 1,
        'categories': [
          {
            'key': 'unknown_user',
            'label': 'Bilinmeyen alıcı',
            'explain': 'Adres yok.',
            'fix': 'Listeyi temizleyin.',
            'owner': 'sender',
            'count': 4,
            'hard': 4,
            'soft': 0,
            'recipients': 4,
            'domains': 1,
          },
        ],
        'domains': [
          {
            'domain': 'uzak.test',
            'total': 5,
            'hard': 4,
            'counts': {'unknown_user': 4},
          },
        ],
        'responses': [
          {'category': 'unknown_user', 'code': '5.1.1', 'text': 'user unknown', 'count': 4, 'last': '2026-11-20T09:00:00Z'},
        ],
        'trend': [
          {
            'at': '2026-11-19T00:00:00Z',
            'total': 5,
            'counts': {'unknown_user': 4, 'other': 1},
          },
        ],
      },
    });
    await ac(t, const TeslimTeshisiEkrani());
    expect(find.text('Listeyi temizleyin.'), findsOneWidget);
    expect(find.text('uzak.test'), findsOneWidget);
    expect(find.text('user unknown'), findsOneWidget);
  });

  testWidgets('Teslimat Kontrol: motor durumu ve etkin fren', (t) async {
    kullaniciAyarla();
    Uyg.api = SahteApi({
      'GET /api/v1/outbound/engine': {
        'available': true,
        'engine': {
          'running_connections': 3,
          'max_connections': 100,
          'running_bulk': 1,
          'reserved_normal': 20,
          'queued': {'normal': 5, 'bulk': 7, 'held': 2, 'held_by_brake': 1},
          'delivered_last_minute': 9,
          'delivered_10m': 80,
          'deferred_10m': 2,
          'failed_10m': 1,
          'per_minute': [
            {'minute': '2026-11-20T10:00:00Z', 'delivered': 9, 'deferred': 1, 'failed': 0},
          ],
          'bulk_paused': false,
          'normal_factor': 1,
          'pause_reason': '',
          'providers': [
            {
              'key': 'gmail',
              'name': 'Gmail',
              'state': 'backoff',
              'connections': 2,
              'max_connections': 10,
              'rate_per_minute': 50,
              'base_rate_per_minute': 100,
              'factor': 0.5,
              'last_reason': '421 4.7.0',
              'delivered_10m': 40,
              'deferred_10m': 2,
              'failed_10m': 0,
              'ready': 3,
            },
          ],
          'down_domains': [],
        },
        'engine_config': {'max_connections': 100, 'providers': null},
        'profiles': [],
        'brake_config': {'release_grace_hours': 24},
        'brakes': [
          {
            'id': 'b1',
            'scope': 'organization',
            'organization_name': 'Örnek AŞ',
            'mailbox': '',
            'kind': 'spike',
            'action': 'hold_bulk',
            'reason': 'Ani artış.',
            'active': true,
            'created_at': '2026-11-20T09:00:00Z',
          },
        ],
        'dnsbl': [],
        'warmup': {'started': null, 'day': 0, 'days': 30, 'cap_today': 0, 'base_daily_limit': 0, 'sent_today': 12, 'schedule': []},
        'inbound': {
          'config': {'max_per_ip': 10, 'per_ip_per_minute': 60, 'pregreet_ms': 300, 'tarpit_ms': 500, 'max_rcpt_failures': 5, 'dnsbl_enabled': false},
          'listening': true,
        },
        'fbl': {
          'addresses': ['fbl@mx.ornek.test'],
          'counts': {'reports_30d': 0, 'parsed_30d': 0, 'unparsed_30d': 0},
        },
      },
    });
    await ac(t, const TeslimatKontrolEkrani());
    expect(find.text('3 / 100'), findsOneWidget);
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('Geri çekildi'), findsOneWidget);
    expect(find.text('Ani gönderim artışı'), findsOneWidget);
    expect(find.text('Kaldır'), findsOneWidget);
  });

  testWidgets('Teslimat Kontrol platform yöneticisi değilse kapalı', (t) async {
    kullaniciAyarla(rol: 'reseller_admin');
    Uyg.api = SahteApi();
    await ac(t, const TeslimatKontrolEkrani());
    expect(find.text('Bu sayfa yalnızca platform yöneticilerine açıktır.'), findsOneWidget);
  });
}
