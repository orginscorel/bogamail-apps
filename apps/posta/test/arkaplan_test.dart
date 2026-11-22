// Arka planda çalışma: hizmetin canlı olaydan bildirim kararları (öndeyken bu hesabın postası yok, açık sohbet odası
// yok, kendi iletisi yok; diğer hesapların postası her zaman, dokununca o hesaba geçilir), öndeyken APNs bildirimi
// gösterme kararı ve Ayarlar › Arka planda çalışma anahtarları. Ağ ve yerel platform yok (sahte platform).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ekranlar/ayarlar/arkaplan_ayari.dart';
import 'package:posta/ekranlar/kabuk.dart';
import 'package:posta/ekranlar/okuyucu.dart';
import 'package:posta/oturum.dart';
import 'package:posta/veri/arkaplan.dart';
import 'package:posta/veri/sohbet_servisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SahtePlatform extends ArkaplanPlatformu {
  final islemler = <String>[];
  bool muaf = false;
  @override
  bool get android => true;
  @override
  bool get windows => false;
  @override
  bool get macos => false;
  @override
  Future<void> hizmetiBaslat() async => islemler.add('başlat');
  @override
  Future<void> hizmetiDurdur() async => islemler.add('durdur');
  @override
  Future<bool> pilMuaf() async => muaf;
  @override
  Future<bool> pilMuafiyetiIste() async {
    islemler.add('pil');
    muaf = true;
    return true;
  }

  @override
  void hizmeteBildir(Map<String, Object?> v) => islemler.add('durum:${v['onPlanda']}:${v['oda']}');
}

void main() {
  group('hizmet bildirim kararı', () {
    final posta = {'message_id': 'm1', 'from': 'Ayşe Yılmaz <ayse@ornek.com>', 'subject': 'Teklif', 'folder_role': 'inbox'};
    test('bu hesabın yeni postası: arka plandayken bildirilir, öndeyken bildirilmez', () {
      final b = olayBildirimi('new_mail', posta);
      expect(b?.baslik, 'Ayşe Yılmaz');
      expect(b?.metin, 'Teklif');
      expect(b?.yuk, 'm1');
      expect(olayBildirimi('new_mail', posta, onPlanda: true), isNull);
      expect(olayBildirimi('new_mail', {...posta, 'folder_role': 'junk'}), isNull);
    });
    test('diğer hesabın postası öndeyken de bildirilir; yük hesabı taşır', () {
      final b = olayBildirimi('unified_new', {...posta, 'account': 'Info@Ornek.com'}, onPlanda: true);
      expect(b?.yuk, 'hesap:info@ornek.com|m1');
      expect(hesapYukuCoz(b!.yuk), (adres: 'info@ornek.com', ileti: 'm1', kutu: ''));
      expect(hesapYukuCoz('m1'), isNull);
      // Sunucu kutu kimliğini de gönderir: hesap önce onunla eşlenir.
      final k = olayBildirimi('unified_new', {...posta, 'account': 'info@ornek.com', 'mailbox_id': 'k7'});
      expect(k?.yuk, 'hesap:info@ornek.com|m1|k7');
      expect(hesapYukuCoz(k!.yuk), (adres: 'info@ornek.com', ileti: 'm1', kutu: 'k7'));
    });
    test('sohbet: kendi iletisi ve öndeyken açık oda bildirilmez', () {
      final s = {'room_id': 'o1', 'sender_id': 'k2', 'sender_name': 'Can', 'preview': 'Selam'};
      expect(olayBildirimi('chat_message', s)?.yuk, 'sohbet:o1');
      expect(olayBildirimi('chat_message', s, benId: 'k2'), isNull);
      expect(olayBildirimi('chat_message', s, onPlanda: true, acikOda: 'o1'), isNull);
      expect(olayBildirimi('chat_message', s, onPlanda: true, acikOda: 'o2'), isNotNull);
    });
  });

  test('öndeyken APNs: açık oda / açık ileti ise banner yok, başka hesabınki gösterilir', () {
    Uyg.kutu.value = {'mailbox_id': 'k1', 'address': 'semih@ornek.com'};
    SohbetDurum.ben.acikOda = 'o1';
    OkuyucuState.acikIleti = 'm9';
    addTearDown(() {
      SohbetDurum.ben.acikOda = null;
      OkuyucuState.acikIleti = null;
    });
    expect(onPlandaGosterilsinMi({'kind': 'chat', 'room_id': 'o1'}), isFalse);
    expect(onPlandaGosterilsinMi({'kind': 'chat', 'room_id': 'o2'}), isTrue);
    expect(onPlandaGosterilsinMi({'kind': 'mail', 'message_id': 'm9'}), isFalse);
    expect(onPlandaGosterilsinMi({'kind': 'mail', 'message_id': 'm1'}), isTrue);
    expect(onPlandaGosterilsinMi({'kind': 'chat', 'room_id': 'o1', 'account': 'info@ornek.com'}), isTrue);
  });

  testWidgets('Ayarlar › Arka planda çalışma: sürekli bağlı kal ve pil muafiyeti', (t) async {
    SharedPreferences.setMockInitialValues({});
    final p = _SahtePlatform();
    final eski = Arkaplan.platform;
    Arkaplan.platform = p;
    addTearDown(() => Arkaplan.platform = eski);
    Arkaplan.surekliBagli.value = true;
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: const Scaffold(body: ArkaplanAyari()),
      ),
    );
    await t.pump();
    expect(find.text('Pil kısıtlaması açık'), findsOneWidget);
    await t.tap(find.text('Muaf tut'));
    await t.pump();
    expect(p.islemler, contains('pil'));
    expect(find.text('Pil kısıtlaması açık'), findsNothing);

    await t.tap(find.byKey(const ValueKey('surekli-bagli')));
    await t.pump();
    expect(Arkaplan.surekliBagli.value, isFalse);
    expect(p.islemler.last, 'durdur');
    await t.tap(find.byKey(const ValueKey('surekli-bagli')));
    await t.pump();
    expect(p.islemler.last, 'başlat');
    expect(find.byKey(const ValueKey('giriste-baslat')), findsNothing, reason: 'Android\'de yok');

    // Oturum açılınca hizmet başlar; uygulama durumu hizmete iletilir.
    p.islemler.clear();
    await Arkaplan.oturumAcildi();
    Arkaplan.durum(onPlanda: false, acikOda: null);
    expect(p.islemler, ['başlat', 'durum:false:null']);
  });
}
