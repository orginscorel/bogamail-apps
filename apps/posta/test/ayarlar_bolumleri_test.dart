// Ayar bölümleri (lib/ekranlar/ayarlar/*): sahte sunucuyla kaydetme gidiş-dönüşleri. Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/ekranlar/ayarlar.dart';
import 'package:posta/ekranlar/ayarlar/bildirimler.dart';
import 'package:posta/ekranlar/ayarlar/genel.dart';
import 'package:posta/ekranlar/ayarlar/klasorler.dart';
import 'package:posta/ekranlar/ayarlar/kurulum.dart';
import 'package:posta/ekranlar/ayarlar/otomatik.dart';
import 'package:posta/ekranlar/ayarlar/tasima.dart';
import 'package:posta/ekranlar/hesap/guvenlik.dart';
import 'package:posta/ekranlar/hesap/imza.dart';
import 'package:posta/ekranlar/hesap/posta_yonetimi.dart';
import 'package:posta/ekranlar/hesap/suzgecler.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/hesap_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_sunucu.dart';

void main() {
  final s = YolSunucusu();
  late Map<String, dynamic> ayar;
  late Map<String, dynamic> ozellik;
  late Map<String, dynamic> baglanti;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    s.kur();
    SharedPreferences.setMockInitialValues({});
    Uyg.kutu.value = {'mailbox_id': 'm1', 'address': 'ayse@ornek.com', 'display_name': 'Ayşe'};
  });

  setUp(() {
    s.istekler.clear();
    ayar = {
      'display_name': 'Ayşe',
      'signature': '',
      'signature_html': '',
      'compose_html': true,
      'notify_desktop': true,
      'notify_sound': true,
      'sync_seconds': 60,
      'theme': 'system',
      'page_size': 50,
      'vacation_enabled': false,
      'vacation_subject': '',
      'vacation_body': '',
      'vacation_start': null,
      'vacation_end': null,
      'undo_send_seconds': 0,
    };
    ozellik = {'imap': true, 'smtp': true, 'pop3': false, 'autoresponder': true, 'chat': true, 'caldav': true, 'tasks': true};
    baglanti = {
      'host': 'posta.ornek.com',
      'imap_enabled': true,
      'imap_port': 993,
      'imap_security': 'SSL/TLS',
      'smtp_enabled': true,
      'smtp_port': 465,
      'smtp_security': 'SSL/TLS',
      'pop3_enabled': false,
      'dav_path': '/dav/',
      'restricted': false,
      'self_signed': false,
    };
    s.yollar
      ..clear()
      ..['GET /api/v1/mail/settings'] = ((Istek _) => (200, {'settings': ayar, 'features': ozellik, 'connection': baglanti}))
      ..['PATCH /api/v1/mail/settings'] = ((Istek i) {
        ayar.addAll(i.json);
        return (200, {'settings': ayar});
      })
      ..['GET /api/v1/mail/chat/me'] = (200, {'show_presence': true})
      ..['PUT /api/v1/mail/chat/me'] = ((Istek i) => (200, {'show_presence': i.json['show_presence']}));
  });

  Future<void> ac(WidgetTester t, Widget w, {Size boyut = const Size(1200, 1600)}) async {
    t.view.physicalSize = boyut;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: Scaffold(body: w),
      ),
    );
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }

  Future<void> kapat(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  }

  Future<void> dokun(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('Genel: yalnızca değişen alanlar kaydedilir, geri alma süresi hemen kaydedilir', (t) async {
    await ac(t, const GenelAyari());
    expect(find.text('Sayfa başına ileti'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('genel-ad')), 'Ayşe Yılmaz');
    await t.enterText(find.byKey(const ValueKey('genel-sayfa')), '75');
    await t.pump();
    await dokun(t, find.text('Düz metin'));
    await dokun(t, find.byKey(const ValueKey('genel-kaydet')));
    final p = s.bul('PATCH', '/api/v1/mail/settings').single.json;
    expect(p, {'display_name': 'Ayşe Yılmaz', 'page_size': 75, 'compose_html': false});
    expect(Uyg.kutu.value?['display_name'], 'Ayşe Yılmaz');

    // Geçersiz sayfa boyutu: kaydet kapalı.
    await t.enterText(find.byKey(const ValueKey('genel-sayfa')), '5');
    await t.pump();
    expect(t.widget<FilledButton>(find.descendant(of: find.byKey(const ValueKey('genel-kaydet')), matching: find.byType(FilledButton))).onPressed, isNull);

    await dokun(t, find.text('10 saniye'));
    expect(s.bul('PATCH', '/api/v1/mail/settings').last.json, {'undo_send_seconds': 10});
    await kapat(t);
  });

  testWidgets('Genel telefonda tek sütun', (t) async {
    await ac(t, const GenelAyari(), boyut: const Size(390, 1600));
    expect(find.text('Gönderimi geri al'), findsOneWidget);
    expect(t.takeException(), isNull);
    await kapat(t);
  });

  testWidgets('Bildirimler: ses/masaüstü/eşitleme kaydedilir; sohbet gizliliği PUT', (t) async {
    await ac(t, const BildirimlerAyari());
    await dokun(t, find.descendant(of: find.byKey(const ValueKey('bildirim-ses')), matching: find.byType(Switch)));
    await dokun(t, find.byKey(const ValueKey('bildirim-esitleme')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('5 dk').last);
    await t.pump(const Duration(milliseconds: 300));
    await dokun(t, find.byKey(const ValueKey('bildirim-kaydet')));
    expect(s.bul('PATCH', '/api/v1/mail/settings').single.json, {'notify_desktop': true, 'notify_sound': false, 'sync_seconds': 300});
    final p = await SharedPreferences.getInstance();
    expect(p.getBool('posta.bildirim.ses'), isFalse);

    await dokun(t, find.descendant(of: find.byKey(const ValueKey('sohbet-gizlilik')), matching: find.byType(Switch)));
    expect(s.bul('PUT', '/api/v1/mail/chat/me').single.json, {'show_presence': false});
    await kapat(t);
  });

  testWidgets('Otomatik yanıt: metin zorunlu, tarihler ve konu gönderilir', (t) async {
    await ac(t, const OtomatikYanitAyari());
    await dokun(t, find.descendant(of: find.byKey(const ValueKey('tatil-ac')), matching: find.byType(Switch)));
    expect(find.text('Otomatik yanıt metnini yazın.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('tatil-konu')), 'İzindeyim');
    await t.enterText(find.byKey(const ValueKey('tatil-metin')), 'Pazartesi dönüyorum.');
    await t.pump();
    await dokun(t, find.byKey(const ValueKey('tatil-kaydet')));
    expect(s.bul('PATCH', '/api/v1/mail/settings').single.json, {
      'vacation_enabled': true,
      'vacation_subject': 'İzindeyim',
      'vacation_body': 'Pazartesi dönüyorum.',
      'vacation_start': null,
      'vacation_end': null,
    });
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Açık'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('Otomatik yanıt paketinde kapalıysa açık kalan yanıt kapatılabilir', (t) async {
    ozellik['autoresponder'] = false;
    ayar['vacation_enabled'] = true;
    ayar['vacation_body'] = 'x';
    await ac(t, const OtomatikYanitAyari());
    expect(find.text('Paketinizde kapalı'), findsWidgets);
    await dokun(t, find.text('Otomatik yanıtı kapat'));
    expect(s.bul('PATCH', '/api/v1/mail/settings').single.json, {'vacation_enabled': false});
    await kapat(t);
  });

  testWidgets('Klasörler: oluştur, Çöp Kutusu onay kutusuyla boşaltılır', (t) async {
    final klasorler = [
      {'id': 'g', 'name': 'INBOX', 'role': 'inbox', 'total': 3, 'unseen': 1},
      {'id': 'c', 'name': 'Trash', 'role': 'trash', 'total': 4, 'unseen': 0},
      {'id': 'k1', 'name': 'Faturalar', 'total': 2, 'unseen': 0},
    ];
    s.yollar
      ..['GET /api/v1/mail/folders'] = ((Istek _) => (200, {'items': klasorler}))
      ..['POST /api/v1/mail/folders'] = ((Istek i) {
        klasorler.add({'id': 'k2', 'name': i.json['name'], 'total': 0, 'unseen': 0});
        return (201, {'id': 'k2'});
      })
      ..['POST /api/v1/mail/folders/c/empty'] = (200, {'deleted': 4});
    await ac(t, const KlasorlerEkrani());
    expect(find.text('Faturalar'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('yeni-klasor-ad')), 'Projeler');
    await t.pump();
    await dokun(t, find.byKey(const ValueKey('yeni-klasor-olustur')));
    await t.pump(const Duration(milliseconds: 100));
    expect(s.bul('POST', '/api/v1/mail/folders').single.json, {'name': 'Projeler'});
    expect(find.text('Projeler'), findsOneWidget);

    await dokun(t, find.byKey(const ValueKey('bosalt-trash')));
    await t.pump(const Duration(milliseconds: 300));
    final sil = find.widgetWithText(FilledButton, 'Kalıcı olarak sil');
    expect(t.widget<FilledButton>(sil).onPressed, isNull);
    await dokun(t, find.byKey(const ValueKey('bosalt-anladim')));
    await dokun(t, sil);
    await t.pump(const Duration(milliseconds: 300));
    expect(s.bul('POST', '/api/v1/mail/folders/c/empty'), hasLength(1));
    await kapat(t);
  });

  testWidgets('Etiket oluştururken renk seçilir', (t) async {
    s.yollar
      ..['GET /api/v1/mail/labels'] = (200, {'items': []})
      ..['POST /api/v1/mail/labels'] = (201, {'id': 'e1'})
      ..['GET /api/v1/mail/folders'] = (200, {'items': []});
    await ac(t, const EtiketlerEkrani());
    await t.pump(const Duration(milliseconds: 500)); // FAB giriş animasyonu
    await dokun(t, find.text('Etiket ekle'));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byKey(const ValueKey('yeni-etiket-ad')), 'Müşteri');
    await dokun(t, find.byKey(const ValueKey('yeni-etiket-renk-green')));
    await dokun(t, find.widgetWithText(FilledButton, 'Oluştur'));
    await t.pump(const Duration(milliseconds: 300));
    expect(s.bul('POST', '/api/v1/mail/labels').single.json, {'name': 'Müşteri', 'color': 'green'});
    await kapat(t);
  });

  test('süzgeç sırası: yeniden numaralanır, yalnızca değişenler kaydedilir', () async {
    s.yollar['PATCH /api/v1/mail/filters/a'] = (200, {});
    s.yollar['PATCH /api/v1/mail/filters/b'] = (200, {});
    s.yollar['PATCH /api/v1/mail/filters/c'] = (200, {});
    final l = [
      Suzgec.json({'id': 'a', 'name': 'A', 'position': 10}),
      Suzgec.json({'id': 'b', 'name': 'B', 'position': 20}),
      Suzgec.json({'id': 'c', 'name': 'C', 'position': 30}),
    ];
    await suzgecTasi(l, 2, -1);
    final yollar = s.istekler.where((i) => i.yontem == 'PATCH').map((i) => (i.yol.split('/').last, i.json['position'])).toSet();
    expect(yollar, {('c', 20), ('b', 30)});
    s.istekler.clear();
    await suzgecTasi(l, 0, -1); // en üstte: değişiklik yok
    expect(s.istekler, isEmpty);
  });

  testWidgets('Taşıma: form gönderilir, ilerleme ve iptal', (t) async {
    var is_ = <String, dynamic>{};
    s.yollar
      ..['GET /api/v1/mail/migration'] = ((Istek _) => (200, {'enabled': true, 'job': is_.isEmpty ? null : is_}))
      ..['GET /api/v1/mail/migration/presets'] = (
        200,
        {
          'items': [
            {
              'key': 'gmail',
              'name': 'Gmail',
              'host': 'imap.gmail.com',
              'port': 993,
              'security': 'tls',
              'auth': 'app_password',
              'steps': ['Uygulama şifresi oluşturun'],
              'notes': [],
            },
          ],
        },
      )
      ..['POST /api/v1/mail/migration'] = ((Istek i) {
        is_ = {
          'id': 'j1',
          'source_host': i.json['host'],
          'source_port': i.json['port'],
          'source_security': i.json['security'],
          'source_username': i.json['username'],
          'status': 'running',
          'messages_total': 10,
          'messages_done': 4,
          'messages_skipped': 1,
          'messages_failed': 0,
          'bytes_done': 2048,
          'created_at': '2026-11-20T10:00:00Z',
          'folders': [
            {'source_name': 'INBOX', 'target_name': 'Gelen Kutusu', 'status': 'running', 'messages_total': 10, 'messages_done': 4},
          ],
        };
        return (201, is_);
      })
      ..['POST /api/v1/mail/migration/cancel'] = ((Istek _) {
        is_ = {...is_, 'status': 'cancelled'};
        return (200, is_);
      });
    await ac(t, const TasimaAyari(yoklama: Duration(hours: 1)));
    await t.pump(const Duration(milliseconds: 100));
    await dokun(t, find.byKey(const ValueKey('tasima-sablon')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Gmail').last);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Bu sağlayıcıda normal şifre yerine bir uygulama şifresi gerekir.'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('tasima-kullanici')), 'ayse@gmail.com');
    await t.enterText(find.byKey(const ValueKey('tasima-sifre')), 'gizli-uygulama-sifresi');
    await t.pump();
    await dokun(t, find.byKey(const ValueKey('tasima-baslat')));
    await t.pump(const Duration(milliseconds: 100));
    expect(s.bul('POST', '/api/v1/mail/migration').single.json, {
      'host': 'imap.gmail.com',
      'port': 993,
      'security': 'tls',
      'username': 'ayse@gmail.com',
      'password': 'gizli-uygulama-sifresi',
    });
    expect(find.text('Çalışıyor'), findsOneWidget);
    expect(find.text('%50'), findsOneWidget);
    expect(find.text('INBOX → Gelen Kutusu'), findsOneWidget);

    await dokun(t, find.byKey(const ValueKey('tasima-iptal')));
    await t.pump(const Duration(milliseconds: 300));
    await dokun(t, find.widgetWithText(FilledButton, 'İptal et'));
    await t.pump(const Duration(milliseconds: 300));
    expect(s.bul('POST', '/api/v1/mail/migration/cancel'), hasLength(1));
    expect(find.text('İptal edildi'), findsOneWidget);
    expect(find.byKey(const ValueKey('tasima-yeni')), findsOneWidget);
    await kapat(t);
  });

  testWidgets('Taşıma paketinde yoksa bilgi gösterilir', (t) async {
    s.yollar['GET /api/v1/mail/migration'] = (200, {'enabled': false, 'job': null});
    await ac(t, const TasimaAyari());
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Paketinizde yok'), findsOneWidget);
    expect(find.byKey(const ValueKey('tasima-baslat')), findsNothing);
    await kapat(t);
  });

  testWidgets('Kayıtlı cihazlar: bu cihaz kaldırılamaz, diğeri DELETE', (t) async {
    s.yollar
      ..['GET /api/v1/mail/security/saved-devices'] = (
        200,
        {
          'items': [
            {'id': 'd1', 'current': true, 'user_agent': 'BogaMail/1.2 Dart/3.9', 'added_at': '2026-11-01T10:00:00Z', 'last_used_at': '2026-11-20T10:00:00Z'},
            {
              'id': 'd2',
              'current': false,
              'user_agent': 'Mozilla/5.0 (Windows NT 10.0) Chrome/130.0 Safari/537.36',
              'added_at': '2026-11-02T10:00:00Z',
              'last_used_at': '2026-11-19T10:00:00Z',
              'ip': '1.2.3.4',
            },
          ],
        },
      )
      ..['DELETE /api/v1/mail/security/saved-devices/d2'] = (204, null);
    await ac(t, const KayitliCihazlarEkrani());
    expect(find.text('BogaMail uygulaması'), findsOneWidget);
    expect(find.text('Chrome · Windows'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kayitli-d1')), matching: find.byTooltip('Kaldır')), findsNothing);
    await dokun(t, find.descendant(of: find.byKey(const ValueKey('kayitli-d2')), matching: find.byTooltip('Kaldır')));
    await t.pump(const Duration(milliseconds: 300));
    await dokun(t, find.widgetWithText(FilledButton, 'Kaldır'));
    await t.pump(const Duration(milliseconds: 300));
    expect(s.bul('DELETE', '/api/v1/mail/security/saved-devices/d2'), hasLength(1));
    await kapat(t);
  });

  testWidgets('Bağlantı ve kurulum: sunucudan gelen portlar ve DAV adresi', (t) async {
    await ac(t, const KurulumAyari());
    expect(find.text('Gelen posta (IMAP)'), findsOneWidget);
    expect(find.text('465'), findsOneWidget);
    expect(find.text('Kullanılabilir'), findsNWidgets(2));
    expect(find.textContaining('/dav/'), findsWidgets);
    expect(find.byKey(const ValueKey('apple-profili')), findsOneWidget);
    expect(find.text('Paketinizde yok'), findsNothing);
    // POP3 sunucuda kapalı
    expect(find.text('Kapalı'), findsOneWidget);
    await kapat(t);
  });

  testWidgets('Bağlantı ve kurulum telefonda taşmaz; IMAP kapalıyken kurulum gizli', (t) async {
    ozellik['imap'] = false;
    ozellik['caldav'] = false;
    await ac(t, const KurulumAyari(), boyut: const Size(390, 4000));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('apple-profili')), findsNothing);
    expect(find.text('Paketinizde kapalı'), findsOneWidget);
    expect(find.text('Paketinizde yok'), findsOneWidget);
    await kapat(t);
  });

  void ekYollar() {
    s.yollar
      ..['GET /api/v1/mail/auth/accounts'] = (200, {'items': []})
      ..['GET /api/v1/mail/folders'] = (200, {'items': []})
      ..['GET /api/v1/mail/labels'] = (200, {'items': []})
      ..['GET /api/v1/mail/migration'] = (200, {'enabled': true, 'job': null})
      ..['GET /api/v1/mail/migration/presets'] = (200, {'items': []});
  }

  testWidgets('geniş Ayarlar: eklenen her bölüm sağ bölmede taşmadan açılır', (t) async {
    ekYollar();
    t.view.physicalSize = const Size(1440, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    for (final (id, metin) in const [
      ('kurulum', 'Bağlantı ayarları'),
      ('genel', 'Sayfa başına ileti'),
      ('gorunum', 'Uzak görseller'),
      ('bildirimler', 'Bildirim tercihleri'),
      ('otomatik', 'Otomatik yanıtı aç'),
      ('etiketler', 'Henüz etiket yok.'),
      ('klasorler', 'Klasörlerim'),
      ('tasima', 'Eski sunucu (IMAP)'),
    ]) {
      await t.tap(find.byKey(ValueKey('ayar-kategori-$id')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(metin), findsWidgets, reason: id);
      expect(t.takeException(), isNull, reason: id);
    }
    await kapat(t);
  });

  testWidgets('telefonda eklenen bölüm satırı tam sayfa açar', (t) async {
    ekYollar();
    t.view.physicalSize = const Size(390, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const AyarlarEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final satir = find.byKey(const ValueKey('ayar-satir-kurulum'));
    await t.scrollUntilVisible(satir, 300, scrollable: find.byType(Scrollable).first);
    await t.tap(satir);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Paketinizdeki özellikler'), findsOneWidget);
    expect(t.takeException(), isNull);
    await kapat(t);
  });

  testWidgets('İmza tasarımcısı: seçilen düzen ve renk biçimli imzaya yazılır ve kaydedilir', (t) async {
    s.yollar['GET /api/v1/mail/profile'] = (200, {'profile': {}, 'editable': true});
    t.view.physicalSize = const Size(1200, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(theme: temaKur(Brightness.light), scaffoldMessengerKey: kokMesaj, home: const ImzaEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    await dokun(t, find.text('Biçimli'));
    await dokun(t, find.byTooltip('Hazır tasarım'));
    await t.pump(const Duration(milliseconds: 300));
    await dokun(t, find.byKey(const ValueKey('imza-duzen-modern')));
    await dokun(t, find.byKey(const ValueKey('imza-tasarim-uygula')));
    await t.pump(const Duration(milliseconds: 300));
    await dokun(t, find.widgetWithText(FilledButton, 'Kaydet'));
    await t.pump(const Duration(milliseconds: 300));
    final p = s.bul('PATCH', '/api/v1/mail/settings').single.json;
    expect(p['signature_html'], contains("Segoe UI"));
    expect(p['signature_html'], contains('#1d4ed8'));
    await kapat(t);
  });
}
