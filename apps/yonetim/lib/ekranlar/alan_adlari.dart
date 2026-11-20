import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'alan_detay.dart';

/// Alan adları: aranabilir liste, durum rozetleri, ayrıntı (DNS denetimi) ve ekleme.
class AlanAdlariEkrani extends StatefulWidget {
  const AlanAdlariEkrani({super.key, this.orgId, this.orgAdi});

  /// Belirli bir müşterinin alan adları (Müşteriler ekranından).
  final String? orgId, orgAdi;

  @override
  State<AlanAdlariEkrani> createState() => _AlanAdlariEkraniState();
}

class _AlanAdlariEkraniState extends State<AlanAdlariEkrani> {
  String _q = '';
  String _mod = '';
  AlanAdi? _secili;
  late final _y = SayfaYukleyici<AlanAdi>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/domains',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': 'name',
          'order': 'asc',
          if (_q.isNotEmpty) 'q': _q,
          if (_mod.isNotEmpty) 'mode': _mod,
          if (widget.orgId != null) 'organization_id': widget.orgId,
        },
      ),
      AlanAdi.coz,
    ),
  )..yenile();

  bool get _ikiMod => !Uyg.musteri || Uyg.paketTuru == 'hybrid' || Uyg.paketTuru.isEmpty;

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _ac(AlanAdi a) {
    if (bolunmus(context)) {
      setState(() => _secili = a);
    } else {
      sayfaAc(context, a.gorunenAd, AlanDetay(alan: a, degisti: (y) => _degisti(a.id, y), tamSayfa: true));
    }
  }

  void _degisti(String id, AlanAdi? yeni) {
    _y.degistir((x) => x.id == id, yeni);
    if (_secili?.id == id) setState(() => _secili = yeni);
  }

  Future<void> _ekle() async {
    final a = await showDialog<AlanAdi>(
      context: context,
      builder: (_) => AlanEkleDialog(orgId: widget.orgId, orgAdi: widget.orgAdi),
    );
    if (a == null || !mounted) return;
    await _y.yenile();
    if (mounted) _ac(a);
  }

  @override
  Widget build(BuildContext context) {
    final yonetir = Uyg.yetki('domains.manage');
    final liste = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            children: [
              AramaAlani(
                ipucu: 'Alan adı ara…',
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
              if (_ikiMod) ...[
                const SizedBox(height: 8),
                SecimCipleri<String>(
                  secenekler: const [('', 'Tümü'), ('hosting', 'Hosting'), ('gateway', 'Gateway')],
                  secili: _mod,
                  secildi: (v) {
                    setState(() => _mod = v);
                    _y.yenile();
                  },
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SayfaliListe<AlanAdi>(
            yukleyici: _y,
            bosMetin: _q.isEmpty ? 'Henüz alan adı yok.' : 'Eşleşen alan adı yok.',
            bosIkon: Icons.language_rounded,
            ayrac: false,
            oge: (c, a) => ListeSatiri(
              secili: _secili?.id == a.id && bolunmus(c),
              onTap: () => _ac(a),
              sol: _AlanIkonu(a),
              baslik: a.gorunenAd,
              alt: [if (!Uyg.musteri) a.orgAdi, if (a.hosting) '${a.kutuSayisi} posta kutusu' else 'Gateway'].join(' · '),
              sag: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [DurumRozeti(a.durum), const SizedBox(height: 4), DnsRozeti(a.dnsDurumu)],
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.orgAdi == null ? 'Alan Adları' : '${widget.orgAdi} · Alan adları', overflow: TextOverflow.ellipsis),
        actions: [
          if (yonetir) IconButton(tooltip: 'Alan adı ekle', onPressed: _ekle, icon: const Icon(Icons.add_rounded)),
          if (bolunmus(context)) IconButton(tooltip: 'Yenile', onPressed: _y.yenile, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: yonetir && !bolunmus(context)
          ? FloatingActionButton.extended(onPressed: _ekle, icon: const Icon(Icons.add_rounded), label: const Text('Alan adı'))
          : null,
      body: AnaDetay(
        liste: liste,
        detay: _secili == null ? null : AlanDetay(key: ValueKey(_secili!.id), alan: _secili!, degisti: (y) => _degisti(_secili!.id, y)),
        bosMetin: 'Ayrıntı ve DNS kayıtları için bir alan adı seçin',
      ),
    );
  }
}

class _AlanIkonu extends StatelessWidget {
  const _AlanIkonu(this.a);
  final AlanAdi a;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(12)),
      child: Icon(a.hosting ? Icons.dns_rounded : Icons.alt_route_rounded, color: r.birincil, size: 20),
    );
  }
}

class DnsRozeti extends StatelessWidget {
  const DnsRozeti(this.durum, {super.key});
  final String durum;
  @override
  Widget build(BuildContext context) => switch (durum) {
    'ok' => const Rozet('DNS tamam', renk: Marka.zumrut, ikon: Icons.check_circle_rounded),
    'issues' => const Rozet('DNS sorunu', renk: Marka.kehribar, ikon: Icons.warning_amber_rounded),
    _ => Rozet('Denetlenmedi', renk: context.r.silik, ikon: Icons.radio_button_unchecked_rounded),
  };
}

/// Alan adı ekleme (POST /domains). Türkçe karakterli alan adları sunucuda punycode'a çevrilir.
class AlanEkleDialog extends StatefulWidget {
  const AlanEkleDialog({super.key, this.orgId, this.orgAdi});
  final String? orgId, orgAdi;
  @override
  State<AlanEkleDialog> createState() => _AlanEkleDialogState();
}

class _AlanEkleDialogState extends State<AlanEkleDialog> {
  final _ad = TextEditingController();
  late String? _orgId = widget.orgId;
  late String? _orgAdi = widget.orgAdi;
  String _mod = 'hosting';
  bool _mesgul = false;
  String? _hata, _alan;

  List<String> get _modlar => switch (Uyg.musteri ? Uyg.paketTuru : '') {
    'hosting' => ['hosting'],
    'gateway' => ['gateway'],
    _ => ['hosting', 'gateway'],
  };

  @override
  void initState() {
    super.initState();
    _mod = _modlar.first;
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      final v = await Uyg.api.post('/api/v1/domains', {if (_orgId != null) 'organization_id': _orgId, 'name': _ad.text.trim(), 'mode': _mod});
      final a = AlanAdi.coz(harita(v));
      bildir('${a.gorunenAd} eklendi', mesaj: 'Şimdi DNS kayıtlarını yayınlayın.', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, a);
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _alan = e.alan;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final musteriGerekli = !Uyg.musteri;
    final hazir = _ad.text.trim().isNotEmpty && (!musteriGerekli || _orgId != null) && !_mesgul;
    return AlertDialog(
      title: Text('Alan adı ekle', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Türkçe karakterli (IDN) alan adları desteklenir ve otomatik olarak punycode biçimine çevrilir.',
                style: TextStyle(color: context.r.silik, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (musteriGerekli) ...[
                SecimAlani(
                  etiket: 'Müşteri',
                  deger: _orgAdi,
                  hata: _alan == 'organization_id' ? _hata : null,
                  onTap: () async {
                    final o = await musteriSec(context);
                    if (o != null) {
                      setState(() {
                        _orgId = o.id;
                        _orgAdi = o.ad;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _ad,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'Alan adı', hintText: 'firma.com.tr', errorText: _alan == 'name' ? _hata : null),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => hazir ? _kaydet() : null,
              ),
              if (_modlar.length > 1) ...[
                const SizedBox(height: 14),
                Text(
                  'Kullanım modu',
                  style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'hosting', icon: Icon(Icons.dns_rounded), label: Text('Mail Hosting')),
                    ButtonSegment(value: 'gateway', icon: Icon(Icons.alt_route_rounded), label: Text('MX Gateway')),
                  ],
                  selected: {_mod},
                  onSelectionChanged: (s) => setState(() => _mod = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _mod == 'hosting' ? 'Posta kutuları bizde barınır.' : 'Gelen posta spam/virüs taramasından sonra müşterinin kendi sunucusuna iletilir. Hedef sunucu web panelindeki Mail Gateway sayfasından girilir; tanımlanana kadar posta geçici hatayla ertelenir, kaybolmaz.',
                  style: TextStyle(color: context.r.silik, fontSize: 12.5),
                ),
              ],
              if (_hata != null && _alan != 'name' && _alan != 'organization_id') ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: hazir ? _kaydet : null,
          child: _mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Ekle'),
        ),
      ],
    );
  }
}
