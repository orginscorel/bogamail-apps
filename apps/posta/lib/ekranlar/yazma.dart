import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/adres_alani.dart';
import '../ortak/ek_listesi.dart';
import '../ortak/izin.dart';
import '../ortak/zengin_duzenleyici.dart';
import '../ortak/simgeler.dart';
import '../veri/baglanti.dart';
import '../veri/kuyruk.dart';
import '../veri/durum.dart';
import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yazma_hazirla.dart';
import '../veri/tercihler.dart';
import '../veri/yardimci.dart';

/// Yazma penceresini açar: telefonda tam ekran, geniş ekranda iletişim kutusu.
Future<void> yazmaAc(BuildContext context, [YazmaBaslangic? b]) async {
  final bas = b ?? YazmaBaslangic();
  if (context.genis) {
    final boyut = MediaQuery.sizeOf(context);
    final boy = boyut.height;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          // Büyük ekranlarda daha geniş/yüksek, küçük pencerelerde pencereye sığar.
          width: (boyut.width * .62).clamp(min(720.0, boyut.width - 48), 1080.0),
          height: min(960.0, boy - 48),
          child: YazmaEkrani(baslangic: bas),
        ),
      ),
    );
  } else {
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => YazmaEkrani(baslangic: bas)));
  }
}

class _YerelEk {
  _YerelEk(this.ad, this.boyut, this._oku);

  /// Giden Kutusu'nda saklanmış (base64) ek.
  _YerelEk.hazir(this.ad, String b64) : boyut = b64.length * 3 ~/ 4, _oku = (() async => base64Decode(b64)), _b64 = b64;
  final String ad;
  final int boyut;
  final Future<List<int>> Function() _oku;
  String? _b64;
  Future<String> veri() async => _b64 ??= base64Encode(await _oku());
}

class YazmaEkrani extends StatefulWidget {
  const YazmaEkrani({super.key, required this.baslangic});
  final YazmaBaslangic baslangic;
  @override
  State<YazmaEkrani> createState() => _YazmaEkraniState();
}

class _YazmaEkraniState extends State<YazmaEkrani> {
  YazmaBaslangic get b => widget.baslangic;
  late final _kime = AliciDenetci(b.kime);
  late final _bilgi = AliciDenetci(b.bilgi);
  late final _gizli = AliciDenetci(b.gizli);
  late final _konu = TextEditingController(text: b.konu);
  late final _metin = TextEditingController(text: b.metin);
  final _metinOdak = FocusNode();
  late bool _bilgiGoster = b.bilgi.isNotEmpty || b.gizli.isNotEmpty;
  late bool _imza = b.imzaEkle && (b.tur == YazmaTuru.yeni ? Tercihler.imzaYeni.value : Tercihler.imzaYanit.value);
  bool _alinti = true;

  /// Biçimli (HTML) düzenleyici mi, düz metin mi. Web ile aynı kural: biçimli taslak → biçimli; düz taslak → düz;
  /// yeni ileti → compose_html ayarı (varsayılan biçimli).
  late bool _bicimli = b.tur == YazmaTuru.taslak ? b.htmlTaslak : (_ayar?.bicimliYazma ?? true);
  ZenginDenetleyici? _zengin;
  final _yerel = <_YerelEk>[];
  late List<DahilEk> _dahil = [...b.dahilEkler];
  late String? _taslakId = b.taslakId;
  late final bool _acilanTaslak = b.taslakId != null;
  late String? _oncelik = b.oncelik;
  late bool _okunduBilgisi = b.okunduBilgisi;
  late int _takipGun = b.takipGun;
  bool _kirli = false;
  bool _mesgul = false;
  double? _ilerleme;
  String? _hata;
  bool _bitti = false;

  PostaAyarlari? get _ayar => PostaDurum.ben.ayarlar;
  String get _etkinImza => _ayar?.etkinImzaHtml ?? '';
  int get _azamiEk => _ayar?.azamiEk ?? 0;
  int get _ekToplam => _yerel.fold<int>(0, (a, e) => a + e.boyut) + _dahil.fold<int>(0, (a, e) => a + e.boyut);

  @override
  void initState() {
    super.initState();
    for (final (ad, b64) in b.yerelEkler) {
      _yerel.add(_YerelEk.hazir(ad, b64));
    }
    // Giden Kutusu'ndan düzenleniyor: pencere açıkken otomatik gönderilmez.
    if (b.gidenId != null) GidenKutusu.ben.duzenlemeBasla(b.gidenId!);
    for (final c in [_konu, _metin]) {
      c.addListener(_degisti);
    }
    if (_ayar == null) {
      PostaDurum.ben.ayarlariYukle().whenComplete(() {
        if (!mounted) return;
        if (b.tur != YazmaTuru.taslak && _zengin == null) _bicimli = _ayar?.bicimliYazma ?? true;
        setState(_zenginiHazirla);
      });
    } else {
      _zenginiHazirla();
    }
    if (b.kime.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _metinOdak.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    if (b.gidenId != null) GidenKutusu.ben.duzenlemeBitti(b.gidenId!);
    for (final d in [_kime, _bilgi, _gizli]) {
      d.dispose();
    }
    _konu.dispose();
    _metin.dispose();
    _metinOdak.dispose();
    _zengin?.dispose();
    super.dispose();
  }

  /// Biçimli düzenleyicinin ilk içeriği (web buildInitialBody ile aynı): yazı bloğu, imza bloğu, alıntı.
  String _ilkHtml() {
    if (b.tur == YazmaTuru.taslak) {
      final h = b.htmlGovde ?? '';
      return h.trim().isNotEmpty ? guvenliHtml(h) : (b.metin.trim().isEmpty ? '<div><br></div>' : '<div>${metniHtmlYap(b.metin)}</div>');
    }
    final ilk = b.metin.trim().isEmpty ? '<div><br></div>' : '<div>${metniHtmlYap(b.metin.trimRight())}</div>';
    final imza = (_imza || (_ayar?.imzaKilitli ?? false)) && _etkinImza.trim().isNotEmpty
        ? '<div><br></div><div data-signature="">${guvenliHtml(_etkinImza)}</div>'
        : '';
    final alinti = (b.alintiHtml ?? '').isNotEmpty ? '<div><br></div>${b.alintiHtml}' : '';
    return '$ilk$imza$alinti';
  }

  /// Ayarlar (imza) bilindiğinde biçimli düzenleyici kurulur.
  void _zenginiHazirla() {
    if (!_bicimli || _zengin != null) return;
    _zengin = ZenginDenetleyici(ilkHtml: _ilkHtml())
      ..degisti = () {
        if (!_kirli && mounted) setState(() => _kirli = true);
      }
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  /// Düz metin ↔ biçimli geçiş (web switchMode): biçim kaldırılır / düz metin HTML'e çevrilir.
  Future<void> _kipDegistir() async {
    if (_bicimli) {
      final c = await _zengin?.icerik();
      final t = (c?.metin ?? '').replaceAll(RegExp(r'\n{3,}'), '\n\n');
      setState(() {
        _zengin?.dispose();
        _zengin = null;
        _bicimli = false;
        _metin.text = t;
        // İmza ve alıntı artık metnin içinde: ayrıca eklenmez.
        _imza = false;
        _alinti = false;
        _kirli = true;
      });
      bildir('Düz metin moduna geçildi; biçimlendirme kaldırıldı.');
    } else {
      final govde = govdeOlustur(
        metin: _metin.text,
        imzaHtml: _imza && b.tur != YazmaTuru.taslak ? _etkinImza : null,
        alintiHtml: _alinti && b.tur != YazmaTuru.taslak ? b.alintiHtml : null,
      );
      setState(() {
        _bicimli = true;
        _zengin = ZenginDenetleyici(ilkHtml: govde.html)
          ..degisti = () {
            if (!_kirli && mounted) setState(() => _kirli = true);
          }
          ..addListener(() {
            if (mounted) setState(() {});
          });
        _alinti = false;
        _kirli = true;
      });
    }
  }

  void _degisti() {
    if (!_kirli && mounted) setState(() => _kirli = true);
  }

  bool get _icerikVar =>
      !_kime.bos ||
      !_bilgi.bos ||
      !_gizli.bos ||
      _konu.text.trim().isNotEmpty ||
      (_bicimli ? !(_zengin?.bos ?? true) : _metin.text.trim().isNotEmpty) ||
      _yerel.isNotEmpty ||
      (_dahil.isNotEmpty && b.tur != YazmaTuru.ilet);

  // ---- istek ----

  Future<Map<String, dynamic>> _istek() async {
    final k = _kime.topla().liste, c = _bilgi.topla().liste, g = _gizli.topla().liste;
    final taslak = b.tur == YazmaTuru.taslak;
    final z = _bicimli ? _zengin : null;
    // Biçimli: imza ve alıntı düzenleyicinin içinde; gövde web gibi innerHTML + innerText.
    final govde = z != null
        ? await z.icerik().then((c) => (metin: c.metin, html: c.html))
        : govdeOlustur(
            metin: _metin.text,
            imzaHtml: _imza && !taslak ? _etkinImza : null,
            alintiHtml: _alinti && !taslak ? b.alintiHtml : null,
            alintiMetin: _alinti && !taslak ? b.alintiMetin : null,
          );
    final r = <String, dynamic>{
      'to': k.map(adresYaz).toList(),
      'cc': c.map(adresYaz).toList(),
      'bcc': g.map(adresYaz).toList(),
      'subject': _konu.text.trim(),
      'text': govde.metin,
      'html': govde.html,
    };
    if (_yerel.isNotEmpty) {
      r['attachments'] = [
        for (final e in _yerel) {'filename': e.ad, 'content_type': icerikTuru(e.ad), 'data': await e.veri()},
      ];
    }
    if (_dahil.isNotEmpty) r['include_parts'] = _dahil.map((d) => d.json).toList();
    if (b.inReplyTo != null) r['in_reply_to'] = b.inReplyTo;
    if (b.references != null) r['references'] = b.references;
    if (b.yanitlananId != null) r['reply_to_id'] = b.yanitlananId;
    if (b.iletilenId != null) r['forward_of_id'] = b.iletilenId;
    if (_taslakId != null) r['draft_id'] = _taslakId;
    if (_oncelik != null) r['priority'] = _oncelik;
    if (_okunduBilgisi) r['read_receipt'] = true;
    if (_takipGun > 0) r['followup_days'] = _takipGun;
    return r;
  }

  String? _dogrula() {
    for (final (ad, d) in [('Kime', _kime), ('Bilgi', _bilgi), ('Gizli', _gizli)]) {
      final t = d.topla();
      if (t.gecersiz != null) return '$ad alanında geçersiz adres: ${t.gecersiz}';
    }
    if (_kime.topla().liste.isEmpty && _bilgi.topla().liste.isEmpty && _gizli.topla().liste.isEmpty) return 'En az bir alıcı ekleyin.';
    if (_azamiEk > 0 && _ekToplam > _azamiEk) return 'Ekler toplam ${boyutYaz(_azamiEk)} sınırını geçemez.';
    return null;
  }

  // ---- gönderim ----

  Future<void> _gonder({DateTime? zaman}) async {
    if (_mesgul) return;
    final h = _dogrula();
    if (h != null) {
      setState(() => _hata = h);
      return;
    }
    if (_konu.text.trim().isEmpty && !await onayla(context, 'Konu olmadan gönderilsin mi?', mesaj: 'Bu iletinin konusu boş.', evet: 'Gönder')) return;
    var dlpOnay = false;
    while (mounted) {
      setState(() {
        _mesgul = true;
        _ilerleme = 0;
        _hata = null;
      });
      Map<String, dynamic>? r;
      try {
        r = await _istek();
        if (dlpOnay) r['dlp_confirm'] = true;
        if (zaman != null) r['send_at'] = zaman.toUtc().toIso8601String();
        // Çevrimdışı: beklemeden Giden Kutusu'na (bağlantı gelince sırayla gönderilir).
        if (Baglanti.ben.cevrimdisi.value) return await _gidenKutusuna(r);
        final s = await Posta.gonder(
          r,
          ilerleme: (a, t) {
            if (mounted && t > 0) setState(() => _ilerleme = a / t);
          },
        );
        _bitti = true;
        if (b.gidenId != null) unawaited(GidenKutusu.ben.sil(b.gidenId!));
        PostaDurum.ben.sayilariYenile();
        if (mounted) Navigator.of(context).pop();
        _sonucBildir(s, zaman);
        return;
      } on GonderimHatasi catch (e) {
        if (e.baglantiYok && r != null) return await _gidenKutusuna(r);
        if (!mounted) return;
        setState(() {
          _mesgul = false;
          _ilerleme = null;
        });
        if (e.dlp != null) {
          final devam = await _dlpGoster(e.dlp!);
          if (devam) {
            dlpOnay = true;
            continue;
          }
          return;
        }
        setState(() => _hata = e.mesaj);
        return;
      } catch (e) {
        if (mounted) {
          setState(() {
            _mesgul = false;
            _ilerleme = null;
            _hata = 'İleti gönderilemedi. Bağlantınızı kontrol edip tekrar deneyin.';
          });
        }
        return;
      }
    }
  }

  /// Sunucuya ulaşılamıyor: ileti (ekleriyle) Giden Kutusu'na alınır, pencere kapanır.
  Future<void> _gidenKutusuna(Map<String, dynamic> r) async {
    final ek = {
      'dahil': [
        for (final d in _dahil) {'ad': d.ad, 'tur': d.tur, 'boyut': d.boyut},
      ],
    };
    await GidenKutusu.ben.ekle(r, ek: ek, eskiId: b.gidenId);
    _bitti = true;
    if (mounted) Navigator.of(context).pop();
    bildir('Çevrimdışı: ileti Giden Kutusu\'nda', mesaj: 'Bağlantı gelince otomatik gönderilecek.');
  }

  static void _sonucBildir(GonderimSonucu s, DateTime? zaman) {
    if (s.bekletme != null && s.bekletme!.isNotEmpty) {
      bildir('İleti onay bekliyor', mesaj: s.bekletme, tur: MesajTur.uyari);
    } else if (zaman != null && !s.geriAlinabilir) {
      bildir('İleti planlandı', mesaj: '${DateFormat('d MMMM HH:mm', 'tr_TR').format(s.planZamani ?? zaman)} için planlandı.', tur: MesajTur.basari);
    } else if (s.geriAlinabilir && s.planId != null) {
      final sn = s.geriAlmaSaniye > 0 ? s.geriAlmaSaniye : 10;
      final m = kokMesaj.currentState;
      m?.hideCurrentSnackBar();
      m?.showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF15142E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          duration: Duration(seconds: sn),
          content: Text('Gönderiliyor… $sn saniye içinde geri alabilirsiniz.', style: const TextStyle(color: Colors.white)),
          action: SnackBarAction(label: 'Geri al', textColor: Marka.lavanta, onPressed: () => _geriAl(s.planId!)),
        ),
      );
    } else {
      bildir('İleti gönderildi', tur: MesajTur.basari);
    }
  }

  static Future<void> _geriAl(String planId) async {
    try {
      final r = await Posta.gonderimiGeriAl(planId);
      final id = '${r['draft_id'] ?? ''}';
      if (id.isEmpty) throw ApiHata(500, 'Taslak oluşturulamadı.');
      final d = await Posta.ileti(id);
      final c = r['compose'] is Map ? Map<String, dynamic>.from(r['compose'] as Map) : null;
      PostaDurum.ben.sayilariYenile();
      bildir('Gönderim geri alındı', mesaj: 'İleti taslak olarak yeniden açıldı.', tur: MesajTur.basari);
      final ctx = kokGezgin.currentContext;
      if (ctx != null && ctx.mounted) await yazmaAc(ctx, taslakHazirla(d, taslakId: id, geriAlinan: c));
    } on ApiHata catch (e) {
      bildir(e.durum == 409 ? 'İleti gönderildi; artık geri alınamaz' : 'Geri alınamadı', mesaj: e.durum == 409 ? null : e.mesaj, tur: MesajTur.hata);
    } catch (_) {
      bildir('Geri alınamadı', tur: MesajTur.hata);
    }
  }

  Future<bool> _dlpGoster(DlpRapor d) async {
    final r = context.r;
    final v = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(d.engel ? Simge.engelle : Simge.gizlilik, color: d.engel ? Marka.gul : Marka.kehribar, size: 32),
        title: Text(d.engel ? 'İleti gönderilemez' : 'Hassas bilgi uyarısı', style: gosterim(19, agirlik: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.mesaj.isNotEmpty
                    ? d.mesaj
                    : d.engel
                    ? 'Kurumunuzun veri koruma politikası bu içeriğin gönderilmesine izin vermiyor.'
                    : 'İleti, kurumunuzun veri koruma politikasına takılan bilgiler içeriyor.',
              ),
              if (d.politikalar.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Politika: ${d.politikalar.join(', ')}', style: TextStyle(color: r.soluk, fontSize: 13)),
              ],
              for (final m in d.eslesmeler) ...[
                const SizedBox(height: 10),
                Text('${m.baslik} (${m.adet})', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (m.ornekler.isNotEmpty)
                  Text(
                    m.ornekler.join(', '),
                    style: TextStyle(color: r.soluk, fontSize: 13, fontFamily: 'monospace'),
                  ),
              ],
              if (d.taranamayan.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Taranamayan ekler: ${d.taranamayan.join('; ')}', style: TextStyle(color: r.soluk, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        actions: d.engel
            ? [FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('Tamam'))]
            : [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Düzenle')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Marka.kehribar),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Yine de gönder'),
                ),
              ],
      ),
    );
    return v ?? false;
  }

  Future<void> _planla() async {
    final simdi = DateTime.now();
    final gun = await showDatePicker(
      context: context,
      firstDate: simdi,
      lastDate: simdi.add(const Duration(days: 365)),
      initialDate: simdi,
      helpText: 'Gönderim günü',
    );
    if (gun == null || !mounted) return;
    final saat = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(simdi.add(const Duration(hours: 1))), helpText: 'Gönderim saati');
    if (saat == null || !mounted) return;
    final z = DateTime(gun.year, gun.month, gun.day, saat.hour, saat.minute);
    if (z.difference(DateTime.now()) < const Duration(minutes: 2)) {
      setState(() => _hata = 'Planlanan zaman en az 2 dakika sonrası olmalı.');
      return;
    }
    await _gonder(zaman: z);
  }

  // ---- taslak ----

  Future<bool> _taslakKaydet({bool bildirim = true}) async {
    setState(() => _mesgul = true);
    try {
      final r = await _istek();
      final id = await Posta.taslakKaydet(r);
      if (id.isNotEmpty) {
        _taslakId = id;
        if (_yerel.isNotEmpty || _dahil.isNotEmpty) {
          // Ekler artık taslağın içinde: bir sonraki kayıtta yeniden yüklenmesin.
          try {
            final d = await Posta.ileti(id);
            _dahil = d.gorunum.dosyaEkleri.map((a) => DahilEk(iletiId: id, sira: a.sira, ad: a.ad, tur: a.tur, boyut: a.boyut)).toList();
            _yerel.clear();
          } catch (_) {}
        }
      }
      PostaDurum.ben.sayilariYenile();
      if (mounted) setState(() => _kirli = false);
      if (bildirim) bildir('Taslak kaydedildi', tur: MesajTur.basari);
      return true;
    } on GonderimHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
      return false;
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  /// İletiyi Şablonlar klasörüne kaydeder (taslağın yerine geçmez).
  Future<void> _sablonKaydet() async {
    if (_konu.text.trim().isEmpty && (_bicimli ? (_zengin?.bos ?? true) : _metin.text.trim().isEmpty)) {
      setState(() => _hata = 'Şablon için konu veya metin yazın.');
      return;
    }
    setState(() => _mesgul = true);
    try {
      final r = await _istek();
      r.remove('draft_id');
      r['template'] = true;
      await Posta.taslakKaydet(r);
      PostaDurum.ben.sayilariYenile();
      bildir('Şablon kaydedildi', mesaj: 'Şablonlar klasöründe bulabilirsiniz.', tur: MesajTur.basari);
    } on GonderimHatasi catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  /// Şablonlar klasöründen bir şablon seçip konu (boşsa) ve metne ekler.
  Future<void> _sablonEkle() async {
    final k = PostaDurum.ben.rolu('templates');
    if (k == null) {
      bildir('Şablonlar klasörü bulunamadı', tur: MesajTur.uyari);
      return;
    }
    List<IletiOzet> l;
    try {
      l = (await Posta.liste(klasorId: k.id, boyut: 100)).ogeler;
    } catch (e) {
      bildir('Şablonlar alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
      return;
    }
    if (!mounted) return;
    final sec = await showModalBottomSheet<IletiOzet>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Şablon ekle', style: gosterim(17, agirlik: FontWeight.w600)),
              ),
              if (l.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Kayıtlı şablon yok. Bir iletiyi menüden "Şablon olarak kaydet" ile kaydedebilirsiniz.'),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in l)
                      ListTile(
                        leading: const Icon(Simge.belge),
                        title: Text(m.konu.trim().isEmpty ? '(konu yok)' : m.konu),
                        subtitle: Text(m.onizleme, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(c, m),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (sec == null) return;
    try {
      final d = await Posta.ileti(sec.id);
      final metin = d.gorunum.metin.trim().isNotEmpty ? d.gorunum.metin.trim() : htmlMetne(d.gorunum.html).trim();
      final z = _bicimli ? _zengin : null;
      if (z != null) {
        // Web insertTemplate: biçimli şablon imleç konumuna HTML olarak eklenir.
        await z.htmlEkle(d.gorunum.html.trim().isNotEmpty ? d.gorunum.html : metniHtmlYap(d.gorunum.metin));
        if (!mounted) return;
        setState(() {
          if (_konu.text.trim().isEmpty) _konu.text = d.gorunum.konu;
          _kirli = true;
        });
        return;
      }
      setState(() {
        if (_konu.text.trim().isEmpty) _konu.text = d.gorunum.konu;
        final t = _metin.text;
        _metin.text = t.trim().isEmpty ? metin : '$t\n$metin';
        _kirli = true;
      });
    } catch (e) {
      bildir('Şablon açılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _takipSec() async {
    const secenekler = [(0, 'Kapalı'), (1, '1 gün'), (2, '2 gün'), (3, '3 gün'), (7, '1 hafta'), (14, '2 hafta')];
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Yanıt gelmezse hatırlat', style: gosterim(17, agirlik: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Seçtiğiniz süre içinde yanıt gelmezse ileti Gelen Kutusu\'nda "Takip" işaretiyle en üstte görünür.',
                style: TextStyle(color: c.r.soluk),
              ),
            ),
            for (final s in secenekler)
              ListTile(
                leading: Icon(s.$1 == _takipGun ? Simge.secimDolu : Simge.secimBos, color: s.$1 == _takipGun ? c.r.vurgu : null),
                title: Text(s.$2),
                onTap: () => Navigator.pop(c, s.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (v != null) {
      setState(() {
        _takipGun = v;
        _kirli = true;
      });
    }
  }

  Future<void> _taslakSil(String id) async {
    // İlk silme Çöp Kutusu'na taşır, ikincisi kalıcı siler (web ile aynı).
    try {
      await Posta.sil(id);
      await Posta.sil(id);
    } catch (_) {}
    PostaDurum.ben.sayilariYenile();
  }

  Future<void> _kapat() async {
    if (_mesgul) return;
    final nav = Navigator.of(context);
    if (!_kirli || !_icerikVar) {
      _bitti = true;
      nav.pop();
      return;
    }
    final s = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Kaydedilmemiş değişiklikler var', style: gosterim(17, agirlik: FontWeight.w600)),
            ),
            ListTile(leading: const Icon(Simge.kaydet), title: const Text('Taslak olarak kaydet'), onTap: () => Navigator.pop(c, 1)),
            ListTile(
              leading: const Icon(Simge.sil, color: Marka.gul),
              title: Text(_acilanTaslak ? 'Değişiklikleri at' : 'İletiyi sil', style: const TextStyle(color: Marka.gul)),
              onTap: () => Navigator.pop(c, 2),
            ),
            ListTile(leading: const Icon(Simge.duzenle), title: const Text('Yazmaya devam et'), onTap: () => Navigator.pop(c, 0)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (s == 1) {
      if (await _taslakKaydet()) {
        _bitti = true;
        nav.pop();
      }
    } else if (s == 2) {
      // Bu oturumda oluşan taslak silinir; açılmış eski taslak yerinde kalır.
      if (!_acilanTaslak && _taslakId != null) unawaited(_taslakSil(_taslakId!));
      _bitti = true;
      nav.pop();
    }
  }

  // ---- ekler ----

  /// Ek ekleme: dosya, galeri (fotoğraf/video) ve telefonda kamera (fotoğraf/video).
  Future<void> _ekSec() async {
    final mobil = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    if (!mobil) return _dosyaSec();
    final s = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Simge.ek), title: const Text('Dosya seç'), onTap: () => Navigator.pop(c, 'dosya')),
            ListTile(leading: const Icon(Simge.galeri), title: const Text('Fotoğraf/Video galerisi'), onTap: () => Navigator.pop(c, 'galeri')),
            ListTile(leading: const Icon(Simge.kamera), title: const Text('Kamerayla fotoğraf çek'), onTap: () => Navigator.pop(c, 'foto')),
            ListTile(leading: const Icon(Simge.video), title: const Text('Kamerayla video çek'), onTap: () => Navigator.pop(c, 'video')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (s) {
      case 'dosya':
        await _dosyaSec();
      case 'galeri' || 'foto' || 'video':
        await _medyaSec(s!);
    }
  }

  Future<void> _dosyaSec() async {
    final List<PlatformFile> l;
    try {
      l = await FilePicker.pickFiles(dialogTitle: 'Dosya ekle');
    } catch (e) {
      bildir('Dosya seçilemedi', tur: MesajTur.hata);
      return;
    }
    if (l.isEmpty) return;
    final adaylar = <({String ad, int boyut, Future<List<int>> Function() oku})>[];
    for (final f in l) {
      adaylar.add((ad: f.name, boyut: f.lengthSync() ?? await f.length() ?? 0, oku: f.readAsBytes));
    }
    _ekleriEkle(adaylar);
  }

  /// Büyük fotoğraflar küçültülür (en uzun kenar 2560 px, JPEG kalite %82); videolar olduğu gibi eklenir.
  Future<void> _medyaSec(String tur) async {
    final p = ImagePicker();
    final List<XFile> l;
    try {
      l = switch (tur) {
        'foto' => [?await p.pickImage(source: ImageSource.camera, imageQuality: 82, maxWidth: 2560, maxHeight: 2560)],
        'video' => [?await p.pickVideo(source: ImageSource.camera, maxDuration: const Duration(minutes: 5))],
        _ => await p.pickMultipleMedia(imageQuality: 82, maxWidth: 2560, maxHeight: 2560),
      };
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code.contains('access_denied') || e.code.contains('permission')) {
        await izinReddedildi(context, kamera: tur != 'galeri');
      } else {
        bildir('Medya alınamadı', mesaj: e.message, tur: MesajTur.hata);
      }
      return;
    } catch (_) {
      bildir('Medya alınamadı', tur: MesajTur.hata);
      return;
    }
    if (l.isEmpty) return;
    final adaylar = <({String ad, int boyut, Future<List<int>> Function() oku})>[];
    for (final f in l) {
      adaylar.add((ad: f.name, boyut: await f.length(), oku: f.readAsBytes));
    }
    _ekleriEkle(adaylar);
  }

  void _ekleriEkle(List<({String ad, int boyut, Future<List<int>> Function() oku})> l) {
    final hatalar = <String>[];
    var toplam = _ekToplam;
    for (final f in l) {
      final n = f.boyut;
      if (n == 0) {
        hatalar.add('"${f.ad}" boş; eklenemedi.');
      } else if (_azamiEk > 0 && toplam + n > _azamiEk) {
        hatalar.add('"${f.ad}" eklenemedi: ekler toplam ${boyutYaz(_azamiEk)} sınırını geçemez.');
      } else {
        _yerel.add(_YerelEk(f.ad, n, f.oku));
        toplam += n;
      }
    }
    setState(() {
      _kirli = true;
      _hata = hatalar.isEmpty ? null : hatalar.join(' ');
    });
  }

  // ---- arayüz ----

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final kutu = Uyg.kutu.value;
    final kimden = '${kutu?['display_name'] ?? ''}'.trim();
    final adres = Uyg.adres;
    return PopScope(
      canPop: _bitti || !_kirli || !_icerikVar,
      onPopInvokedWithResult: (bitti, _) {
        if (!bitti) _kapat();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _gonder,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _gonder,
          const SingleActivator(LogicalKeyboardKey.escape): _kapat,
        },
        child: Scaffold(
          backgroundColor: r.kart,
          appBar: AppBar(
            backgroundColor: r.kart,
            leading: IconButton(icon: const Icon(Simge.kapat), tooltip: 'Kapat', onPressed: _kapat),
            title: Text(b.baslik),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Diğer seçenekler',
                enabled: !_mesgul,
                onSelected: (v) async {
                  switch (v) {
                    case 'kaydet':
                      await _taslakKaydet();
                    case 'planla':
                      await _planla();
                    case 'sablonEkle':
                      await _sablonEkle();
                    case 'sablonKaydet':
                      await _sablonKaydet();
                    case 'takip':
                      await _takipSec();
                    case 'oncelik':
                      setState(() {
                        _oncelik = _oncelik == 'high' ? null : 'high';
                        _kirli = true;
                      });
                    case 'kip':
                      await _kipDegistir();
                    case 'okundu':
                      setState(() {
                        _okunduBilgisi = !_okunduBilgisi;
                        _kirli = true;
                      });
                    case 'sil':
                      if (_taslakId != null && await onayla(context, 'Taslak silinsin mi?', evet: 'Sil', tehlikeli: true)) {
                        await _taslakSil(_taslakId!);
                        _bitti = true;
                        if (context.mounted) Navigator.of(context).pop();
                        bildir('Taslak silindi');
                      }
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'kaydet',
                    child: ListTile(leading: Icon(Simge.kaydet), title: Text('Taslağı kaydet')),
                  ),
                  const PopupMenuItem(
                    value: 'planla',
                    child: ListTile(leading: Icon(Simge.planliGonder), title: Text('Daha sonra gönder…')),
                  ),
                  const PopupMenuItem(
                    value: 'sablonEkle',
                    child: ListTile(leading: Icon(Simge.belge), title: Text('Şablon ekle…')),
                  ),
                  const PopupMenuItem(
                    value: 'sablonKaydet',
                    child: ListTile(leading: Icon(Simge.farkliKaydet), title: Text('Şablon olarak kaydet')),
                  ),
                  PopupMenuItem(
                    value: 'takip',
                    child: ListTile(
                      leading: const Icon(Simge.hatirlatma),
                      title: Text(_takipGun > 0 ? 'Yanıt gelmezse hatırlat: $_takipGun gün' : 'Yanıt gelmezse hatırlat…'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(value: 'oncelik', checked: _oncelik == 'high', child: const Text('Yüksek önem')),
                  PopupMenuItem(
                    key: const ValueKey('kip-degistir'),
                    value: 'kip',
                    child: ListTile(
                      leading: Icon(_bicimli ? Simge.duzMetin : Simge.bicim),
                      title: Text(_bicimli ? 'Düz metne geç (biçimlendirme kaldırılır)' : 'Biçimli metne geç'),
                    ),
                  ),
                  CheckedPopupMenuItem(value: 'okundu', checked: _okunduBilgisi, child: const Text('Okundu bilgisi iste')),
                  if (_taslakId != null)
                    const PopupMenuItem(
                      value: 'sil',
                      child: ListTile(
                        leading: Icon(Simge.sil, color: Marka.gul),
                        title: Text('Taslağı sil'),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('gonder'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        backgroundColor: r.vurgu,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(20))),
                      ),
                      onPressed: _mesgul ? null : _gonder,
                      icon: const Icon(Simge.gonder, size: 18),
                      label: const Text('Gönder'),
                    ),
                    const SizedBox(width: 2),
                    Tooltip(
                      message: 'Daha sonra gönder',
                      child: FilledButton(
                        key: const ValueKey('planla'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(40, 40),
                          padding: EdgeInsets.zero,
                          backgroundColor: r.vurgu,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(20))),
                        ),
                        onPressed: _mesgul ? null : _planla,
                        child: const Icon(Simge.planliGonder, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            bottom: _mesgul
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(3),
                    child: LinearProgressIndicator(minHeight: 3, value: _ilerleme == null || _ilerleme == 0 || _ilerleme! >= 1 ? null : _ilerleme),
                  )
                : null,
          ),
          bottomNavigationBar: _aracCubugu(r),
          body: AbsorbPointer(
            absorbing: _mesgul,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              children: [
                if (_hata != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Simge.hata, color: Marka.gul, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13.5)),
                        ),
                        IconButton(icon: const Icon(Simge.kapat, size: 18), tooltip: 'Kapat', onPressed: () => setState(() => _hata = null)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text('Kimden', style: TextStyle(color: r.silik, fontSize: 14)),
                      ),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(24)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Avatar(kimden.isEmpty ? adres : kimden, boyut: 26, tohum: adres),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  kimden.isEmpty ? adres : '$kimden · $adres',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: r.metin, fontSize: 13.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                AdresAlani(
                  etiket: 'Kime',
                  denetci: _kime,
                  otomatikOdak: b.kime.isEmpty && b.tur != YazmaTuru.taslak,
                  degisti: _degisti,
                  sag: _bilgiGoster ? null : TextButton(onPressed: () => setState(() => _bilgiGoster = true), child: const Text('Bilgi/Gizli')),
                ),
                if (_bilgiGoster) ...[
                  const Divider(),
                  AdresAlani(etiket: 'Bilgi', denetci: _bilgi, degisti: _degisti),
                  const Divider(),
                  AdresAlani(etiket: 'Gizli', denetci: _gizli, degisti: _degisti),
                ],
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _konu,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    style: gosterim(18, agirlik: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: 'Konu',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                const Divider(),
                if (_oncelik == 'high' || _okunduBilgisi)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Wrap(
                      spacing: 6,
                      children: [
                        if (_oncelik == 'high') const Rozet('Yüksek önem', renk: Marka.gul, ikon: Simge.onem),
                        if (_okunduBilgisi) const Rozet('Okundu bilgisi istenecek', ikon: Simge.okunduYap),
                      ],
                    ),
                  ),
                if (b.htmlTaslak && !_bicimli)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      'Bu taslak biçimlendirilmiş metin içeriyor; uygulamada düz metin olarak düzenlenir.',
                      style: TextStyle(color: r.silik, fontSize: 12.5),
                    ),
                  ),
                if (_bicimli)
                  _zengin == null
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator.adaptive()),
                        )
                      : ZenginDuzenleyici(key: const ValueKey('zengin-duzenleyici'), denetleyici: _zengin!)
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: TextField(
                      controller: _metin,
                      focusNode: _metinOdak,
                      minLines: 8,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15, height: 1.5),
                      decoration: const InputDecoration(
                        hintText: 'İletinizi yazın',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                if (_yerel.isNotEmpty || _dahil.isNotEmpty) _ekler(r),
                if (b.tur != YazmaTuru.taslak && _etkinImza.isNotEmpty) _imzaKarti(r),
                if (!_bicimli && b.alintiMetin != null && b.alintiMetin!.isNotEmpty && (_alinti || b.tur != YazmaTuru.taslak)) _alintiKarti(r),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Klavyenin üstünde duran araç çubuğu: ek, kamera, şablon, takip, öncelik, okundu bilgisi.
  Widget _aracCubugu(Renkler r) {
    final mobil = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    Widget arac(IconData i, String ipucu, VoidCallback? f, {bool etkin = false, Key? key}) => IconButton(
      key: key,
      tooltip: ipucu,
      onPressed: _mesgul ? null : f,
      isSelected: etkin,
      style: IconButton.styleFrom(foregroundColor: r.soluk),
      selectedIcon: Icon(i, color: r.vurgu),
      icon: Icon(i),
    );
    return Material(
      color: r.kart,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: r.kenar)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                arac(Simge.ek, 'Ek ekle', _ekSec, key: const ValueKey('ek-ekle')),
                if (mobil) arac(Simge.kamera, 'Kamerayla çek', () => _medyaSec('foto')),
                if (mobil) arac(Simge.galeri, 'Galeriden ekle', () => _medyaSec('galeri')),
                arac(Simge.belge, 'Şablon ekle', _sablonEkle),
                arac(
                  Simge.hatirlatma,
                  _takipGun > 0 ? 'Yanıt gelmezse $_takipGun gün sonra hatırlat' : 'Yanıt gelmezse hatırlat',
                  _takipSec,
                  etkin: _takipGun > 0,
                ),
                arac(
                  Simge.onem,
                  'Yüksek önem',
                  key: const ValueKey('yuksek-onem'),
                  () => setState(() {
                    _oncelik = _oncelik == 'high' ? null : 'high';
                    _kirli = true;
                  }),
                  etkin: _oncelik == 'high',
                ),
                arac(
                  Simge.okunduYap,
                  'Okundu bilgisi iste',
                  () => setState(() {
                    _okunduBilgisi = !_okunduBilgisi;
                    _kirli = true;
                  }),
                  etkin: _okunduBilgisi,
                ),
                arac(Simge.kaydet, 'Taslağı kaydet', _taslakKaydet),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ek şeridi: yatay kartlar ve toplam boyut göstergesi.
  Widget _ekler(Renkler r) {
    final oran = _azamiEk > 0 ? (_ekToplam / _azamiEk).clamp(0.0, 1.0) : 0.0;
    final kartlar = <Widget>[
      for (final e in _yerel) _ekKarti(r, e.ad, icerikTuru(e.ad), e.boyut, () => setState(() => _yerel.remove(e))),
      for (final e in _dahil)
        _ekKarti(
          r,
          e.ad,
          e.tur,
          e.boyut,
          () => setState(() {
            _dahil.remove(e);
            _kirli = true;
          }),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6, right: 4),
            child: Row(
              children: [
                Icon(Simge.ek, size: 16, color: r.silik),
                const SizedBox(width: 4),
                Text(
                  '${kartlar.length} ek · ${boyutYaz(_ekToplam)}${_azamiEk > 0 ? ' / ${boyutYaz(_azamiEk)}' : ''}',
                  style: TextStyle(color: r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                if (_azamiEk > 0) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: oran,
                        minHeight: 5,
                        backgroundColor: r.ic,
                        color: oran > .9 ? Marka.gul : (oran > .75 ? Marka.kehribar : r.vurgu),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kartlar.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => kartlar[i],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ekKarti(Renkler r, String ad, String tur, int boyut, VoidCallback kaldir) {
    final renk = ekRengi(tur, ad);
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
      decoration: BoxDecoration(
        color: r.kart,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: r.kenar),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: renk.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
            child: Icon(ekSimgesi(tur, ad), color: renk, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.metin),
                ),
                Text(boyutYaz(boyut), style: TextStyle(fontSize: 11.5, color: r.silik)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Eki kaldır',
            icon: Icon(Simge.kapat, size: 18, color: r.silik),
            onPressed: kaldir,
          ),
        ],
      ),
    );
  }

  Widget _imzaKarti(Renkler r) {
    final kilitli = _ayar?.imzaKilitli ?? false;
    final metin = htmlMetne(_etkinImza);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Simge.imza, size: 17, color: r.silik),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  kilitli ? 'Kurum imzası' : 'İmza',
                  style: TextStyle(color: r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              Tooltip(
                message: kilitli ? 'İmza kurumunuz tarafından zorunlu tutuluyor' : (_imza ? 'İmzayı kaldır' : 'İmza ekle'),
                child: Switch.adaptive(
                  value: _bicimli ? ((_zengin?.imzaVar ?? false) || kilitli) : (_imza || kilitli),
                  onChanged: kilitli
                      ? null
                      : (v) {
                          // Biçimli: imza düzenleyicinin içindeki [data-signature] bloğudur (web toggleSignature).
                          if (_bicimli) {
                            _zengin?.imzaDegistir(_etkinImza);
                            return;
                          }
                          setState(() {
                            _imza = v;
                            _kirli = true;
                          });
                        },
                ),
              ),
            ],
          ),
          if (!_bicimli && (_imza || kilitli))
            Text(
              metin,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: r.soluk, fontSize: 13),
            ),
        ],
      ),
    );
  }

  Widget _alintiKarti(Renkler r) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
          shape: const RoundedRectangleBorder(),
          leading: Checkbox(
            value: _alinti,
            onChanged: (v) => setState(() {
              _alinti = v ?? true;
              _kirli = true;
            }),
          ),
          title: Text(b.tur == YazmaTuru.ilet ? 'İletilen ileti' : 'Alıntılanan ileti', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(_alinti ? 'İletinin altına eklenecek' : 'Eklenmeyecek', style: TextStyle(fontSize: 12, color: r.silik)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedAlignment: Alignment.topLeft,
          children: [
            Text(
              b.alintiMetin!,
              maxLines: 40,
              overflow: TextOverflow.fade,
              style: TextStyle(color: r.soluk, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
