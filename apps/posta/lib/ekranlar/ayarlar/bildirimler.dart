// Ayarlar → Bildirimler (web NotificationsSection): bu cihazın bildirimleri (APNs / Android / Windows), sunucudaki
// bildirim tercihleri (notify_desktop, notify_sound, sync_seconds), anlık bağlantı durumu ve sohbet gizliliği.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../oturum.dart';
import '../../veri/ayar_servisi.dart';
import '../../veri/bildirim.dart';
import '../../veri/bildirim_sesi.dart';
import '../../veri/canli.dart';
import '../../veri/posta_servisi.dart';
import '../../veri/sohbet_servisi.dart';
import 'ayar_ortak.dart';

const esitlemeSecenekleri = {15: '15 sn', 30: '30 sn', 60: '1 dk', 120: '2 dk', 300: '5 dk', 900: '15 dk', 1800: '30 dk', 3600: '60 dk'};

class BildirimlerAyari extends StatelessWidget {
  const BildirimlerAyari({super.key});

  @override
  Widget build(BuildContext context) => SunucuAyarGovdesi(
    olustur: (context, a, kaydet) => [
      const _CihazBildirimleri(),
      if (SesCalar.destekli || BildirimSesiKarti.zorla) const BildirimSesiKarti(),
      _TercihFormu(key: ValueKey('bil-${a.bildirimMasaustu}|${a.bildirimSes}|${a.esitlemeSaniye}'), a: a, kaydet: kaydet),
      IkiSutun(children: [const _CanliKarti(), if (a.ozellik('chat')) const SohbetGizliligiKarti()]),
    ],
  );
}

/// Bu cihazın bildirim düzeni: iPhone/iPad/Mac'te sunucu anlık bildirimi, Android'de izin + arka plan denetimi,
/// Windows'ta pencere arka plandayken bildirim.
class _CihazBildirimleri extends StatefulWidget {
  const _CihazBildirimleri();
  @override
  State<_CihazBildirimleri> createState() => _CihazBildirimleriState();
}

class _CihazBildirimleriState extends State<_CihazBildirimleri> {
  Map<String, dynamic>? _push;
  bool _izin = true;
  bool _arkaPlan = true;

  @override
  void initState() {
    super.initState();
    _durum();
  }

  Future<void> _durum() async {
    if (Push.destekli) {
      try {
        final p = await Posta.pushBilgi();
        if (mounted) setState(() => _push = p);
      } catch (_) {}
    }
    if (Bildirim.android) {
      final i = await Bildirim.izinVar();
      final a = await Bildirim.arkaPlanAcik();
      if (mounted) {
        setState(() {
          _izin = i;
          _arkaPlan = a;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    Widget icerik;
    if (Push.destekli) {
      final p = _push;
      final acik = p?['available'] == true;
      final cihaz = (p?['devices'] as num?)?.toInt() ?? 0;
      icerik = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            p == null
                ? 'Bildirim durumu alınıyor…'
                : !acik
                ? '${p['reason'] ?? 'Uygulama bildirimleri bu sunucuda kapalı.'}'
                : cihaz > 0
                ? 'Bildirimler açık · $cihaz cihaz kayıtlı'
                : 'Bu cihaz henüz kayıtlı değil.',
            style: TextStyle(color: r.soluk),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: !acik
                    ? null
                    : () async {
                        final ok = await Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
                        bildir(
                          ok ? 'Bildirimler etkinleştirildi' : 'Bildirim izni verilmedi',
                          mesaj: ok ? null : 'Sistem Ayarları > Bildirimler bölümünden BogaMail\'e izin verin.',
                          tur: ok ? MesajTur.basari : MesajTur.uyari,
                        );
                        await _durum();
                      },
                icon: const Icon(Simge.hatirlatma),
                label: const Text('Bildirimleri etkinleştir'),
              ),
              OutlinedButton.icon(
                onPressed: !acik || cihaz == 0 ? null : () => islem(Posta.pushTest, tamam: 'Test bildirimi gönderildi'),
                icon: const Icon(Simge.gonder),
                label: const Text('Test bildirimi gönder'),
              ),
            ],
          ),
        ],
      );
    } else if (Bildirim.android) {
      icerik = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_izin)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Simge.bildirimKapali, color: Marka.kehribar),
              title: const Text('Bildirim izni kapalı'),
              subtitle: const Text('Yeni e-postalardan haberdar olmak için izin verin.'),
              trailing: TextButton(
                onPressed: () async {
                  await Bildirim.izinIste();
                  await _durum();
                },
                child: const Text('İzin ver'),
              ),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _arkaPlan,
            onChanged: (v) async {
              await Bildirim.arkaPlanAyarla(v);
              setState(() => _arkaPlan = v);
            },
            title: const Text('Arka planda yeni posta denetimi'),
            subtitle: const Text(
              'Uygulama kapalıyken Gelen Kutusu yaklaşık 15 dakikada bir denetlenir (Android en kısa bu aralığa izin verir; pil tasarrufu modunda gecikebilir).',
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: 'Bildirimler bu cihazda çalışıyor.'),
              icon: const Icon(Simge.bildirimDolu),
              label: const Text('Test bildirimi göster'),
            ),
          ),
        ],
      );
    } else if (Bildirim.windows) {
      icerik = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BogaMail açıkken pencere arka plandaysa yeni e-postalar için Windows bildirimi gösterilir.', style: TextStyle(color: r.soluk)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: 'Bildirimler bu bilgisayarda çalışıyor.'),
              icon: const Icon(Simge.bildirimDolu),
              label: const Text('Test bildirimi göster'),
            ),
          ),
        ],
      );
    } else {
      icerik = Text('Bu platformda bildirim desteklenmiyor.', style: TextStyle(color: r.soluk));
    }
    return AyarKarti(ikon: Simge.telefon, baslik: 'Bu cihaz', aciklama: 'Yeni posta geldiğinde bu cihazda nasıl haberdar olacağınız.', child: icerik);
  }
}

/// Bildirim sesi önizlemesi: bildirimlerde çalınan BogaMail seslerini dinletir (platforma göre aynı yol: iOS/macOS
/// sistem sesi, Android MediaPlayer, Windows PlaySound).
class BildirimSesiKarti extends StatelessWidget {
  const BildirimSesiKarti({super.key});

  /// Testlerde platform desteği olmadan da göster.
  @visibleForTesting
  static bool zorla = false;

  @override
  Widget build(BuildContext context) {
    Widget satir(BildirimSesi s, IconData ikon, String baslik, String alt) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ikon),
      title: Text(baslik),
      subtitle: Text(alt),
      trailing: OutlinedButton.icon(
        key: ValueKey('ses-dinle-${s.name}'),
        onPressed: () async {
          if (!await SesCalar.cal(s)) bildir('Ses çalınamadı', mesaj: 'Cihazın sesi kapalı ya da sessiz modda olabilir.', tur: MesajTur.uyari);
        },
        icon: const Icon(Simge.oynat, size: 18),
        label: const Text('Sesi dinle'),
      ),
    );
    return AyarKarti(
      ikon: Simge.ses,
      baslik: 'Bildirim sesi',
      aciklama: 'Yeni posta ve sohbet iletileri kendine özgü BogaMail sesiyle gelir. Sesli uyarı kapalıysa bu cihazın bildirimleri sessizdir.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          satir(BildirimSesi.posta, Simge.posta, 'Posta', 'Yeni e-posta geldiğinde'),
          satir(BildirimSesi.sohbet, Simge.sohbet, 'Sohbet', 'Yeni sohbet iletisi geldiğinde'),
        ],
      ),
    );
  }
}

class _TercihFormu extends StatefulWidget {
  const _TercihFormu({super.key, required this.a, required this.kaydet});
  final SunucuAyarlari a;
  final AyarKaydedici kaydet;
  @override
  State<_TercihFormu> createState() => _TercihFormuState();
}

class _TercihFormuState extends State<_TercihFormu> {
  late bool _masaustu = widget.a.bildirimMasaustu;
  late bool _ses = widget.a.bildirimSes;
  late int _esitleme = widget.a.esitlemeSaniye;
  bool _mesgul = false;

  bool get _kirli => _masaustu != widget.a.bildirimMasaustu || _ses != widget.a.bildirimSes || _esitleme != widget.a.esitlemeSaniye;

  Future<void> _gonder() async {
    setState(() => _mesgul = true);
    final ok = await widget.kaydet({'notify_desktop': _masaustu, 'notify_sound': _ses, 'sync_seconds': _esitleme}, tamam: 'Bildirim tercihleri kaydedildi');
    if (ok) await Bildirim.tercihleriUygula(masaustu: _masaustu, ses: _ses);
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    final secenekler = {...esitlemeSecenekleri};
    if (!secenekler.containsKey(_esitleme)) secenekler[_esitleme] = '$_esitleme sn';
    final sirali = Map.fromEntries(secenekler.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    return AyarKarti(
      ikon: Simge.bildirim,
      baslik: 'Bildirim tercihleri',
      aciklama: 'Hesabınıza kayıtlı; webmail ve bu uygulama birlikte kullanır.',
      alt: KaydetDugmesi(key: const ValueKey('bildirim-kaydet'), etkin: _kirli, mesgul: _mesgul, basildi: _gonder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('bildirim-masaustu'),
            contentPadding: EdgeInsets.zero,
            value: _masaustu,
            onChanged: (v) => setState(() => _masaustu = v),
            title: const Text('Masaüstü bildirimleri'),
            subtitle: const Text('Webmail sekmesi ve Windows uygulaması arka plandayken ekranın köşesinde kısa bir bildirim gösterilir.'),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey('bildirim-ses'),
            contentPadding: EdgeInsets.zero,
            value: _ses,
            onChanged: (v) => setState(() => _ses = v),
            title: const Text('Sesli uyarı'),
            subtitle: const Text('Yeni posta geldiğinde kısa bir uyarı sesi çalınır. Kapalıyken bu cihazın bildirimleri de sessiz gelir.'),
          ),
          const SizedBox(height: 8),
          AyarAlani(
            etiket: 'Senkron süresi',
            ipucu: 'Anlık bağlantı açıkken yeni postalar zaten saniyesinde düşer; bu süre webmail\'de bağlantı koparsa tam eşitleme aralığıdır.',
            child: DropdownButton<int>(
              key: const ValueKey('bildirim-esitleme'),
              value: _esitleme,
              items: [for (final e in sirali.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _esitleme = v ?? _esitleme),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sunucuyla canlı bağlantının durumu (web LiveStatusCard).
class _CanliKarti extends StatelessWidget {
  const _CanliKarti();
  @override
  Widget build(BuildContext context) {
    final c = Canli.ben;
    return AyarKarti(
      ikon: Simge.wifi,
      baslik: 'Anlık bağlantı',
      aciklama: 'Sunucuyla canlı bağlantının durumu.',
      child: ValueListenableBuilder<CanliDurumu>(
        valueListenable: c.durum,
        builder: (context, d, _) {
          final (metin, renk) = switch (d.tur) {
            CanliTur.bagli => ('Bağlı — yeni postalar anında geliyor', Marka.zumrut),
            CanliTur.baglaniyor => ('Bağlanıyor…', Marka.kehribar),
            CanliTur.yok => ('Bağlantı yok — yeniden denenecek', Marka.gul),
            CanliTur.kapali => ('Kapalı', context.r.silik),
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: renk, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(metin)),
                ],
              ),
              ValueListenableBuilder<DateTime?>(
                valueListenable: c.sonOlay,
                builder: (_, t, _) => t == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Son eşitleme: ${tamZaman(t)}', style: TextStyle(color: context.r.silik, fontSize: 12.5)),
                      ),
              ),
              if (d.tur == CanliTur.yok || d.tur == CanliTur.kapali)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton.icon(onPressed: c.simdiBaglan, icon: const Icon(Simge.esitle, size: 18), label: const Text('Şimdi bağlan')),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Sohbet gizliliği: çevrimiçi durumu ve son görülme (PUT /mail/chat/me show_presence).
class SohbetGizliligiKarti extends StatefulWidget {
  const SohbetGizliligiKarti({super.key});
  @override
  State<SohbetGizliligiKarti> createState() => _SohbetGizliligiKartiState();
}

class _SohbetGizliligiKartiState extends State<SohbetGizliligiKarti> {
  bool? _goster;
  bool _yok = false;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    Sohbet.ben().then(
      (p) {
        if (mounted) setState(() => _goster = p.cevrimiciGoster);
      },
      onError: (Object e) {
        if (mounted) setState(() => _yok = e is ApiHata && e.durum == 403);
      },
    );
  }

  Future<void> _degistir(bool v) async {
    setState(() => _mesgul = true);
    try {
      final p = await Sohbet.benKaydet(cevrimiciGoster: v);
      if (mounted) setState(() => _goster = p.cevrimiciGoster);
      bildir(v ? 'Çevrimiçi durumunuz artık görünür' : 'Çevrimiçi durumunuz gizlendi', tur: MesajTur.basari);
    } catch (e) {
      bildir('Kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_yok) return const SizedBox.shrink();
    return AyarKarti(
      ikon: Simge.goster,
      baslik: 'Sohbet gizliliği',
      aciklama: 'Kurum içi sohbette iş arkadaşlarınızın sizi nasıl göreceği.',
      child: SwitchListTile.adaptive(
        key: const ValueKey('sohbet-gizlilik'),
        contentPadding: EdgeInsets.zero,
        value: _goster ?? true,
        onChanged: _goster == null || _mesgul ? null : _degistir,
        title: const Text('Çevrimiçi durumumu ve son görülme bilgimi göster'),
        subtitle: const Text(
          'Kapatırsanız kimse çevrimiçi olduğunuzu ve son görülme zamanınızı göremez; siz de başkalarınınkini göremezsiniz. Durum metniniz yine görünür.',
        ),
      ),
    );
  }
}
