import 'package:flutter_test/flutter_test.dart';
import 'package:yonetim/veri/modeller.dart';
import 'package:yonetim/veri/operasyon.dart';

void main() {
  test('DnsRaporu.coz', () {
    expect(DnsRaporu.coz({'report': null}), isNull);
    expect(DnsRaporu.coz('bozuk'), isNull);
    final r = DnsRaporu.coz({
      'report': {
        'checked_at': '2026-01-01T00:00:00Z',
        'verified': true,
        'checks': [
          {'id': 'mx', 'label': 'MX', 'status': 'ok', 'found': ['10 mx.ornek.com.']},
          {'id': 'spf', 'label': 'SPF', 'status': 'warn', 'problems': ['~all']},
          {'id': 'dkim', 'label': 'DKIM', 'status': 'fail'},
          'çöp',
        ],
      },
    })!;
    expect(r.dogrulandi, isTrue);
    expect(r.kontroller.length, 3);
    expect(r.sayi('ok'), 1);
    expect(r.sayi('warn'), 1);
    expect(r.sayi('fail'), 1);
    expect(r.kontroller.first.bulunan, ['10 mx.ornek.com.']);
    expect(r.kontroller[1].sorunlar, ['~all']);
  });

  test('AlanAdi ve PostaKutusu eksik alanlarla çökmez', () {
    final a = AlanAdi.coz({'id': 'd1', 'name': 'xn--firma-zua.com', 'unicode_name': 'firmaç.com', 'mode': 'gateway'});
    expect(a.gorunenAd, 'firmaç.com');
    expect(a.hosting, isFalse);
    expect(a.dkim, isNull);
    final k = PostaKutusu.coz({'id': 'm1', 'address': 'ali@firma.com', 'status': 'active', 'quota_bytes': '1073741824'});
    expect(k.aktif, isTrue);
    expect(k.kota, 1 << 30);
    expect(k.sonGiris, isNull);
  });

  test('kaynaklariSirala: en düşmanca üstte, eşitlikte en yeni', () {
    final l = kaynaklariSirala([
      SshKaynagi.coz({'ip': 'a', 'dropped': 1, 'last_seen': '2026-01-01T00:00:00Z'}),
      SshKaynagi.coz({'ip': 'b', 'failed': 5, 'invalid_user': 2}),
      SshKaynagi.coz({'ip': 'c', 'dropped': 1, 'last_seen': '2026-02-01T00:00:00Z'}),
      SshKaynagi.coz({'ip': 'd', 'accepted': 50}),
    ]);
    expect(l.map((s) => s.ip), ['b', 'c', 'a', 'd']);
    expect(l.first.toplamHatali, 7);
  });

  test('SunucuErisimi ve OtomatikYasak', () {
    final s = SunucuErisimi({
      'my_ip': '1.2.3.4',
      'my_ip_ssh_allowed': false,
      'ssh_allow': [
        {'ip': '5.6.7.8'},
      ],
      'bans': [
        {'ip': '9.9.9.9', 'reason': 'kaba kuvvet', 'auto': true, 'expires_at': null},
      ],
      'autoban': {'enabled': true, 'threshold': 10, 'window_minutes': 30, 'ban_hours': 168},
      'totals': {'failed': 3},
    });
    expect(s.benimIp, '1.2.3.4');
    expect(s.sshIzinleri, ['5.6.7.8']);
    expect(s.yasaklar.single.otomatik, isTrue);
    expect(s.yasaklar.single.bitis, isNull);
    expect(s.gun, 7);
    expect(s.toplamlar['failed'], 3);
    expect(s.otomatik.kopya(esik: 20).json(), {'enabled': true, 'threshold': 20, 'window_minutes': 30, 'ban_hours': 168});
  });

  test('KuyrukYaniti', () {
    final y = KuyrukYaniti({
      'enabled': true,
      'can_manage': true,
      'matched': 120,
      'items': [
        {'queue_id': 'Q1', 'direction': 'outbound', 'recipients': ['a@b.c'], 'status': 'deferred', 'age_seconds': 90},
      ],
      'error_class_labels': [
        {'key': 'dns', 'label': 'DNS hatası'},
      ],
      'stats': {
        'total': 1,
        'error_classes': [
          {'key': 'dns', 'label': 'DNS hatası', 'count': 1},
        ],
      },
    });
    expect(y.eslesen, 120);
    expect(y.yonetebilir, isTrue);
    expect(y.ogeler.single.giden, isTrue);
    expect(y.hataSiniflari['dns'], 'DNS hatası');
    expect(y.hataSayilari.single, ('dns', 'DNS hatası', 1));
  });

  test('AlarmOlayi ve KarantinaOgesi', () {
    final o = AlarmOlayi.coz({
      'id': 42,
      'status': 'firing',
      'deliveries': [
        {'channel': 'Panel', 'ok': true},
        {'channel': 'Webhook', 'ok': false, 'error': '500'},
      ],
    });
    expect(o.id, 42);
    expect(o.teslimler.last, ('Webhook', false, '500'));
    final k = KarantinaOgesi.coz({
      'id': 'q',
      'reason': 'virus',
      'findings': [
        {'kind': 'virus', 'name': 'Eicar-Test-Signature', 'file': 'a.zip'},
      ],
    });
    expect(k.bulgular.single.ad, 'Eicar-Test-Signature');
    expect(k.durum, 'held');
  });
}
