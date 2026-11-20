// Ayarlar → Taşıma (IMAP) (web MigrationSection): eski sağlayıcıdaki iletileri klasörleriyle bu kutuya aktarır.
// Etkin iş varken 2 sn'de bir durum sorulur; iptal / devam / yeni taşıma.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/ayar_servisi.dart';
import 'ayar_ortak.dart';

const tasimaDurumAdlari = {
  'queued': 'Sırada',
  'running': 'Çalışıyor',
  'paused': 'Duraklatıldı',
  'completed': 'Tamamlandı',
  'failed': 'Başarısız',
  'cancelled': 'İptal edildi',
};
const _klasorDurumAdlari = {'pending': 'Bekliyor', 'running': 'Aktarılıyor', 'done': 'Bitti', 'failed': 'Başarısız', 'skipped': 'Atlandı'};
const _guvenlikAdlari = {'tls': 'SSL/TLS', 'starttls': 'STARTTLS', 'insecure': 'Şifresiz'};

class TasimaAyari extends StatefulWidget {
  const TasimaAyari({super.key, this.yoklama = const Duration(seconds: 2)});

  /// Etkin iş varken durum sorma aralığı.
  final Duration yoklama;
  @override
  State<TasimaAyari> createState() => _TasimaAyariState();
}

class _TasimaAyariState extends State<TasimaAyari> {
  bool? _acik;
  TasimaIsi? _is;
  String? _hata;
  bool _yeniForm = false;
  Timer? _zaman;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _zaman?.cancel();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final d = await Ayar.tasima();
      if (!mounted) return;
      setState(() {
        _acik = d.acik;
        _is = d.is_;
        _hata = null;
      });
      _zamanla();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  void _zamanla() {
    _zaman?.cancel();
    if (_is?.etkin ?? false) _zaman = Timer(widget.yoklama, _yukle);
  }

  Future<void> _eylem(Future<TasimaIsi> Function() f, String tamam) async {
    final j = await islem(f, tamam: tamam);
    if (j != null && mounted) {
      setState(() => _is = j);
      _zamanla();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget icerik;
    if (_acik == null) {
      icerik = _hata != null ? Text(_hata!, style: TextStyle(color: context.r.soluk)) : const Center(child: CircularProgressIndicator());
    } else if (!_acik! && _is == null) {
      icerik = const AyarNotu('IMAP ile taşıma paketinizde bulunmuyor. Yöneticinize başvurun.', baslik: 'Paketinizde yok', ton: NotTonu.uyari);
    } else if (_is != null && (_is!.etkin || !_yeniForm)) {
      icerik = _ilerleme(_is!);
    } else {
      icerik = _TasimaFormu(
        vazgec: _is == null ? null : () => setState(() => _yeniForm = false),
        basladi: (j) {
          setState(() {
            _is = j;
            _yeniForm = false;
          });
          _zamanla();
        },
      );
    }
    return AyarListesi(
      yenile: _yukle,
      children: [
        AyarKarti(
          ikon: Icons.move_down_rounded,
          baslik: 'Taşıma (IMAP)',
          aciklama: 'Eski e-posta sağlayıcınızdaki iletileri klasörleriyle birlikte bu kutuya aktarın. Taşıma arka planda sürer; sayfadan ayrılabilirsiniz.',
          child: icerik,
        ),
      ],
    );
  }

  Widget _ilerleme(TasimaIsi j) {
    final r = context.r;
    final islenen = j.yapilan + j.atlanan + j.hatali;
    final renk = switch (j.durum) {
      'completed' => Marka.zumrut,
      'failed' => Marka.gul,
      'paused' => Marka.kehribar,
      'running' => r.vurgu,
      _ => r.silik,
    };
    Widget sayi(String ad, String deger, {Color? c}) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ad, style: TextStyle(color: r.silik, fontSize: 12)),
          const SizedBox(height: 2),
          Text(
            deger,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: c),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Rozet(tasimaDurumAdlari[j.durum] ?? j.durum, renk: renk),
            if (j.iptalIstendi && j.etkin) Text('İptal ediliyor…', style: TextStyle(color: r.silik, fontSize: 12)),
            Text('${j.kullanici} @ ${j.sunucu}:${j.port} · ${_guvenlikAdlari[j.guvenlik] ?? j.guvenlik}', style: TextStyle(color: r.soluk, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                j.toplam > 0
                    ? '${sayiYaz(islenen)} / ${sayiYaz(j.toplam)} ileti'
                    : j.durum == 'queued'
                    ? 'Sırada bekliyor'
                    : j.durum == 'running'
                    ? 'Klasörler taranıyor…'
                    : 'İleti yok',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
            ),
            Text('%${j.yuzde}', style: TextStyle(color: r.soluk, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: j.yuzde / 100, minHeight: 8, backgroundColor: r.ic),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, k) {
            final s = k.maxWidth >= 560 ? 4 : 2;
            final g = (k.maxWidth - (s - 1) * 8) / s;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in [
                  sayi('Aktarılan', sayiYaz(j.yapilan)),
                  sayi('Atlanan (zaten var)', sayiYaz(j.atlanan)),
                  sayi('Hatalı', sayiYaz(j.hatali), c: j.hatali > 0 ? Marka.gul : null),
                  sayi('Aktarılan boyut', boyutYaz(j.bayt)),
                ])
                  SizedBox(width: g, child: w),
              ],
            );
          },
        ),
        if (j.cokBuyuk > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${sayiYaz(j.cokBuyuk)} ileti boyut sınırını aştığı için aktarılmadı.', style: TextStyle(color: r.silik, fontSize: 12.5)),
          ),
        if (j.sonHata.isNotEmpty) ...[const SizedBox(height: 10), AyarNotu(j.sonHata, ton: j.durum == 'paused' ? NotTonu.uyari : NotTonu.tehlike)],
        if (j.klasorler.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: r.kenar),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                for (final (i, f) in j.klasorler.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar),
                  ListTile(
                    dense: true,
                    title: Text('${f.kaynak} → ${f.hedef}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [_klasorDurumAdlari[f.durum] ?? f.durum, if (f.atlanan > 0) '${f.atlanan} atlandı', if (f.hatali > 0) '${f.hatali} hatalı'].join(' · '),
                    ),
                    trailing: Text('${sayiYaz(f.yapilan + f.atlanan + f.hatali)} / ${sayiYaz(f.toplam)}'),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          'Başlatıldı: ${tamZaman(j.olusturuldu)}${j.bitti != null ? ' · Bitti: ${tamZaman(j.bitti)}' : ''}',
          style: TextStyle(color: r.silik, fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            if (j.etkin && !j.iptalIstendi)
              OutlinedButton.icon(
                key: const ValueKey('tasima-iptal'),
                onPressed: () async {
                  if (!await onayla(
                    context,
                    'Taşıma iptal edilsin mi?',
                    mesaj: 'Şimdiye kadar aktarılan iletiler kutunuzda kalır. Daha sonra yeni bir taşıma başlatabilirsiniz.',
                    evet: 'İptal et',
                    tehlikeli: true,
                  )) {
                    return;
                  }
                  await _eylem(Ayar.tasimaIptal, 'Taşıma iptal edildi');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('İptal et'),
              ),
            if (j.durum == 'paused' && !j.iptalIstendi)
              FilledButton.icon(
                key: const ValueKey('tasima-devam'),
                onPressed: () => _eylem(Ayar.tasimaDevam, 'Taşıma devam ettiriliyor'),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Devam ettir'),
              ),
            if (!j.etkin && (_acik ?? false))
              FilledButton.icon(
                key: const ValueKey('tasima-yeni'),
                onPressed: () => setState(() => _yeniForm = true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Yeni taşıma'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TasimaFormu extends StatefulWidget {
  const _TasimaFormu({required this.basladi, this.vazgec});
  final ValueChanged<TasimaIsi> basladi;
  final VoidCallback? vazgec;
  @override
  State<_TasimaFormu> createState() => _TasimaFormuState();
}

class _TasimaFormuState extends State<_TasimaFormu> {
  List<TasimaSablonu> _sablonlar = const [];
  TasimaSablonu? _sablon;
  final _sunucu = TextEditingController();
  final _kullanici = TextEditingController();
  final _sifre = TextEditingController();
  String _guvenlik = 'tls';
  int _port = 993;
  bool _goster = false;
  bool _mesgul = false;
  ({String alan, String mesaj})? _hata;

  @override
  void initState() {
    super.initState();
    for (final c in [_sunucu, _kullanici, _sifre]) {
      c.addListener(() => setState(() {}));
    }
    Ayar.tasimaSablonlari().then((l) {
      if (mounted) setState(() => _sablonlar = l);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    for (final c in [_sunucu, _kullanici, _sifre]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sablonSec(String? anahtar) {
    final x = _sablonlar.where((s) => s.anahtar == anahtar).firstOrNull;
    setState(() {
      _sablon = x;
      if (x != null) {
        _sunucu.text = x.sunucuIcin(_kullanici.text);
        _guvenlik = x.guvenlik;
        _port = x.port;
      }
    });
  }

  Future<void> _baslat() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final j = await Ayar.tasimaBaslat(sunucu: _sunucu.text, port: _port, guvenlik: _guvenlik, kullanici: _kullanici.text, sifre: _sifre.text);
      _sifre.clear();
      bildir('Taşıma başlatıldı', tur: MesajTur.basari);
      widget.basladi(j);
    } catch (e) {
      if (mounted) setState(() => _hata = (alan: e is ApiHata ? (e.alan ?? '') : '', mesaj: hataMetni(e)));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? _alanHatasi(String a) => _hata?.alan == a ? _hata!.mesaj : null;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = _sablon;
    final hazir = _sunucu.text.trim().isNotEmpty && _kullanici.text.trim().isNotEmpty && _sifre.text.isNotEmpty;
    final genelHata = _hata != null && !const {'host', 'port', 'security', 'username', 'password'}.contains(_hata!.alan) ? _hata!.mesaj : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sablonlar.isNotEmpty) ...[
          AyarAlani(
            etiket: 'Eski sağlayıcı',
            child: DropdownButtonFormField<String>(
              key: const ValueKey('tasima-sablon'),
              initialValue: s?.anahtar,
              isExpanded: true,
              hint: const Text('Sağlayıcı seçin (isteğe bağlı)'),
              items: [for (final x in _sablonlar) DropdownMenuItem(value: x.anahtar, child: Text(x.ad))],
              onChanged: _mesgul ? null : _sablonSec,
            ),
          ),
          if (s != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.oauthDurumu.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${s.oauthDurumu}${s.sifreBasarisiz ? ' Şifreyle deneme büyük olasılıkla başarısız olur.' : ''}',
                        style: TextStyle(color: s.sifreBasarisiz ? Marka.kehribar : r.soluk, fontSize: 13),
                      ),
                    ),
                  if (s.yetki == 'app_password')
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Bu sağlayıcıda normal şifre yerine bir uygulama şifresi gerekir.',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  for (final (i, a) in s.adimlar.indexed) Text('${i + 1}. $a', style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.4)),
                  for (final n in s.notlar) Text('• $n', style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.4)),
                ],
              ),
            ),
          ],
        ],
        IkiSutun(
          esik: 520,
          children: [
            AyarAlani(
              etiket: 'Eski sunucu (IMAP)',
              child: TextField(
                key: const ValueKey('tasima-sunucu'),
                controller: _sunucu,
                enabled: !_mesgul,
                maxLength: 253,
                autocorrect: false,
                decoration: InputDecoration(hintText: 'imap.eskisaglayici.com', counterText: '', errorText: _alanHatasi('host')),
              ),
            ),
            AyarAlani(
              etiket: 'Güvenlik ve port',
              ipucu: 'Yalnızca 993 ve 143 portlarına, geçerli sertifikalı şifreli bağlantıyla bağlanılır.',
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'tls', label: Text('SSL/TLS (993)')),
                  ButtonSegment(value: 'starttls', label: Text('STARTTLS (143)')),
                ],
                selected: {_guvenlik},
                onSelectionChanged: _mesgul
                    ? null
                    : (v) => setState(() {
                        _guvenlik = v.first;
                        _port = _guvenlik == 'tls' ? 993 : 143;
                      }),
              ),
            ),
          ],
        ),
        IkiSutun(
          esik: 520,
          children: [
            AyarAlani(
              etiket: 'Kullanıcı adı',
              child: Focus(
                onFocusChange: (f) {
                  final x = _sablon;
                  if (!f && x != null && x.sunucu.contains('{domain}') && (_sunucu.text.isEmpty || _sunucu.text == x.sunucuIcin(''))) {
                    _sunucu.text = x.sunucuIcin(_kullanici.text);
                  }
                },
                child: TextField(
                  key: const ValueKey('tasima-kullanici'),
                  controller: _kullanici,
                  enabled: !_mesgul,
                  maxLength: 320,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: s?.kullaniciIpucu.isNotEmpty == true ? s!.kullaniciIpucu : 'ad@eskialanadi.com',
                    counterText: '',
                    errorText: _alanHatasi('username'),
                  ),
                ),
              ),
            ),
            AyarAlani(
              etiket: 'Şifre',
              child: TextField(
                key: const ValueKey('tasima-sifre'),
                controller: _sifre,
                enabled: !_mesgul,
                obscureText: !_goster,
                autocorrect: false,
                decoration: InputDecoration(
                  errorText: _alanHatasi('password'),
                  suffixIcon: IconButton(
                    tooltip: _goster ? 'Şifreyi gizle' : 'Şifreyi göster',
                    icon: Icon(_goster ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _goster = !_goster),
                  ),
                ),
              ),
            ),
          ],
        ),
        Text(
          'Şifre yalnızca taşıma süresince şifrelenmiş olarak saklanır ve iş bitince ya da iptal edilince silinir. Klasörler, okundu/yıldız işaretleri ve '
          'tarihler korunur; daha önce aktarılmış iletiler tekrar kopyalanmaz.',
          style: TextStyle(color: r.silik, fontSize: 12.5, height: 1.35),
        ),
        if (genelHata != null || _alanHatasi('port') != null || _alanHatasi('security') != null) ...[
          const SizedBox(height: 10),
          AyarNotu(genelHata ?? _hata!.mesaj, ton: NotTonu.tehlike),
        ],
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          children: [
            if (widget.vazgec != null) OutlinedButton(onPressed: _mesgul ? null : widget.vazgec, child: const Text('Vazgeç')),
            KaydetDugmesi(key: const ValueKey('tasima-baslat'), etkin: hazir, mesgul: _mesgul, basildi: _baslat, metin: 'Taşımayı başlat'),
          ],
        ),
      ],
    );
  }
}
