import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/sohbet_servisi.dart';
import '../hesap/ortak.dart';

/// Kurum kanalları: göz at, katıl, ayrıl, oluştur; yetkiliyse düzenle/arşivle. Bir kanala dokununca oda kimliği döner.
class KanallarEkrani extends StatelessWidget {
  const KanallarEkrani({super.key});

  static Future<String?> ac(BuildContext context) => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const KanallarEkrani()));

  Future<({String ad, String aciklama})?> _form(BuildContext context, {String ad = '', String aciklama = '', required String baslik}) async {
    final a = TextEditingController(text: ad);
    final d = TextEditingController(text: aciklama);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w700)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: a,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Kanal adı', prefixText: '# '),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: d,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    );
    final v = (ad: a.text.trim(), aciklama: d.text.trim());
    a.dispose();
    d.dispose();
    return ok == true && v.ad.isNotEmpty ? v : null;
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<({List<Kanal> kanallar, bool hepsiniYonetir})>(
    baslik: 'Kanallar',
    altBaslik: 'Kanallar kurumunuzdaki herkese açıktır. Katıldığınız kanallar sohbet listenizde görünür.',
    yukle: Sohbet.kanallar,
    fab: (context, yenile) => FloatingActionButton.extended(
      onPressed: () async {
        final f = await _form(context, baslik: 'Yeni kanal');
        if (f == null) return;
        final id = await islem(() => Sohbet.kanalOlustur(f.ad, f.aciklama), tamam: 'Kanal oluşturuldu');
        await SohbetDurum.ben.yenile();
        if (id != null && context.mounted) Navigator.pop(context, id);
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Kanal oluştur'),
    ),
    govde: (context, v, yenile) {
      final r = context.r;
      final acik = v.kanallar.where((k) => !k.arsivli).toList();
      final arsiv = v.kanallar.where((k) => k.arsivli).toList();
      Widget satir(Kanal k) => ListTile(
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: k.arsivli ? r.ic : r.vurguYumusak, borderRadius: BorderRadius.circular(12)),
          child: Text('#', style: gosterim(20, renk: k.arsivli ? r.silik : r.vurgu)),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(k.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (k.varsayilan) ...[const SizedBox(width: 6), const Rozet('Genel', renk: Marka.zumrut)],
            if (k.katildi && !k.varsayilan) ...[const SizedBox(width: 6), Rozet('Üyesiniz', renk: r.vurgu)],
          ],
        ),
        subtitle: Text(
          [if (k.aciklama.isNotEmpty) k.aciklama, '${k.uyeSayisi} üye', if (k.olusturanAd.isNotEmpty) 'Oluşturan: ${k.olusturanAd}'].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: k.arsivli && !k.katildi ? null : () => Navigator.pop(context, k.id),
        trailing: PopupMenuButton<String>(
          tooltip: 'Seçenekler',
          onSelected: (s) async {
            switch (s) {
              case 'katil':
                await islem(() => Sohbet.kanalaKatil(k.id), tamam: '#${k.ad} kanalına katıldınız');
              case 'ayril':
                if (!await onayla(context, '#${k.ad} kanalından ayrılınsın mı?', evet: 'Ayrıl')) return;
                await islem(() => Sohbet.kanaldanAyril(k.id), tamam: 'Kanaldan ayrıldınız');
              case 'duzenle':
                final f = await _form(context, ad: k.ad, aciklama: k.aciklama, baslik: 'Kanalı düzenle');
                if (f == null) return;
                await islem(
                  () => Sohbet.kanalGuncelle(k.id, ad: f.ad, aciklama: f.aciklama),
                  tamam: 'Kanal güncellendi',
                );
              case 'arsiv':
                if (!k.arsivli && !await onayla(context, '#${k.ad} arşivlensin mi?', mesaj: 'Arşivlenen kanala yeni ileti yazılamaz.', evet: 'Arşivle')) return;
                await islem(() => Sohbet.kanalGuncelle(k.id, arsiv: !k.arsivli), tamam: k.arsivli ? 'Kanal arşivden çıkarıldı' : 'Kanal arşivlendi');
            }
            await SohbetDurum.ben.yenile();
            await yenile();
          },
          itemBuilder: (_) => [
            if (!k.katildi && !k.arsivli && !k.varsayilan)
              const PopupMenuItem(
                value: 'katil',
                child: ListTile(leading: Icon(Icons.login_rounded), title: Text('Katıl')),
              ),
            if (k.katildi && !k.varsayilan)
              const PopupMenuItem(
                value: 'ayril',
                child: ListTile(leading: Icon(Icons.logout_rounded), title: Text('Ayrıl')),
              ),
            if (k.yonetebilir) ...[
              const PopupMenuItem(
                value: 'duzenle',
                child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Düzenle')),
              ),
              if (!k.varsayilan)
                PopupMenuItem(
                  value: 'arsiv',
                  child: ListTile(leading: const Icon(Icons.archive_outlined), title: Text(k.arsivli ? 'Arşivden çıkar' : 'Arşivle')),
                ),
            ],
          ],
        ),
      );
      return [
        if (acik.isEmpty) const BosKart('Henüz kanal yok.', ikon: Icons.tag_rounded) else KartListe(children: [for (final k in acik) satir(k)]),
        if (arsiv.isNotEmpty) ...[
          const Baslik('Arşivlenmiş kanallar'),
          KartListe(children: [for (final k in arsiv) satir(k)]),
        ],
      ];
    },
  );
}
