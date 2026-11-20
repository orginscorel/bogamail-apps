import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../veri/takvim_servisi.dart';

/// İletideki toplantı daveti: ayrıntılar ve Katıl / Belki / Katılma yanıtı; iptal ve yanıt iletileri için bilgi.
class DavetKarti extends StatefulWidget {
  const DavetKarti({super.key, required this.iletiId});
  final String iletiId;
  @override
  State<DavetKarti> createState() => _DavetKartiState();
}

class _DavetKartiState extends State<DavetKarti> {
  Davet? _d;
  bool _yok = false;
  String? _mesgul;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final d = await TakvimApi.davet(widget.iletiId);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      if (mounted) setState(() => _yok = true);
    }
  }

  Future<void> _yanitla(String y) async {
    var yanitsiz = false;
    if (_d!.duzenleyen.isNotEmpty) {
      final s = await showModalBottomSheet<bool>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(leading: const Icon(Simge.gonder), title: const Text('Yanıtı düzenleyene gönder'), onTap: () => Navigator.pop(c, false)),
              ListTile(
                leading: const Icon(Simge.etkinlikOnay),
                title: const Text('Yalnızca takvimime işle'),
                subtitle: const Text('Düzenleyene e-posta gitmez'),
                onTap: () => Navigator.pop(c, true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (s == null) return;
      yanitsiz = s;
    }
    setState(() => _mesgul = y);
    try {
      final v = await TakvimApi.davetYanitla(widget.iletiId, y, yanitsiz: yanitsiz);
      if (v.hata.isNotEmpty) {
        bildir('Takviminize işlendi, yanıt gönderilemedi', mesaj: v.hata, tur: MesajTur.uyari);
      } else {
        bildir(v.yanitlandi ? 'Yanıtınız gönderildi' : 'Takviminize işlendi', tur: MesajTur.basari);
      }
      await _yukle();
    } catch (e) {
      bildir('Yanıtlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = null);
    }
  }

  Future<void> _iptal() async {
    setState(() => _mesgul = 'iptal');
    try {
      final not = await TakvimApi.iptaliUygula(widget.iletiId);
      bildir('Etkinlik takviminizden kaldırıldı', mesaj: not.isEmpty ? null : not, tur: MesajTur.basari);
      await _yukle();
    } catch (e) {
      bildir('Uygulanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (_yok || d == null) return const SizedBox.shrink();
    final r = context.r;
    final iptal = d.yontem == 'CANCEL';
    final yanit = d.yontem == 'REPLY';
    final tarih = d.baslangic == null
        ? ''
        : d.tumGun
        ? DateFormat('d MMMM y EEEE', 'tr_TR').format(d.baslangic!)
        : '${DateFormat('d MMMM y EEEE, HH:mm', 'tr_TR').format(d.baslangic!)}${d.bitis != null ? ' – ${DateFormat('HH:mm').format(d.bitis!)}' : ''}';
    Widget dugme(String deger, String ad, IconData i) {
      final secili = d.yanitim == deger;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: secili
              ? FilledButton.icon(onPressed: null, icon: Icon(i, size: 18), label: Text(ad))
              : OutlinedButton.icon(
                  onPressed: _mesgul != null ? null : () => _yanitla(deger),
                  icon: _mesgul == deger ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(i, size: 18),
                  label: Text(ad),
                ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: iptal ? Marka.gul.withValues(alpha: .07) : r.vurguYumusak,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iptal ? Marka.gul.withValues(alpha: .3) : r.vurgu.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iptal ? Simge.etkinlikIptal : Simge.etkinlik, color: iptal ? Marka.gul : r.vurgu),
              const SizedBox(width: 8),
              Text(
                iptal ? 'Toplantı iptal edildi' : (yanit ? 'Davet yanıtı' : 'Toplantı daveti'),
                style: TextStyle(fontWeight: FontWeight.w600, color: iptal ? Marka.gul : r.vurgu),
              ),
              if (d.eskimis) ...[const SizedBox(width: 8), const Rozet('Güncel değil', renk: Marka.kehribar)],
            ],
          ),
          const SizedBox(height: 8),
          Text(d.baslik.isEmpty ? '(başlıksız)' : d.baslik, style: gosterim(17, agirlik: FontWeight.w600)),
          if (tarih.isNotEmpty) Text(tarih + (d.tekrarli ? ' · tekrarlanır' : ''), style: TextStyle(color: r.soluk)),
          if (d.yer.isNotEmpty) Text(d.yer, style: TextStyle(color: r.soluk)),
          if (d.duzenleyen.isNotEmpty)
            Text('Düzenleyen: ${d.duzenleyenAd.isNotEmpty ? d.duzenleyenAd : d.duzenleyen}', style: TextStyle(color: r.silik, fontSize: 12.5)),
          if (d.katilimcilar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final k in d.katilimcilar.take(12))
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Avatar(k.gorunen, boyut: 20, tohum: k.eposta),
                      label: Text(k.yanit.isEmpty ? k.gorunen : '${k.gorunen} · ${katilimAdlari[k.yanit] ?? k.yanit}', style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          if (yanit)
            Text(
              [
                if (d.yanitVeren.isNotEmpty) '${d.yanitVeren}: ${katilimAdlari[d.yanitDurumu] ?? d.yanitDurumu}',
                d.yanitUygulandi ? 'Takviminize işlendi.' : (d.yanitNotu.isNotEmpty ? d.yanitNotu : ''),
              ].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(color: r.metin),
            )
          else if (iptal)
            d.etkinlikId.isEmpty
                ? Text('Etkinlik takviminizde değil.', style: TextStyle(color: r.soluk))
                : FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Marka.gul),
                    onPressed: _mesgul != null ? null : _iptal,
                    icon: const Icon(Simge.etkinlikIptal),
                    label: const Text('Takvimimden kaldır'),
                  )
          else if (d.duzenleyenBenim)
            Text('Bu toplantıyı siz düzenlediniz.', style: TextStyle(color: r.soluk))
          else if (!d.eskimis)
            Row(children: [dugme('ACCEPTED', 'Katıl', Simge.onay), dugme('TENTATIVE', 'Belki', Simge.yardim), dugme('DECLINED', 'Katılma', Simge.kapat)]),
        ],
      ),
    );
  }
}
