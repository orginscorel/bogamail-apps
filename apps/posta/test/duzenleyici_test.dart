// Biçimli düzenleyici: web ile aynı gövde yapısı (yazı bloğu, [data-signature], alıntı), imza aç/kapa, şablon ekleme,
// araç çubuğu komutları. Web görünümü olmayan test ortamında bellek motoru kullanılır. Ağ yok.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:posta/ortak/zengin_duzenleyici.dart';

void main() {
  const ilk = '<div><br></div><div><br></div><div data-signature="">Ayşe<br>Boga</div><div><br></div><blockquote>eski</blockquote>';

  Future<ZenginDenetleyici> kur(WidgetTester t, {String html = ilk}) async {
    final d = ZenginDenetleyici(ilkHtml: html);
    await t.pumpWidget(
      MaterialApp(
        theme: temaKur(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(child: ZenginDuzenleyici(denetleyici: d)),
        ),
      ),
    );
    return d;
  }

  testWidgets('yazılan metin ilk bloğa girer; imza ve alıntı korunur; düz metin innerText gibi', (t) async {
    final d = await kur(t);
    var kirli = false;
    d.degisti = () => kirli = true;
    // Web bodyHasContent gibi: imza sayılmaz, alıntı sayılır.
    expect(d.bos, isFalse);
    expect(d.imzaVar, isTrue);
    await t.enterText(find.byKey(const ValueKey('zengin-metin')), 'Merhaba\n<dünya>');
    expect(kirli, isTrue);
    expect(d.bos, isFalse);
    final c = await d.icerik();
    expect(c.html, '<div>Merhaba<br>&lt;dünya&gt;</div><div><br></div><div data-signature="">Ayşe<br>Boga</div><div><br></div><blockquote>eski</blockquote>');
    expect(c.metin, contains('Merhaba'));
    expect(c.metin, contains('Ayşe'));
    expect(c.metin, contains('eski'));
  });

  testWidgets('imza aç/kapa: blok kaldırılır, alıntıdan önce geri eklenir (web toggleSignature)', (t) async {
    final d = await kur(t);
    await d.imzaDegistir('Ayşe');
    expect(d.imzaVar, isFalse);
    expect((await d.icerik()).html, '<div><br></div><div><br></div><div><br></div><blockquote>eski</blockquote>');
    await d.imzaDegistir('<b>Ayşe</b><script>x()</script>');
    expect(d.imzaVar, isTrue);
    expect((await d.icerik()).html, '<div><br></div><div><br></div><div><br></div><div data-signature=""><b>Ayşe</b></div><blockquote>eski</blockquote>');
  });

  testWidgets('şablon HTML olarak eklenir ve temizlenir', (t) async {
    final d = await kur(t, html: '<div><br></div>');
    expect(d.bos, isTrue);
    await d.htmlEkle('<p onclick="x()">Şablon <i>metni</i></p><iframe src="x"></iframe>');
    final h = (await d.icerik()).html;
    expect(h, '<div><br></div><p>Şablon <i>metni</i></p>');
    expect(d.bos, isFalse);
  });

  testWidgets('araç çubuğu web ile aynı komutları gönderir', (t) async {
    final d = await kur(t);
    final m = d.motor! as BellekMotoru;
    for (final ad in [
      'Kalın (Ctrl+B)',
      'İtalik (Ctrl+I)',
      'Altı çizili (Ctrl+U)',
      'Üstü çizili',
      'Madde işaretli liste',
      'Numaralı liste',
      'Girintiyi artır',
      'Girintiyi azalt',
      'Sola hizala',
      'Ortala',
      'Sağa hizala',
      'Alıntı',
      'Yatay çizgi',
      'Geri al (Ctrl+Z)',
      'Yinele (Ctrl+Y)',
      'Biçimlendirmeyi temizle',
    ]) {
      final f = find.byKey(ValueKey('bicim-$ad'));
      await t.ensureVisible(f);
      await t.tap(f);
      await t.pump();
    }
    expect(m.komutlar.map((k) => k.$1), [
      'bold',
      'italic',
      'underline',
      'strikeThrough',
      'insertUnorderedList',
      'insertOrderedList',
      'indent',
      'outdent',
      'justifyLeft',
      'justifyCenter',
      'justifyRight',
      'formatBlock',
      'insertHorizontalRule',
      'undo',
      'redo',
      'removeFormat',
      'unlink',
    ]);
    expect(m.komutlar[11].$2, 'blockquote');

    // Yazı boyutu ve renkler.
    await t.ensureVisible(find.byKey(const ValueKey('bicim-Yazı boyutu')));
    await t.tap(find.byKey(const ValueKey('bicim-Yazı boyutu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Büyük'));
    await t.pumpAndSettle();
    expect(m.komutlar.last, ('fontSize', '5'));
    await t.ensureVisible(find.byKey(const ValueKey('bicim-Yazı rengi')));
    await t.tap(find.byKey(const ValueKey('bicim-Yazı rengi')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('renk-#dc2626')));
    await t.pumpAndSettle();
    expect(m.komutlar.last, ('foreColor', '#dc2626'));
    await t.ensureVisible(find.byKey(const ValueKey('bicim-Vurgu rengi')));
    await t.tap(find.byKey(const ValueKey('bicim-Vurgu rengi')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('renk-#fef08a')));
    await t.pumpAndSettle();
    expect(m.komutlar.last, ('hiliteColor', '#fef08a'));

    // Bağlantı: şemasız adres https ile tamamlanır.
    await t.ensureVisible(find.byKey(const ValueKey('bicim-Bağlantı ekle')));
    await t.tap(find.byKey(const ValueKey('bicim-Bağlantı ekle')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('baglanti-adres')), 'ornek.com');
    await t.enterText(find.byKey(const ValueKey('baglanti-metin')), 'Örnek');
    await t.tap(find.text('Ekle'));
    await t.pumpAndSettle();
    expect((await d.icerik()).html, startsWith('<div><br><a href="https://ornek.com">Örnek</a></div>'));
  });
}
