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
class EkListesi extends StatelessWidget {
  const EkListesi({super.key, required this.iletiId, required this.ekler});
  final String iletiId;
  final List<Ek> ekler;

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
              Icon(Icons.attach_file_rounded, size: 16, color: context.r.silik),
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
          children: [for (final e in ekler) _EkKarti(iletiId: iletiId, ek: e)],
        ),
      ],
    );
  }
}

class _EkKarti extends StatefulWidget {
  const _EkKarti({required this.iletiId, required this.ek});
  final String iletiId;
  final Ek ek;
  @override
  State<_EkKarti> createState() => _EkKartiState();
}

class _EkKartiState extends State<_EkKarti> {
  double? _ilerleme;
  final _menuAnahtari = GlobalKey();

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
      return await Posta.ekIndir(
        widget.iletiId,
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
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: r.silik),
                  onSelected: (v) => switch (v) {
                    0 => _ac(),
                    1 => _paylas(),
                    _ => _kaydet(),
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 0,
                      child: ListTile(leading: Icon(Icons.open_in_new_rounded), title: Text('Aç')),
                    ),
                    const PopupMenuItem(
                      value: 1,
                      child: ListTile(leading: Icon(Icons.ios_share_rounded), title: Text('Paylaş')),
                    ),
                    PopupMenuItem(
                      value: 2,
                      child: ListTile(leading: const Icon(Icons.download_rounded), title: Text(_masaustu ? 'Farklı kaydet…' : 'Dosyalara kaydet')),
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
