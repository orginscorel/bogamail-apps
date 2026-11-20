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
import '../ortak/izin.dart';
import '../ortak/simgeler.dart';
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
    final boy = MediaQuery.sizeOf(context).height;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 820,
          height: min(800.0, boy - 48),
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
    for (final c in [_konu, _metin]) {
      c.addListener(_degisti);
    }
    if (_ayar == null) PostaDurum.ben.ayarlariYukle().then((_) => mounted ? setState(() {}) : null);
    if (b.kime.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _metinOdak.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final d in [_kime, _bilgi, _gizli]) {
      d.dispose();
    }
    _konu.dispose();
    _metin.dispose();
    _metinOdak.dispose();
    super.dispose();
  }

  void _degisti() {
    if (!_kirli && mounted) setState(() => _kirli = true);
  }

  bool get _icerikVar =>
      !_kime.bos ||
      !_bilgi.bos ||
      !_gizli.bos ||
      _konu.text.trim().isNotEmpty ||
      _metin.text.trim().isNotEmpty ||
      _yerel.isNotEmpty ||
      (_dahil.isNotEmpty && b.tur != YazmaTuru.ilet);

  // ---- istek ----

  Future<Map<String, dynamic>> _istek() async {
    final k = _kime.topla().liste, c = _bilgi.topla().liste, g = _gizli.topla().liste;
    final taslak = b.tur == YazmaTuru.taslak;
    final govde = govdeOlustur(
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
      try {
        final r = await _istek();
        if (dlpOnay) r['dlp_confirm'] = true;
        if (zaman != null) r['send_at'] = zaman.toUtc().toIso8601String();
        final s = await Posta.gonder(
          r,
          ilerleme: (a, t) {
            if (mounted && t > 0) setState(() => _ilerleme = a / t);
          },
        );
        _bitti = true;
        PostaDurum.ben.sayilariYenile();
        if (mounted) Navigator.of(context).pop();
        _sonucBildir(s, zaman);
        return;
      } on GonderimHatasi catch (e) {
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
        icon: Icon(d.engel ? Icons.block_rounded : Icons.privacy_tip_outlined, color: d.engel ? Marka.gul : Marka.kehribar, size: 32),
        title: Text(d.engel ? 'İleti gönderilemez' : 'Hassas bilgi uyarısı', style: gosterim(19, agirlik: FontWeight.w700)),
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
    if (_konu.text.trim().isEmpty && _metin.text.trim().isEmpty) {
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
                child: Text('Şablon ekle', style: gosterim(17, agirlik: FontWeight.w700)),
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
                        leading: const Icon(Icons.description_outlined),
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
              child: Text('Yanıt gelmezse hatırlat', style: gosterim(17, agirlik: FontWeight.w700)),
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
                leading: Icon(
                  s.$1 == _takipGun ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: s.$1 == _takipGun ? c.r.vurgu : null,
                ),
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
              child: Text('Kaydedilmemiş değişiklikler var', style: gosterim(17, agirlik: FontWeight.w700)),
            ),
            ListTile(leading: const Icon(Icons.save_outlined), title: const Text('Taslak olarak kaydet'), onTap: () => Navigator.pop(c, 1)),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Marka.gul),
              title: Text(_acilanTaslak ? 'Değişiklikleri at' : 'İletiyi sil', style: const TextStyle(color: Marka.gul)),
              onTap: () => Navigator.pop(c, 2),
            ),
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Yazmaya devam et'), onTap: () => Navigator.pop(c, 0)),
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
            ListTile(leading: const Icon(Icons.attach_file_rounded), title: const Text('Dosya seç'), onTap: () => Navigator.pop(c, 'dosya')),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Fotoğraf/Video galerisi'), onTap: () => Navigator.pop(c, 'galeri')),
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Kamerayla fotoğraf çek'), onTap: () => Navigator.pop(c, 'foto')),
            ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Kamerayla video çek'), onTap: () => Navigator.pop(c, 'video')),
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
            leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Kapat', onPressed: _kapat),
            title: Text(b.baslik),
            actions: [
              IconButton(icon: const Icon(Icons.attach_file_rounded), tooltip: 'Dosya ekle', onPressed: _mesgul ? null : _ekSec),
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
                    child: ListTile(leading: Icon(Icons.save_outlined), title: Text('Taslağı kaydet')),
                  ),
                  const PopupMenuItem(
                    value: 'planla',
                    child: ListTile(leading: Icon(Icons.schedule_send_outlined), title: Text('Daha sonra gönder…')),
                  ),
                  const PopupMenuItem(
                    value: 'sablonEkle',
                    child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Şablon ekle…')),
                  ),
                  const PopupMenuItem(
                    value: 'sablonKaydet',
                    child: ListTile(leading: Icon(Icons.save_as_outlined), title: Text('Şablon olarak kaydet')),
                  ),
                  PopupMenuItem(
                    value: 'takip',
                    child: ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(_takipGun > 0 ? 'Yanıt gelmezse hatırlat: $_takipGun gün' : 'Yanıt gelmezse hatırlat…'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  CheckedPopupMenuItem(value: 'oncelik', checked: _oncelik == 'high', child: const Text('Yüksek öncelik')),
                  CheckedPopupMenuItem(value: 'okundu', checked: _okunduBilgisi, child: const Text('Okundu bilgisi iste')),
                  if (_taslakId != null)
                    const PopupMenuItem(
                      value: 'sil',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: Marka.gul),
                        title: Text('Taslağı sil'),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, left: 4),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: _mesgul ? null : _gonder,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Gönder'),
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
                        const Icon(Icons.error_outline_rounded, color: Marka.gul, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13.5)),
                        ),
                        IconButton(icon: const Icon(Icons.close_rounded, size: 18), tooltip: 'Kapat', onPressed: () => setState(() => _hata = null)),
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
                      Expanded(
                        child: Text(
                          kimden.isEmpty ? adres : '$kimden <$adres>',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.soluk, fontSize: 14),
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
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
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
                        if (_oncelik == 'high') const Rozet('Yüksek öncelik', renk: Marka.gul, ikon: Icons.priority_high_rounded),
                        if (_okunduBilgisi) const Rozet('Okundu bilgisi istenecek', ikon: Icons.mark_email_read_outlined),
                      ],
                    ),
                  ),
                if (b.htmlTaslak)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Text(
                      'Bu taslak biçimlendirilmiş metin içeriyor; uygulamada düz metin olarak düzenlenir.',
                      style: TextStyle(color: r.silik, fontSize: 12.5),
                    ),
                  ),
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
                if (b.alintiMetin != null && b.alintiMetin!.isNotEmpty) _alintiKarti(r),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ekler(Renkler r) {
    final limit = _azamiEk > 0 ? ' / ${boyutYaz(_azamiEk)}' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'Ekler · ${boyutYaz(_ekToplam)}$limit',
              style: TextStyle(color: r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _yerel) _ekCipi(r, e.ad, icerikTuru(e.ad), e.boyut, () => setState(() => _yerel.remove(e))),
              for (final e in _dahil)
                _ekCipi(
                  r,
                  e.ad,
                  e.tur,
                  e.boyut,
                  () => setState(() {
                    _dahil.remove(e);
                    _kirli = true;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ekCipi(Renkler r, String ad, String tur, int boyut, VoidCallback kaldir) => InputChip(
    avatar: Icon(ekSimgesi(tur, ad), size: 18, color: r.birincil),
    label: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text('$ad · ${boyutYaz(boyut)}', overflow: TextOverflow.ellipsis),
    ),
    deleteButtonTooltipMessage: 'Eki kaldır',
    onDeleted: kaldir,
  );

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
              Icon(Icons.draw_outlined, size: 17, color: r.silik),
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
                  value: _imza || kilitli,
                  onChanged: kilitli
                      ? null
                      : (v) => setState(() {
                          _imza = v;
                          _kirli = true;
                        }),
                ),
              ),
            ],
          ),
          if (_imza || kilitli)
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
