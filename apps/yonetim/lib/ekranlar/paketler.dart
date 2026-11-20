import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'hizmet_ortak.dart';
import '../ortak/simgeler.dart';

/// Paketler: satılan paketler (fiyat, sınırlar, özellikler), oluşturma ve düzenleme.
/// Web: admin/plans. Uç noktalar: GET /plans[?status=all], GET /catalog, POST /plans, PATCH /plans/{id}
/// (organizations.manage; platform paketlerini yalnızca süper yönetici, bayi paketlerini yalnızca o bayi düzenler).
class PaketlerEkrani extends StatefulWidget {
  const PaketlerEkrani({super.key});
  @override
  State<PaketlerEkrani> createState() => _PaketlerEkraniState();
}

const _turler = {'hosting': 'Posta barındırma', 'gateway': 'Mail gateway', 'relay': 'Gönderim (relay)', 'hybrid': 'Karma'};
const _mib = 1024 * 1024, _gib = 1024 * 1024 * 1024;

String _para(Object? v, String birim) {
  final d = ondalikYa(v);
  if (d == null) return '—';
  return NumberFormat.simpleCurrency(locale: 'tr_TR', name: birim.isEmpty ? 'TRY' : birim).format(d);
}

String _lim(Object? n) => n == null ? 'Sınırsız' : sayiYaz(tamsayi(n));
String _bayt(Object? n) => n == null ? 'Sınırsız' : boyutYaz(tamsayi(n));

class _Veri {
  _Veri(this.paketler, this.katalog);
  final List<Map<String, dynamic>> paketler;
  final List<KatalogOzelligi> katalog;
}

class _PaketlerEkraniState extends State<PaketlerEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<_Veri>>();
  bool _arsiv = false;

  bool get _duzenleyebilir => !Uyg.musteri && Uyg.yetki('organizations.manage') && Uyg.taklit == null;

  /// Sunucu kuralı: platform paketini yalnızca süper yönetici, bayi paketini yalnızca sahibi bayi düzenler.
  bool _buPaketi(Map<String, dynamic> p) => _duzenleyebilir && (Uyg.platformYoneticisi || p['reseller_id'] != null);

  Future<_Veri> _getir() async {
    final s = await Future.wait<dynamic>([
      Uyg.api.get('/api/v1/plans', q: {if (_arsiv) 'status': 'all'}),
      Uyg.api.get('/api/v1/catalog'),
    ]);
    return _Veri(haritalar(harita(s[0])['items']), katalogOzellikleri(s[1]));
  }

  Future<void> _duzenle(Map<String, dynamic>? p, List<KatalogOzelligi> katalog) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => PaketFormu(paket: p, katalog: katalog)),
    );
    if (ok == true) _anahtar.currentState?.yenile();
  }

  Future<void> _yeni() async {
    try {
      final k = katalogOzellikleri(await Uyg.api.get('/api/v1/catalog'));
      if (mounted) await _duzenle(null, k);
    } catch (e) {
      bildir('Katalog alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Paketler',
      alt: 'Satılan paketler: fiyat, sınırlar ve özellikler',
      yenile: () => _anahtar.currentState?.yenile(),
      eylemler: [
        IconButton(
          tooltip: _arsiv ? 'Arşivlenenleri gizle' : 'Arşivlenenleri göster',
          isSelected: _arsiv,
          icon: const Icon(Simgeler.archive),
          selectedIcon: const Icon(Simgeler.archive),
          onPressed: () {
            setState(() => _arsiv = !_arsiv);
            _anahtar.currentState?.yenile();
          },
        ),
      ],
      birincil: _duzenleyebilir ? BirincilEylem(Simgeler.add, 'Yeni paket', _yeni) : null,
      govde: TekYukleme<_Veri>(
        key: _anahtar,
        getir: _getir,
        icerik: (c, v, yenile) => IcerikListesi(
          children: [
            Text(
              'Müşteriye atanan paket, posta kutularının neyi kullanabileceğini belirler.',
              style: TextStyle(color: c.r.silik, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            if (v.paketler.isEmpty)
              const SizedBox(height: 320, child: Kapali('Paket yok. İlk paketinizi oluşturun.', ikon: Simgeler.inventory2))
            else
              Izgara(
                enAz: 280,
                children: [
                  for (final p in v.paketler) _PaketKarti(paket: p, katalog: v.katalog, duzenle: _buPaketi(p) ? () => _duzenle(p, v.katalog) : null),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _PaketKarti extends StatelessWidget {
  const _PaketKarti({required this.paket, required this.katalog, this.duzenle});
  final Map<String, dynamic> paket;
  final List<KatalogOzelligi> katalog;
  final VoidCallback? duzenle;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final p = paket;
    final birim = metin(p['currency'], 'TRY');
    final arsiv = p['status'] == 'archived';
    final ozellik = harita(p['features']);
    String ekImza(Object? v) => v == null || tamsayi(v) == 0 ? 'Platform' : boyutYaz(tamsayi(v));
    return Opacity(
      opacity: arsiv ? .65 : 1,
      child: Kutu(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metin(p['name']), style: gosterim(16, agirlik: FontWeight.w600)),
                      Text('${_turler[p['kind']] ?? metin(p['kind'])} · ${metin(p['code'])}', style: TextStyle(color: r.silik, fontSize: 12)),
                    ],
                  ),
                ),
                if (arsiv) Rozet('Arşiv', renk: r.silik),
                if (p['reseller_id'] != null) ...[const SizedBox(width: 4), const Rozet('Bayi paketi', renk: Marka.mavi)],
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: _para(p['price_monthly'], birim), style: gosterim(22, agirlik: FontWeight.w600, renk: r.metin)),
                  TextSpan(text: ' /ay', style: TextStyle(color: r.silik, fontSize: 13)),
                ],
              ),
            ),
            Text('${_para(p['price_yearly'], birim)} /yıl', style: TextStyle(color: r.silik, fontSize: 12)),
            if (metinYa(p['description']) != null) ...[
              const SizedBox(height: 8),
              Text(metin(p['description']), style: TextStyle(color: r.soluk, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            DegerSatiri('Mail hesabı', _lim(p['max_mailboxes'])),
            DegerSatiri('Toplam alan', _bayt(p['total_quota_bytes'])),
            DegerSatiri('Alan adı', _lim(p['max_domains'])),
            DegerSatiri('Kutu başı (vars.)', _bayt(p['default_mailbox_quota_bytes'])),
            DegerSatiri('Gönderim', '${sayiYaz(tamsayi(p['send_limit_per_hour']))}/saat · ${_lim(p['daily_send_limit'])}/gün'),
            DegerSatiri('İleti boyutu', _bayt(p['max_message_bytes'])),
            DegerSatiri('Ek / imza', '${ekImza(p['max_attachment_bytes'])} / ${ekImza(p['max_signature_bytes'])}'),
            const Divider(height: 20),
            for (final f in katalog)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      mantik(ozellik[f.anahtar]) ? Simgeler.check : Simgeler.close,
                      size: 15,
                      color: mantik(ozellik[f.anahtar]) ? Marka.zumrut : r.silik,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: mantik(ozellik[f.anahtar]) ? r.metin : r.silik,
                          decoration: mantik(ozellik[f.anahtar]) ? null : TextDecoration.lineThrough,
                          decorationColor: r.silik.withValues(alpha: .5),
                        ),
                      ),
                    ),
                    if (mantik(ozellik[f.anahtar]) && !f.hazir) Rozet(f.faz.isEmpty ? 'yakında' : f.faz, renk: r.silik),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('${tamsayi(p['organization_count'])} müşteri', style: TextStyle(color: r.silik, fontSize: 12)),
                ),
                if (duzenle != null)
                  OutlinedButton.icon(onPressed: duzenle, icon: const Icon(Simgeler.edit, size: 17), label: const Text('Düzenle')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sayısal sınır alanı: (anahtar, etiket, birim, boş olabilir mi, boş ipucu).
typedef _SayiAlani = (String, String, String, bool, String?);

const List<_SayiAlani> _sayiAlanlari = [
  ('max_mailboxes', 'Mail hesabı', 'adet', true, null),
  ('max_domains', 'Alan adı', 'adet', true, null),
  ('total_quota_bytes', 'Toplam depolama (GB)', 'GB', true, null),
  ('default_mailbox_quota_bytes', 'Yeni kutu kotası (GB)', 'GB', true, null),
  ('max_mailbox_quota_bytes', 'Kutu başına en fazla (GB)', 'GB', true, null),
  ('max_aliases', 'Takma ad (alias)', 'adet', true, null),
  ('send_limit_per_hour', 'Kutu başı saatlik gönderim', 'adet', false, null),
  ('daily_send_limit', 'Kutu başı günlük gönderim', 'adet', true, null),
  ('max_recipients_per_message', 'İleti başına alıcı', 'adet', false, null),
  ('max_message_bytes', 'İleti boyutu (MB)', 'MB', false, null),
  ('max_attachment_bytes', 'Ek yükleme toplamı (MB)', 'MB', true, 'Platform varsayılanı'),
  ('max_signature_bytes', 'İmza boyutu (KB)', 'KB', true, 'Platform varsayılanı'),
  ('continuity_quota_bytes', 'Kesinti modu depolama (GB)', 'GB', true, 'Sınırsız'),
  ('max_contacts', 'Toplu gönderim kişi sınırı', 'adet', true, 'Sınırsız'),
  ('max_campaign_sends_monthly', 'Aylık kampanya gönderimi', 'adet', true, 'Sınırsız'),
];

int _carpan(String birim) => switch (birim) {
  'GB' => _gib,
  'MB' => _mib,
  'KB' => 1024,
  _ => 1,
};

String _birimeCevir(Object? v, String birim) {
  if (v == null) return '';
  final n = ondalik(v) / _carpan(birim);
  final b = birim == 'KB' ? 1 : 2;
  final s = n.toStringAsFixed(birim == 'adet' ? 0 : b);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Paket oluşturma / düzenleme formu (tam ekran).
class PaketFormu extends StatefulWidget {
  const PaketFormu({super.key, this.paket, required this.katalog});
  final Map<String, dynamic>? paket;
  final List<KatalogOzelligi> katalog;
  @override
  State<PaketFormu> createState() => _PaketFormuState();
}

class _PaketFormuState extends State<PaketFormu> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> p = widget.paket ?? const {};
  late final _ad = TextEditingController(text: metin(p['name']));
  late final _kod = TextEditingController(text: metin(p['code']));
  late final _aciklama = TextEditingController(text: metin(p['description']));
  late final _aylik = TextEditingController(text: p['price_monthly'] == null ? '' : metin(p['price_monthly']));
  late final _yillik = TextEditingController(text: p['price_yearly'] == null ? '' : metin(p['price_yearly']));
  late final _sira = TextEditingController(text: '${tamsayi(p['sort_order'], 100)}');
  late String _tur = metin(p['kind'], 'hosting');
  late String _durum = metin(p['status'], 'active');
  late String _birim = metin(p['currency'], 'TRY');
  late final _sayilar = {
    for (final (k, _, b, _, _) in _sayiAlanlari)
      k: TextEditingController(
        text: _birimeCevir(
          widget.paket == null
              ? switch (k) {
                  'max_message_bytes' => 25 * _mib,
                  'send_limit_per_hour' => 300,
                  'max_recipients_per_message' => 100,
                  _ => null,
                }
              : p[k],
          b,
        ),
      ),
  };
  static const _varsayilanOzellikler = {'webmail', 'smtp', 'imap', 'pop3', 'external_send', 'antispam', 'antivirus', 'dkim'};
  late final Map<String, bool> _ozellikler = widget.paket == null
      ? {for (final f in widget.katalog) f.anahtar: _varsayilanOzellikler.contains(f.anahtar)}
      : {for (final e in harita(p['features']).entries) e.key: mantik(e.value)};
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in [_ad, _kod, _aciklama, _aylik, _yillik, _sira, ..._sayilar.values]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (!_form.currentState!.validate()) {
      setState(() => _hata = 'Formdaki hataları düzeltin.');
      return;
    }
    num? sayi(String s) => s.trim().isEmpty ? null : num.parse(s.trim().replaceAll(',', '.'));
    final govde = <String, dynamic>{
      'name': _ad.text.trim(),
      'kind': _tur,
      'description': _aciklama.text,
      'status': _durum,
      'currency': _birim,
      'price_monthly': sayi(_aylik.text),
      'price_yearly': sayi(_yillik.text),
      'sort_order': int.tryParse(_sira.text.trim()) ?? 100,
      'features': _ozellikler,
    };
    for (final (k, _, b, _, _) in _sayiAlanlari) {
      final n = sayi(_sayilar[k]!.text);
      govde[k] = n == null ? null : (n * _carpan(b)).round();
    }
    final kod = _kod.text.trim();
    if (widget.paket == null || metin(p['code']) != kod) govde['code'] = kod;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      if (widget.paket == null) {
        await Uyg.api.post('/api/v1/plans', govde);
      } else {
        await Uyg.api.patch('/api/v1/plans/${p['id']}', govde);
      }
      bildir(widget.paket == null ? 'Paket oluşturuldu' : 'Paket güncellendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  Widget _secim(String etiket, String deger, Map<String, String> secenekler, ValueChanged<String> degisti) => DropdownButtonFormField<String>(
    initialValue: secenekler.containsKey(deger) ? deger : secenekler.keys.first,
    isExpanded: true,
    decoration: InputDecoration(labelText: etiket),
    items: [for (final e in secenekler.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
    onChanged: (v) => v == null ? null : setState(() => degisti(v)),
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final gruplar = KatalogOzelligi.grupla(widget.katalog);
    final ikili = MediaQuery.sizeOf(context).width >= 640;
    Widget cift(Widget a, Widget b) => ikili
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          )
        : Column(children: [a, const SizedBox(height: 12), b]);
    String? fiyat(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return null;
      return num.tryParse(s.replaceAll(',', '.')) == null ? 'Sayı girin' : null;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.paket == null ? 'Yeni paket' : '${metin(p['name'])} paketini düzenle', overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: IcerikListesi(
          enFazla: 900,
          children: [
            Bant(
              'Boş bırakılan sınır alanları "sınırsız" (ek ve imza boyutunda "platform varsayılanı") anlamına gelir. '
              'Mevcut müşterileri sınır dışında bırakan değişiklikler reddedilir.',
            ),
            const SizedBox(height: 16),
            BolumKarti(
              baslik: 'Genel',
              ikon: Simgeler.inventory2,
              child: Column(
                children: [
                  cift(
                    TextFormField(
                      controller: _ad,
                      decoration: const InputDecoration(labelText: 'Paket adı'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Zorunlu' : ((v ?? '').trim().length > 120 ? 'En fazla 120 karakter' : null),
                    ),
                    TextFormField(
                      controller: _kod,
                      decoration: const InputDecoration(labelText: 'Kod', hintText: 'kurumsal-mail-5'),
                      onChanged: (v) {
                        final k = v.toLowerCase();
                        if (k != v) _kod.value = _kod.value.copyWith(text: k);
                      },
                      validator: (v) => RegExp(r'^[a-z0-9][a-z0-9-]{1,62}$').hasMatch((v ?? '').trim()) ? null : '2–63 küçük harf, rakam veya "-"',
                    ),
                  ),
                  const SizedBox(height: 12),
                  cift(
                    _secim('Tür', _tur, _turler, (v) => _tur = v),
                    _secim('Durum', _durum, const {'active': 'Satışta', 'archived': 'Arşiv (yeni müşteriye verilemez)'}, (v) => _durum = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _aciklama,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Açıklama'),
                    validator: (v) => (v ?? '').length > 1000 ? 'Açıklama çok uzun' : null,
                  ),
                  const SizedBox(height: 12),
                  cift(
                    TextFormField(
                      controller: _aylik,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Aylık fiyat'),
                      validator: fiyat,
                    ),
                    TextFormField(
                      controller: _yillik,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Yıllık fiyat'),
                      validator: fiyat,
                    ),
                  ),
                  const SizedBox(height: 12),
                  cift(
                    _secim('Para birimi', _birim, const {'TRY': 'TRY (₺)', 'USD': 'USD', 'EUR': 'EUR'}, (v) => _birim = v),
                    TextFormField(
                      controller: _sira,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Sıra'),
                      validator: (v) => int.tryParse((v ?? '').trim()) == null ? 'Tam sayı girin' : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BolumKarti(
              baslik: 'Sınırlar',
              ikon: Simgeler.tune,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final (k, e, _, bos, ipucu) in _sayiAlanlari)
                    SizedBox(
                      width: ikili ? 400 : double.infinity,
                      child: TextFormField(
                        controller: _sayilar[k],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: e, hintText: ipucu ?? (bos ? 'Sınırsız' : null)),
                        validator: (v) {
                          final h = sayiDogrula(v, bosOlur: bos);
                          if (h != null) return h == 'Zorunlu' ? '$e boş bırakılamaz' : h;
                          final n = num.tryParse((v ?? '').trim().replaceAll(',', '.'));
                          if (k == 'max_recipients_per_message' && n != null && (n < 1 || n > 10000)) return '1–10000 olmalı';
                          if (k == 'max_message_bytes' && n != null && (n < 1 || n > 150)) return '1–150 MB olmalı';
                          return null;
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            BolumKarti(
              baslik: 'Özellikler',
              ikon: Simgeler.toggleOn,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final g in gruplar.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Text(g.key, style: TextStyle(color: r.silik, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    for (final f in g.value)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _ozellikler[f.anahtar] ?? false,
                        onChanged: (v) => setState(() => _ozellikler[f.anahtar] = v ?? false),
                        title: Text(f.ad, style: const TextStyle(fontSize: 13.5)),
                        secondary: f.hazir ? null : Rozet(f.faz.isEmpty ? 'yakında' : f.faz, renk: r.silik),
                      ),
                  ],
                ],
              ),
            ),
            if (_hata != null) ...[const SizedBox(height: 16), Bant(_hata!, renk: Marka.gul, ikon: Simgeler.errorOutline)],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _mesgul ? null : _kaydet,
                icon: _mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Simgeler.save),
                label: const Text('Kaydet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
