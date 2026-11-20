import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/secimler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';

/// Takma adlar ve dağıtım listeleri (GET/POST/PATCH/DELETE /aliases).
class TakmaAdlarEkrani extends StatefulWidget {
  const TakmaAdlarEkrani({super.key, this.orgId, this.alanId, this.alanAdi});
  final String? orgId, alanId, alanAdi;
  @override
  State<TakmaAdlarEkrani> createState() => _TakmaAdlarEkraniState();
}

class _TakmaAdlarEkraniState extends State<TakmaAdlarEkrani> {
  String _tur = 'alias';
  String _q = '';
  List<TakmaAd>? _liste;
  String? _hata;
  int _nesil = 0;

  bool get _yonetir => Uyg.yetki('mailboxes.manage');

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final n = ++_nesil;
    setState(() => _hata = null);
    try {
      final v = await Uyg.api.get(
        '/api/v1/aliases',
        q: {
          'kind': _tur,
          if (_q.isNotEmpty) 'q': _q,
          if (widget.alanId != null) 'domain_id': widget.alanId,
          if (widget.orgId != null) 'organization_id': widget.orgId,
        },
      );
      if (mounted && n == _nesil) setState(() => _liste = haritalar(harita(v)['items']).map(TakmaAd.coz).toList());
    } catch (e) {
      if (mounted && n == _nesil) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _yeni() async {
    final t = await showDialog<TakmaAd>(
      context: context,
      builder: (_) => TakmaAdDialog(liste: _tur == 'list', orgId: widget.orgId, alanId: widget.alanId, alanAdi: widget.alanAdi),
    );
    if (t != null) _yukle();
  }

  Future<void> _ayrinti(TakmaAd t) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(t.adres, style: gosterim(18, agirlik: FontWeight.w700)),
              Text(
                [t.liste ? 'Dağıtım listesi' : 'Takma ad', if (t.ad.isNotEmpty) t.ad, if (!Uyg.musteri) t.orgAdi].join(' · '),
                style: TextStyle(color: c.r.silik),
              ),
              const SizedBox(height: 12),
              if (t.liste) BilgiSatiri('Kimler gönderebilir', gonderimIzinleri[t.gonderimIzni] ?? t.gonderimIzni),
              BilgiSatiri('Durum', t.etkin ? 'Etkin' : 'Devre dışı'),
              const SizedBox(height: 6),
              Text(
                t.liste ? '${t.hedefler.length} üye' : 'Hedef adresler',
                style: TextStyle(color: c.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .3),
                child: ListView(shrinkWrap: true, children: [for (final h in t.hedefler) KopyaKutusu(h)]),
              ),
              if (_yonetir) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(t.etkin ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        label: Text(t.etkin ? 'Devre dışı bırak' : 'Etkinleştir'),
                        onPressed: () async {
                          Navigator.pop(c);
                          final v = await islem(
                            () => Uyg.api.patch('/api/v1/aliases/${t.id}', {'enabled': !t.etkin}),
                            tamam: t.etkin ? 'Devre dışı bırakıldı' : 'Etkinleştirildi',
                          );
                          if (v != null) _yukle();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Marka.gul),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Sil'),
                        onPressed: () async {
                          Navigator.pop(c);
                          if (!await onayla(
                            context,
                            '${t.adres} silinsin mi?',
                            mesaj: 'Bu adrese gelen posta artık iletilmez. Bu işlem geri alınamaz.',
                            evet: 'Sil',
                            tehlikeli: true,
                          )) {
                            return;
                          }
                          final v = await islem(() => Uyg.api.delete('/api/v1/aliases/${t.id}').then((_) => true), tamam: 'Silindi');
                          if (v == true) _yukle();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _liste;
    return Scaffold(
      appBar: AppBar(title: Text(widget.alanAdi == null ? 'Takma Adlar' : 'Takma Adlar · ${widget.alanAdi}', overflow: TextOverflow.ellipsis)),
      floatingActionButton: _yonetir
          ? FloatingActionButton.extended(onPressed: _yeni, icon: const Icon(Icons.add_rounded), label: Text(_tur == 'list' ? 'Liste' : 'Takma ad'))
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Column(
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'alias', label: Text('Takma adlar')),
                    ButtonSegment(value: 'list', label: Text('Dağıtım listeleri')),
                  ],
                  selected: {_tur},
                  onSelectionChanged: (s) {
                    setState(() {
                      _tur = s.first;
                      _liste = null;
                    });
                    _yukle();
                  },
                ),
                const SizedBox(height: 8),
                AramaAlani(
                  ipucu: _tur == 'list' ? 'Liste veya üye ara…' : 'Adres veya hedef ara…',
                  degisti: (v) {
                    _q = v;
                    _yukle();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator.adaptive(
              onRefresh: _yukle,
              child: _hata != null && l == null
                  ? ListView(
                      children: [SizedBox(height: 300, child: Durum.hata(_hata!, tekrar: _yukle))],
                    )
                  : l == null
                  ? const Durum.yukleniyor()
                  : l.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: 300,
                          child: Durum.bos(_tur == 'list' ? 'Henüz dağıtım listesi yok.' : 'Henüz takma ad yok.', ikon: Icons.alternate_email_rounded),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      itemCount: l.length,
                      itemBuilder: (c, i) {
                        final t = l[i];
                        return ListeSatiri(
                          onTap: () => _ayrinti(t),
                          sol: CircleAvatar(
                            backgroundColor: r.birincilYumusak,
                            child: Icon(t.liste ? Icons.groups_rounded : Icons.alternate_email_rounded, color: r.birincil, size: 20),
                          ),
                          baslik: t.adres,
                          alt: t.liste ? '${t.hedefler.length} üye · ${gonderimIzinleri[t.gonderimIzni] ?? t.gonderimIzni}' : '→ ${t.hedefler.join(', ')}',
                          alt2: [if (t.ad.isNotEmpty) t.ad, if (!Uyg.musteri) t.orgAdi].join(' · '),
                          sag: t.etkin ? null : const Rozet('kapalı', renk: Marka.kehribar),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yeni takma ad / dağıtım listesi (POST /aliases).
class TakmaAdDialog extends StatefulWidget {
  const TakmaAdDialog({super.key, required this.liste, this.orgId, this.alanId, this.alanAdi});
  final bool liste;
  final String? orgId, alanId, alanAdi;
  @override
  State<TakmaAdDialog> createState() => _TakmaAdDialogState();
}

class _TakmaAdDialogState extends State<TakmaAdDialog> {
  late String? _alanId = widget.alanId;
  late String? _alanAdi = widget.alanAdi;
  final _yerel = TextEditingController();
  final _ad = TextEditingController();
  final _hedefler = TextEditingController();
  String _izin = 'anyone';
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void dispose() {
    _yerel.dispose();
    _ad.dispose();
    _hedefler.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
      _alan = null;
    });
    try {
      final v = await Uyg.api.post('/api/v1/aliases', {
        'domain_id': _alanId,
        'local_part': _yerel.text.trim().toLowerCase(),
        'kind': widget.liste ? 'list' : 'alias',
        if (widget.liste && _ad.text.trim().isNotEmpty) 'name': _ad.text.trim(),
        'destinations': adresleriAyir(_hedefler.text),
        if (widget.liste) 'send_policy': _izin,
      });
      bildir(widget.liste ? 'Dağıtım listesi oluşturuldu' : 'Takma ad oluşturuldu', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, TakmaAd.coz(harita(v)));
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
    final hazir = !_mesgul && _alanId != null && _yerel.text.trim().isNotEmpty && adresleriAyir(_hedefler.text).isNotEmpty;
    return AlertDialog(
      title: Text(widget.liste ? 'Yeni dağıtım listesi' : 'Yeni takma ad', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SecimAlani(
                etiket: 'Alan adı',
                deger: _alanAdi,
                hata: _alan == 'domain_id' ? _hata : null,
                onTap: () async {
                  final d = await alanSec(context, orgId: widget.orgId);
                  if (d != null) {
                    setState(() {
                      _alanId = d.id;
                      _alanAdi = d.gorunenAd;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _yerel,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Adres',
                  hintText: widget.liste ? 'satis' : 'info',
                  suffixText: _alanAdi == null ? null : '@$_alanAdi',
                  errorText: _alan == 'local_part' ? _hata : null,
                ),
              ),
              if (widget.liste) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _ad,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Liste adı', hintText: 'Satış ekibi'),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _hedefler,
                minLines: 3,
                maxLines: 8,
                autocorrect: false,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: widget.liste ? 'Üyeler (her satıra bir adres)' : 'Hedef adresler (her satıra bir adres)',
                  alignLabelWithHint: true,
                  errorText: _alan == 'destinations' ? _hata : null,
                ),
              ),
              if (widget.liste) ...[
                const SizedBox(height: 12),
                Text(
                  'Kimler gönderebilir?',
                  style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SecimCipleri<String>(
                  secenekler: [for (final e in gonderimIzinleri.entries) (e.key, e.value)],
                  secili: _izin,
                  secildi: (v) => setState(() => _izin = v),
                ),
              ],
              if (_hata != null && !{'domain_id', 'local_part', 'destinations'}.contains(_alan)) ...[
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
          child: _mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Oluştur'),
        ),
      ],
    );
  }
}
