import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../oturum.dart';
import '../../ortak/html_govde.dart';
import '../../veri/durum.dart';
import '../../veri/hesap_servisi.dart';
import '../../veri/html_temizle.dart';
import '../../veri/modeller.dart';
import '../../veri/posta_servisi.dart';
import '../../veri/tercihler.dart';
import '../../veri/yardimci.dart';
import 'profil.dart';

/// Sunucunun desteklediği imza değişkenleri (internal/signature).
const imzaDegiskenleri = {
  'ad': 'Ad soyad',
  'unvan': 'Unvan',
  'departman': 'Departman',
  'sirket': 'Şirket',
  'telefon': 'Telefon',
  'cep': 'Cep telefonu',
  'eposta': 'E-posta',
  'web': 'Web adresi',
};

/// Hazır biçimli imza şablonu (boş değişkenli satırlar gönderimde kendiliğinden düşer: data-optional).
const imzaSablonu = '''<div style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#1f2937;line-height:1.45">
<div style="font-size:15px;font-weight:bold;color:#111827">{{ad}}</div>
<div data-optional="unvan" style="color:#4b5563">{{unvan}}</div>
<div data-optional="departman" style="color:#6b7280">{{departman}}</div>
<div style="margin-top:6px;font-weight:bold;color:#5443d2">{{sirket}}</div>
<div data-optional="telefon">Tel: {{telefon}}</div>
<div data-optional="cep">Cep: {{cep}}</div>
<div><a href="mailto:{{eposta}}" style="color:#5443d2">{{eposta}}</a></div>
<div data-optional="web"><a href="{{web}}" style="color:#5443d2">{{web}}</a></div>
</div>''';

/// İmza yönetimi: düz metin veya biçimli (HTML, görsel ve değişkenlerle), önizleme, kurum politikası, varsayılan kullanım.
class ImzaEkrani extends StatefulWidget {
  const ImzaEkrani({super.key});
  @override
  State<ImzaEkrani> createState() => _ImzaEkraniState();
}

class _ImzaEkraniState extends State<ImzaEkrani> {
  PostaAyarlari? _a;
  ImzaProfili? _profil;
  String? _hata;
  bool _bicimli = false;
  final _metin = TextEditingController();
  final _html = TextEditingController();
  bool _kirli = false;
  bool _kaydediyor = false;
  int _sekme = 0; // biçimli: 0 düzenle, 1 önizleme

  @override
  void initState() {
    super.initState();
    _yukle();
    _metin.addListener(_degisti);
    _html.addListener(_degisti);
  }

  @override
  void dispose() {
    _metin.dispose();
    _html.dispose();
    super.dispose();
  }

  void _degisti() {
    if (!_kirli && mounted) setState(() => _kirli = true);
  }

  Future<void> _yukle() async {
    try {
      final a = await Posta.ayarlar();
      ImzaProfili? p;
      try {
        p = await Hesap.profil();
      } catch (_) {}
      if (!mounted) return;
      PostaDurum.ben.ayarlar = a;
      final zengin = a.imzaHtml.trim().isNotEmpty && a.imzaHtml.trim() != metindenHtml(a.imza.trim());
      setState(() {
        _a = a;
        _profil = p;
        _bicimli = zengin;
        _metin.text = a.imza.isNotEmpty ? a.imza : htmlMetne(a.imzaHtml);
        _html.text = a.imzaHtml.isNotEmpty ? a.imzaHtml : metindenHtml(a.imza);
        _kirli = false;
        _hata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  /// Değişkenleri önizleme için yerelde doldurur (sunucu gönderimde aynısını yapar).
  String _doldur(String tpl) {
    final p = _profil;
    final kutu = Uyg.kutu.value;
    final v = <String, String>{
      'ad': Uyg.ad.trim().isNotEmpty ? Uyg.ad.trim() : Uyg.adres,
      'unvan': p?.unvan ?? '',
      'departman': p?.departman ?? '',
      'sirket': '${kutu?['organization_name'] ?? kutu?['company'] ?? ''}',
      'telefon': p?.telefon ?? '',
      'cep': p?.cep ?? '',
      'eposta': Uyg.adres,
      'web': p?.web ?? '',
      ...?p?.sosyal,
    };
    var s = tpl.replaceAllMapped(
      RegExp(r'<(span|div|p|tr|td|a|li)\b[^>]*\bdata-optional="([a-zA-Z_]+)"[^>]*>.*?</\1>', caseSensitive: false, dotAll: true),
      (m) => (v[m.group(2)!.toLowerCase()] ?? '').isEmpty ? '' : m.group(0)!,
    );
    s = s.replaceAllMapped(RegExp(r'\{\{\s*([a-zA-Z_]+)\s*\}\}'), (m) {
      final d = v[m.group(1)!.toLowerCase()];
      return d == null ? m.group(0)! : htmlKacis(d);
    });
    return s;
  }

  void _ekle(String once, [String sonra = '']) {
    final t = _html.text;
    final s = _html.selection;
    final bas = s.isValid ? s.start : t.length;
    final son = s.isValid ? s.end : t.length;
    final secili = t.substring(bas, son);
    final yeni = t.replaceRange(bas, son, '$once$secili$sonra');
    _html.value = TextEditingValue(
      text: yeni,
      selection: TextSelection.collapsed(offset: bas + once.length + secili.length + (secili.isEmpty ? 0 : sonra.length)),
    );
  }

  Future<void> _baglanti() async {
    final u = await metinSor(context, 'Bağlantı adresi', ipucu: 'https://', tamam: 'Ekle');
    if (u == null || u.trim().isEmpty) return;
    var adr = u.trim();
    if (!adr.contains(':')) adr = 'https://$adr';
    _ekle('<a href="${htmlKacis(adr)}" style="color:#5443d2">', '</a>');
  }

  /// Logo/görsel: galeriden seçilir, küçültülür ve imzaya gömülür (data: URI; PNG/JPEG).
  Future<void> _gorsel() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 300, imageQuality: 85);
      if (f == null) return;
      final b = await f.readAsBytes();
      final sinir = _a?.azamiImza ?? 0;
      if (b.length > 200 * 1024 || (sinir > 0 && b.length * 4 / 3 > sinir)) {
        bildir('Görsel çok büyük', mesaj: 'İmza görseli küçük olmalı (en fazla ~200 KB). Daha küçük bir logo seçin.', tur: MesajTur.uyari);
        return;
      }
      final tur = f.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      _ekle('<img src="data:$tur;base64,${base64Encode(b)}" alt="logo" style="max-width:200px;height:auto;display:block;margin:4px 0">');
    } catch (e) {
      bildir('Görsel eklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _kaydet() async {
    final a = _a!;
    final d = <String, dynamic>{};
    if (_bicimli) {
      final h = _html.text.trim();
      d['signature_html'] = h;
      d['signature'] = h.isEmpty ? '' : htmlMetne(h);
    } else {
      final m = _metin.text.trimRight();
      final zengin = a.imzaHtml.trim().isNotEmpty && a.imzaHtml.trim() != metindenHtml(a.imza.trim());
      if (zengin && !await onayla(context, 'Biçimli imza düz metne çevrilsin mi?', mesaj: 'Görseller, renkler ve bağlantılar kaldırılır.', evet: 'Çevir')) {
        return;
      }
      d['signature'] = m;
      d['signature_html'] = m.isEmpty ? '' : metindenHtml(m);
    }
    setState(() => _kaydediyor = true);
    try {
      await Posta.ayarKaydet(d);
      bildir('İmza kaydedildi', tur: MesajTur.basari);
      await _yukle();
    } catch (e) {
      bildir('İmza kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _kaydediyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final a = _a;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('İmza')),
        body: _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor(),
      );
    }
    final kilitli = a.imzaKilitli;
    return PopScope(
      canPop: !_kirli,
      onPopInvokedWithResult: (cikti, _) async {
        if (cikti) return;
        if (await onayla(context, 'Değişiklikler kaydedilmedi', mesaj: 'Çıkarsanız imzadaki değişiklikler kaybolur.', evet: 'Çık', tehlikeli: true)) {
          setState(() => _kirli = false);
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('İmza'),
          actions: [
            if (!kilitli)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(onPressed: _kirli && !_kaydediyor ? _kaydet : null, child: const Text('Kaydet')),
              ),
          ],
          bottom: _kaydediyor ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (kilitli || a.imzaKurumdan)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: r.vurguYumusak, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Icon(kilitli ? Icons.lock_outline_rounded : Icons.apartment_rounded, color: r.vurgu),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        kilitli
                            ? 'İmzanız kurumunuzun şablonuyla belirleniyor ve değiştirilemez. Bilgilerinizi "İmza bilgilerim" bölümünden güncelleyebilirsiniz.'
                            : 'Kendi imzanız boşsa kurumunuzun imza şablonu kullanılır.',
                        style: TextStyle(color: r.metin, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (kilitli) ...[
              const Baslik('Etkin imza'),
              _onizleme(a.etkinImzaHtml, doldur: false),
            ] else ...[
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.notes_rounded), label: Text('Düz metin')),
                  ButtonSegment(value: true, icon: Icon(Icons.format_paint_outlined), label: Text('Biçimli')),
                ],
                selected: {_bicimli},
                onSelectionChanged: (v) => setState(() {
                  _bicimli = v.first;
                  if (_bicimli && _html.text.trim().isEmpty && _metin.text.trim().isNotEmpty) _html.text = metindenHtml(_metin.text.trim());
                  if (!_bicimli && _metin.text.trim().isEmpty && _html.text.trim().isNotEmpty) _metin.text = htmlMetne(_html.text);
                  _kirli = true;
                }),
              ),
              const SizedBox(height: 12),
              if (!_bicimli)
                TextField(
                  key: const ValueKey('imza-metin'),
                  controller: _metin,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(labelText: 'İmza', alignLabelWithHint: true, hintText: 'Ad Soyad\nUnvan · Şirket\nTelefon'),
                )
              else
                _bicimliDuzenleyici(r),
            ],
            const Baslik('Ne zaman eklensin?'),
            Kutu(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: Tercihler.imzaYeni,
                    builder: (_, v, _) => SwitchListTile.adaptive(
                      value: v,
                      onChanged: (x) => Tercihler.imzaVarsayilanAyarla(yeni: x),
                      title: const Text('Yeni iletilerde'),
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: Tercihler.imzaYanit,
                    builder: (_, v, _) => SwitchListTile.adaptive(
                      value: v,
                      onChanged: (x) => Tercihler.imzaVarsayilanAyarla(yanit: x),
                      title: const Text('Yanıt ve iletmelerde'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                'Yazarken imza kartından tek dokunuşla eklenip kaldırılabilir. Bu tercih bu cihazda saklanır.',
                style: TextStyle(color: r.silik, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('İmza bilgilerim'),
              subtitle: const Text('Unvan, departman, telefon, web ve sosyal bağlantılar ({{unvan}} gibi değişkenleri doldurur)'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImzaProfiliEkrani()));
                _yukle();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _bicimliDuzenleyici(Renkler r) {
    Widget arac(IconData i, String ipucu, VoidCallback f) =>
        IconButton(tooltip: ipucu, icon: Icon(i, size: 20), onPressed: f, visualDensity: VisualDensity.compact);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 0, label: Text('Düzenle')),
            ButtonSegment(value: 1, label: Text('Önizleme')),
          ],
          selected: {_sekme},
          onSelectionChanged: (v) => setState(() => _sekme = v.first),
        ),
        const SizedBox(height: 10),
        if (_sekme == 1)
          _onizleme(_html.text)
        else ...[
          Container(
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
            child: Wrap(
              children: [
                arac(Icons.format_bold_rounded, 'Kalın', () => _ekle('<b>', '</b>')),
                arac(Icons.format_italic_rounded, 'İtalik', () => _ekle('<i>', '</i>')),
                arac(Icons.format_underlined_rounded, 'Altı çizili', () => _ekle('<u>', '</u>')),
                arac(Icons.format_color_text_rounded, 'Marka rengi', () => _ekle('<span style="color:#5443d2">', '</span>')),
                arac(Icons.link_rounded, 'Bağlantı', _baglanti),
                arac(Icons.image_outlined, 'Logo / görsel', _gorsel),
                arac(Icons.keyboard_return_rounded, 'Satır sonu', () => _ekle('<br>')),
                PopupMenuButton<String>(
                  tooltip: 'Değişken ekle',
                  icon: const Icon(Icons.data_object_rounded, size: 20),
                  onSelected: (k) => _ekle('{{$k}}'),
                  itemBuilder: (_) => [for (final e in imzaDegiskenleri.entries) PopupMenuItem(value: e.key, child: Text('${e.value}  ·  {{${e.key}}}'))],
                ),
                arac(Icons.auto_awesome_outlined, 'Hazır şablon', () async {
                  if (_html.text.trim().isNotEmpty &&
                      !await onayla(context, 'Hazır şablon uygulansın mı?', mesaj: 'Mevcut biçimli imza değiştirilir.', evet: 'Uygula')) {
                    return;
                  }
                  _html.text = imzaSablonu;
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('imza-html'),
            controller: _html,
            minLines: 8,
            maxLines: 18,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(labelText: 'Biçimli imza (HTML)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 6),
          Text(
            '{{ad}}, {{unvan}} gibi değişkenler gönderirken bilgilerinizle doldurulur. Boş bilgi satırları (data-optional) kendiliğinden gizlenir.',
            style: TextStyle(color: r.silik, fontSize: 12.5),
          ),
        ],
      ],
    );
  }

  Widget _onizleme(String html, {bool doldur = true}) {
    final r = context.r;
    final h = doldur ? _doldur(html) : html;
    if (h.trim().isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
        child: Text('İmza boş.', style: TextStyle(color: r.silik)),
      );
    }
    return Container(
      height: 220,
      decoration: BoxDecoration(
        border: Border.all(color: r.kenar),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: HtmlGovde(iletiId: 'imza', html: htmlTemizle(h, uzakKalsin: true).html, ekler: const <Ek>[]),
    );
  }
}
