import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart' show Izgara;
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import '../veri/tercihler.dart';
import 'hesap_avatar.dart';
import 'hesap_mfa.dart';
import 'liste_ortak.dart' show Sigdir;
import 'kabuk.dart' show cikisOnayi;

/// Ayarlar ve profil: kullanıcı bilgisi, tema, bildirimler (APNs), açık oturumlar, sunucu ve sürüm, çıkış.
class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key});
  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  Map<String, dynamic>? _push;
  bool _buCihazKayitli = false;
  bool? _mfa;
  List<PanelOturumu>? _oturumlar;
  String? _oturumHatasi;
  bool _pushMesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    await Future.wait([_pushYukle(), _mfaYukle(), _oturumYukle()]);
  }

  Future<void> _pushYukle() async {
    try {
      final v = harita(await Uyg.api.get(Uyg.pushYolu));
      var kayitli = false;
      try {
        kayitli = (await SharedPreferences.getInstance()).getString('${Uyg.api.uygulama}.push') != null;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _push = v;
          _buCihazKayitli = kayitli;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _push = const {'available': false, '_hata': true});
    }
  }

  Future<void> _mfaYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/auth/mfa'));
      if (mounted) setState(() => _mfa = mantik(v['enabled']));
    } catch (_) {}
  }

  Future<void> _oturumYukle() async {
    try {
      final v = await Uyg.api.get('/api/v1/auth/sessions');
      final l = haritalar(harita(v)['items']).map(PanelOturumu.coz).toList()..sort((a, b) => (b.gecerli ? 1 : 0).compareTo(a.gecerli ? 1 : 0));
      if (mounted) {
        setState(() {
          _oturumlar = l;
          _oturumHatasi = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _oturumHatasi = hataMetni(e));
    }
  }

  Future<void> _pushAc() async {
    setState(() => _pushMesgul = true);
    final ok = await Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
    if (!mounted) return;
    setState(() => _pushMesgul = false);
    if (ok) {
      bildir('Bildirimler açıldı', mesaj: 'Bu cihaz alarm bildirimlerini alacak.', tur: MesajTur.basari);
    } else {
      bildir(
        'Bildirimler açılamadı',
        mesaj: 'Sistem ayarlarından BogaMail Yönetim için bildirim iznini verin ve tekrar deneyin.',
        tur: MesajTur.uyari,
      );
    }
    _pushYukle();
  }

  Future<void> _pushKapat() async {
    if (!await onayla(context, 'Bu cihazda bildirimler kapatılsın mı?', mesaj: 'Bu cihaz artık alarm bildirimi almaz.', evet: 'Kapat')) return;
    setState(() => _pushMesgul = true);
    await Push.sil(Uyg.api, yol: Uyg.pushYolu);
    if (!mounted) return;
    setState(() => _pushMesgul = false);
    bildir('Bu cihazda bildirimler kapatıldı');
    _pushYukle();
  }

  Future<void> _pushTest() async {
    final v = await islem(() => Uyg.api.post('${Uyg.pushYolu}/test'));
    if (v == null) return;
    final n = tamsayi(harita(v)['sent']);
    bildir(
      n > 0 ? 'Test bildirimi gönderildi' : 'Gönderilecek cihaz yok',
      mesaj: n > 0 ? '$n cihaza gönderildi.' : 'Önce bu cihazda bildirimleri açın.',
      tur: n > 0 ? MesajTur.basari : MesajTur.uyari,
    );
  }

  Future<void> _oturumKapat(PanelOturumu o) async {
    if (!await onayla(
      context,
      'Oturum kapatılsın mı?',
      mesaj: '${cihazAdi(o.tarayici)} cihazındaki oturum sonlandırılır.',
      evet: 'Oturumu kapat',
      tehlikeli: true,
    )) {
      return;
    }
    final v = await islem(() => Uyg.api.delete('/api/v1/auth/sessions/${o.id}').then((_) => true), tamam: 'Oturum kapatıldı');
    if (v != null) _oturumYukle();
  }

  Future<void> _digerleriniKapat() async {
    if (!await onayla(
      context,
      'Diğer tüm oturumlar kapatılsın mı?',
      mesaj: 'Bu cihaz dışındaki tüm cihazlarda yönetim paneli oturumu sonlandırılır.',
      evet: 'Hepsini kapat',
      tehlikeli: true,
    )) {
      return;
    }
    final v = await islem(() => Uyg.api.delete('/api/v1/auth/sessions'));
    if (v == null) return;
    bildir('${tamsayi(harita(v)['revoked'])} oturum kapatıldı', tur: MesajTur.basari);
    _oturumYukle();
  }

  /// Ayar bölümleri: (anahtar, başlık, simge, içerik). Dar ekranda alt alta, geniş ekranda solda kategori listesi.
  List<(String, String, IconData, List<Widget>)> _bolumler(BuildContext context) {
    final r = context.r;
    final taklit = (Uyg.ben.value ?? const {})['impersonation'];
    final profil = Kutu(
      child: Row(
        children: [
          const ProfilResmi(boyut: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad, style: gosterim(18, agirlik: FontWeight.w700)),
                if (Uyg.ad.isNotEmpty) Text(Uyg.adres, style: TextStyle(color: r.soluk)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Rozet(rolEtiketi(Uyg.rol), ikon: Icons.badge_outlined),
                    if (_mfa != null)
                      Rozet(
                        _mfa! ? 'İki adımlı doğrulama açık' : 'İki adımlı doğrulama kapalı',
                        renk: _mfa! ? Marka.zumrut : Marka.kehribar,
                        ikon: _mfa! ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                      ),
                    if (taklit is Map) Rozet('Müşteri görünümü', renk: Marka.kehribar, ikon: Icons.visibility_rounded),
                  ].map(Sigdir.new).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final mfa = _mfa != null && taklit is! Map
        ? Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _mfa!
                      ? 'Girişte şifrenize ek olarak doğrulayıcı uygulamadaki kod istenir.'
                      : 'Hesabınızı korumak için doğrulayıcı uygulamayla iki adımlı doğrulamayı açın.',
                  style: TextStyle(color: r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!_mfa!)
                      FilledButton.icon(
                        onPressed: () async {
                          if (await mfaAc(context)) _mfaYukle();
                        },
                        icon: const Icon(Icons.verified_user_rounded, size: 18),
                        label: const Text('İki adımlı doğrulamayı aç'),
                      )
                    else ...[
                      OutlinedButton.icon(
                        onPressed: () => mfaKodlariYenile(context),
                        icon: const Icon(Icons.key_rounded, size: 18),
                        label: const Text('Yeni kurtarma kodları'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Marka.gul),
                        onPressed: () async {
                          if (await mfaKapat(context)) _mfaYukle();
                        },
                        icon: const Icon(Icons.gpp_bad_outlined, size: 18),
                        label: const Text('Kapat'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          )
        : null;
    final gorunum = Kutu(
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: temaKipi,
        builder: (c, m, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tema',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded), label: Text('Sistem')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded), label: Text('Açık')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded), label: Text('Koyu')),
              ],
              selected: {m},
              onSelectionChanged: (s) => temaKaydet(s.first),
            ),
          ],
        ),
      ),
    );
    final uygulama = Kutu(
      child: Column(
        children: [
          BilgiSatiri('Sunucu', Uyg.api.sunucu.replaceFirst(RegExp(r'^https?://'), ''), kopyalanabilir: true),
          BilgiSatiri('Sürüm', Uyg.api.surum.isEmpty ? '—' : Uyg.api.surum),
        ],
      ),
    );
    final oturumBasligi = Baslik(
      'Açık oturumlar',
      sag: (_oturumlar?.where((o) => !o.gecerli).isNotEmpty ?? false)
          ? TextButton(onPressed: _digerleriniKapat, child: const Text('Diğerlerini kapat'))
          : null,
    );
    return [
      (
        'hesap',
        'Hesap ve güvenlik',
        Icons.person_rounded,
        [
          profil,
          if (mfa != null) ...[const Baslik('İki adımlı doğrulama'), mfa],
        ],
      ),
      ('gorunum', 'Görünüm', Icons.palette_outlined, [const Baslik('Görünüm'), gorunum]),
      ('bildirim', 'Bildirimler', Icons.notifications_none_rounded, [const Baslik('Bildirimler'), _bildirimKarti()]),
      ('oturum', 'Açık oturumlar', Icons.devices_rounded, [oturumBasligi, _oturumKarti()]),
      (
        'uygulama',
        'Uygulama ve güncelleme',
        Icons.system_update_alt_rounded,
        [
          const Baslik('Uygulama sürümü ve güncelleme'),
          GuncellemeKarti(api: Uyg.api),
          BilgiSatiriListesi(baslik: 'Panel', satirlar: [('Panel', Uyg.panelAdi), if (Uyg.panelAlt.isNotEmpty) ('Kapsam', Uyg.panelAlt)]),
          const Baslik('Uygulama'),
          uygulama,
          const SizedBox(height: 12),
          const SurumEtiketi(ortala: true),
        ],
      ),
    ];
  }

  Widget _cikisDugmesi(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: Marka.gul,
      side: BorderSide(color: Marka.gul.withValues(alpha: .5)),
      minimumSize: const Size.fromHeight(48),
    ),
    onPressed: () => cikisOnayi(context),
    icon: const Icon(Icons.logout_rounded),
    label: const Text('Çıkış yap'),
  );

  String _secili = 'hesap';

  @override
  Widget build(BuildContext context) {
    final bolumler = _bolumler(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar ve Profil')),
      body: LayoutBuilder(
        builder: (context, k) {
          if (k.maxWidth < 900) {
            return RefreshIndicator.adaptive(
              onRefresh: _yukle,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                    children: [for (final b in bolumler) ...b.$4, const SizedBox(height: 16), _cikisDugmesi(context)],
                  ),
                ),
              ),
            );
          }
          final secili = bolumler.firstWhere((b) => b.$1 == _secili, orElse: () => bolumler.first);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kategoriListesi(context, bolumler, secili.$1),
              VerticalDivider(width: 1, color: context.r.kenar),
              Expanded(
                child: RefreshIndicator.adaptive(
                  onRefresh: _yukle,
                  child: ListView(
                    key: PageStorageKey('ayarlar-${secili.$1}'),
                    padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(secili.$2, style: gosterim(24, agirlik: FontWeight.w700)),
                              const SizedBox(height: 4),
                              ..._icerik(secili),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Geniş ekranda bölüm içeriği: başlık + kart çiftleri iki sütunlu ızgaraya yerleşir (kart en az 380 px).
  List<Widget> _icerik((String, String, IconData, List<Widget>) b) {
    if (b.$1 == 'hesap' || b.$1 == 'uygulama') {
      // Başlıklı kartları gruplar: [Baslik, kart] çiftleri yan yana; başlıksız kartlar da birer hücre.
      final hucreler = <Widget>[];
      final l = b.$4.where((w) => w is! SizedBox && w is! SurumEtiketi).toList();
      for (var i = 0; i < l.length; i++) {
        if (l[i] is Baslik && i + 1 < l.length) {
          hucreler.add(Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [l[i], l[i + 1]]));
          i++;
        } else {
          hucreler.add(
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [const SizedBox(height: 18), l[i]]),
          );
        }
      }
      return [
        Izgara(enAz: 380, bosluk: 20, children: hucreler),
        if (b.$1 == 'uygulama') ...[const SizedBox(height: 16), const SurumEtiketi()],
      ];
    }
    return b.$4;
  }

  Widget _kategoriListesi(BuildContext context, List<(String, String, IconData, List<Widget>)> bolumler, String secili) {
    final r = context.r;
    return SizedBox(
      width: 280,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Row(
              children: [
                const ProfilResmi(boyut: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(rolEtiketi(Uyg.rol), style: TextStyle(color: r.soluk, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final b in bolumler)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                selected: b.$1 == secili,
                selectedTileColor: r.birincilYumusak,
                selectedColor: r.birincil,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(b.$3, size: 21),
                title: Text(b.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                dense: true,
                onTap: () => setState(() => _secili = b.$1),
              ),
            ),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _cikisDugmesi(context)),
        ],
      ),
    );
  }

  Widget _bildirimKarti() {
    final r = context.r;
    final p = _push;
    if (!Push.destekli) {
      return Kutu(
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: r.silik),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bu platformda anlık bildirim desteklenmiyor. Alarmları iPhone, iPad veya Mac uygulamasından ya da e-posta kanalından alabilirsiniz.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    if (p == null) return const Kutu(child: Center(child: CircularProgressIndicator.adaptive()));
    final acik = mantik(p['available']);
    if (!acik) {
      return Kutu(
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined, color: r.silik),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                p['_hata'] == true ? 'Bildirim durumu alınamadı.' : 'Uygulama bildirimleri bu sunucuda kapalı (APNs yapılandırılmamış).',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final cihaz = tamsayi(p['devices']);
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _buCihazKayitli ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                color: _buCihazKayitli ? Marka.zumrut : r.silik,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _buCihazKayitli ? 'Bu cihaz alarm bildirimlerini alıyor' : 'Bu cihazda bildirimler kapalı',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text('Hesabınıza kayıtlı $cihaz cihaz', style: TextStyle(color: r.silik, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_buCihazKayitli)
                OutlinedButton.icon(
                  onPressed: _pushMesgul ? null : _pushKapat,
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: const Text('Bu cihazda kapat'),
                )
              else
                FilledButton.icon(
                  onPressed: _pushMesgul ? null : _pushAc,
                  icon: _pushMesgul
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.notifications_active_rounded, size: 18),
                  label: const Text('Bildirimleri aç'),
                ),
              OutlinedButton.icon(
                onPressed: cihaz > 0 ? _pushTest : null,
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Test bildirimi gönder'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hangi alarmların bildirim göndereceği Uyarılar › Kurallar sekmesinden (Panel kanalı) ayarlanır.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _oturumKarti() {
    final r = context.r;
    final l = _oturumlar;
    if (l == null) {
      return Kutu(
        child: _oturumHatasi != null
            ? Text(_oturumHatasi!, style: TextStyle(color: r.silik))
            : const Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (l.isEmpty) {
      return Kutu(
        child: Text('Açık oturum yok.', style: TextStyle(color: r.silik)),
      );
    }
    return Kutu(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (final (i, o) in l.indexed) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(_cihazIkonu(o.tarayici), color: o.gecerli ? Marka.zumrut : r.soluk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                cihazAdi(o.tarayici),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (o.gecerli) ...[const SizedBox(width: 6), const Rozet('bu cihaz', renk: Marka.zumrut)],
                          ],
                        ),
                        Text(
                          [
                            if (o.ip != null) o.ip!,
                            'son etkinlik ${goreliZaman(o.sonGorulme ?? o.olusturma)}',
                            if (o.musteriGorunumu != null) 'müşteri görünümü: ${o.musteriGorunumu}',
                          ].join(' · '),
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (!o.gecerli)
                    IconButton(tooltip: 'Oturumu kapat', onPressed: () => _oturumKapat(o), icon: const Icon(Icons.logout_rounded, size: 20)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

IconData _cihazIkonu(String ua) {
  final u = ua.toLowerCase();
  if (u.contains('iphone') || u.contains('android') || u.contains('mobile')) return Icons.smartphone_rounded;
  if (u.contains('ipad') || u.contains('tablet')) return Icons.tablet_mac_rounded;
  return Icons.computer_rounded;
}

/// Başlıklı küçük bilgi kartı.
class BilgiSatiriListesi extends StatelessWidget {
  const BilgiSatiriListesi({super.key, required this.baslik, required this.satirlar});
  final String baslik;
  final List<(String, String)> satirlar;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Baslik(baslik),
      Kutu(child: Column(children: [for (final (a, d) in satirlar) BilgiSatiri(a, d)])),
    ],
  );
}
