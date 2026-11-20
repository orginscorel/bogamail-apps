import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'kutu_detay.dart';
import 'kutu_formlari.dart';
import 'takma_adlar.dart';

/// Posta kutuları: aranabilir, sayfalı liste (alan adı ve durum filtresi), ayrıntı ve oluşturma.
class PostaKutulariEkrani extends StatefulWidget {
  const PostaKutulariEkrani({super.key, this.orgId, this.orgAdi, this.alanId, this.alanAdi});
  final String? orgId, orgAdi, alanId, alanAdi;
  @override
  State<PostaKutulariEkrani> createState() => _PostaKutulariEkraniState();
}

class _PostaKutulariEkraniState extends State<PostaKutulariEkrani> {
  String _q = '';
  String _durum = '';
  late String? _alanId = widget.alanId;
  late String? _alanAdi = widget.alanAdi;
  PostaKutusu? _secili;

  late final _y = SayfaYukleyici<PostaKutusu>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/mailboxes',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': 'address',
          'order': 'asc',
          if (_q.isNotEmpty) 'q': _q,
          if (_durum.isNotEmpty) 'status': _durum,
          if (_alanId != null) 'domain_id': _alanId,
          if (widget.orgId != null) 'organization_id': widget.orgId,
        },
      ),
      PostaKutusu.coz,
    ),
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _ac(PostaKutusu k) {
    if (bolunmus(context)) {
      setState(() => _secili = k);
    } else {
      sayfaAc(context, k.adres, KutuDetay(kutu: k, degisti: (y) => _degisti(k.id, y), tamSayfa: true));
    }
  }

  void _degisti(String id, PostaKutusu? y) {
    _y.degistir((x) => x.id == id, y);
    if (_secili?.id == id) setState(() => _secili = y);
  }

  Future<void> _yeni() async {
    final k = await showDialog<PostaKutusu>(
      context: context,
      builder: (_) => KutuOlusturDialog(orgId: widget.orgId, alanId: _alanId, alanAdi: _alanAdi),
    );
    if (k == null || !mounted) return;
    await _y.yenile();
    if (mounted) _ac(k);
  }

  Future<void> _alanFiltresi() async {
    if (_alanId != null) {
      setState(() => _alanId = _alanAdi = null);
      _y.yenile();
      return;
    }
    final d = await alanSec(context, orgId: widget.orgId);
    if (d == null) return;
    setState(() {
      _alanId = d.id;
      _alanAdi = d.gorunenAd;
    });
    _y.yenile();
  }

  @override
  Widget build(BuildContext context) {
    final yonetir = Uyg.yetki('mailboxes.manage');
    final r = context.r;
    final baslik = widget.alanAdi != null && widget.alanId == _alanId
        ? '${widget.alanAdi}'
        : (widget.orgAdi != null ? '${widget.orgAdi} · Posta kutuları' : 'Posta Kutuları');
    final liste = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: Column(
            children: [
              AramaAlani(
                ipucu: 'Adres veya ad ara…',
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    InputChip(
                      avatar: const Icon(Icons.language_rounded, size: 17),
                      label: Text(_alanAdi ?? 'Tüm alan adları'),
                      selected: _alanId != null,
                      showCheckmark: false,
                      onPressed: _alanFiltresi,
                      onDeleted: _alanId == null ? null : _alanFiltresi,
                      deleteButtonTooltipMessage: 'Filtreyi kaldır',
                    ),
                    const SizedBox(width: 8),
                    for (final (d, e) in const [('', 'Tümü'), ('active', 'Aktif'), ('suspended', 'Askıda')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(e),
                          selected: _durum == d,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() => _durum = d);
                            _y.yenile();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SayfaliListe<PostaKutusu>(
            yukleyici: _y,
            ayrac: false,
            bosMetin: _q.isEmpty && _durum.isEmpty ? 'Henüz posta kutusu yok.' : 'Eşleşen posta kutusu yok.',
            bosIkon: Icons.inbox_rounded,
            oge: (c, k) {
              final oran = kullanimOrani(k.kullanilan, k.kota);
              return ListeSatiri(
                secili: _secili?.id == k.id && bolunmus(c),
                onTap: () => _ac(k),
                sol: Avatar(k.gorunenAd.isEmpty ? k.adres : k.gorunenAd, tohum: k.adres),
                baslik: k.adres,
                alt: [if (k.gorunenAd.isNotEmpty) k.gorunenAd, if (!Uyg.musteri) k.orgAdi].join(' · '),
                alt2: k.sonGiris == null ? 'Hiç giriş yapılmadı' : 'Son giriş ${goreliZaman(k.sonGiris)}',
                sag: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!k.aktif) ...[DurumRozeti(k.durum), const SizedBox(height: 4)],
                    Text(
                      boyutYaz(k.kullanilan),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: (oran ?? 0) >= .9 ? Marka.gul : null),
                    ),
                    Text(sinirsizMi(k.kota) ? 'sınırsız' : '/ ${boyutYaz(k.kota)}', style: TextStyle(color: r.silik, fontSize: 11.5)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(baslik, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Takma adlar ve listeler',
            icon: const Icon(Icons.alternate_email_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TakmaAdlarEkrani(orgId: widget.orgId, alanId: _alanId, alanAdi: _alanAdi),
              ),
            ),
          ),
          if (yonetir && bolunmus(context)) IconButton(tooltip: 'Yeni posta kutusu', onPressed: _yeni, icon: const Icon(Icons.add_rounded)),
          if (bolunmus(context)) IconButton(tooltip: 'Yenile', onPressed: _y.yenile, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: yonetir && !bolunmus(context)
          ? FloatingActionButton.extended(onPressed: _yeni, icon: const Icon(Icons.person_add_alt_rounded), label: const Text('Posta kutusu'))
          : null,
      body: AnaDetay(
        liste: liste,
        detay: _secili == null ? null : KutuDetay(key: ValueKey(_secili!.id), kutu: _secili!, degisti: (y) => _degisti(_secili!.id, y)),
        bosMetin: 'Ayrıntı için bir posta kutusu seçin',
      ),
    );
  }
}
