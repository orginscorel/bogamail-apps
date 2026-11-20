import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show HtmlOnizleme;
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'ekip_kampanya_ortak.dart';

const _blokEtiketleri = {
  'heading': 'Başlık',
  'text': 'Metin',
  'image': 'Resim',
  'button': 'Düğme',
  'divider': 'Ayraç',
  'spacer': 'Boşluk',
  'columns': 'Sütunlar',
  'footer': 'Alt bilgi notu',
};

Map<String, dynamic> _yeniBlok(String t) => switch (t) {
  'heading' => {'type': t, 'text': 'Başlık', 'level': 1},
  'text' => {'type': t, 'text': 'Merhaba {{ad|Değerli müşterimiz}},\n\nMetninizi buraya yazın.'},
  'image' => {'type': t, 'url': '', 'alt': ''},
  'button' => {'type': t, 'text': 'İncele', 'url': 'https://'},
  'spacer' => {'type': t, 'height': 24},
  'columns' => {
    'type': t,
    'columns': [
      {'type': 'text', 'text': 'Sol sütun'},
      {'type': 'text', 'text': 'Sağ sütun'},
    ],
  },
  'footer' => {'type': t, 'text': ''},
  _ => {'type': t},
};

final _baslangic = <Map<String, dynamic>>[
  {'type': 'heading', 'text': 'Merhaba {{ad|Değerli müşterimiz}}', 'level': 1},
  {'type': 'text', 'text': 'Size özel haberlerimizi paylaşmak istedik.\n\n**Kalın** yazı ve [bağlantı](https://ornek.com) kullanabilirsiniz.'},
  {'type': 'button', 'text': 'Hemen inceleyin', 'url': 'https://'},
];

Map<String, dynamic> _derinKopya(Map<String, dynamic> m) => {
  for (final e in m.entries)
    e.key: e.value is Map
        ? _derinKopya(harita(e.value))
        : (e.value is List ? [for (final x in e.value as List) x is Map ? _derinKopya(harita(x)) : x] : e.value),
};

/// Toplu Gönderim → Şablonlar: liste, blok düzenleyici, önizleme (düz metin) ve test gönderimi.
class SablonlarSekmesi extends StatefulWidget {
  const SablonlarSekmesi({super.key, required this.b});
  final KampanyaBaglami b;
  @override
  State<SablonlarSekmesi> createState() => _SablonlarSekmesiState();
}

class _SablonlarSekmesiState extends State<SablonlarSekmesi> {
  late final _y = SayfaYukleyici.yerel<Map<String, dynamic>>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/campaigns/templates', q: widget.b.q))['items']),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _duzenle(Map<String, dynamic>? t) async {
    final yeni = t == null || metin(t['id']).isEmpty;
    await ekipPencere<void>(context, yeni ? 'Yeni şablon' : 'Şablonu düzenle', SablonDuzenleyici(b: widget.b, ilk: t, kaydedildi: _y.yenile), genislik: 1100);
    _y.yenile();
  }

  Future<void> _sil(Map<String, dynamic> t) async {
    final ok = await onayla(context, 'Şablon silinsin mi?', mesaj: '"${metin(t['name'])}" kalıcı olarak silinir.', evet: 'Sil', tehlikeli: true);
    if (!ok) return;
    await islem(() => Uyg.api.delete('/api/v1/campaigns/templates/${metin(t['id'])}'), tamam: 'Şablon silindi');
    _y.yenile();
  }

  int _blok(Map<String, dynamic> t) => t['blocks'] is List ? (t['blocks'] as List).length : 0;

  List<SatirEylemi> _eylemler(Map<String, dynamic> t) => [
    SatirEylemi(Icons.edit_outlined, 'Düzenle', () => _duzenle(t)),
    if (widget.b.acik) SatirEylemi(Icons.copy_rounded, 'Kopyasını oluştur', () => _duzenle({...t, 'id': '', 'name': '${metin(t['name'])} (kopya)'})),
    SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(t), tehlikeli: true),
  ];

  @override
  Widget build(BuildContext context) {
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Henüz şablon yok. İlk şablonunuzu oluşturun; kampanyalarda tekrar tekrar kullanabilirsiniz.',
      bosIkon: Icons.dashboard_customize_outlined,
      onTap: _duzenle,
      eylemler: _eylemler,
      ust: Padding(
        padding: EdgeInsets.fromLTRB(yatay, 10, yatay, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                'Bloklarla e-posta tasarlayın; tüm e-posta istemcilerinde ve mobilde düzgün görünen HTML sunucuda üretilir.',
                style: TextStyle(color: context.r.soluk, fontSize: 12.5),
              ),
            ),
            FilledButton.icon(onPressed: widget.b.acik ? () => _duzenle(null) : null, icon: const Icon(Icons.add_rounded), label: const Text('Yeni şablon')),
          ],
        ),
      ),
      sutunlar: [
        Sutun('Şablon', esnek: 5, hucre: (c, t) => IkiSatir(metin(t['name']))),
        Sutun('Blok', esnek: 1, hucre: (c, t) => SolukMetin('${_blok(t)}')),
        Sutun('Güncellendi', esnek: 2, hucre: (c, t) => SolukMetin(tamZaman(tarihOku(t['updated_at'])))),
      ],
      kart: (c, t) => VeriKarti(
        baslik: metin(t['name']),
        alanlar: [('Blok', '${_blok(t)}'), ('Güncellendi', kisaZaman(tarihOku(t['updated_at'])))],
        eylemler: _eylemler(t),
        onTap: () => _duzenle(t),
      ),
    );
  }
}

/// Blok tabanlı şablon düzenleyici. Önizleme sunucuda üretilir (POST /campaigns/preview); HTML sürümü güvenli önizlemede, düz metin ayrıca gösterilir.
class SablonDuzenleyici extends StatefulWidget {
  const SablonDuzenleyici({super.key, required this.b, this.ilk, required this.kaydedildi});
  final KampanyaBaglami b;
  final Map<String, dynamic>? ilk;
  final VoidCallback kaydedildi;
  @override
  State<SablonDuzenleyici> createState() => _SablonDuzenleyiciState();
}

class _SablonDuzenleyiciState extends State<SablonDuzenleyici> {
  late String _id = metin(widget.ilk?['id']);
  late final _ad = TextEditingController(text: metin(widget.ilk?['name']));
  late final List<Map<String, dynamic>> _bloklar = haritalar(widget.ilk?['blocks']).isNotEmpty
      ? haritalar(widget.ilk?['blocks']).map(_derinKopya).toList()
      : _baslangic.map(_derinKopya).toList();
  late final Map<String, dynamic> _stil = Map<String, dynamic>.from(harita(widget.ilk?['style']));
  final _konu = TextEditingController(text: 'Önizleme konusu');
  final _onMetin = TextEditingController();
  String _ekleTur = 'text';
  int _surum = 0;
  Timer? _gecikme;
  String? _onizleme;
  String _onizlemeHtml = '';
  bool _htmlGorunum = true;
  String? _onizlemeHata;
  bool _mesgul = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _onizlemeIste();
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    _ad.dispose();
    _konu.dispose();
    _onMetin.dispose();
    super.dispose();
  }

  void _degisti() {
    setState(() {});
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 600), _onizlemeIste);
  }

  Future<void> _onizlemeIste() async {
    try {
      final r = harita(
        await Uyg.api.post('/api/v1/campaigns/preview', {
          'organization_id': widget.b.orgId,
          'subject': _konu.text,
          'preheader': _onMetin.text,
          'blocks': _bloklar,
          'style': _stil,
        }),
      );
      if (!mounted) return;
      setState(() {
        _onizleme = metin(r['text']);
        _onizlemeHtml = metin(r['html']);
        _onizlemeHata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _onizlemeHata = hataMetni(e));
    }
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final govde = {'organization_id': widget.b.orgId, 'name': _ad.text.trim(), 'blocks': _bloklar, 'style': _stil};
    try {
      if (_id.isNotEmpty) {
        await Uyg.api.put('/api/v1/campaigns/templates/$_id', govde);
      } else {
        final t = harita(await Uyg.api.post('/api/v1/campaigns/templates', govde));
        _id = metin(t['id']);
      }
      bildir('Şablon kaydedildi', tur: MesajTur.basari);
      widget.kaydedildi();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  void _tasi(int i, int d) {
    final j = i + d;
    if (j < 0 || j >= _bloklar.length) return;
    final x = _bloklar[i];
    _bloklar[i] = _bloklar[j];
    _bloklar[j] = x;
    _surum++;
    _degisti();
  }

  Widget _metinAlani(Map<String, dynamic> b, String anahtar, String etiket, {int satir = 1, String? ipucu, TextInputType? tur}) => TextFormField(
    initialValue: metin(b[anahtar]),
    minLines: satir,
    maxLines: satir == 1 ? 1 : satir + 4,
    keyboardType: tur,
    decoration: InputDecoration(labelText: etiket, hintText: ipucu),
    onChanged: (v) {
      b[anahtar] = v;
      _degisti();
    },
  );

  Widget _sayiAlani(Map<String, dynamic> b, String anahtar, String etiket, {double genislik = 120}) => SizedBox(
    width: genislik,
    child: TextFormField(
      initialValue: '${tamsayi(b[anahtar])}',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: etiket),
      onChanged: (v) {
        b[anahtar] = int.tryParse(v) ?? 0;
        _degisti();
      },
    ),
  );

  Widget _hizalama(Map<String, dynamic> b) => SizedBox(
    width: 150,
    child: DropdownButtonFormField<String>(
      initialValue: const {'left', 'center', 'right'}.contains(b['align']) ? metin(b['align']) : 'left',
      decoration: const InputDecoration(labelText: 'Hizalama'),
      items: const [
        DropdownMenuItem(value: 'left', child: Text('Sola')),
        DropdownMenuItem(value: 'center', child: Text('Ortaya')),
        DropdownMenuItem(value: 'right', child: Text('Sağa')),
      ],
      onChanged: (v) {
        b['align'] = v ?? 'left';
        _degisti();
      },
    ),
  );

  Widget _renkAlani(Map<String, dynamic> m, String anahtar, String etiket, String varsayilan, {double genislik = 170}) {
    final deger = metin(m[anahtar]).isEmpty ? varsayilan : metin(m[anahtar]);
    final c = int.tryParse(deger.replaceFirst('#', ''), radix: 16);
    return SizedBox(
      width: genislik,
      child: TextFormField(
        initialValue: metin(m[anahtar]),
        autocorrect: false,
        decoration: InputDecoration(
          labelText: etiket,
          hintText: varsayilan,
          prefixIcon: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: c == null || deger.length != 7 ? Colors.transparent : Color(0xFF000000 | c),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: context.r.kenar),
              ),
            ),
          ),
        ),
        onChanged: (v) {
          final t = v.trim();
          if (t.isEmpty) {
            m.remove(anahtar);
          } else {
            m[anahtar] = t;
          }
          _degisti();
        },
      ),
    );
  }

  Widget _blokAlanlari(Map<String, dynamic> b, {bool hucre = false}) {
    switch (metin(b['type'])) {
      case 'heading':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(width: 320, child: _metinAlani(b, 'text', 'Başlık metni')),
            SizedBox(
              width: 120,
              child: DropdownButtonFormField<int>(
                initialValue: const {1, 2, 3}.contains(tamsayi(b['level'], 1)) ? tamsayi(b['level'], 1) : 1,
                decoration: const InputDecoration(labelText: 'Boyut'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Büyük')),
                  DropdownMenuItem(value: 2, child: Text('Orta')),
                  DropdownMenuItem(value: 3, child: Text('Küçük')),
                ],
                onChanged: (v) {
                  b['level'] = v ?? 1;
                  _degisti();
                },
              ),
            ),
            _hizalama(b),
          ],
        );
      case 'text':
      case 'footer':
        final alt = b['type'] == 'footer';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _metinAlani(
              b,
              'text',
              alt ? 'Alt bilgi notu' : 'Metin',
              satir: alt ? 2 : 4,
              ipucu: alt ? 'ör. Bu iletiyi web sitemizden abone olduğunuz için alıyorsunuz.' : null,
            ),
            if (!alt) ...[const SizedBox(height: 8), Align(alignment: Alignment.centerLeft, child: _hizalama(b))],
          ],
        );
      case 'image':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 420,
              child: _metinAlani(b, 'url', 'Resim adresi', ipucu: 'https://…/resim.png', tur: TextInputType.url),
            ),
            SizedBox(width: 220, child: _metinAlani(b, 'alt', 'Alternatif metin')),
            SizedBox(width: 280, child: _metinAlani(b, 'link', 'Tıklama bağlantısı (isteğe bağlı)', tur: TextInputType.url)),
            _sayiAlani(b, 'width', 'Genişlik (px, 0 = tam)', genislik: 170),
          ],
        );
      case 'button':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(width: 240, child: _metinAlani(b, 'text', 'Düğme metni')),
            SizedBox(
              width: 320,
              child: _metinAlani(b, 'url', 'Bağlantı', ipucu: 'https://…', tur: TextInputType.url),
            ),
            _renkAlani(b, 'color', 'Renk', '#2563eb'),
            if (!hucre) _hizalama(b),
          ],
        );
      case 'divider':
        return Text('Yatay ayırıcı çizgi.', style: TextStyle(color: context.r.silik, fontSize: 12.5));
      case 'spacer':
        return Align(alignment: Alignment.centerLeft, child: _sayiAlani(b, 'height', 'Yükseklik (px)', genislik: 160));
      case 'columns':
        final sutunlar = haritalar(b['columns']);
        b['columns'] = sutunlar;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Mobilde alt alta dizilir.', style: TextStyle(color: context.r.silik, fontSize: 12)),
                OutlinedButton.icon(
                  onPressed: sutunlar.length >= 3
                      ? null
                      : () {
                          sutunlar.add({'type': 'text', 'text': ''});
                          _surum++;
                          _degisti();
                        },
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Sütun'),
                ),
                OutlinedButton.icon(
                  onPressed: sutunlar.length <= 2
                      ? null
                      : () {
                          sutunlar.removeLast();
                          _surum++;
                          _degisti();
                        },
                  icon: const Icon(Icons.remove_rounded, size: 17),
                  label: const Text('Son sütunu kaldır'),
                ),
              ],
            ),
            for (var i = 0; i < sutunlar.length; i++)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: context.r.kenar),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Sütun ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('st$_surum-$i-${sutunlar[i]['type']}'),
                            initialValue: const {'text', 'heading', 'image', 'button'}.contains(sutunlar[i]['type']) ? metin(sutunlar[i]['type']) : 'text',
                            isDense: true,
                            items: [
                              for (final t in const ['text', 'heading', 'image', 'button']) DropdownMenuItem(value: t, child: Text(_blokEtiketleri[t]!)),
                            ],
                            onChanged: (v) {
                              sutunlar[i] = _yeniBlok(v ?? 'text');
                              _surum++;
                              _degisti();
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    KeyedSubtree(key: ValueKey('sc$_surum-$i'), child: _blokAlanlari(sutunlar[i], hucre: true)),
                  ],
                ),
              ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _testGonder() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TestDialog(b: widget.b, konu: _konu.text, onMetin: _onMetin.text, bloklar: _bloklar, stil: _stil),
    );
  }

  Widget _duzenleyici() {
    final r = context.r;
    final etiketler = haritalar(widget.b.ov['merge_tags']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Zorunlu alt bilgi (şirket adı, adres, abonelikten çıkma bağlantısı) her iletiye otomatik eklenir; buraya eklemeniz gerekmez.',
          style: TextStyle(color: r.soluk, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _ad,
          maxLength: 120,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Şablon adı', counterText: ''),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _bloklar.length; i++)
          Container(
            key: ValueKey('b$_surum-$i'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
            decoration: BoxDecoration(
              color: r.kart,
              border: Border.all(color: r.kenar),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _blokEtiketleri[metin(_bloklar[i]['type'])] ?? metin(_bloklar[i]['type']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(tooltip: 'Yukarı taşı', onPressed: i == 0 ? null : () => _tasi(i, -1), icon: const Icon(Icons.arrow_upward_rounded, size: 19)),
                    IconButton(
                      tooltip: 'Aşağı taşı',
                      onPressed: i == _bloklar.length - 1 ? null : () => _tasi(i, 1),
                      icon: const Icon(Icons.arrow_downward_rounded, size: 19),
                    ),
                    IconButton(
                      tooltip: 'Bloğu sil',
                      onPressed: () {
                        _bloklar.removeAt(i);
                        _surum++;
                        _degisti();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 19, color: Marka.gul),
                    ),
                  ],
                ),
                Padding(padding: const EdgeInsets.only(right: 6), child: _blokAlanlari(_bloklar[i])),
              ],
            ),
          ),
        Row(
          children: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: _ekleTur,
                decoration: const InputDecoration(labelText: 'Blok türü'),
                items: [for (final e in _blokEtiketleri.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _ekleTur = v ?? 'text'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _bloklar.length >= 80
                  ? null
                  : () {
                      _bloklar.add(_yeniBlok(_ekleTur));
                      _degisti();
                    },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Blok ekle'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Renkler',
          style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _renkAlani(_stil, 'background', 'Arka plan', '#f4f4f5'),
            _renkAlani(_stil, 'content', 'İçerik kutusu', '#ffffff'),
            _renkAlani(_stil, 'text', 'Metin', '#18181b'),
            _renkAlani(_stil, 'accent', 'Vurgu / bağlantı', '#2563eb'),
          ],
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Birleştirme etiketleri ve biçimlendirme', style: TextStyle(fontSize: 14)),
          children: [
            for (final t in etiketler)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('{{${metin(t['key'])}}}', style: const TextStyle(fontFamily: 'monospace')),
                subtitle: Text(metin(t['description'])),
              ),
            Text(
              'Varsayılan değer: {{ad|Değerli müşterimiz}} · Kalın: **metin** · Bağlantı: [etiket](https://…)',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _onizlemeBolumu() {
    final r = context.r;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _konu,
                onChanged: (_) => _degisti(),
                decoration: const InputDecoration(labelText: 'Önizleme konusu'),
              ),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                controller: _onMetin,
                onChanged: (_) => _degisti(),
                decoration: const InputDecoration(labelText: 'Ön izleme metni'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Önizleme (düz metin sürümü, örnek verilerle)',
          style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 12.5),
        ),
        const SizedBox(height: 6),
        if (_onizlemeHata != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_onizlemeHata!, style: const TextStyle(color: Marka.gul)),
          ),
        Container(
          constraints: const BoxConstraints(minHeight: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: r.ic,
            border: Border.all(color: r.kenar),
            borderRadius: BorderRadius.circular(10),
          ),
          child: _onizleme == null
              ? const Center(child: CircularProgressIndicator())
              : _htmlGorunum && _onizlemeHtml.trim().isNotEmpty
                  ? HtmlOnizleme(html: _onizlemeHtml, yukseklik: 420)
                  : SelectableText(_onizleme!, style: const TextStyle(fontSize: 12.5)),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('Betikler çalışmaz, uzak görseller yüklenmez; asıl görünüm için test gönderimi yapın.', style: TextStyle(color: r.silik, fontSize: 12))),
            TextButton(
              onPressed: () => setState(() => _htmlGorunum = !_htmlGorunum),
              child: Text(_htmlGorunum ? 'Düz metin' : 'HTML'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final acik = widget.b.acik;
    final genis = MediaQuery.sizeOf(context).width >= 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: genis
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 12, 20), children: [_duzenleyici()]),
                    ),
                    Expanded(
                      child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 20, 20), children: [_onizlemeBolumu()]),
                    ),
                  ],
                )
              : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 20), children: [_duzenleyici(), const SizedBox(height: 16), _onizlemeBolumu()]),
        ),
        if (_hata != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
          ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(onPressed: acik ? _testGonder : null, icon: const Icon(Icons.send_rounded, size: 18), label: const Text('Test gönder')),
              FilledButton(onPressed: _mesgul || !acik || _ad.text.trim().isEmpty ? null : _kaydet, child: const Text('Kaydet')),
            ],
          ),
        ),
      ],
    );
  }
}

class _TestDialog extends StatefulWidget {
  const _TestDialog({required this.b, required this.konu, required this.onMetin, required this.bloklar, required this.stil});
  final KampanyaBaglami b;
  final String konu, onMetin;
  final List<Map<String, dynamic>> bloklar;
  final Map<String, dynamic> stil;
  @override
  State<_TestDialog> createState() => _TestDialogState();
}

class _TestDialogState extends State<_TestDialog> {
  late String? _kutu = widget.b.gondericiler.isEmpty ? null : metin(widget.b.gondericiler.first['mailbox_id']);
  late final _alici = TextEditingController(text: Uyg.adres);
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _alici.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final g = widget.b.gondericiler.where((s) => metin(s['mailbox_id']) == _kutu).firstOrNull;
    try {
      await Uyg.api.post('/api/v1/campaigns/test-send', {
        'organization_id': widget.b.orgId,
        'mailbox_id': _kutu,
        'from_name': metin(g?['display_name']),
        'to': _alici.text.trim(),
        'subject': widget.konu,
        'preheader': widget.onMetin,
        'blocks': widget.bloklar,
        'style': widget.stil,
      });
      bildir('Test iletisi ${_alici.text.trim()} adresine gönderildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Test gönder'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Örnek verilerle tek bir kopya gönderilir (konuya [TEST] eklenir). Yalnızca kendi adresinize veya bu müşterinin posta kutularına.',
            style: TextStyle(color: context.r.soluk, fontSize: 13),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _kutu,
            isExpanded: true,
            hint: const Text('Posta kutusu seçin'),
            decoration: const InputDecoration(labelText: 'Gönderen'),
            items: [
              for (final s in widget.b.gondericiler)
                DropdownMenuItem(
                  value: metin(s['mailbox_id']),
                  child: Text(metin(s['address']), overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _kutu = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _alici,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Alıcı'),
          ),
          if (_hata != null) ...[const SizedBox(height: 8), Text(_hata!, style: const TextStyle(color: Marka.gul))],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul || _kutu == null || _alici.text.trim().isEmpty ? null : _gonder, child: const Text('Gönder')),
    ],
  );
}
