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

/// Hazır imza düzenleri (web lib/webmail-productivity.ts SIGNATURE_LAYOUTS ile aynı). Boş değişkenli satırlar
/// gönderimde kendiliğinden düşer (data-optional).
typedef ImzaDuzeni = ({String id, String ad, String Function(String? logo, String renk) html});

final List<ImzaDuzeni> imzaDuzenleri = [
  (
    id: 'classic',
    ad: 'Klasik',
    html: (logo, renk) =>
        '<table cellpadding="0" cellspacing="0" style="font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.45;color:#333333">'
        '<tr>${logo != null ? '<td style="padding-right:14px;vertical-align:top"><img src="$logo" alt="" style="max-width:96px;max-height:96px"></td>' : ''}'
        '<td style="vertical-align:top;border-left:3px solid $renk;padding-left:12px">'
        '<div style="font-size:15px;font-weight:bold;color:$renk">{{ad}}</div>'
        '<div data-optional="unvan">{{unvan}}</div><div data-optional="departman" style="color:#666666">{{departman}}</div>'
        '<div style="margin-top:6px"><b>{{sirket}}</b></div>'
        '<div data-optional="telefon">Tel: {{telefon}}</div><div data-optional="cep">Cep: {{cep}}</div>'
        '<div><a href="mailto:{{eposta}}" style="color:$renk;text-decoration:none">{{eposta}}</a></div>'
        '<div data-optional="web"><a href="{{web}}" style="color:$renk;text-decoration:none">{{web}}</a></div>'
        '</td></tr></table>',
  ),
  (
    id: 'modern',
    ad: 'Modern',
    html: (logo, renk) =>
        '<div style="font-family:\'Segoe UI\',Arial,sans-serif;font-size:13px;line-height:1.5;color:#2b2b2b">'
        '<div style="font-size:16px;font-weight:600">{{ad}}</div>'
        '<div data-optional="unvan" style="color:$renk;font-weight:600">{{unvan}}</div>'
        '<div style="height:2px;width:48px;background:$renk;margin:8px 0"></div>'
        '${logo != null ? '<div style="margin:6px 0"><img src="$logo" alt="" style="max-height:48px"></div>' : ''}'
        '<div>{{sirket}}<span data-optional="departman"> · {{departman}}</span></div>'
        '<div><span data-optional="telefon">{{telefon}} · </span><a href="mailto:{{eposta}}" style="color:#2b2b2b">{{eposta}}</a></div>'
        '<div data-optional="web"><a href="{{web}}" style="color:$renk">{{web}}</a></div>'
        '<div style="margin-top:6px"><a data-optional="linkedin" href="{{linkedin}}" style="color:$renk;margin-right:8px">LinkedIn</a><a data-optional="x" href="{{x}}" style="color:$renk;margin-right:8px">X</a><a data-optional="instagram" href="{{instagram}}" style="color:$renk;margin-right:8px">Instagram</a></div>'
        '</div>',
  ),
  (
    id: 'compact',
    ad: 'Kompakt',
    html: (logo, renk) =>
        '<div style="font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.4;color:#444444">'
        '<b style="color:$renk">{{ad}}</b><span data-optional="unvan"> | {{unvan}}</span> | {{sirket}}<br>'
        '<span data-optional="telefon">T: {{telefon}} | </span><a href="mailto:{{eposta}}" style="color:#444444">{{eposta}}</a><span data-optional="web"> | <a href="{{web}}" style="color:$renk">{{web}}</a></span>'
        '</div>',
  ),
  (
    id: 'corporate',
    ad: 'Kurumsal (logo üstte)',
    html: (logo, renk) =>
        '<table cellpadding="0" cellspacing="0" style="font-family:Georgia,\'Times New Roman\',serif;font-size:13px;line-height:1.5;color:#222222">'
        '${logo != null ? '<tr><td style="padding-bottom:8px"><img src="$logo" alt="" style="max-height:56px"></td></tr>' : ''}'
        '<tr><td style="border-top:1px solid $renk;padding-top:8px">'
        '<div style="font-size:15px"><b>{{ad}}</b></div><div data-optional="unvan"><i>{{unvan}}</i></div>'
        '<div data-optional="departman">{{departman}}</div><div>{{sirket}}</div>'
        '<div style="margin-top:4px;color:#555555"><span data-optional="telefon">T {{telefon}}&nbsp;&nbsp;</span><span data-optional="cep">M {{cep}}&nbsp;&nbsp;</span>E {{eposta}}</div>'
        '<div data-optional="web"><a href="{{web}}" style="color:$renk">{{web}}</a></div>'
        '<div style="margin-top:8px;font-size:10px;color:#888888">Bu e-posta ve ekleri yalnızca alıcısına yöneliktir. Yanlışlıkla size ulaştıysa lütfen gönderene bildirip siliniz.</div>'
        '</td></tr></table>',
  ),
];

/// İmza tasarımcısındaki vurgu renkleri (web SIGNATURE_COLORS + marka moru).
const imzaRenkleri = ['#1d4ed8', '#5443d2', '#111827', '#6b7280', '#0e7490', '#047857', '#b45309', '#b91c1c', '#7c3aed'];

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
                    Icon(kilitli ? Simge.kilit : Simge.kurum, color: r.vurgu),
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
                  ButtonSegment(value: false, icon: Icon(Simge.notlar), label: Text('Düz metin')),
                  ButtonSegment(value: true, icon: Icon(Simge.bicim), label: Text('Biçimli')),
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
            if (!kilitli && !_kirli && a.etkinImzaHtml.trim().isNotEmpty) ...[
              const Baslik('Gönderilen imzanız'),
              _onizleme(a.etkinImzaHtml, doldur: false),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                child: Text(
                  a.imzaKurumdan ? 'Kendi imzanız boş olduğu için kurumunuzun varsayılan imzası kullanılıyor.' : 'Değişkenler bilgilerinizle doldurulmuş hâli.',
                  style: TextStyle(color: r.silik, fontSize: 12.5),
                ),
              ),
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
              leading: const Icon(Simge.kimlik),
              title: const Text('İmza bilgilerim'),
              subtitle: const Text('Unvan, departman, telefon, web ve sosyal bağlantılar ({{unvan}} gibi değişkenleri doldurur)'),
              trailing: const Icon(Simge.ileri),
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

  /// İmza tasarımcısı: hazır düzen + vurgu rengi + isteğe bağlı logo, canlı önizlemeyle; seçilen düzen
  /// biçimli düzenleyiciye yazılır (kaydetmeden önce düzenlenebilir).
  Future<void> _tasarimSec() async {
    var duzen = imzaDuzenleri.first;
    var renk = imzaRenkleri.first;
    String? logo;
    final sonuc = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) {
          final r = c.r;
          final html = duzen.html(logo, renk);
          return AlertDialog(
            title: const Text('İmza tasarımcısı'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in imzaDuzenleri)
                          ChoiceChip(
                            key: ValueKey('imza-duzen-${d.id}'),
                            label: Text(d.ad),
                            selected: d.id == duzen.id,
                            onSelected: (_) => ss(() => duzen = d),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Renk', style: TextStyle(color: r.soluk)),
                        for (final h in imzaRenkleri)
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => ss(() => renk = h),
                            child: CircleAvatar(
                              radius: 13,
                              backgroundColor: Color(int.parse('ff${h.substring(1)}', radix: 16)),
                              child: h == renk ? const Icon(Simge.onay, size: 16, color: Colors.white) : null,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final l = await _logoSec();
                            if (l != null) ss(() => logo = l);
                          },
                          icon: const Icon(Simge.gorselEkle, size: 18),
                          label: Text(logo == null ? 'Logo / fotoğraf ekle' : 'Logoyu değiştir'),
                        ),
                        if (logo != null) TextButton(onPressed: () => ss(() => logo = null), child: const Text('Kaldır')),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _onizleme(html),
                    const SizedBox(height: 6),
                    Text(
                      'Değişkenler (ör. {{unvan}}) profil bilgilerinizle doldurulur; boş kalan satırlar imzada görünmez.',
                      style: TextStyle(color: r.silik, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
              FilledButton(key: const ValueKey('imza-tasarim-uygula'), onPressed: () => Navigator.pop(c, html), child: const Text('Bu tasarımı kullan')),
            ],
          );
        },
      ),
    );
    if (sonuc == null || !mounted) return;
    final sinir = _a?.azamiImza ?? 0;
    if (sinir > 0 && utf8.encode(sonuc).length > sinir) {
      bildir('Tasarım imza sınırını aşıyor', mesaj: 'En fazla ${boyutYaz(sinir)}. Daha küçük bir logo seçin.', tur: MesajTur.uyari);
      return;
    }
    if (_html.text.trim().isNotEmpty && !await onayla(context, 'Mevcut imzanız bu tasarımla değiştirilsin mi?', evet: 'Değiştir')) return;
    setState(() {
      _bicimli = true;
      _sekme = 1;
      _html.text = sonuc;
      _kirli = true;
    });
  }

  /// Galeriden logo: küçültülür ve data: URI olarak döner (PNG/JPEG).
  Future<String?> _logoSec() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 240, maxHeight: 120, imageQuality: 85);
      if (f == null) return null;
      final b = await f.readAsBytes();
      if (b.length > 200 * 1024) {
        bildir('Görsel çok büyük', mesaj: 'İmza görseli küçük olmalı (en fazla ~200 KB).', tur: MesajTur.uyari);
        return null;
      }
      final tur = f.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      return 'data:$tur;base64,${base64Encode(b)}';
    } catch (e) {
      bildir('Görsel eklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
      return null;
    }
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
                arac(Simge.kalin, 'Kalın', () => _ekle('<b>', '</b>')),
                arac(Simge.italik, 'İtalik', () => _ekle('<i>', '</i>')),
                arac(Simge.altiCizili, 'Altı çizili', () => _ekle('<u>', '</u>')),
                arac(Simge.yaziRengi, 'Marka rengi', () => _ekle('<span style="color:#5443d2">', '</span>')),
                arac(Simge.baglanti, 'Bağlantı', _baglanti),
                arac(Simge.gorsel, 'Logo / görsel', _gorsel),
                arac(Simge.enter, 'Satır sonu', () => _ekle('<br>')),
                PopupMenuButton<String>(
                  tooltip: 'Değişken ekle',
                  icon: const Icon(Simge.veri, size: 20),
                  onSelected: (k) => _ekle('{{$k}}'),
                  itemBuilder: (_) => [for (final e in imzaDegiskenleri.entries) PopupMenuItem(value: e.key, child: Text('${e.value}  ·  {{${e.key}}}'))],
                ),
                arac(Simge.parilti, 'Hazır tasarım', _tasarimSec),
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
