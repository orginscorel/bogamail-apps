import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'bolumler.dart';
import 'ekip_gateway_ortak.dart';
import 'ekip_gateway_sihirbaz.dart';
import 'ekip_gateway_yonet.dart';
import '../ortak/simgeler.dart';

class _GwVeri {
  const _GwVeri(this.alanlar, this.disMod, this.uyarilar);
  final List<GwAlan> alanlar;
  final String disMod;
  final List<Map<String, dynamic>> uyarilar;
}

/// Mail Gateway: MX'i platformu gösteren alan adlarının postası taranıp müşterinin kendi sunucusuna iletilir.
/// Alan adı kartları (hedefler, kuyruk, son saat), durum uyarıları, yönetim ve yeni müşteri sihirbazı. 30 sn'de bir yenilenir.
class GatewayEkrani extends StatefulWidget {
  const GatewayEkrani({super.key});
  @override
  State<GatewayEkrani> createState() => _GatewayEkraniState();
}

class _GatewayEkraniState extends State<GatewayEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<_GwVeri>>();
  Timer? _zamanlayici;
  List<GwAlan> _alanlar = const [];

  bool get _yonetir => Uyg.yetki('domains.manage');

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 30), (_) => _yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  void _yenile() => _anahtar.currentState?.yenile();

  Future<_GwVeri> _getir() async {
    final s = await Future.wait([
      Uyg.api.get('/api/v1/gateway/domains'),
      Uyg.api.get('/api/v1/gateway/alerts', q: {'limit': '20'}).then<Object?>((v) => v, onError: (_) => null),
    ]);
    final d = harita(s[0]);
    final alanlar = haritalar(d['items']).map(GwAlan.coz).toList();
    _alanlar = alanlar;
    return _GwVeri(alanlar, metin(d['outbound_mode']), haritalar(harita(s[1])['items']));
  }

  void _yonet(GwAlan a) => gatewayYonetimiAc(context, a, _yenile);

  Widget _alanKarti(GwAlan d) {
    final r = context.r;
    final kuyruk = d.kuyruk;
    final ayar = d.ayar;
    final kesinti = d.kesinti;
    final kesintiSaat = tarihOku(ayar['outage_since']);
    Widget sayi(String e, String v) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e, style: TextStyle(color: r.silik, fontSize: 11.5)),
        Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    );
    return Kutu(
      onTap: _yonetir ? () => _yonet(d) : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.ad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: gosterim(16, agirlik: FontWeight.w600),
                ),
              ),
              if (_yonetir) Icon(Simgeler.chevronRight, color: r.silik),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              DurumRozeti(d.durum),
              Rozet(gwSaglikEtiketi[d.saglik] ?? d.saglik, renk: gwSaglikRengi(d.saglik)),
              if (d.kesintiAktif) const Rozet('Kesinti modu', renk: Marka.kehribar),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${d.orgAdi}${d.durum != 'active' ? ' · MX doğrulanana kadar posta kabul edilmez' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: r.soluk, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          if (d.hedefler.isEmpty)
            const Text('Teslim hedefi yok: gelen posta 451 ile geri çevrilir.', style: TextStyle(color: Marka.kehribar, fontSize: 12.5))
          else
            for (final t in d.hedefler)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    DurumNoktasi(gwHedefRengi(t, r.silik)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: '${t.sunucu}:${t.port} · ${gwTlsEtiketi[t.tls] ?? t.tls}',
                        child: Text(
                          '${t.oncelik} · ${t.sunucu}:${t.port}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(t.etkin ? (gwDurumEtiketi[t.durum] ?? t.durum) : 'Devre dışı', style: TextStyle(color: r.soluk, fontSize: 12)),
                  ],
                ),
              ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              sayi('Kuyrukta', mantik(kuyruk['available']) ? sayiYaz(tamsayi(kuyruk['count'])) : '—'),
              sayi('En eski', tamsayi(kuyruk['count']) > 0 ? gwYas(tamsayi(kuyruk['oldest_age_seconds'])) : '—'),
              sayi('Teslim (1 sa)', sayiYaz(d.teslimSaat)),
              sayi('Ertelenen (1 sa)', sayiYaz(d.ertelenenSaat)),
            ],
          ),
          if (kesintiSaat != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(SimgelerKalin.warningAmber, size: 16, color: Marka.gul),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tüm hedefler ${goreliZaman(kesintiSaat)} erişilemiyor; posta en fazla ${tamsayi(ayar['retention_hours'])} saat kuyrukta tutulur.',
                    style: const TextStyle(color: Marka.gul, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ],
          if (d.sonHata.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Son hata: ${d.sonHata}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ],
          if (tamsayi(kesinti['messages']) > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Kesinti kopyaları: ${tamsayi(kesinti['messages'])} ileti, ${boyutYaz(tamsayi(kesinti['bytes']))} (${tamsayi(kesinti['users'])} adres)',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          ],
          if (_yonetir) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(onPressed: () => _yonet(d), icon: const Icon(Simgeler.settings, size: 18), label: const Text('Yönet')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _uyarilar(List<Map<String, dynamic>> l) {
    final r = context.r;
    return BolumKarti(
      baslik: 'Son durum değişiklikleri',
      ikon: Simgeler.history,
      altBaslik: 'Hedef kapandı/düzeldi, tüm hedefler kapalı, kesinti modu uyarıları (30 sn\'de bir yenilenir).',
      child: l.isEmpty
          ? Text('Henüz uyarı yok.', style: TextStyle(color: r.soluk))
          : Column(
              children: [
                for (var i = 0; i < l.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Builder(
                      builder: (c) {
                        final a = l[i];
                        final onem = metin(a['severity']);
                        final tur = metin(a['kind']);
                        final hedef = metin(a['target']);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Rozet(gwUyariEtiketi[tur] ?? tur, renk: onem == 'critical' ? Marka.gul : (onem == 'warning' ? Marka.kehribar : Marka.mavi)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    [metin(a['domain']), if (hedef.isNotEmpty) hedef].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                Tooltip(
                                  message: tamZaman(tarihOku(a['at'])),
                                  child: Text(goreliZaman(tarihOku(a['at'])), style: TextStyle(color: r.silik, fontSize: 12)),
                                ),
                              ],
                            ),
                            if (metin(a['message']).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  metin(a['message']),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: r.soluk, fontSize: 12),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Mail Gateway',
      alt: 'Taranan posta müşterinin kendi sunucusuna iletilir',
      yenile: _yenile,
      eylemler: [
        if (_yonetir) IconButton(tooltip: 'Gateway alan adı ekle', onPressed: () => bolumeGit(Bolum.alanlar), icon: const Icon(Simgeler.addLink)),
      ],
      birincil: _yonetir ? BirincilEylem(Simgeler.autoFixHigh, 'Yeni gateway müşterisi', () => gatewaySihirbaziAc(context, _alanlar, _yenile)) : null,
      govde: TekYukleme<_GwVeri>(
        key: _anahtar,
        getir: _getir,
        icerik: (c, v, yenile) => IcerikListesi(
          children: [
            Text(
              'MX\'i bu platformu gösteren alan adlarının postası taranıp müşterinin kendi sunucusuna (Microsoft 365, Google Workspace, cPanel…) iletilir. '
              'Hedef çalışmazsa posta kuyrukta güvenle bekler.',
              style: TextStyle(color: c.r.soluk, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (v.disMod.isNotEmpty && v.disMod != 'direct') ...[
              Bant(
                'Sunucuda dış teslim modu ${v.disMod}: gateway alan adlarına gelen iletiler şu an 451 geçici hata ile geri çevrilir '
                '(gönderen sunucu tekrar dener, posta kaybolmaz) ve bağlantı testleri yapılamaz.',
                renk: Marka.kehribar,
                ikon: Simgeler.warningAmber,
              ),
              const SizedBox(height: 12),
            ],
            if (v.alanlar.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Kapali(
                  'Gateway alan adı yok.\n"Yeni gateway müşterisi" ile kurulumu başlatın veya Alan Adları\'ndan "MX Gateway" modunda alan adı ekleyin.',
                  ikon: Simgeler.altRoute,
                ),
              )
            else
              Izgara(enAz: 420, children: [for (final d in v.alanlar) _alanKarti(d)]),
            const SizedBox(height: 16),
            _uyarilar(v.uyarilar),
            const SizedBox(height: 12),
            Text(
              'Hedefe SMTP AUTH (PLAIN/LOGIN, yalnızca TLS sonrası) teslim hedefleri ekranından ayarlanır. Henüz yok: alıcı doğrulama (callout/LDAP), '
              'müşteri başına karantina/etiketleme politikaları.',
              style: TextStyle(color: c.r.silik, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
