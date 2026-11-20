import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/hesap_servisi.dart';
import '../../veri/html_temizle.dart';
import '../../veri/yardimci.dart';
import 'ortak.dart';

const _zamanlamalar = {'always': 'Her zaman', 'inside': 'Belirli saatlerde', 'outside': 'Belirli saatler dışında'};
const _gondericiler = {'any': 'Herkese', 'internal': 'Yalnızca kurum içine', 'external': 'Yalnızca kurum dışına'};
const _gunAdlari = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

String kuralOzeti(OtomatikKural k) {
  final z = switch (k.zamanlama) {
    'inside' => '${k.gunler.map((g) => _gunAdlari[(g - 1).clamp(0, 6)]).join(', ')} ${k.baslangicSaati}–${k.bitisSaati}',
    'outside' => '${k.baslangicSaati}–${k.bitisSaati} dışında',
    _ => 'Her zaman',
  };
  return '$z · ${_gondericiler[k.gonderen] ?? k.gonderen} · ${k.araGun} günde bir';
}

/// Kural tabanlı otomatik yanıtlar (mesai dışı, belirli günler, iç/dış gönderen).
class OtomatikYanitKurallariEkrani extends StatelessWidget {
  const OtomatikYanitKurallariEkrani({super.key});

  Future<void> _duzenle(BuildContext context, OtomatikKural? k, Future<void> Function() yenile) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _KuralDuzenleyici(kural: k)));
    if (ok == true) await yenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<({List<OtomatikKural> benim, List<OtomatikKural> kurum})>(
    baslik: 'Otomatik yanıt kuralları',
    altBaslik: 'Örneğin mesai saatleri dışında yazanlara otomatik yanıt verin. Basit izin yanıtı için Ayarlar › Otomatik yanıt bölümünü kullanın.',
    yukle: Hesap.otomatikKurallar,
    fab: (context, yenile) =>
        FloatingActionButton.extended(onPressed: () => _duzenle(context, null, yenile), icon: const Icon(Icons.add_rounded), label: const Text('Kural ekle')),
    govde: (context, v, yenile) => [
      if (v.benim.isEmpty)
        const BosKart('Henüz kuralınız yok.', ikon: Icons.auto_mode_rounded)
      else
        KartListe(
          children: [
            for (final k in v.benim)
              ListTile(
                onTap: () => _duzenle(context, k, yenile),
                leading: Switch.adaptive(
                  value: k.acik,
                  onChanged: (a) async {
                    k.acik = a;
                    await islem(() => Hesap.otomatikKuralKaydet(k), tamam: a ? 'Kural açıldı' : 'Kural kapatıldı');
                    await yenile();
                  },
                ),
                title: Text(k.ad.isEmpty ? 'Adsız kural' : k.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(kuralOzeti(k)),
                trailing: IconButton(
                  tooltip: 'Sil',
                  icon: Icon(Icons.delete_outline_rounded, color: context.r.silik),
                  onPressed: () async {
                    if (!await onayla(context, 'Kural silinsin mi?', evet: 'Sil', tehlikeli: true)) return;
                    await islem(() => Hesap.otomatikKuralSil(k.id), tamam: 'Kural silindi');
                    await yenile();
                  },
                ),
              ),
          ],
        ),
      if (v.kurum.isNotEmpty) ...[
        const Baslik('Kurumunuzun kuralları'),
        KartListe(
          children: [
            for (final k in v.kurum)
              ListTile(
                leading: Icon(Icons.apartment_rounded, color: context.r.silik),
                title: Text(k.ad),
                subtitle: Text(kuralOzeti(k)),
                trailing: Rozet(k.acik ? 'Açık' : 'Kapalı', renk: k.acik ? Marka.zumrut : const Color(0xFF94A3B8)),
              ),
          ],
        ),
      ],
    ],
  );
}

class _KuralDuzenleyici extends StatefulWidget {
  const _KuralDuzenleyici({this.kural});
  final OtomatikKural? kural;
  @override
  State<_KuralDuzenleyici> createState() => _KuralDuzenleyiciState();
}

class _KuralDuzenleyiciState extends State<_KuralDuzenleyici> {
  late final OtomatikKural _k = widget.kural ?? OtomatikKural(gunler: [1, 2, 3, 4, 5], baslangicSaati: '09:00', bitisSaati: '18:00', zamanlama: 'outside');
  late final _ad = TextEditingController(text: _k.ad);
  late final _konu = TextEditingController(text: _k.konu);
  late final _metin = TextEditingController(text: _k.govdeHtml.isEmpty ? '' : htmlMetne(_k.govdeHtml));
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _konu.dispose();
    _metin.dispose();
    super.dispose();
  }

  Future<void> _saat(bool baslangic) async {
    final s = (baslangic ? _k.baslangicSaati : _k.bitisSaati).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(s.first) ?? 9, minute: s.length > 1 ? int.tryParse(s[1]) ?? 0 : 0),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => baslangic ? _k.baslangicSaati = v : _k.bitisSaati = v);
  }

  Future<void> _kaydet() async {
    _k.ad = _ad.text.trim();
    _k.konu = _konu.text.trim();
    final eski = _k.govdeHtml.isEmpty ? '' : htmlMetne(_k.govdeHtml);
    if (_metin.text != eski) _k.govdeHtml = metindenHtml(_metin.text.trim());
    if (_k.ad.isEmpty) return bildir('Kurala bir ad verin', tur: MesajTur.uyari);
    if (_metin.text.trim().isEmpty) return bildir('Yanıt metnini yazın', tur: MesajTur.uyari);
    if (_k.zamanlama != 'always' && _k.gunler.isEmpty) return bildir('En az bir gün seçin', tur: MesajTur.uyari);
    setState(() => _mesgul = true);
    final ok = await islem(() async {
      await Hesap.otomatikKuralKaydet(_k);
      return true;
    }, tamam: 'Kural kaydedildi');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.kural == null ? 'Yeni kural' : 'Kuralı düzenle'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              TextField(
                controller: _ad,
                decoration: const InputDecoration(labelText: 'Kural adı', hintText: 'Örn. Mesai dışı yanıtı'),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _k.acik,
                onChanged: (v) => setState(() => _k.acik = v),
                title: const Text('Etkin'),
              ),
              const Baslik('Ne zaman'),
              DropdownButtonFormField<String>(
                initialValue: _k.zamanlama,
                items: [for (final e in _zamanlamalar.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _k.zamanlama = v ?? 'always'),
              ),
              if (_k.zamanlama != 'always') ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var g = 1; g <= 7; g++)
                      FilterChip(
                        label: Text(_gunAdlari[g - 1]),
                        selected: _k.gunler.contains(g),
                        onSelected: (v) => setState(
                          () => v
                              ? (_k.gunler
                                  ..add(g)
                                  ..sort())
                              : _k.gunler.remove(g),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _saat(true),
                        icon: const Icon(Icons.schedule_rounded, size: 18),
                        label: Text('Başlangıç ${_k.baslangicSaati.isEmpty ? '—' : _k.baslangicSaati}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _saat(false),
                        icon: const Icon(Icons.schedule_rounded, size: 18),
                        label: Text('Bitiş ${_k.bitisSaati.isEmpty ? '—' : _k.bitisSaati}'),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Saatler Türkiye saatine göredir.', style: TextStyle(color: r.silik, fontSize: 12.5)),
                ),
              ],
              const Baslik('Kime'),
              DropdownButtonFormField<String>(
                initialValue: _k.gonderen,
                items: [for (final e in _gondericiler.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _k.gonderen = v ?? 'any'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(child: Text('Aynı kişiye en fazla')),
                  DropdownButton<int>(
                    value: const [1, 2, 3, 4, 7, 14, 30].contains(_k.araGun) ? _k.araGun : 4,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final g in const [1, 2, 3, 4, 7, 14, 30]) DropdownMenuItem(value: g, child: Text('$g günde bir')),
                    ],
                    onChanged: (v) => setState(() => _k.araGun = v ?? 4),
                  ),
                ],
              ),
              const Baslik('Yanıt'),
              TextField(
                controller: _konu,
                decoration: const InputDecoration(labelText: 'Konu'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _metin,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(labelText: 'Yanıt metni', alignLabelWithHint: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
