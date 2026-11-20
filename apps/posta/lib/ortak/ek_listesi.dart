import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';
import 'simgeler.dart';

bool get _masaustu => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// İletinin dosya ekleri: dokununca indirip açar; menüden paylaş / kaydet.
typedef EkIndirici = Future<Uint8List> Function(int sira, {void Function(int, int)? ilerleme});

class EkListesi extends StatelessWidget {
  const EkListesi({super.key, required this.iletiId, required this.ekler, this.indir});
  final String iletiId;
  final List<Ek> ekler;

  /// Ek indirme (varsayılan: oturumdaki hesabın ileti eki; birleşik görünümde başka hesabın eki).
  final EkIndirici? indir;

  @override
  Widget build(BuildContext context) {
    if (ekler.isEmpty) return const SizedBox.shrink();
    final toplam = ekler.fold<int>(0, (a, e) => a + e.boyut);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Simge.ek, size: 16, color: context.r.silik),
              const SizedBox(width: 4),
              Text(
                '${ekler.length} ek · ${boyutYaz(toplam)}',
                style: TextStyle(color: context.r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final e in ekler) _EkKarti(iletiId: iletiId, ek: e, indir: indir)],
        ),
      ],
    );
  }
}

/// Sıkı ek şeridi (konuşma görünümü): tek satır, yatay kayar; görseller 64 px küçük resim, diğerleri tür simgeli
/// küçük hap (ad kısaltılır, boyut). Gövdeyi aşağı itmez.
class EkSeridi extends StatelessWidget {
  const EkSeridi({super.key, required this.iletiId, required this.ekler, this.indir});
  final String iletiId;
  final List<Ek> ekler;
  final EkIndirici? indir;

  static bool gorselMi(Ek e) => e.tur.toLowerCase().startsWith('image/') && !e.tur.toLowerCase().contains('svg');

  @override
  Widget build(BuildContext context) {
    if (ekler.isEmpty) return const SizedBox.shrink();
    final gorselVar = ekler.any(gorselMi);
    return SizedBox(
      height: gorselVar ? 64 : 40,
      child: ListView.separated(
        key: const ValueKey('ek-seridi'),
        scrollDirection: Axis.horizontal,
        itemCount: ekler.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(
          child: _EkKarti(iletiId: iletiId, ek: ekler[i], indir: indir, kompakt: true),
        ),
      ),
    );
  }
}

/// Tüm ekleri indirir: masaüstünde seçilen klasöre kaydeder, telefonda paylaşım sayfasıyla (Dosyalara kaydet vb.).
Future<void> tumEkleriIndir(String iletiId, List<Ek> ekler, {EkIndirici? indir}) async {
  if (ekler.isEmpty) return;
  Future<Uint8List> al(Ek e) => (indir ?? (int sira, {void Function(int, int)? ilerleme}) => Posta.ekIndir(iletiId, sira))(e.sira);
  try {
    if (_masaustu) {
      final u = await FilePicker.pickDirectory(dialogTitle: 'Eklerin kaydedileceği klasör');
      final klasor = u == null ? null : (u.scheme == 'file' ? u.toFilePath() : u.path);
      if (klasor == null) return;
      for (final e in ekler) {
        await File('$klasor/${guvenliDosyaAdi(e.ad)}').writeAsBytes(await al(e), flush: true);
      }
      bildir('${ekler.length} ek kaydedildi', tur: MesajTur.basari);
      return;
    }
    final dizin = await getTemporaryDirectory();
    final d = Directory('${dizin.path}/ekler/${iletiId}_tumu');
    await d.create(recursive: true);
    final dosyalar = <XFile>[];
    for (final e in ekler) {
      final f = File('${d.path}/${guvenliDosyaAdi(e.ad)}');
      if (!await f.exists() || await f.length() == 0) await f.writeAsBytes(await al(e), flush: true);
      dosyalar.add(XFile(f.path, mimeType: e.tur.isEmpty ? null : e.tur));
    }
    await SharePlus.instance.share(ShareParams(files: dosyalar));
  } catch (e) {
    bildir('Ekler indirilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
  }
}

/// Küçük resim önbelleği (bellek, en çok 48 görsel).
final _kucukResimler = <String, Uint8List>{};

class _EkKarti extends StatefulWidget {
  const _EkKarti({required this.iletiId, required this.ek, this.indir, this.kompakt = false});
  final String iletiId;
  final Ek ek;
  final EkIndirici? indir;
  final bool kompakt;
  @override
  State<_EkKarti> createState() => _EkKartiState();
}

class _EkKartiState extends State<_EkKarti> {
  double? _ilerleme;
  final _menuAnahtari = GlobalKey();
  Uint8List? _kucuk;

  String get _kucukAnahtar => '${widget.iletiId}/${widget.ek.sira}';

  @override
  void initState() {
    super.initState();
    if (widget.kompakt && EkSeridi.gorselMi(widget.ek) && widget.ek.boyut <= 4 * 1024 * 1024) {
      _kucuk = _kucukResimler[_kucukAnahtar];
      if (_kucuk == null) _kucukYukle();
    }
  }

  Future<void> _kucukYukle() async {
    try {
      final b = await (widget.indir ?? (int sira, {void Function(int, int)? ilerleme}) => Posta.ekIndir(widget.iletiId, sira))(widget.ek.sira);
      if (_kucukResimler.length >= 48) _kucukResimler.remove(_kucukResimler.keys.first);
      _kucukResimler[_kucukAnahtar] = b;
      if (mounted) setState(() => _kucuk = b);
    } catch (_) {}
  }

  void _menuAc(Offset konum) async {
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(konum.dx, konum.dy, konum.dx, konum.dy),
      items: [
        const PopupMenuItem(value: 0, child: Text('Aç')),
        const PopupMenuItem(value: 1, child: Text('Paylaş')),
        PopupMenuItem(value: 2, child: Text(_masaustu ? 'Farklı kaydet…' : 'Dosyalara kaydet')),
      ],
    );
    switch (v) {
      case 0:
        await _ac();
      case 1:
        await _paylas();
      case 2:
        await _kaydet();
    }
  }

  Widget _kompakt(BuildContext context) {
    final r = context.r;
    final e = widget.ek;
    final renk = ekRengi(e.tur, e.ad);
    final ilerleme = _ilerleme != null
        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, value: _ilerleme == 0 ? null : _ilerleme))
        : null;
    final Widget icerik;
    if (EkSeridi.gorselMi(e)) {
      icerik = SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_kucuk != null)
              Image.memory(
                _kucuk!,
                fit: BoxFit.cover,
                cacheWidth: 192,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => Icon(Simge.gorsel, color: renk),
              )
            else
              Container(
                color: renk.withValues(alpha: .1),
                child: Icon(Simge.gorsel, color: renk, size: 22),
              ),
            ?(ilerleme == null ? null : Center(child: ilerleme)),
          ],
        ),
      );
    } else {
      icerik = Container(
        height: 36,
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.only(left: 8, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ilerleme ?? Icon(ekSimgesi(e.tur, e.ad), color: renk, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                e.ad,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: r.metin),
              ),
            ),
            const SizedBox(width: 6),
            Text(boyutYaz(e.boyut), style: TextStyle(fontSize: 11.5, color: r.silik)),
          ],
        ),
      );
    }
    return Tooltip(
      message: '${e.ad} · ${boyutYaz(e.boyut)}',
      child: Semantics(
        button: true,
        label: 'Ek: ${e.ad}, ${boyutYaz(e.boyut)}. Açmak için dokunun.',
        child: Material(
          key: ValueKey('ek-${e.sira}'),
          color: r.kart,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: r.kenar),
          ),
          child: InkWell(onTap: _ac, onLongPress: _paylas, onSecondaryTapDown: (d) => _menuAc(d.globalPosition), child: icerik),
        ),
      ),
    );
  }

  Future<File> _dosya() async {
    final dizin = await getTemporaryDirectory();
    final d = Directory('${dizin.path}/ekler/${widget.iletiId}_${widget.ek.sira}');
    final f = File('${d.path}/${guvenliDosyaAdi(widget.ek.ad)}');
    if (await f.exists() && await f.length() > 0) return f;
    final b = await _indir();
    await d.create(recursive: true);
    await f.writeAsBytes(b, flush: true);
    return f;
  }

  Future<Uint8List> _indir() async {
    setState(() => _ilerleme = 0);
    try {
      return await (widget.indir ?? (int sira, {void Function(int, int)? ilerleme}) => Posta.ekIndir(widget.iletiId, sira, ilerleme: ilerleme))(
        widget.ek.sira,
        ilerleme: (a, t) {
          if (mounted && t > 0) setState(() => _ilerleme = a / t);
        },
      );
    } finally {
      if (mounted) setState(() => _ilerleme = null);
    }
  }

  Future<void> _ac() async {
    if (_ilerleme != null) return;
    try {
      final f = await _dosya();
      if (_masaustu) {
        if (!await launchUrl(Uri.file(f.path))) bildir('Dosya açılamadı', mesaj: 'Bu dosya türünü açacak bir uygulama bulunamadı.', tur: MesajTur.uyari);
        return;
      }
      final r = await OpenFilex.open(f.path, type: widget.ek.tur.isEmpty ? null : widget.ek.tur);
      if (r.type == ResultType.noAppToOpen) {
        bildir('Dosya açılamadı', mesaj: 'Bu dosya türünü açacak bir uygulama yok. Paylaş ile başka uygulamaya gönderebilirsiniz.', tur: MesajTur.uyari);
      } else if (r.type != ResultType.done) {
        bildir('Dosya açılamadı', tur: MesajTur.hata);
      }
    } catch (e) {
      bildir('Ek indirilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _paylas() async {
    if (_ilerleme != null) return;
    final kutu = _menuAnahtari.currentContext?.findRenderObject() as RenderBox?;
    final konum = kutu == null ? null : kutu.localToGlobal(Offset.zero) & kutu.size;
    try {
      final f = await _dosya();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: widget.ek.tur.isEmpty ? null : widget.ek.tur)],
          sharePositionOrigin: konum,
        ),
      );
    } catch (e) {
      bildir('Paylaşılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  Future<void> _kaydet() async {
    if (_ilerleme != null) return;
    try {
      final b = await _indir();
      final u = await FilePicker.saveFile(
        fileName: guvenliDosyaAdi(widget.ek.ad),
        bytes: b,
        mimeType: widget.ek.tur.isEmpty ? 'application/octet-stream' : widget.ek.tur,
        dialogTitle: 'Eki kaydet',
      );
      if (u != null) bildir('Ek kaydedildi', tur: MesajTur.basari);
    } catch (e) {
      bildir('Ek kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.kompakt) return _kompakt(context);
    final r = context.r;
    final e = widget.ek;
    return Semantics(
      button: true,
      label: 'Ek: ${e.ad}, ${boyutYaz(e.boyut)}. Açmak için dokunun.',
      child: Material(
        color: r.kart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: r.kenar),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _ac,
          onLongPress: _paylas,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280, minWidth: 180),
            padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: _ilerleme != null
                      ? Padding(
                          padding: const EdgeInsets.all(6),
                          child: CircularProgressIndicator(strokeWidth: 2.5, value: _ilerleme == 0 ? null : _ilerleme),
                        )
                      : Container(
                          decoration: BoxDecoration(color: ekRengi(e.tur, e.ad).withValues(alpha: .14), borderRadius: BorderRadius.circular(9)),
                          child: Icon(ekSimgesi(e.tur, e.ad), color: ekRengi(e.tur, e.ad), size: 20),
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        e.ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      Text(boyutYaz(e.boyut), style: TextStyle(fontSize: 11.5, color: r.silik)),
                    ],
                  ),
                ),
                PopupMenuButton<int>(
                  key: _menuAnahtari,
                  tooltip: 'Ek seçenekleri',
                  icon: Icon(Simge.dahaFazlaDikey, size: 20, color: r.silik),
                  onSelected: (v) => switch (v) {
                    0 => _ac(),
                    1 => _paylas(),
                    _ => _kaydet(),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 0,
                      child: ListTile(leading: Icon(Simge.disaAc), title: Text('Aç')),
                    ),
                    const PopupMenuItem(
                      value: 1,
                      child: ListTile(leading: Icon(Simge.paylas), title: Text('Paylaş')),
                    ),
                    PopupMenuItem(
                      value: 2,
                      child: ListTile(leading: const Icon(Simge.indir), title: Text(_masaustu ? 'Farklı kaydet…' : 'Dosyalara kaydet')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ek türüne göre renk (PDF kırmızı, tablo yeşil, belge mavi, görsel mor, arşiv turuncu).
Color ekRengi(String tur, String ad) {
  final a = ad.toLowerCase();
  final t = tur.toLowerCase();
  if (t.contains('pdf') || a.endsWith('.pdf')) return const Color(0xFFDC2626);
  if (RegExp(r'\.(xlsx?|csv|ods|xlsm)$').hasMatch(a) || t.contains('spreadsheet')) return const Color(0xFF16A34A);
  if (RegExp(r'\.(docx?|odt|rtf|txt|docm)$').hasMatch(a) || t.contains('word')) return const Color(0xFF2563EB);
  if (RegExp(r'\.(pptx?|odp|pptm)$').hasMatch(a) || t.contains('presentation')) return const Color(0xFFEA580C);
  if (t.startsWith('image/')) return const Color(0xFF9333EA);
  if (t.startsWith('video/') || t.startsWith('audio/')) return const Color(0xFFDB2777);
  if (RegExp(r'\.(zip|rar|7z|tar|gz)$').hasMatch(a)) return const Color(0xFFB45309);
  return const Color(0xFF64748B);
}
