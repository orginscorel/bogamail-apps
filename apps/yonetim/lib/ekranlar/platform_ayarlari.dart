import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../oturum.dart';
import '../veri/json.dart';
import 'bolumler.dart';

/// Platform ayarları (web: /admin/settings): spam eşikleri, Exchange ActiveSync, platform boyut limitleri ve salt okunur
/// sistem yapılandırması. GET /settings, /activesync/settings, /settings/limits. Yalnızca süper yönetici; müşteri/bayi
/// görünümünde (sunucu /settings yazmalarını engeller) form salt okunurdur.
class PlatformAyarlariEkrani extends StatefulWidget {
  const PlatformAyarlariEkrani({super.key});

  @override
  State<PlatformAyarlariEkrani> createState() => _PlatformAyarlariEkraniState();
}

/// Sayfanın tüm verisi: /settings zorunlu, diğerleri ayrı ayrı hata verebilir.
class PlatformAyarVerisi {
  const PlatformAyarVerisi({required this.ayarlar, this.eas, this.easHata, this.limitler, this.limitHata});
  final Map<String, dynamic> ayarlar;
  final Map<String, dynamic>? eas, limitler;
  final String? easHata, limitHata;
}

class _PlatformAyarlariEkraniState extends State<PlatformAyarlariEkrani> {
  final _anahtar = GlobalKey<TekYuklemeState<PlatformAyarVerisi>>();

  static Future<(Map<String, dynamic>?, String?)> _dene(String yol) async {
    try {
      return (harita(await Uyg.api.get(yol)), null);
    } catch (e) {
      return (null, hataMetni(e));
    }
  }

  Future<PlatformAyarVerisi> _getir() async {
    final eas = _dene('/api/v1/activesync/settings');
    final lim = _dene('/api/v1/settings/limits');
    final ayarlar = harita(await Uyg.api.get('/api/v1/settings'));
    final (e, eh) = await eas;
    final (l, lh) = await lim;
    return PlatformAyarVerisi(ayarlar: ayarlar, eas: e, easHata: eh, limitler: l, limitHata: lh);
  }

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Platform Ayarları', govde: Kapali('Bu bölüm yalnızca platform yöneticilerine açıktır.'));
    }
    final yazabilir = Uyg.taklit == null;
    return Iskelet(
      baslik: 'Platform Ayarları',
      alt: 'Platform politikaları · değişiklikler denetim kaydına yazılır',
      yenile: () => _anahtar.currentState?.yenile(),
      govde: TekYukleme<PlatformAyarVerisi>(
        key: _anahtar,
        getir: _getir,
        icerik: (c, v, yenile) {
          final spam = harita(v.ayarlar['spam']);
          final sol = <Widget>[
            if (!yazabilir) const Bant('Müşteri görünümündeyken platform ayarları değiştirilemez.', renk: Marka.kehribar, ikon: Icons.visibility_rounded),
            SpamAyarKarti(key: ValueKey(jsonEncode(spam)), spam: spam, yazabilir: yazabilir, kaydedildi: yenile),
            if (v.eas != null)
              ActiveSyncKarti(key: ValueKey(jsonEncode(v.eas)), veri: v.eas!, kaydedildi: yenile)
            else
              BolumKarti(
                ikon: Icons.smartphone_rounded,
                baslik: 'Exchange ActiveSync (mobil eşitleme)',
                child: Text(v.easHata ?? '', style: const TextStyle(color: Marka.gul)),
              ),
          ];
          final sag = <Widget>[
            if (v.limitler != null)
              BoyutLimitleriKarti(key: ValueKey(jsonEncode(v.limitler)), veri: v.limitler!, yazabilir: yazabilir && Uyg.platformYoneticisi, kaydedildi: yenile)
            else
              BolumKarti(
                ikon: Icons.straighten_rounded,
                baslik: 'Boyut limitleri (platform varsayılanı)',
                child: Text(v.limitHata ?? '', style: const TextStyle(color: Marka.gul)),
              ),
            SistemYapilandirmasiKarti(sistem: harita(v.ayarlar['system'])),
          ];
          Widget sutun(List<Widget> l) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final w in l) ...[w, const SizedBox(height: 16)],
            ],
          );
          return IcerikListesi(
            enFazla: 1600,
            children: [
              LayoutBuilder(
                builder: (c, k) => k.maxWidth >= 1150
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: sutun(sol)),
                          const SizedBox(width: 16),
                          Expanded(child: sutun(sag)),
                        ],
                      )
                    : sutun([...sol, ...sag]),
              ),
              Text(
                'Müşteri markası Hizmet → Marka bölümündedir. Gelen posta sınırları (DNSBL, bağlantı limitleri) Teslimat Kontrol bölümündedir.',
                style: TextStyle(color: c.r.silik, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Hata metni satırı.
class _HataMetni extends StatelessWidget {
  const _HataMetni(this.metin);
  final String? metin;
  @override
  Widget build(BuildContext context) => metin == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(metin!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
        );
}

Widget _kaydetDugmesi({required bool mesgul, required VoidCallback? onPressed}) => Align(
  alignment: Alignment.centerLeft,
  child: FilledButton.icon(
    onPressed: mesgul ? null : onPressed,
    icon: mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
    label: const Text('Kaydet'),
  ),
);

// ---- spam -----------------------------------------------------------------------------------------------------

/// Spam filtresi: PATCH /settings {spam: {enabled, junk_threshold, reject_threshold}} (1 ≤ gereksiz < ret ≤ 100).
class SpamAyarKarti extends StatefulWidget {
  const SpamAyarKarti({super.key, required this.spam, required this.yazabilir, required this.kaydedildi});
  final Map<String, dynamic> spam;
  final bool yazabilir;
  final Future<void> Function() kaydedildi;

  @override
  State<SpamAyarKarti> createState() => _SpamAyarKartiState();
}

String _sayiMetni(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _SpamAyarKartiState extends State<SpamAyarKarti> {
  late bool _etkin = mantik(widget.spam['enabled']);
  late final _gereksiz = TextEditingController(text: _sayiMetni(ondalik(widget.spam['junk_threshold'])));
  late final _ret = TextEditingController(text: _sayiMetni(ondalik(widget.spam['reject_threshold'])));
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    _gereksiz.dispose();
    _ret.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final j = double.tryParse(_gereksiz.text.trim().replaceAll(',', '.'));
    final r = double.tryParse(_ret.text.trim().replaceAll(',', '.'));
    String? h;
    if (j == null || r == null) {
      h = 'Eşikler sayı olmalı';
    } else if (j < 1 || j > 50) {
      h = 'Gereksiz eşiği 1–50 arasında olmalı';
    } else if (r < 2 || r > 100) {
      h = 'Ret eşiği 2–100 arasında olmalı';
    } else if (r <= j) {
      h = 'Ret eşiği gereksiz eşiğinden büyük olmalı';
    }
    setState(() => _hata = h);
    if (h != null) return;
    setState(() => _mesgul = true);
    try {
      await Uyg.api.patch('/api/v1/settings', {
        'spam': {'enabled': _etkin, 'junk_threshold': j, 'reject_threshold': r},
      });
      bildir('Spam ayarları kaydedildi', tur: MesajTur.basari);
      await widget.kaydedildi();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final y = widget.yazabilir;
    Widget alan(TextEditingController k, String etiket) => SizedBox(
      width: 150,
      child: TextField(
        controller: k,
        enabled: y,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: etiket),
      ),
    );
    return BolumKarti(
      ikon: Icons.gpp_maybe_rounded,
      baslik: 'Spam filtresi',
      altBaslik: 'Puan ≥ Gereksiz eşiği → Gereksiz klasörü; ≥ Ret eşiği → SMTP aşamasında 550 ile ret (ileti saklanmaz).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Spam taraması etkin'),
            value: _etkin,
            onChanged: y ? (v) => setState(() => _etkin = v) : null,
          ),
          const SizedBox(height: 4),
          Wrap(spacing: 16, runSpacing: 12, children: [alan(_gereksiz, 'Gereksiz eşiği'), alan(_ret, 'Ret eşiği')]),
          _HataMetni(_hata),
          if (y) ...[const SizedBox(height: 14), _kaydetDugmesi(mesgul: _mesgul, onPressed: _kaydet)],
        ],
      ),
    );
  }
}

// ---- ActiveSync -----------------------------------------------------------------------------------------------

const _easLisansNotu = 'Ticari kullanım için Microsoft EAS lisansı gerekebilir';

/// Exchange ActiveSync platform anahtarı: PUT /activesync/settings {enabled, max_devices (1–100), eas16}. Yalnızca gerçek
/// süper yönetici oturumu düzenler (yanıttaki can_edit).
class ActiveSyncKarti extends StatefulWidget {
  const ActiveSyncKarti({super.key, required this.veri, required this.kaydedildi});
  final Map<String, dynamic> veri;
  final Future<void> Function() kaydedildi;

  @override
  State<ActiveSyncKarti> createState() => _ActiveSyncKartiState();
}

class _ActiveSyncKartiState extends State<ActiveSyncKarti> {
  late bool _etkin = mantik(widget.veri['enabled']);
  late bool _eas16 = mantik(widget.veri['eas16']);
  late final _cihaz = TextEditingController(text: '${tamsayi(widget.veri['max_devices'], 10)}');
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    _cihaz.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final n = int.tryParse(_cihaz.text.trim());
    if (n == null || n < 1 || n > 100) {
      setState(() => _hata = 'Posta kutusu başına cihaz 1–100 arasında olmalı');
      return;
    }
    setState(() {
      _hata = null;
      _mesgul = true;
    });
    try {
      final d = harita(await Uyg.api.put('/api/v1/activesync/settings', {'enabled': _etkin, 'max_devices': n, 'eas16': _eas16}));
      bildir(mantik(d['enabled']) ? 'ActiveSync açık' : 'ActiveSync kapalı', tur: MesajTur.basari);
      await widget.kaydedildi();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = widget.veri;
    final y = mantik(v['can_edit']);
    final aciliyor = _etkin && !mantik(v['enabled']);
    final not = metin(v['license_note'], _easLisansNotu);
    return BolumKarti(
      ikon: Icons.smartphone_rounded,
      baslik: 'Exchange ActiveSync (mobil eşitleme)',
      altBaslik:
          'Telefonların "Exchange" hesabıyla posta, takvim ve kişileri eşitlemesi. Kapalıyken uç nokta yanıt vermez (404) ve otomatik keşif ActiveSync önermez.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Bant(
            '$not. Protokol Microsoft Open Specifications ([MS-ASCMD] vb.) belgelerine göre uygulandı; ticari satıştan önce lisans durumunu değerlendirin.',
            renk: Marka.kehribar,
            ikon: Icons.warning_amber_rounded,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('ActiveSync etkin'),
            subtitle: const Text('Varsayılan: kapalı'),
            value: _etkin,
            onChanged: y ? (x) => setState(() => _etkin = x) : null,
          ),
          if (aciliyor)
            Text(
              'Açıldığında yalnızca paketinde "Exchange ActiveSync" özelliği olan müşterilerin kullanıcıları bağlanabilir.',
              style: TextStyle(color: r.silik, fontSize: 12.5),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 220,
              child: TextField(
                controller: _cihaz,
                enabled: y,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Posta kutusu başına cihaz', helperText: '1–100'),
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('EAS 16.0 / 16.1 sürümlerini de öner'),
            subtitle: const Text('Deneysel; 14.1 her zaman açık'),
            value: _eas16,
            onChanged: y ? (x) => setState(() => _eas16 = x) : null,
          ),
          BilgiSatiri('Sunucu adresi', metin(v['url'], metin(v['path'])), mono: true, kopyalanabilir: true),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => bolumeGit(Bolum.cihazlar),
              icon: const Icon(Icons.smartphone_rounded, size: 18),
              label: const Text('Mobil cihazlar'),
            ),
          ),
          _HataMetni(_hata),
          const SizedBox(height: 8),
          if (y)
            _kaydetDugmesi(mesgul: _mesgul, onPressed: _kaydet)
          else
            Text('Yalnızca platform yöneticisi değiştirebilir.', style: TextStyle(color: r.silik, fontSize: 12.5)),
        ],
      ),
    );
  }
}

// ---- boyut limitleri --------------------------------------------------------------------------------------------

const _kib = 1024, _mib = 1024 * 1024;

const boyutLimitAnahtarlari = ['max_message_bytes', 'max_attachment_bytes', 'max_signature_bytes', 'max_avatar_bytes'];

const boyutLimitEtiketleri = {
  'max_message_bytes': 'En büyük ileti',
  'max_attachment_bytes': 'Ek yükleme (toplam)',
  'max_signature_bytes': 'İmza (resimler dahil)',
  'max_avatar_bytes': 'Profil resmi',
};

const _boyutIpuclari = {
  'max_message_bytes': 'Gönderilen/alınan tek iletinin en büyük boyutu.',
  'max_attachment_bytes': "Webmail'de bir iletiye eklenebilecek dosyaların toplamı.",
  'max_signature_bytes': 'HTML imzanın boyutu; gömülü logo/fotoğraf dahil.',
  'max_avatar_bytes': 'Yüklenen profil resmi ve müşteri logosu dosyası (yalnızca platform düzeyinde).',
};

String _kirp(double v, int basamak) {
  var s = v.toStringAsFixed(basamak);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// Bayt → (sayı metni, birim) (web: sizeValue). [kbTercih] küçük limitler (imza, profil resmi) için.
(String, bool) boyutDegeri(int bayt, {bool kbTercih = false}) {
  if (bayt >= _mib && !kbTercih) return (_kirp(bayt / _mib, 2), true);
  if (bayt >= _mib && bayt % _mib == 0) return ('${bayt ~/ _mib}', true);
  return (_kirp(bayt / _kib, 1), false);
}

/// (metin, MB mi) → bayt; boşsa null, geçersizse -1 (web: sizeBytes).
int? boyutBayt(String metin, bool mb) {
  final t = metin.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final n = double.tryParse(t);
  if (n == null || !n.isFinite || n <= 0) return -1;
  return (n * (mb ? _mib : _kib)).round();
}

/// Platform boyut varsayılanları: PUT /settings/limits {anahtar: bayt} (yalnızca süper yönetici; aralık sunucudan).
class BoyutLimitleriKarti extends StatefulWidget {
  const BoyutLimitleriKarti({super.key, required this.veri, required this.yazabilir, required this.kaydedildi});
  final Map<String, dynamic> veri;
  final bool yazabilir;
  final Future<void> Function() kaydedildi;

  @override
  State<BoyutLimitleriKarti> createState() => _BoyutLimitleriKartiState();
}

class _BoyutLimitleriKartiState extends State<BoyutLimitleriKarti> {
  final _metin = <String, TextEditingController>{};
  final _mb = <String, bool>{};
  String? _hata, _hataAlani;
  bool _mesgul = false;

  Map<String, dynamic> get _limitler => harita(widget.veri['limits']);
  Map<String, dynamic> get _sinirlar => harita(widget.veri['bounds']);

  (int, int)? _aralik(String k) {
    final b = _sinirlar[k];
    if (b is List && b.length == 2) return (tamsayi(b[0]), tamsayi(b[1]));
    return null;
  }

  @override
  void initState() {
    super.initState();
    for (final k in boyutLimitAnahtarlari) {
      final (t, mb) = boyutDegeri(tamsayi(_limitler[k]), kbTercih: k == 'max_signature_bytes' || k == 'max_avatar_bytes');
      _metin[k] = TextEditingController(text: t);
      _mb[k] = mb;
    }
  }

  @override
  void dispose() {
    for (final c in _metin.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    final govde = <String, int>{};
    for (final k in boyutLimitAnahtarlari) {
      final b = boyutBayt(_metin[k]!.text, _mb[k]!);
      final etiket = boyutLimitEtiketleri[k]!;
      String? h;
      if (b == null) {
        h = '$etiket: boş bırakılamaz';
      } else if (b < 0) {
        h = '$etiket: geçerli bir sayı girin';
      } else {
        final a = _aralik(k);
        if (a != null && (b < a.$1 || b > a.$2)) h = '$etiket: ${boyutYaz(a.$1)} – ${boyutYaz(a.$2)} arasında olmalı';
      }
      if (h != null) {
        setState(() {
          _hata = h;
          _hataAlani = k;
        });
        return;
      }
      govde[k] = b!;
    }
    setState(() {
      _hata = _hataAlani = null;
      _mesgul = true;
    });
    try {
      await Uyg.api.put('/api/v1/settings/limits', govde);
      bildir('Boyut limitleri kaydedildi', tur: MesajTur.basari);
      await widget.kaydedildi();
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _hata = e.mesaj;
          _hataAlani = e.alan;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final y = widget.yazabilir;
    final smtp = tamsayi(widget.veri['smtp_hard_max_bytes']);
    Widget alan(String k) {
      final a = _aralik(k);
      final ipucu = [
        _boyutIpuclari[k]!,
        if (a != null) 'Aralık: ${boyutYaz(a.$1)} – ${boyutYaz(a.$2)}',
        if (k == 'max_message_bytes' && smtp > 0) 'SMTP üst sınırı: ${boyutYaz(smtp)}',
      ].join(' · ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _metin[k],
                  enabled: y,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: boyutLimitEtiketleri[k],
                    errorText: _hataAlani == k ? '' : null,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [ButtonSegment(value: true, label: Text('MB')), ButtonSegment(value: false, label: Text('KB'))],
                selected: {_mb[k]!},
                onSelectionChanged: y ? (s) => setState(() => _mb[k] = s.first) : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(ipucu, style: TextStyle(color: r.silik, fontSize: 12)),
        ],
      );
    }

    return BolumKarti(
      ikon: Icons.straighten_rounded,
      baslik: 'Boyut limitleri (platform varsayılanı)',
      altBaslik:
          'Paket, müşteri veya posta kutusu düzeyinde ayrıca tanımlanmadıkça geçerli olan değerler.${y ? '' : ' Yalnızca süper yönetici değiştirebilir.'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Izgara(
            enAz: 280,
            bosluk: 16,
            children: [for (final k in boyutLimitAnahtarlari) alan(k)],
          ),
          const SizedBox(height: 12),
          Text(
            'Öncelik: Kutu > Müşteri > Paket > Platform; en özel düzeyde tanımlı değer geçerlidir. İleti boyutu SMTP sunucusunun üst '
            'sınırını${smtp > 0 ? ' (${boyutYaz(smtp)})' : ''} aşamaz; ekler base64 kodlaması nedeniyle ileti boyutunun en fazla 3/4\'ü kadar olabilir.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
          _HataMetni(_hata),
          if (y) ...[const SizedBox(height: 14), _kaydetDugmesi(mesgul: _mesgul, onPressed: _kaydet)],
        ],
      ),
    );
  }
}

// ---- sistem yapılandırması ----------------------------------------------------------------------------------

const _disGonderimMetni = {
  'disabled': 'Kapalı — hiçbir ileti sunucudan dışarı çıkmaz',
  'sink': 'Test alıcısı — giden iletiler yerel test sunucusuna gider',
  'direct': "Doğrudan — MX ile İnternet'e teslim",
};

/// GET /settings → system: ortam değişkenlerinden okunur, panelden değiştirilemez.
class SistemYapilandirmasiKarti extends StatelessWidget {
  const SistemYapilandirmasiKarti({super.key, required this.sistem});
  final Map<String, dynamic> sistem;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = sistem;
    final mod = metin(s['outbound_mode']);
    final ipler = metinler(s['public_ips']);
    String yaDaKapali(Object? v) => metin(v).isEmpty ? 'kapalı' : metin(v);
    return BolumKarti(
      ikon: Icons.tune_rounded,
      baslik: 'Sistem yapılandırması',
      altBaslik: 'Sunucu ortam değişkenlerinden (.env) okunur; güvenlik nedeniyle panelden değiştirilemez.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BilgiSatiri('SMTP sunucu adı', metin(s['smtp_hostname']), mono: true),
          BilgiSatiri('SMTP gelen dinleyici', yaDaKapali(s['smtp_addr']), mono: true),
          BilgiSatiri('Gönderim (submission)', yaDaKapali(s['submission_addr']), mono: true),
          BilgiSatiri(
            'Dış gönderim modu',
            _disGonderimMetni[mod] ?? '',
            sag: Rozet(mod.isEmpty ? '—' : mod, renk: mod == 'direct' ? Marka.zumrut : r.silik),
          ),
          BilgiSatiri("Genel IP'ler", ipler.isEmpty ? '—' : ipler.join(', '), mono: true),
          BilgiSatiri('En büyük ileti', boyutYaz(tamsayi(s['max_message_bytes']))),
          BilgiSatiri('Mesaj takibi saklama', '${tamsayi(s['event_retention_days'])} gün'),
          const BilgiSatiri('TLS sertifikası (SMTP)', 'Yapılandırılmadı'),
          BilgiSatiri('Güvenli çerez', mantik(s['cookie_secure']) ? 'açık' : 'kapalı'),
        ],
      ),
    );
  }
}
