// Giden Kutusu (Outlook gibi): çevrimdışıyken gönderilen iletiler. Her öğe durumunu gösterir (Bekliyor /
// Gönderiliyor… / Hata: neden + Tekrar dene); açılıp düzenlenebilir (yazma penceresine döner) ya da gitmeden
// silinebilir. Bağlantı gelince sırayla kendiliğinden gönderilir; sunucu Gönderilenler'e koyar.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../veri/baglanti.dart';
import '../veri/kuyruk.dart';
import '../veri/yazma_hazirla.dart';
import 'yazma.dart';

/// Öğeyi yazma penceresinde açar (düzenleme). Pencere açıkken öğe gönderilmez.
Future<void> gidenDuzenle(BuildContext context, GidenOge o) async {
  final c = await GidenKutusu.ben.icerik(o.id);
  if (c == null || !context.mounted) return;
  await yazmaAc(context, gidenHazirla(o.id, c.$1, c.$2));
}

class GidenKutusuEkrani extends StatelessWidget {
  const GidenKutusuEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giden Kutusu'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: Baglanti.ben.cevrimdisi,
            builder: (_, cd, _) => TextButton.icon(
              key: const ValueKey('giden-simdi-gonder'),
              onPressed: () => unawaited(GidenKutusu.ben.gonder()),
              icon: const Icon(Simge.gonder, size: 18),
              label: Text(cd ? 'Yeniden dene' : 'Şimdi gönder'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ValueListenableBuilder<List<GidenOge>>(
        valueListenable: GidenKutusu.ben.ogeler,
        builder: (context, l, _) {
          if (l.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Simge.gidenKutusu, size: 40, color: r.silik),
                  const SizedBox(height: 10),
                  Text('Gönderilmeyi bekleyen ileti yok.', style: TextStyle(color: r.soluk)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: l.length + 1,
            separatorBuilder: (_, _) => Divider(height: 1, color: r.kenar),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Text(
                    'Bu iletiler bağlantı gelince sırayla gönderilir ve Gönderilenler\'e taşınır. Gitmeden açıp düzenleyebilir ya da silebilirsiniz.',
                    style: TextStyle(fontSize: 13, color: r.soluk),
                  ),
                );
              }
              return _GidenSatiri(o: l[i - 1]);
            },
          );
        },
      ),
    );
  }
}

class _GidenSatiri extends StatelessWidget {
  const _GidenSatiri({required this.o});
  final GidenOge o;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final (metin, renk) = switch (o.durum) {
      GidenDurum.bekliyor => ('Bekliyor', Marka.kehribar),
      GidenDurum.gonderiliyor => ('Gönderiliyor…', r.birincil),
      GidenDurum.hata => ('Hata: ${o.hata ?? 'gönderilemedi'}', Marka.gul),
    };
    return InkWell(
      key: ValueKey('giden-${o.id}'),
      onTap: o.durum == GidenDurum.gonderiliyor ? null : () => gidenDuzenle(context, o),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(o.durum == GidenDurum.hata ? Simge.hata : Simge.gidenKutusu, size: 20, color: renk),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.kime.isEmpty ? '(alıcı yok)' : o.kime,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                        ),
                      ),
                      Text(DateFormat('d MMM HH:mm', 'tr_TR').format(o.zaman), style: TextStyle(fontSize: 12, color: r.silik)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    o.konu.trim().isEmpty ? '(konu yok)' : o.konu,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: r.metin),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        key: ValueKey('giden-durum-${o.id}'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                        child: Text(
                          metin,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: renk),
                        ),
                      ),
                      if (o.ekSayisi > 0)
                        Text('${o.ekSayisi} ek${o.boyut > 0 ? ' · ${boyutYaz(o.boyut)}' : ''}', style: TextStyle(fontSize: 12, color: r.silik)),
                      if (o.durum == GidenDurum.hata)
                        TextButton(
                          key: ValueKey('giden-tekrar-${o.id}'),
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                          onPressed: () => unawaited(GidenKutusu.ben.tekrarDene(o.id)),
                          child: const Text('Tekrar dene'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('giden-menu-${o.id}'),
              tooltip: 'Seçenekler',
              enabled: o.durum != GidenDurum.gonderiliyor,
              onSelected: (v) async {
                if (v == 'duzenle') {
                  await gidenDuzenle(context, o);
                } else if (await onayla(context, 'İleti silinsin mi?', mesaj: 'Giden Kutusu\'ndan kaldırılır, gönderilmez.', evet: 'Sil', tehlikeli: true)) {
                  await GidenKutusu.ben.sil(o.id);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'duzenle',
                  child: ListTile(leading: Icon(Simge.duzenle), title: Text('Aç ve düzenle')),
                ),
                PopupMenuItem(
                  value: 'sil',
                  child: ListTile(
                    leading: Icon(Simge.sil, color: Marka.gul),
                    title: Text('Sil'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
