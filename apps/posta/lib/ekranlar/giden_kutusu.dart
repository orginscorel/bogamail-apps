// Giden Kutusu (Outlook / web ile aynı): çevrimdışıyken gönderilen iletiler (yerel kuyruk) + sunucu kuyruğu (GET
// /mail/scheduled: geri alma süresindeki, planlı, gönderilemeyen). Tekrar dene = POST …/retry, Düzenle = …/restore,
// Sil = DELETE. Yerel iletiler: Her öğe durumunu gösterir (Bekliyor /
// Gönderiliyor… / Hata: neden + Tekrar dene); açılıp düzenlenebilir (yazma penceresine döner) ya da gitmeden
// silinebilir. Bağlantı gelince sırayla kendiliğinden gönderilir; sunucu Gönderilenler'e koyar.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../veri/baglanti.dart';
import '../veri/durum.dart';
import '../veri/hesap_servisi.dart';
import '../veri/kuyruk.dart';
import '../veri/posta_servisi.dart';
import '../veri/yazma_hazirla.dart';
import 'yazma.dart';

/// Öğeyi yazma penceresinde açar (düzenleme). Pencere açıkken öğe gönderilmez.
Future<void> gidenDuzenle(BuildContext context, GidenOge o) async {
  final c = await GidenKutusu.ben.icerik(o.id);
  if (c == null || !context.mounted) return;
  await yazmaAc(context, gidenHazirla(o.id, c.$1, c.$2));
}

/// Sunucudaki bekleyen / planlı iletiyi düzenlemeye açar (restore → taslak → yazma penceresi). Planlıysa
/// (2 dakikadan uzaksa) pencerede "Planla" aynı saatle gelir.
Future<void> planliDuzenle(BuildContext context, Planli p) async {
  try {
    final r = await Hesap.planGeriAl(p.id);
    final taslak = '${r['draft_id'] ?? ''}';
    if (taslak.isEmpty) throw ApiHata(500, 'Taslak oluşturulamadı.');
    final d = await Posta.ileti(taslak);
    final zaman = DateTime.tryParse('${r['send_at'] ?? ''}')?.toLocal();
    final plan = r['kind'] == 'scheduled' && zaman != null && zaman.isAfter(DateTime.now().add(const Duration(minutes: 2))) ? zaman : null;
    final c = r['compose'] is Map ? Map<String, dynamic>.from(r['compose'] as Map) : null;
    unawaited(GidenKutusu.ben.sunucuTazele());
    PostaDurum.ben.sayilariYenile();
    bildir('İleti düzenlemeye açıldı', mesaj: 'Kapatırsanız Taslaklar\'da kalır.');
    if (context.mounted) await yazmaAc(context, taslakHazirla(d, taslakId: taslak, geriAlinan: c, planZamani: plan));
  } on ApiHata catch (e) {
    unawaited(GidenKutusu.ben.sunucuTazele());
    bildir('İleti düzenlemeye açılamadı', mesaj: e.mesaj, tur: MesajTur.hata);
  }
}

class GidenKutusuEkrani extends StatefulWidget {
  const GidenKutusuEkrani({super.key});

  @override
  State<GidenKutusuEkrani> createState() => _GidenKutusuEkraniState();
}

class _GidenKutusuEkraniState extends State<GidenKutusuEkrani> {
  Timer? _yokla;

  @override
  void initState() {
    super.initState();
    // Sunucu kuyruğu (geri alma / planlı / gönderilemeyen) açıkken 15 sn'de bir tazelenir (web ile aynı).
    unawaited(GidenKutusu.ben.sunucuTazele());
    _yokla = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(GidenKutusu.ben.sunucuTazele()));
  }

  @override
  void dispose() {
    _yokla?.cancel();
    super.dispose();
  }

  Future<void> _islem(Future<void> Function() f, String tamam, String hata) async {
    try {
      await f();
      bildir(tamam, tur: MesajTur.basari);
    } on ApiHata catch (e) {
      bildir(
        hata,
        mesaj: e.durum == 409 && e.kod != 'already_sent' && e.kod != 'send_unknown' ? 'İleti bu arada gönderildi veya değişti; liste yenilendi.' : e.mesaj,
        tur: MesajTur.hata,
      );
    } catch (e) {
      bildir(hata, mesaj: hataMetni(e), tur: MesajTur.hata);
    }
    await GidenKutusu.ben.sunucuTazele();
    PostaDurum.ben.sayilariYenile();
  }

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
              onPressed: () {
                unawaited(GidenKutusu.ben.gonder());
                unawaited(GidenKutusu.ben.sunucuTazele());
              },
              icon: Icon(cd ? Simge.cevrimdisi : Simge.gonder, size: 18),
              label: Text(cd ? 'Yeniden dene' : 'Şimdi gönder'),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([GidenKutusu.ben.ogeler, GidenKutusu.ben.sunucu]),
        builder: (context, _) {
          final l = GidenKutusu.ben.ogeler.value;
          final sv = [...GidenKutusu.ben.sunucu.value]..sort((a, b) => (a.zaman ?? DateTime(0)).compareTo(b.zaman ?? DateTime(0)));
          if (l.isEmpty && sv.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Simge.gidenKutusu, size: 40, color: r.silik),
                    const SizedBox(height: 10),
                    const Text('Giden Kutusu boş', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      'Gönderilmeyi bekleyen, planlanan veya gönderilemeyen iletiler burada görünür. Bağlantı yokken gönderdikleriniz de burada bekler.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: r.soluk, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  'Bekleyen iletiler sırayla gönderilir ve Gönderilenler\'e taşınır. Gitmeden açıp düzenleyebilir ya da silebilirsiniz.',
                  style: TextStyle(fontSize: 13, color: r.soluk),
                ),
              ),
              for (final o in l) ...[Divider(height: 1, color: r.kenar), _GidenSatiri(o: o)],
              for (final p in sv) ...[Divider(height: 1, color: r.kenar), _SunucuSatiri(p: p, islem: _islem)],
              Divider(height: 1, color: r.kenar),
            ],
          );
        },
      ),
    );
  }
}

/// Durum rozeti: Bekliyor (amber) / Gönderiliyor… (birincil) / Hata (kırmızı).
Widget _durumRozeti(BuildContext context, Key key, String metin, Color renk, {bool donen = false}) => Container(
  key: key,
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
  decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (donen) ...[SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: renk)), const SizedBox(width: 5)],
      Flexible(
        child: Text(
          metin,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: renk),
        ),
      ),
    ],
  ),
);

/// Sunucu kuyruğundaki öğe (geri alma süresinde, planlı ya da gönderilemeyen).
class _SunucuSatiri extends StatelessWidget {
  const _SunucuSatiri({required this.p, required this.islem});
  final Planli p;
  final Future<void> Function(Future<void> Function(), String, String) islem;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final hata = p.durum == 'failed';
    final gidiyor = p.durum == 'sending';
    final (metin, renk) = hata ? ('Hata', Marka.gul) : (gidiyor ? ('Gönderiliyor…', r.birincil) : ('Bekliyor', Marka.kehribar));
    final ne = p.tur == 'undo'
        ? 'Geri alma süresi doluyor'
        : 'Planlandı: ${p.zaman == null ? '—' : DateFormat('d MMM HH:mm', 'tr_TR').format(p.zaman!.toLocal())}';
    Future<void> tekrar() async {
      if (p.kesildi &&
          !await onayla(
            context,
            'Yeniden gönderilsin mi?',
            mesaj: 'Bu ileti daha önce kısmen gönderilmiş olabilir. Yine de tekrar gönderilsin mi?',
            evet: 'Gönder',
          )) {
        return;
      }
      await islem(() => Hesap.planTekrar(p.id), 'İleti yeniden gönderime alındı', 'Yeniden denenemedi');
    }

    return Padding(
      key: ValueKey('giden-sunucu-${p.id}'),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(hata ? Simge.hata : (p.tur == 'undo' ? Simge.gonder : Simge.planliGonder), size: 20, color: renk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.kime.isEmpty ? '(alıcı yok)' : p.kime.join(', '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text(
                  p.konu.trim().isEmpty ? '(konu yok)' : p.konu,
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
                    _durumRozeti(context, ValueKey('giden-durum-${p.id}'), metin, renk, donen: gidiyor),
                    Text(ne, style: TextStyle(fontSize: 12, color: r.silik)),
                    if (hata)
                      TextButton(
                        key: ValueKey('giden-tekrar-${p.id}'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: tekrar,
                        child: const Text('Tekrar dene'),
                      ),
                  ],
                ),
                if (hata)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Gönderilemedi: ${p.hata.isEmpty ? 'nedeni bildirilmedi' : p.hata}', style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('giden-menu-${p.id}'),
            tooltip: 'Seçenekler',
            enabled: !gidiyor,
            onSelected: (v) async {
              if (v == 'duzenle') {
                await planliDuzenle(context, p);
              } else if (v == 'tekrar') {
                await tekrar();
              } else if (await onayla(
                context,
                'Gönderilmesin ve silinsin mi?',
                mesaj: p.konu.trim().isEmpty ? null : '"${p.konu}"',
                evet: 'Sil',
                tehlikeli: true,
              )) {
                await islem(() => Hesap.planIptal(p.id), 'Gönderim iptal edildi', 'Silinemedi');
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'duzenle',
                child: ListTile(leading: Icon(Simge.duzenle), title: Text('Düzenle')),
              ),
              if (hata)
                const PopupMenuItem(
                  value: 'tekrar',
                  child: ListTile(leading: Icon(Simge.yenile), title: Text('Tekrar dene')),
                ),
              const PopupMenuItem(
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
