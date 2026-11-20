import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:posta/veri/html_temizle.dart';
import 'package:posta/veri/modeller.dart';
import 'package:posta/veri/yardimci.dart';
import 'package:posta/veri/yazma_hazirla.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('adres ayrıştırma', () {
    test('ad ve adres', () {
      final a = adresCoz('Ayşe Yılmaz <ayse@firma.com.tr>');
      expect(a.ad, 'Ayşe Yılmaz');
      expect(a.eposta, 'ayse@firma.com.tr');
    });

    test('tırnaklı ad ve çıplak adres', () {
      expect(adresCoz('"Yılmaz, Ayşe" <ayse@firma.com>').ad, 'Yılmaz, Ayşe');
      final b = adresCoz('  <ali@ornek.com> ');
      expect(b.ad, '');
      expect(b.eposta, 'ali@ornek.com');
    });

    test('liste: tırnak içindeki virgül bölmez', () {
      final l = adresListesiCoz('"Yılmaz, Ayşe" <ayse@a.com>, ali@b.com; Veli <veli@c.com>');
      expect(l.map((a) => a.eposta), ['ayse@a.com', 'ali@b.com', 'veli@c.com']);
      expect(l.first.ad, 'Yılmaz, Ayşe');
    });

    test('biçimleme özel karakterde tırnaklar', () {
      expect(adresYaz(const Adres('Ali', 'ali@a.com')), 'Ali <ali@a.com>');
      expect(adresYaz(const Adres('Yılmaz, Ali', 'ali@a.com')), '"Yılmaz, Ali" <ali@a.com>');
      expect(adresYaz(const Adres('', 'ali@a.com')), 'ali@a.com');
    });

    test('görünen ad', () {
      expect(gorunenAd('Ali Veli <ali@a.com>'), 'Ali Veli');
      expect(gorunenAd('ali@a.com'), 'ali@a.com');
      expect(gorunenAd(''), '(gönderen yok)');
    });

    test('e-posta doğrulama', () {
      expect(gecerliEposta('ali@firma.com.tr'), isTrue);
      expect(gecerliEposta('ali@şirket.com'), isTrue);
      expect(gecerliEposta('ali@firma'), isFalse);
      expect(gecerliEposta('ali firma@a.com'), isFalse);
      expect(gecerliEposta(''), isFalse);
      expect(aliciCoz('Ali <ali@a.com>,')?.eposta, 'ali@a.com');
      expect(aliciCoz('yanlis'), isNull);
    });
  });

  group('tarih grupları', () {
    // 2026-11-19 Perşembe
    final simdi = DateTime(2026, 11, 19, 15, 30);
    test('bugün, dün, bu hafta, geçen hafta, bu ay, eski ay', () {
      expect(tarihGrubu(DateTime(2026, 11, 19, 8), simdi), 'Bugün');
      expect(tarihGrubu(DateTime(2026, 11, 18, 23), simdi), 'Dün');
      expect(tarihGrubu(DateTime(2026, 11, 16, 9), simdi), 'Bu hafta'); // Pazartesi
      expect(tarihGrubu(DateTime(2026, 11, 15, 9), simdi), 'Geçen hafta'); // Pazar
      expect(tarihGrubu(DateTime(2026, 11, 3), simdi), 'Bu ay');
      expect(tarihGrubu(DateTime(2026, 10, 3), simdi), 'Ekim 2026');
      expect(tarihGrubu(DateTime(2025, 1, 3), simdi), 'Ocak 2025');
    });
    test('gelecek tarih bugün sayılır', () {
      expect(tarihGrubu(DateTime(2026, 11, 20), simdi), 'Bugün');
    });
  });

  group('alıntılama ve konu', () {
    test('önek tekrarlanmaz', () {
      expect(onekli('Re', 'Toplantı'), 'Re: Toplantı');
      expect(onekli('Re', 'RE: Toplantı'), 'RE: Toplantı');
      expect(onekli('Re', 'Ynt: Toplantı'), 'Ynt: Toplantı');
      expect(onekli('Fwd', 'Fw: Rapor'), 'Fw: Rapor');
      expect(onekli('Fwd', 'Rapor'), 'Fwd: Rapor');
    });

    test('düz metin alıntısı', () {
      expect(alintila('Merhaba\n\nNasılsın?\n> eski\n\n'), '> Merhaba\n>\n> Nasılsın?\n>> eski');
    });

    test('alıntılanan geçmiş ayrılır', () {
      final p = alintiAyir('Teşekkürler.\n\n19 Kasım 2026 10:00 tarihinde Ali <ali@a.com> yazdı:\n> soru');
      expect(p.ana, 'Teşekkürler.');
      expect(p.alinti, startsWith('19 Kasım'));
      final q = alintiAyir('Tamam\n> önceki\n> satır\n');
      expect(q.ana, 'Tamam');
      expect(q.alinti, contains('> önceki'));
      expect(alintiAyir('Sadece metin').alinti, '');
    });

    test('HTML kaçışı', () {
      expect(metindenHtml('a < b & "c"\nd'), 'a &lt; b &amp; &quot;c&quot;<br>d');
    });
  });

  group('yanıt alıcıları', () {
    const ben = 'ben@firma.com';
    test('yanıt: Reply-To öncelikli', () {
      final r = yanitAlicilari(
        kimden: const [Adres('Ali', 'ali@a.com')],
        yanitAdresi: const [Adres('', 'destek@a.com')],
        kime: const [Adres('', ben)],
        bilgi: const [],
        ben: ben,
        tumu: false,
      );
      expect(r.kime.map((a) => a.eposta), ['destek@a.com']);
      expect(r.bilgi, isEmpty);
    });

    test('tümünü yanıtla: kendisi ve tekrarlar çıkar', () {
      final r = yanitAlicilari(
        kimden: const [Adres('Ali', 'ali@a.com')],
        yanitAdresi: const [],
        kime: const [Adres('', 'BEN@firma.com'), Adres('', 'veli@a.com')],
        bilgi: const [Adres('', 'ali@a.com'), Adres('', 'can@a.com')],
        ben: ben,
        tumu: true,
      );
      expect(r.kime.map((a) => a.eposta), ['ali@a.com']);
      expect(r.bilgi.map((a) => a.eposta), ['veli@a.com', 'can@a.com']);
    });

    test('kendi gönderdiği iletiye yanıt asıl alıcılara gider', () {
      final r = yanitAlicilari(
        kimden: const [Adres('Ben', ben)],
        yanitAdresi: const [],
        kime: const [Adres('', 'musteri@b.com')],
        bilgi: const [],
        ben: ben,
        tumu: false,
      );
      expect(r.kime.map((a) => a.eposta), ['musteri@b.com']);
    });
  });

  group('kota', () {
    test('1 PiB ve üstü sınırsız', () {
      expect(sinirsizKota(1125899906842624), isTrue);
      expect(sinirsizKota(0), isTrue);
      expect(sinirsizKota(5 * 1024 * 1024 * 1024), isFalse);
    });
  });

  group('HTML temizleme', () {
    test('betik, olay ve uzak görsel atılır', () {
      final t = htmlTemizle('<p onclick="x()">Merhaba</p><script>alert(1)</script><img src="https://iz.example/p.gif"><a href="javascript:x">b</a>');
      expect(t.html, isNot(contains('script')));
      expect(t.html, isNot(contains('onclick')));
      expect(t.html, isNot(contains('iz.example')));
      expect(t.html, isNot(contains('javascript')));
      expect(t.engellenen, 1);
    });

    test('vekil görsel ve cid değiştirilir, korunan bağlantı uygulanır', () {
      final t = htmlTemizle(
        '<img src="https://a.com/x.png"><img src="cid:Logo1"><a href="https://a.com/l">l</a>',
        uzak: {'https://a.com/x.png': 'data:image/png;base64,AA'},
        cid: {'logo1': 'data:image/png;base64,BB'},
        baglantilar: {'https://a.com/l': '/api/v1/click/abc'},
        kok: 'https://posta.example',
      );
      expect(t.html, contains('data:image/png;base64,AA'));
      expect(t.html, contains('data:image/png;base64,BB'));
      expect(t.html, contains('https://posta.example/api/v1/click/abc'));
      expect(t.engellenen, 0);
    });

    test('uzak görsel listesi', () {
      expect(
        uzakGorseller('<img src="https://a.com/1.png"><img src="data:image/png;base64,AA"><table><tr><td background="//b.com/2.png">x</td></tr></table>'),
        ['https://a.com/1.png', '//b.com/2.png'],
      );
    });

    test('HTML → düz metin', () {
      expect(htmlMetne('<p>Merhaba<br>dünya</p><ul><li>bir</li><li>iki</li></ul>'), 'Merhaba\ndünya\n\n• bir\n• iki');
    });

    test('alıntı katlanır', () {
      final h = alintilariKatla('<p>Yanıt</p><blockquote type="cite">eski</blockquote>');
      expect(h, contains('<details class="bm-quote">'));
      // Yalnızca alıntı varsa katlanmaz.
      expect(alintilariKatla('<blockquote type="cite">eski</blockquote>'), isNot(contains('details')));
    });
  });

  group('yazma hazırlığı', () {
    IletiDetay ileti() => IletiDetay.json({
      'message': {'id': 'm1', 'subject': 'Teklif', 'from': 'Ali <ali@a.com>', 'seen': true},
      'view': {
        'subject': 'Teklif',
        'from': [
          {'name': 'Ali', 'email': 'ali@a.com'},
        ],
        'to': [
          {'name': '', 'email': 'ben@firma.com'},
        ],
        'cc': [
          {'name': 'Can', 'email': 'can@a.com'},
        ],
        'reply_to': [],
        'date': '2026-11-19T10:00:00Z',
        'message_id': '<abc@a.com>',
        'text': 'Fiyat ekte.',
        'html': '',
        'attachments': [
          {'index': 2, 'filename': 'teklif.pdf', 'content_type': 'application/pdf', 'size': 1200, 'inline': false},
          {'index': 3, 'filename': 'logo.png', 'content_type': 'image/png', 'size': 10, 'inline': true, 'content_id': 'logo'},
        ],
      },
    });

    test('yanıt', () {
      final b = yanitHazirla(ileti(), ben: 'ben@firma.com', tumu: true);
      expect(b.konu, 'Re: Teklif');
      expect(b.kime.single.eposta, 'ali@a.com');
      expect(b.bilgi.single.eposta, 'can@a.com');
      expect(b.inReplyTo, '<abc@a.com>');
      expect(b.yanitlananId, 'm1');
      expect(b.alintiMetin, contains('> Fiyat ekte.'));
      expect(b.alintiHtml, contains('data-quote'));
    });

    test('iletme: yalnızca dosya ekleri dahil edilir', () {
      final b = iletHazirla(ileti());
      expect(b.konu, 'Fwd: Teklif');
      expect(b.dahilEkler.map((e) => e.sira), [2]);
      expect(b.iletilenId, 'm1');
      expect(b.alintiMetin, contains('İletilen ileti'));
    });

    test('gövde: metin + imza + alıntı', () {
      final g = govdeOlustur(metin: 'Merhaba <dünya>\n', imzaHtml: '<b>Ali</b><script>x</script>', alintiHtml: '<div data-quote>q</div>', alintiMetin: '> q');
      expect(g.metin, 'Merhaba <dünya>\n\n-- \nAli\n\n> q');
      expect(g.html, startsWith('<div>Merhaba &lt;dünya&gt;</div>'));
      expect(g.html, contains('data-signature'));
      expect(g.html, isNot(contains('script')));
      expect(g.html, endsWith('<div data-quote>q</div>'));
    });
  });

  group('modeller', () {
    test('eksik alanlar çökertmez', () {
      final o = IletiOzet.json({'id': 'x'});
      expect(o.konu, '');
      expect(o.tarih, isNull);
      expect(o.etiketler, isEmpty);
      final d = IletiDetay.json(null);
      expect(d.gorunum.ekler, isEmpty);
      final a = PostaAyarlari.json({
        'settings': {'signature': 'Ali'},
      });
      expect(a.etkinImzaHtml, 'Ali');
      expect(Klasor.json({'id': 'k', 'role': 'inbox', 'name': 'INBOX'}).gorunenAd, 'Gelen Kutusu');
    });
  });
}
