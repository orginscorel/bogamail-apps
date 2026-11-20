import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:yonetim/ekranlar/bayiler.dart';
import 'package:yonetim/ekranlar/yoneticiler.dart';
import 'package:yonetim/ortak/simgeler.dart';
import 'package:yonetim/oturum.dart';

import 'sahte_api.dart';

Map<String, dynamic> _bayi(String id, String ad, int musteri) => {
  'id': id,
  'name': ad,
  'status': 'active',
  'max_customers': null,
  'max_mailboxes': null,
  'max_storage_bytes': null,
  'contact_email': '$id@bayi.test',
  'admin_count': 1,
  'usage': {'customers': musteri, 'mailboxes': 0, 'allocated_bytes': 0, 'used_bytes': 0},
  'branding': {},
};

Map<String, dynamic> _kullanici(String id, String eposta, String ad, String rol) => {
  'id': id,
  'email': eposta,
  'display_name': ad,
  'role': rol,
  'status': 'active',
  'mfa_enabled': false,
  'permissions': null,
  'last_login_at': null,
  'created_at': '2026-01-01T10:00:00Z',
  'phone': '',
  'title': '',
  'note': '',
};

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => kullaniciAyarla());

  /// Listenin ilk satırının "⋮" menüsünü açar (testlerde silinecek bayi ilk sıradadır).
  Future<void> satirMenusu(WidgetTester t, String ad) async {
    expect(find.text(ad), findsWidgets);
    await t.tap(find.byIcon(Simgeler.moreVert).first);
    await t.pumpAndSettle();
  }

  group('Bayi silme', () {
    testWidgets('müşterisiz görünse de sunucu 409 dönerse platforma bağlayarak silinir', (t) async {
      ekranBoyutu(t, const Size(1400, 900));
      final api = SahteApi({
        'GET /api/v1/resellers/summary': {
          'items': [_bayi('r1', 'Anadolu Bilişim', 0)],
        },
        'DELETE /api/v1/resellers/r1': (Object? _, Map<String, dynamic>? q) {
          if (q == null || q.isEmpty) throw ApiHata(409, 'Bayinin müşterileri var.', kod: 'reseller_has_customers');
          return null;
        },
      });
      Uyg.api = api;
      await t.pumpWidget(testUygulamasi(const BayilerEkrani()));
      await t.pumpAndSettle();
      await satirMenusu(t, 'Anadolu Bilişim');
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      await t.tap(find.text('Bayiyi sil'));
      await t.pumpAndSettle();
      // 409 → müşteri seçenekleri; başka bayi olmadığı için yalnızca "platforma bağla".
      expect(find.textContaining('Bu bayiye bağlı müşteriler var.'), findsOneWidget);
      expect(find.text('Başka bayiye taşı'), findsNothing);
      final dugme = find.widgetWithText(FilledButton, 'Platforma bağla ve sil');
      expect(t.widget<FilledButton>(dugme).onPressed, isNull, reason: 'onay kutusu işaretlenmeden silinmez');
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(dugme);
      await t.pumpAndSettle();
      final silme = api.istekler.where((i) => i.$1 == 'DELETE').toList();
      expect(silme.length, 2);
      expect(silme.last.$4, {'detach': '1'});
      expect(find.text('Bayi silindi'), findsOneWidget);
    });

    testWidgets('müşterisi olan bayi başka bayiye taşınarak silinir', (t) async {
      ekranBoyutu(t, const Size(1400, 900));
      final api = SahteApi({
        'GET /api/v1/resellers/summary': {
          'items': [_bayi('r1', 'Anadolu Bilişim', 3), _bayi('r2', 'Ege Hosting', 5)],
        },
        'DELETE /api/v1/resellers/r1': (Object? _, Map<String, dynamic>? q) => null,
      });
      Uyg.api = api;
      await t.pumpWidget(testUygulamasi(const BayilerEkrani()));
      await t.pumpAndSettle();
      await satirMenusu(t, 'Anadolu Bilişim');
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      expect(find.textContaining('Bu bayiye bağlı 3 müşteri var.'), findsOneWidget);
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Ege Hosting').last);
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox));
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Taşı ve sil'));
      await t.pumpAndSettle();
      final silme = api.istekler.singleWhere((i) => i.$1 == 'DELETE');
      expect(silme.$2, '/api/v1/resellers/r1');
      expect(silme.$4, {'reassign_to': 'r2'});
    });

    testWidgets('yalnızca süper yönetici silebilir', (t) async {
      ekranBoyutu(t, const Size(1400, 900));
      kullaniciAyarla(rol: 'reseller_admin');
      Uyg.api = SahteApi({
        'GET /api/v1/resellers/summary': {
          'items': [_bayi('r1', 'Anadolu Bilişim', 0)],
        },
      });
      await t.pumpWidget(testUygulamasi(const BayilerEkrani()));
      await t.pumpAndSettle();
      await satirMenusu(t, 'Anadolu Bilişim');
      expect(find.text('Sil'), findsNothing);
    });
  });

  group('Yönetici silme', () {
    Map<String, Object?> yanitlar(Object? Function(Object?, Map<String, dynamic>?) sil) => {
      'GET /api/v1/users': {
        'items': [
          _kullanici('u1', 'yonetici@ornek.test', 'Deneme Yönetici', 'super_admin'),
          _kullanici('u3', 'ikinci@ornek.test', 'İkinci Süper', 'super_admin'),
        ],
      },
      'GET /api/v1/catalog': {'permissions': <Object>[], 'role_templates': <String, Object?>{}},
      'GET /api/v1/security/mfa-policy': {'required_roles': <String>[], 'editable': true},
      'DELETE /api/v1/users/u3': sil,
    };

    testWidgets('kendi hesabında Sil yok; başkasında onayla silinir', (t) async {
      ekranBoyutu(t, const Size(1500, 1000));
      final api = SahteApi(yanitlar((_, _) => null));
      Uyg.api = api;
      await t.pumpWidget(testUygulamasi(const YoneticilerEkrani()));
      await t.pumpAndSettle();
      await t.tap(find.text('Deneme Yönetici'));
      await t.pumpAndSettle();
      expect(find.text('Sil'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await t.tap(find.text('İkinci Süper'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      expect(find.text('Kullanıcı silinsin mi?'), findsOneWidget);
      await t.tap(find.text('Kalıcı olarak sil'));
      await t.pumpAndSettle();
      expect(api.istendi('DELETE', '/api/v1/users/u3'), isTrue);
      expect(find.text('Kullanıcı silindi'), findsOneWidget);
    });

    testWidgets('son süper yönetici silinemez: anlaşılır mesaj', (t) async {
      ekranBoyutu(t, const Size(1500, 1000));
      Uyg.api = SahteApi(yanitlar((_, _) => ApiHata(409, 'last super admin', kod: 'last_super_admin')));
      await t.pumpWidget(testUygulamasi(const YoneticilerEkrani()));
      await t.pumpAndSettle();
      await t.tap(find.text('İkinci Süper'));
      await t.pumpAndSettle();
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      await t.tap(find.text('Kalıcı olarak sil'));
      await t.pumpAndSettle();
      expect(find.text('Kullanıcı silinemedi'), findsOneWidget);
      expect(find.textContaining('son süper yönetici'), findsOneWidget);
    });
  });
}
