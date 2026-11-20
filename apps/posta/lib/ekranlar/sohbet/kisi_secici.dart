import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/sohbet_servisi.dart';
import 'ortak.dart';
import '../../ortak/uyarlanir.dart';

/// Kurum rehberi: arama, çevrimiçi durumu. [coklu] ise birden fazla kişi seçilip grup adı girilir.
class KisiSecici extends StatefulWidget {
  const KisiSecici({super.key, this.coklu = false});
  final bool coklu;

  /// Tek kişi → birebir sohbet; çoklu → grup. Oluşan oda kimliğini döndürür.
  static Future<String?> ac(BuildContext context, {bool coklu = false}) => uyarlanirAc<String>(context, (_) => KisiSecici(coklu: coklu), genislik: 560);

  @override
  State<KisiSecici> createState() => _KisiSeciciState();
}

class _KisiSeciciState extends State<KisiSecici> {
  final _ara = TextEditingController();
  final _ad = TextEditingController();
  List<SohbetKisi>? _l;
  String? _hata;
  bool _gorunur = true;
  final _secili = <String, SohbetKisi>{};
  Timer? _gecikme;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    _ara.dispose();
    _ad.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final q = _ara.text;
    try {
      final v = await Sohbet.kisiler(q: q);
      if (!mounted || q != _ara.text) return;
      setState(() {
        _l = v.kisiler;
        _gorunur = v.cevrimiciGorunur;
        _hata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _olustur(List<SohbetKisi> kisiler, {String ad = ''}) async {
    setState(() => _mesgul = true);
    try {
      final id = await Sohbet.odaOlustur(kisiler.map((k) => k.id).toList(), ad: ad);
      await SohbetDurum.ben.yenile();
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      bildir('Sohbet başlatılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _l;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.coklu ? 'Yeni grup' : 'Yeni sohbet'),
        actions: [
          if (widget.coklu)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _secili.isEmpty || _mesgul
                    ? null
                    : () {
                        if (_ad.text.trim().isEmpty) {
                          bildir('Gruba bir ad verin', tur: MesajTur.uyari);
                          return;
                        }
                        _olustur(_secili.values.toList(), ad: _ad.text);
                      },
                child: Text('Oluştur (${_secili.length})'),
              ),
            ),
        ],
        bottom: _mesgul ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: Column(
        children: [
          if (widget.coklu)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _ad,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Grup adı', counterText: '', prefixIcon: Icon(Simge.gruplar)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _ara,
              autofocus: !widget.coklu,
              decoration: const InputDecoration(hintText: 'Ad, adres, departman ara', prefixIcon: Icon(Simge.ara), isDense: true),
              onChanged: (_) {
                _gecikme?.cancel();
                _gecikme = Timer(const Duration(milliseconds: 250), _yukle);
              },
            ),
          ),
          if (widget.coklu && _secili.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final k in _secili.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InputChip(
                        avatar: Avatar(k.gorunen, boyut: 22, tohum: k.adres),
                        label: Text(k.gorunen),
                        onDeleted: () => setState(() => _secili.remove(k.id)),
                      ),
                    ),
                ],
              ),
            ),
          if (!_gorunur)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Çevrimiçi durumunuzu gizlediğiniz için başkalarının durumunu da göremezsiniz.', style: TextStyle(color: r.silik, fontSize: 12)),
            ),
          Expanded(
            child: _hata != null && l == null
                ? Durum.hata(_hata!, tekrar: _yukle)
                : l == null
                ? const Durum.yukleniyor()
                : l.isEmpty
                ? const Durum.bos('Kişi bulunamadı.', ikon: Simge.kisiAra)
                : ListView.builder(
                    itemCount: l.length,
                    itemBuilder: (_, i) {
                      final k = l[i];
                      final v = varlikMetni(k);
                      final alt = [
                        if (k.altBilgi.isNotEmpty) k.altBilgi,
                        if (k.durum.isNotEmpty) sohbetDurumAdlari[k.durum] ?? '',
                        if (k.durumMetni.isNotEmpty) k.durumMetni,
                        if (v.metin.isNotEmpty) v.metin,
                      ].where((s) => s.isNotEmpty).join(' · ');
                      return ListTile(
                        leading: VarlikAvatari(kisi: k),
                        title: Text(k.gorunen, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(alt.isEmpty ? k.adres : alt, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: widget.coklu
                            ? Checkbox(value: _secili.containsKey(k.id), onChanged: (v) => setState(() => v == true ? _secili[k.id] = k : _secili.remove(k.id)))
                            : Icon(Simge.mesaj, color: r.vurgu),
                        onTap: _mesgul
                            ? null
                            : () {
                                if (widget.coklu) {
                                  setState(() => _secili.containsKey(k.id) ? _secili.remove(k.id) : _secili[k.id] = k);
                                } else {
                                  _olustur([k]);
                                }
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
