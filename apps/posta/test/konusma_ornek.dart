// 8 iletili örnek konuşma (biçimli + düz metin, ekli, alıntılı geçmiş, tekrarlanan imza). Tasarım görüntüleri ve
// konuşma testleri kullanır. Gerçek veri değildir.

import 'sahte_sunucu.dart';

const konusmaKonu = 'Kurumsal e-posta geçişi: teklif ve takvim';

String _t(int gun, int saat) => DateTime.utc(2026, 11, 10 + gun, saat).toIso8601String();

const _imzaAyse = 'Ayşe Yılmaz\nSatış Müdürü · Örnek Bilişim\n+90 212 000 00 00';
const _imzaAyseHtml = '<div class="gmail_signature">Ayşe Yılmaz<br>Satış Müdürü · Örnek Bilişim<br>+90 212 000 00 00</div>';

String _alintiHtml(String kim, String metin) =>
    '<div class="gmail_quote"><div class="gmail_attr">20 Kas 2026 Per, 10:00 tarihinde $kim şunu yazdı:</div><blockquote class="gmail_quote">$metin</blockquote></div>';

/// (id, kimden, tarih, okundu, düz metin, html, ekler)
final konusmaIletileri = <(String, String, String, bool, String, String, List<Map<String, Object>>)>[
  (
    'k1',
    'Ayşe Yılmaz <ayse@ornek.com>',
    _t(0, 9),
    true,
    'Merhaba Semih Bey,\n\nGörüşmemizde konuştuğumuz kurumsal e-posta geçişi için teklifimizi ekte bulabilirsiniz. 120 kullanıcı, 50 GB kutu ve arşivleme dahil.\n\n-- \n$_imzaAyse',
    '<p>Merhaba Semih Bey,</p><p>Görüşmemizde konuştuğumuz <b>kurumsal e-posta geçişi</b> için teklifimizi ekte bulabilirsiniz. 120 kullanıcı, 50 GB kutu ve arşivleme dahil.</p>$_imzaAyseHtml',
    [
      {'index': 1, 'filename': 'Teklif-2026-114.pdf', 'content_type': 'application/pdf', 'size': 482133},
      {'index': 2, 'filename': 'Fiyat-tablosu.xlsx', 'content_type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'size': 38211},
    ],
  ),
  (
    'k2',
    'Semih Boğa <semih@ornek.com>',
    _t(0, 11),
    true,
    'Teşekkürler Ayşe Hanım, ekiple inceleyip döneceğim.\n\n20 Kas 2026 Per, 09:00 tarihinde Ayşe Yılmaz şunu yazdı:\n> Merhaba Semih Bey,\n> Görüşmemizde konuştuğumuz kurumsal e-posta geçişi için teklifimizi ekte bulabilirsiniz.',
    '',
    [],
  ),
  (
    'k3',
    'Can Demir <can@ornek.com>',
    _t(1, 10),
    true,
    'Arkadaşlar, geçiş takvimi taslağını ekledim. Hafta sonu kesintisiz geçiş öneriyorum.',
    '<p>Arkadaşlar, geçiş takvimi taslağını ekledim. Hafta sonu <i>kesintisiz</i> geçiş öneriyorum.</p>${_alintiHtml('Semih Boğa', 'Teşekkürler Ayşe Hanım, ekiple inceleyip döneceğim.')}',
    [
      {'index': 1, 'filename': 'gecis-takvimi.png', 'content_type': 'image/png', 'size': 214500},
      {'index': 2, 'filename': 'mevcut-yapi.png', 'content_type': 'image/png', 'size': 188020},
      {'index': 3, 'filename': 'Gecis-Plani-v2.docx', 'content_type': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'size': 96400},
    ],
  ),
  (
    'k4',
    'Ayşe Yılmaz <ayse@ornek.com>',
    _t(1, 14),
    true,
    'Takvim bize uyar. DNS değişikliklerini cuma akşamı yapabiliriz.\n\n-- \n$_imzaAyse',
    '<p>Takvim bize uyar. DNS değişikliklerini cuma akşamı yapabiliriz.</p>$_imzaAyseHtml${_alintiHtml('Can Demir', 'Arkadaşlar, geçiş takvimi taslağını ekledim.')}',
    [],
  ),
  (
    'k5',
    'Semih Boğa <semih@ornek.com>',
    _t(2, 9),
    true,
    'Bütçe onayı için finans ekibine ilettim. Fiyat tablosundaki arşivleme kalemini netleştirebilir miyiz?',
    '',
    [],
  ),
  (
    'k6',
    'Ayşe Yılmaz <ayse@ornek.com>',
    _t(2, 16),
    true,
    'Arşivleme 10 yıl saklama ve e-keşif içeriyor; güncel tabloyu ekledim.\n\n-- \n$_imzaAyse',
    '<p>Arşivleme <b>10 yıl saklama</b> ve e-keşif içeriyor; güncel tabloyu ekledim.</p>$_imzaAyseHtml${_alintiHtml('Semih Boğa', 'Bütçe onayı için finans ekibine ilettim.')}',
    [
      {'index': 1, 'filename': 'Fiyat-tablosu-v2.xlsx', 'content_type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'size': 40122},
    ],
  ),
  (
    'k7',
    'Can Demir <can@ornek.com>',
    _t(3, 10),
    false,
    'Finans onayladı. Sözleşme taslağını hukuktan aldım, ekte. Pazartesi imzaya hazır olur.',
    '<p>Finans onayladı. Sözleşme taslağını hukuktan aldım, ekte. Pazartesi imzaya hazır olur.</p>',
    [
      {'index': 1, 'filename': 'Sozlesme-taslagi.pdf', 'content_type': 'application/pdf', 'size': 812000},
    ],
  ),
  (
    'k8',
    'Ayşe Yılmaz <ayse@ornek.com>',
    _t(3, 15),
    false,
    'Harika! Pazartesi 14:00 için imza toplantısı planlayalım mı? Takvim davetini gönderiyorum.\n\n-- \n$_imzaAyse',
    '<p>Harika! Pazartesi 14:00 için imza toplantısı planlayalım mı? Takvim davetini gönderiyorum.</p>$_imzaAyseHtml${_alintiHtml('Can Demir', 'Finans onayladı. Sözleşme taslağını hukuktan aldım.')}',
    [],
  ),
];

Map<String, Object?> _ozet((String, String, String, bool, String, String, List<Map<String, Object>>) m) => {
  'id': m.$1,
  'folder_id': 'g',
  'subject': m.$1 == 'k1' ? konusmaKonu : 'Re: $konusmaKonu',
  'from': m.$2,
  'to': 'Semih Boğa <semih@ornek.com>',
  'date': m.$3,
  'seen': m.$4,
  'preview': m.$5.split('\n').first,
  'has_attachments': m.$7.isNotEmpty,
  'labels': ['e2'],
  'message_id': '<${m.$1}@ornek.com>',
};

/// Sahte sunucuya konuşma uçlarını kurar.
void konusmaKur(YolSunucusu s) {
  final ozetler = [for (final m in konusmaIletileri) _ozet(m)];
  for (final m in konusmaIletileri) {
    s.yollar['GET /api/v1/mail/messages/${m.$1}/thread'] = (200, {'items': ozetler});
    s.yollar['GET /api/v1/mail/messages/${m.$1}'] = (
      200,
      {
        'message': _ozet(m),
        'view': {
          'subject': _ozet(m)['subject'],
          'from': [
            {'name': m.$2.split(' <').first, 'email': m.$2.split('<').last.replaceAll('>', '')},
          ],
          'to': [
            {'name': 'Semih Boğa', 'email': 'semih@ornek.com'},
            if (m.$1 == 'k3' || m.$1 == 'k7') {'name': 'Ayşe Yılmaz', 'email': 'ayse@ornek.com'},
          ],
          'cc': [
            if (m.$1 != 'k2') {'name': 'Can Demir', 'email': 'can@ornek.com'},
          ],
          'reply_to': [],
          'date': m.$3,
          'text': m.$5,
          'html': m.$6,
          'attachments': m.$7,
        },
      },
    );
    s.yollar['PATCH /api/v1/mail/messages/${m.$1}'] = (200, {'ok': true});
  }
  s.yollar['GET /api/v1/mail/messages'] = (200, {'items': ozetler.reversed.toList(), 'total': ozetler.length, 'page': 1, 'page_size': 25});
  s.yollar['POST /api/v1/mail/actions'] = (200, {'ok': true});
}
