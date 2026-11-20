import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show dosyaSec;
import '../ortak/iskelet.dart';
import '../veri/json.dart';

/// Marka (beyaz etiket): müşterinin webmail ve panelinde görünen ürün adı, ana renk, destek bilgileri, logo ve
/// kendi alan adıyla giriş adresi. Web: admin/branding (+ login-host).
/// Uç noktalar: GET/PUT /organizations/{id}/branding, GET/DELETE /organizations/{id}/branding/logo?variant=,
/// GET/PUT /organizations/{id}/login-host, POST /organizations/{id}/login-host/verify, (ortaklar) GET /organizations.
/// Logo yükleme: PUT /organizations/{id}/branding/logo?variant= {data: base64 PNG/JPEG/GIF}; sunucu 640×200'e sığdırır.
class MarkaEkrani extends StatefulWidget {
  const MarkaEkrani({super.key, this.orgId, this.orgAdi});
  final String? orgId, orgAdi;
  @override
  State<MarkaEkrani> createState() => _MarkaEkraniState();
}

final _renkRe = RegExp(r'^#[0-9a-fA-F]{6}$');
Color? _renk(String s) => _renkRe.hasMatch(s) ? Color(int.parse('FF${s.substring(1)}', radix: 16)) : null;

double _parlaklik(Color c) {
  double k(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * k(c.r) + .7152 * k(c.g) + .0722 * k(c.b);
}

double _kontrast(Color a, Color b) {
  final x = _parlaklik(a), y = _parlaklik(b);
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// Renk üzerinde okunaklı yazı rengi (beyaz ya da koyu).
Color _onRenk(Color c) => _kontrast(c, Colors.white) >= _kontrast(c, const Color(0xFF111216)) ? Colors.white : const Color(0xFF111216);

class _MarkaEkraniState extends State<MarkaEkrani> {
  late String? _org = widget.orgId ?? (Uyg.musteri ? metinYa(Uyg.ben.value?['organization_id']) : null);
  late String? _orgAdi = widget.orgAdi;
  int _nesil = 0;

  bool get _ortak => !Uyg.musteri;

  Future<void> _musteriSec() async {
    final s = await showDialog<(String, String)>(context: context, builder: (_) => const _MusteriSecici());
    if (s == null) return;
    setState(() {
      _org = s.$1;
      _orgAdi = s.$2;
      _nesil++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final org = _org;
    return Iskelet(
      baslik: 'Marka',
      alt: _orgAdi ?? 'Webmail ve müşteri panelinde görünen logo, ürün adı, ana renk ve destek bilgileri',
      eylemler: [
        if (_ortak) IconButton(tooltip: 'Müşteri seçin', onPressed: _musteriSec, icon: const Icon(Icons.apartment_rounded)),
      ],
      yenile: org == null ? null : () => setState(() => _nesil++),
      govde: org == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Kapali(
                    _ortak ? 'Markasını düzenlemek istediğiniz müşteriyi seçin.' : 'Bu kullanıcı bir müşteriye bağlı değil.',
                    ikon: Icons.palette_outlined,
                  ),
                  if (_ortak) FilledButton.icon(onPressed: _musteriSec, icon: const Icon(Icons.apartment_rounded), label: const Text('Müşteri seçin')),
                ],
              ),
            )
          : TekYukleme<Map<String, dynamic>>(
              key: ValueKey('$org/$_nesil'),
              getir: () async => harita(await Uyg.api.get('/api/v1/organizations/$org/branding')),
              icerik: (c, b, yenile) {
                final etkin = mantik(b['enabled']);
                if (!etkin && !_ortak) {
                  return const Kapali(
                    'Paketiniz özel marka özelliğini içermiyor. Logonuzu, ürün adınızı ve renginizi webmail\'de kullanmak için hizmet sağlayıcınızdan '
                    'özel marka içeren bir pakete geçmeyi isteyin.',
                  );
                }
                final duzenler = Uyg.yetki('branding.manage');
                return IcerikListesi(
                  children: [
                    if (!etkin && _ortak) ...[
                      const Bant(
                        'Bu müşterinin paketinde özel marka özelliği yok: ayarlar kaydedilir ancak paket bu özelliği içerene kadar webmail\'de uygulanmaz.',
                        renk: Marka.kehribar,
                        ikon: Icons.warning_amber_rounded,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!duzenler) ...[
                      const Bant('Marka ayarlarını değiştirme yetkiniz yok (branding.manage). Yalnızca görüntüleyebilirsiniz.', ikon: Icons.lock_outline_rounded),
                      const SizedBox(height: 12),
                    ],
                    _MarkaDuzenleyici(key: ValueKey(b['version']), b: b, duzenler: duzenler, yenile: yenile),
                    const SizedBox(height: 16),
                    _GirisAdresi(orgId: org, duzenler: duzenler && etkin),
                  ],
                );
              },
            ),
    );
  }
}

/// Ortaklar için müşteri seçici (GET /organizations?q=).
class _MusteriSecici extends StatefulWidget {
  const _MusteriSecici();
  @override
  State<_MusteriSecici> createState() => _MusteriSeciciState();
}

class _MusteriSeciciState extends State<_MusteriSecici> {
  String _q = '';
  late Future<List<Map<String, dynamic>>> _l = _getir();

  Future<List<Map<String, dynamic>>> _getir() async => haritalar(
    harita(await Uyg.api.get('/api/v1/organizations', q: {'page': '1', 'page_size': '50', 'sort': 'name', 'order': 'asc', if (_q.isNotEmpty) 'q': _q}))['items'],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Müşteri seçin', style: gosterim(19, agirlik: FontWeight.w700)),
    content: SizedBox(
      width: 440,
      height: 420,
      child: Column(
        children: [
          AramaAlani(
            ipucu: 'Ad ile ara…',
            degisti: (v) => setState(() {
              _q = v;
              _l = _getir();
            }),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _l,
              builder: (c, s) {
                if (s.hasError) return Center(child: Text(hataMetni(s.error!)));
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final l = s.data!;
                if (l.isEmpty) return Center(child: Text('Müşteri bulunamadı', style: TextStyle(color: c.r.silik)));
                return ListView(
                  children: [
                    for (final o in l)
                      ListeSatiri(
                        baslik: metin(o['name']),
                        alt: metinYa(o['plan_name']),
                        sol: Avatar(metin(o['name']), tohum: metin(o['id'])),
                        onTap: () => Navigator.pop(context, (metin(o['id']), metin(o['name']))),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç'))],
  );
}

class _MarkaDuzenleyici extends StatefulWidget {
  const _MarkaDuzenleyici({super.key, required this.b, required this.duzenler, required this.yenile});
  final Map<String, dynamic> b;
  final bool duzenler;
  final Future<void> Function() yenile;
  @override
  State<_MarkaDuzenleyici> createState() => _MarkaDuzenleyiciState();
}

class _MarkaDuzenleyiciState extends State<_MarkaDuzenleyici> {
  final _form = GlobalKey<FormState>();
  late final _ad = TextEditingController(text: metin(widget.b['product_name']));
  late final _renkK = TextEditingController(text: metin(widget.b['primary_color']));
  late final _eposta = TextEditingController(text: metin(widget.b['support_email']));
  late final _url = TextEditingController(text: metin(widget.b['support_url']));
  late final _alt = TextEditingController(text: metin(widget.b['footer_text']));
  bool _mesgul = false, _koyu = false;
  String? _hata;
  final _logolar = <String, Uint8List?>{};

  String get _org => metin(widget.b['organization_id']);

  static const _hazirRenkler = ['#4f46e5', '#2563eb', '#0f766e', '#059669', '#d97706', '#dc2626', '#db2777', '#7c3aed', '#111827'];

  @override
  void initState() {
    super.initState();
    for (final (v, var_) in [('light', 'has_logo'), ('dark', 'has_logo_dark')]) {
      if (mantik(widget.b[var_])) _logoYukle(v);
    }
  }

  @override
  void dispose() {
    for (final k in [_ad, _renkK, _eposta, _url, _alt]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _logoYukle(String v) async {
    try {
      final b = await Uyg.api.indir('/api/v1/organizations/$_org/branding/logo', q: {'variant': v, 'v': metin(widget.b['version'])});
      if (mounted) setState(() => _logolar[v] = b);
    } catch (_) {}
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.put('/api/v1/organizations/$_org/branding', {
        'product_name': _ad.text.trim(),
        'primary_color': _renkK.text.trim(),
        'support_email': _eposta.text.trim(),
        'support_url': _url.text.trim(),
        'footer_text': _alt.text.trim(),
      });
      bildir('Marka ayarları kaydedildi', tur: MesajTur.basari);
      if (mounted) setState(() => _mesgul = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  Future<void> _logoSec(String v, String etiket) async {
    final l = await dosyaSec(baslik: '$etiket seç', uzantilar: const ['png', 'jpg', 'jpeg', 'gif']);
    if (l.isEmpty || !mounted) return;
    final b = l.first.bayt;
    if (b.length > 2 * 1024 * 1024) {
      bildir('Resim çok büyük', mesaj: 'Daha küçük bir resim seçin (genellikle en fazla 512 KB).', tur: MesajTur.uyari);
      return;
    }
    final ok = await islem(
      () => Uyg.api.put('/api/v1/organizations/$_org/branding/logo?variant=$v', {'data': base64Encode(b)}),
      tamam: '$etiket yüklendi',
    );
    if (ok != null) {
      if (mounted) setState(() => _logolar[v] = b);
      await widget.yenile();
    }
  }

  Future<void> _logoSil(String v, String etiket) async {
    if (!await onayla(context, '$etiket kaldırılsın mı?', evet: 'Kaldır', tehlikeli: true)) return;
    final ok = await islem(() => Uyg.api.delete('/api/v1/organizations/$_org/branding/logo', q: {'variant': v}), tamam: '$etiket kaldırıldı');
    if (ok != null) await widget.yenile();
  }

  Widget _renkNotlari(BuildContext c) {
    final r = c.r;
    final s = _renkK.text.trim();
    final stil = TextStyle(color: r.silik, fontSize: 12);
    if (s.isEmpty) return Text('Boş: BogaMail\'in varsayılan mor tonu kullanılır.', style: stil);
    final renk = _renk(s);
    if (renk == null) return const Text('#RRGGBB biçiminde girin (ör. #0f766e).', style: TextStyle(color: Marka.gul, fontSize: 12));
    final on = _onRenk(renk);
    final uyari = TextStyle(color: Marka.kehribar, fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Başlık yazısı otomatik olarak ${on == Colors.white ? 'beyaz' : 'koyu'} seçilir (kontrast ${_kontrast(renk, on).toStringAsFixed(1)}:1).', style: stil),
        if (_kontrast(renk, Colors.white) < 3)
          Text('Açık temada düğme ve bağlantı rengi olarak okunaklı değil; orada varsayılan renk kalır, yalnızca başlıkta kullanılır.', style: uyari),
        if (_kontrast(renk, const Color(0xFF111216)) < 3)
          Text('Koyu temada düğme ve bağlantı rengi olarak okunaklı değil; orada varsayılan renk kalır, yalnızca başlıkta kullanılır.', style: uyari),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final genis = MediaQuery.sizeOf(context).width >= 1000;
    final form = BolumKarti(
      baslik: 'Ad, renk ve destek bilgileri',
      ikon: Icons.palette_outlined,
      altBaslik: 'Boş bırakılan alanlarda BogaMail varsayılanları kullanılır.',
      child: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _ad,
              enabled: widget.duzenler,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Ürün adı', hintText: 'BogaMail', helperText: 'Webmail başlığında ve sekme adında görünür.'),
              validator: (v) => RegExp(r'[<>\r\n]').hasMatch(v ?? '') ? '< > içermemeli' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _renkK,
              enabled: widget.duzenler,
              maxLength: 7,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Ana renk',
                hintText: '#rrggbb',
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _renk(_renkK.text.trim()) ?? const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: r.kenar),
                    ),
                  ),
                ),
                suffixIcon: _renkK.text.isEmpty || !widget.duzenler
                    ? null
                    : IconButton(tooltip: 'Varsayılana dön', icon: const Icon(Icons.restart_alt_rounded), onPressed: () => setState(_renkK.clear)),
              ),
              validator: (v) => (v ?? '').trim().isNotEmpty && !_renkRe.hasMatch((v ?? '').trim()) ? 'Renk #RRGGBB biçiminde olmalı' : null,
            ),
            if (widget.duzenler)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in _hazirRenkler)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _renkK.text = h),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _renk(h),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _renkK.text.toLowerCase() == h ? r.metin : r.kenar, width: _renkK.text.toLowerCase() == h ? 2 : 1),
                        ),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            _renkNotlari(context),
            const SizedBox(height: 14),
            TextFormField(
              controller: _eposta,
              enabled: widget.duzenler,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Destek e-postası', hintText: 'destek@ornek.com'),
              validator: (v) => (v ?? '').trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? 'Geçerli bir e-posta adresi girin' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              enabled: widget.duzenler,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Destek sayfası', hintText: 'https://destek.ornek.com'),
              validator: (v) => (v ?? '').trim().isNotEmpty && !(v ?? '').trim().startsWith('https://') ? 'Adres https:// ile başlamalı' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _alt,
              enabled: widget.duzenler,
              maxLines: 2,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Alt bilgi metni',
                hintText: '© Örnek A.Ş. — Kurumsal e-posta',
                helperText: 'Webmail hesap menüsünün altında görünür. HTML kullanılamaz.',
              ),
              validator: (v) => RegExp(r'[<>]').hasMatch(v ?? '') ? '< > içermemeli' : null,
            ),
            if (_hata != null) ...[const SizedBox(height: 8), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
            if (widget.duzenler) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _mesgul ? null : _kaydet,
                  icon: _mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                  label: const Text('Kaydet'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final logo = BolumKarti(
      baslik: 'Logo',
      ikon: Icons.image_outlined,
      altBaslik: 'PNG, JPEG veya GIF; sunucu en fazla 640×200 piksele sığdırır. Şeffaf zeminli yatay logo önerilir.',
      child: Izgara(
        enAz: 220,
        children: [
          _logoYuvasi(context, 'light', 'Açık tema logosu', mantik(widget.b['has_logo'])),
          _logoYuvasi(context, 'dark', 'Koyu tema logosu', mantik(widget.b['has_logo_dark'])),
        ],
      ),
    );
    final onizleme = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Canlı önizleme', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.light_mode_outlined, size: 16), label: Text('Açık')),
                ButtonSegment(value: true, icon: Icon(Icons.dark_mode_outlined, size: 16), label: Text('Koyu')),
              ],
              selected: {_koyu},
              onSelectionChanged: (s) => setState(() => _koyu = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _onizleme(context),
        const SizedBox(height: 6),
        Text('Önizleme kaydedilmemiş değişiklikleri de gösterir.', style: TextStyle(color: r.silik, fontSize: 12)),
      ],
    );
    if (genis) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(children: [form, const SizedBox(height: 16), logo]),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: onizleme),
        ],
      );
    }
    return Column(children: [form, const SizedBox(height: 16), onizleme, const SizedBox(height: 16), logo]);
  }

  Widget _logoYuvasi(BuildContext c, String v, String etiket, bool var_) {
    final koyu = v == 'dark';
    final veri = _logolar[v];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(etiket, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          height: 90,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: koyu ? const Color(0xFF111216) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.r.kenar),
          ),
          alignment: Alignment.center,
          child: var_ && veri != null
              ? Image.memory(veri, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))
              : Text(
                  var_ ? 'Yükleniyor…' : (koyu ? 'Yok — koyu temada açık logo kullanılır' : 'Logo yok'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: koyu ? const Color(0xFFA1A1AA) : const Color(0xFF71717A), fontSize: 12),
                ),
        ),
        if (widget.duzenler)
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _logoSec(v, etiket),
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text(var_ ? 'Değiştir' : 'Yükle'),
              ),
              if (var_)
                TextButton.icon(
                  onPressed: () => _logoSil(v, etiket),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Kaldır'),
                  style: TextButton.styleFrom(foregroundColor: Marka.gul),
                ),
            ],
          ),
      ],
    );
  }

  Widget _onizleme(BuildContext c) {
    final renk = _renk(_renkK.text.trim());
    final koyu = _koyu;
    final zemin = koyu ? const Color(0xFF111216) : Colors.white;
    final yazi = koyu ? const Color(0xFFF4F4F5) : const Color(0xFF18181B);
    final kenar = koyu ? Colors.white.withValues(alpha: .1) : const Color(0xFFE4E4E7);
    final ustYazi = renk == null ? Colors.white : _onRenk(renk);
    final vurgu = renk != null && _kontrast(renk, zemin) >= 3 ? renk : (koyu ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5));
    final logo = koyu && _logolar['dark'] != null ? _logolar['dark'] : (_logolar['light'] ?? _logolar['dark']);
    final ad = _ad.text.trim().isEmpty ? 'BogaMail' : _ad.text.trim();
    final destek = _eposta.text.trim(), altBilgi = _alt.text.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(color: zemin, border: Border.all(color: kenar), borderRadius: BorderRadius.circular(14)),
        child: DefaultTextStyle(
          style: TextStyle(color: yazi, fontSize: 11.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: renk,
                  gradient: renk == null ? const LinearGradient(colors: [Color(0xFF3B2DA8), Color(0xFF5443D2), Color(0xFF2563EB)]) : null,
                ),
                child: Row(
                  children: [
                    if (logo != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130, maxHeight: 28),
                        child: Image.memory(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                      )
                    else
                      Icon(Icons.mail_rounded, color: ustYazi, size: 24),
                    if (logo == null || _ad.text.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: ustYazi, fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                    ],
                    const Spacer(),
                    Container(
                      width: 90,
                      height: 22,
                      decoration: BoxDecoration(color: ustYazi.withValues(alpha: .25), borderRadius: BorderRadius.circular(20)),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(radius: 13, backgroundColor: ustYazi.withValues(alpha: .4)),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 96,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(border: Border(right: BorderSide(color: kenar))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: vurgu.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
                          child: Text('Gelen', style: TextStyle(color: vurgu, fontWeight: FontWeight.w600)),
                        ),
                        for (final k in ['Gönderilen', 'Taslaklar'])
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                            child: Text(k, style: TextStyle(color: yazi.withValues(alpha: .6))),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FractionallySizedBox(
                            widthFactor: .75,
                            child: Container(height: 9, decoration: BoxDecoration(color: yazi.withValues(alpha: .18), borderRadius: BorderRadius.circular(4))),
                          ),
                          const SizedBox(height: 6),
                          FractionallySizedBox(
                            widthFactor: .5,
                            child: Container(height: 9, decoration: BoxDecoration(color: yazi.withValues(alpha: .12), borderRadius: BorderRadius.circular(4))),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(color: vurgu, borderRadius: BorderRadius.circular(6)),
                            child: Text('Yeni e-posta', style: TextStyle(color: _onRenk(vurgu), fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(height: 8),
                          Text('bağlantı örneği', style: TextStyle(color: vurgu, decoration: TextDecoration.underline, decorationColor: vurgu)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (destek.isNotEmpty || altBilgi.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: kenar))),
                  child: Text(
                    [if (destek.isNotEmpty) 'Destek: $destek', if (altBilgi.isNotEmpty) altBilgi].join('  '),
                    style: TextStyle(color: yazi.withValues(alpha: .7)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kendi alan adıyla giriş (GET/PUT /organizations/{id}/login-host, POST …/login-host/verify).
class _GirisAdresi extends StatefulWidget {
  const _GirisAdresi({required this.orgId, required this.duzenler});
  final String orgId;
  final bool duzenler;
  @override
  State<_GirisAdresi> createState() => _GirisAdresiState();
}

class _GirisAdresiState extends State<_GirisAdresi> {
  Map<String, dynamic>? _v;
  String? _hata, _alanHata;
  bool _mesgul = false;
  final _k = TextEditingController();

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _k.dispose();
    super.dispose();
  }

  void _ata(Object? v) {
    _v = harita(v);
    _k.text = metin(harita(_v!['login_host'])['hostname']);
  }

  Future<void> _yukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/organizations/${widget.orgId}/login-host');
      if (mounted) setState(() => _ata(v));
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _kaydet(String ad) async {
    setState(() {
      _mesgul = true;
      _alanHata = null;
    });
    try {
      final v = await Uyg.api.put('/api/v1/organizations/${widget.orgId}/login-host', {'hostname': ad});
      bildir(ad.isEmpty ? 'Giriş adresi kaldırıldı' : 'Giriş adresi kaydedildi', tur: MesajTur.basari);
      if (mounted) setState(() => _ata(v));
    } catch (e) {
      if (mounted) setState(() => _alanHata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _denetle() async {
    setState(() => _mesgul = true);
    final v = await islem(() => Uyg.api.post('/api/v1/organizations/${widget.orgId}/login-host/verify'));
    if (!mounted) return;
    setState(() {
      _mesgul = false;
      if (v != null) _ata(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = _v;
    return BolumKarti(
      baslik: 'Kendi alan adınızla giriş',
      ikon: Icons.public_rounded,
      altBaslik:
          'Kullanıcılarınız webmail ve panele kendi adresinizden (ör. posta.firmaniz.com) girer; giriş sayfası logonuz, ürün adınız ve renginizle görünür. '
          'Adres, etkin alan adlarınızdan birinin altında olmalıdır.',
      child: _hata != null
          ? Text('Yüklenemedi: $_hata', style: const TextStyle(color: Marka.gul))
          : v == null
          ? const LinearProgressIndicator(minHeight: 2)
          : Builder(
              builder: (c) {
                final h = harita(v['login_host']);
                final ad = metin(h['hostname']);
                final durum = metin(h['status']);
                final ipler = metinler(h['expected_ips']);
                final yer = ad.isEmpty ? 'posta.firmaniz.com' : ad;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _k,
                      enabled: widget.duzenler && !_mesgul,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: 'Giriş adresi', hintText: 'posta.firmaniz.com', errorText: _alanHata),
                    ),
                    if (widget.duzenler) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _mesgul || _k.text.trim().isEmpty || _k.text.trim() == ad ? null : () => _kaydet(_k.text.trim()),
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('Kaydet ve denetle'),
                          ),
                          if (ad.isNotEmpty)
                            OutlinedButton.icon(onPressed: _mesgul ? null : _denetle, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Yeniden denetle')),
                          if (ad.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: _mesgul ? null : () => _kaydet(''),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Text('Kaldır'),
                            ),
                        ],
                      ),
                    ],
                    if (ad.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            BilgiSatiri(
                              'DNS durumu',
                              metin(h['detail']),
                              sag: switch (durum) {
                                'verified' => const Rozet('Doğrulandı', renk: Marka.zumrut),
                                'failed' => const Rozet('Başarısız', renk: Marka.gul),
                                _ => const Rozet('Bekliyor', renk: Marka.kehribar),
                              },
                            ),
                            BilgiSatiri(
                              'HTTPS sertifikası',
                              h['tls_status'] == 'active'
                                  ? 'Etkin'
                                  : 'Onay bekliyor — sertifika, platform yöneticisi otomatik sertifika (on-demand TLS) ayarını açtıktan sonra ilk ziyarette alınır. '
                                        'O zamana kadar bu adres HTTPS ile açılmaz.',
                            ),
                            if (h['checked_at'] != null) BilgiSatiri('Son denetim', tamZaman(tarihOku(h['checked_at']))),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('DNS kaydı', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Alan adınızın DNS yönetiminde aşağıdakilerden birini ekleyin:', style: TextStyle(color: r.soluk, fontSize: 13)),
                    if (metinYa(h['expected_cname']) != null) KopyaKutusu(metin(h['expected_cname']), etiket: 'CNAME'),
                    if (metinYa(h['expected_cname']) != null) Text('$yer → CNAME (önerilen)', style: TextStyle(color: r.silik, fontSize: 12)),
                    if (ipler.isNotEmpty) KopyaKutusu(ipler.join(', '), etiket: 'A/AAAA'),
                    if (ipler.isNotEmpty) Text('$yer → A/AAAA', style: TextStyle(color: r.silik, fontSize: 12)),
                    const SizedBox(height: 6),
                    Text('DNS her 6 saatte bir yeniden denetlenir; kayıt kaldırılırsa adres devre dışı kalır.', style: TextStyle(color: r.silik, fontSize: 12)),
                    if (!mantik(v['branding_enabled'], true)) ...[
                      const SizedBox(height: 10),
                      const Bant('Paket özel marka içermediği için giriş sayfası markalanmaz.', renk: Marka.kehribar, ikon: Icons.warning_amber_rounded),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
