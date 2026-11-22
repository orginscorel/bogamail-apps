// Bildirim sesleri: Android kanal kimlikleri ve ses kaynakları, eski kanalın silinmesi, Windows toast'ının sessiz
// olması (ses ayrıca çalınır), Ayarlar › Bildirimler'deki "Sesi dinle" düğmeleri. Ağ yok; yerel kanallar sahte.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ekranlar/ayarlar/bildirimler.dart';
import 'package:posta/veri/bildirim.dart';
import 'package:posta/veri/bildirim_sesi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('yükten ses türü: sohbet odası sohbet sesi, diğerleri posta sesi', () {
    expect(BildirimSesi.yuktan('sohbet:oda1'), BildirimSesi.sohbet);
    expect(BildirimSesi.yuktan('ileti-1'), BildirimSesi.posta);
    expect(BildirimSesi.yuktan('hesap:a@b.com|ileti-1'), BildirimSesi.posta);
    expect(BildirimSesi.yuktan(''), BildirimSesi.posta);
    // APNs "sound" alanı (sunucu) ve Android res/raw adlarıyla aynı.
    expect(BildirimSesi.posta.dosya, 'bogamail_posta.wav');
    expect(BildirimSesi.sohbet.dosya, 'bogamail_sohbet.wav');
  });

  test('Android ayrıntısı: yeni kanal, kendi ses kaynağı; ses kapalıysa sessiz', () {
    final p = Bildirim.androidAyrinti(BildirimSesi.posta, true, 'konu');
    expect(p.channelId, 'posta_v2');
    expect(p.importance, Importance.high);
    expect(p.playSound, isTrue);
    expect(p.silent, isFalse);
    expect((p.sound as RawResourceAndroidNotificationSound).sound, 'bogamail_posta');

    final c = Bildirim.androidAyrinti(BildirimSesi.sohbet, true, 'merhaba');
    expect(c.channelId, 'sohbet_v2');
    expect((c.sound as RawResourceAndroidNotificationSound).sound, 'bogamail_sohbet');
    expect(c.category, AndroidNotificationCategory.message);

    final sessiz = Bildirim.androidAyrinti(BildirimSesi.sohbet, false, 'x');
    expect(sessiz.channelId, 'sohbet_v2');
    expect(sessiz.silent, isTrue);
    expect(sessiz.playSound, isFalse);
  });

  test('Windows toast sessiz (BogaMail sesi ayrıca çalınır, çift ses olmaz)', () {
    expect(Bildirim.windowsAyrinti().audio?.isSilent, isTrue);
  });

  test('Android kanalları: eski "yeni_posta" silinir, posta_v2 / sohbet_v2 kendi sesleriyle yüksek önemde açılır', () async {
    final cagrilar = <MethodCall>[];
    const kanal = MethodChannel('dexterous.com/flutter/local_notifications');
    m.setMockMethodCallHandler(kanal, (c) async {
      cagrilar.add(c);
      return null;
    });
    addTearDown(() => m.setMockMethodCallHandler(kanal, null));
    await Bildirim.kanallariKur(AndroidFlutterLocalNotificationsPlugin());
    expect(cagrilar.first.method, 'deleteNotificationChannel');
    expect(cagrilar.first.arguments, 'yeni_posta');
    final olusan = cagrilar.where((c) => c.method == 'createNotificationChannel').map((c) => Map<String, dynamic>.from(c.arguments as Map)).toList();
    expect(olusan.map((k) => k['id']), ['posta_v2', 'sohbet_v2', 'gorev_v1']);
    for (final k in olusan) {
      expect(k['importance'], Importance.high.value);
      expect(k['playSound'], isTrue);
      expect(k['sound'], k['id'] == 'sohbet_v2' ? 'bogamail_sohbet' : 'bogamail_posta');
    }
  });

  testWidgets('Ayarlar › Bildirimler: "Sesi dinle" düğmeleri doğru sesi çalar; çalınamazsa uyarı', (t) async {
    final calinan = <Object?>[];
    var sonuc = true;
    m.setMockMethodCallHandler(SesCalar.kanal, (c) async {
      calinan.add(c.method == 'cal' ? c.arguments : c.method);
      return sonuc;
    });
    addTearDown(() => m.setMockMethodCallHandler(SesCalar.kanal, null));
    // Telefon genişliğinde taşmaz.
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        scaffoldMessengerKey: kokMesaj,
        home: const Scaffold(body: SingleChildScrollView(child: BildirimSesiKarti())),
      ),
    );
    expect(find.text('Bildirim sesi'), findsOneWidget);
    expect(find.text('Sesi dinle'), findsNWidgets(2));
    await t.tap(find.byKey(const ValueKey('ses-dinle-posta')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('ses-dinle-sohbet')));
    await t.pump();
    expect(calinan, ['posta', 'sohbet']);
    expect(find.text('Ses çalınamadı'), findsNothing);

    sonuc = false;
    await t.tap(find.byKey(const ValueKey('ses-dinle-posta')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Ses çalınamadı'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  test('görev hatırlatması ayrıntısı: kendi kanalı, BogaMail sesi; ses kapalıysa sessiz', () {
    final d = Bildirim.gorevAyrintisi('Son tarih: bugün 10:00', ses: true);
    expect(d.android!.channelId, 'gorev_v1');
    expect(d.android!.category, AndroidNotificationCategory.reminder);
    expect((d.android!.sound as RawResourceAndroidNotificationSound).sound, 'bogamail_posta');
    expect(d.windows!.audio?.isSilent ?? false, isFalse, reason: 'zamanlanmış bildirimde uygulama ses çalamaz, sistem sesi');
    final sessiz = Bildirim.gorevAyrintisi('x', ses: false);
    expect(sessiz.android!.silent, isTrue);
    expect(sessiz.windows!.audio?.isSilent, isTrue);
  });
}
