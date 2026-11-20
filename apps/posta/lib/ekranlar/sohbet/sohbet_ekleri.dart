import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ortak/ek_listesi.dart';
import '../../ortak/simgeler.dart';
import '../../veri/sohbet_servisi.dart';
import '../../veri/yardimci.dart';

/// Küçük resim önbelleği (oturum boyunca; çerezli indirme gerektiğinden Image.network kullanılamaz).
final _kucukler = <String, Future<Uint8List>>{};

Future<Uint8List> _kucukResim(SohbetEki e) => _kucukler.putIfAbsent(e.kucukUrl ?? e.url, () => Sohbet.ekIndir(e.kucukUrl ?? e.url));

/// Mesajdaki ekler: resimler küçük resim olarak, diğerleri dosya kartı olarak.
class SohbetEkleri extends StatelessWidget {
  const SohbetEkleri({super.key, required this.ekler, this.benim = false});
  final List<SohbetEki> ekler;
  final bool benim;

  @override
  Widget build(BuildContext context) {
    final resimler = ekler.where((e) => e.resim && e.kucukUrl != null).toList();
    final dosyalar = ekler.where((e) => !(e.resim && e.kucukUrl != null)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (resimler.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final e in resimler) SohbetResmi(ek: e, boyut: resimler.length == 1 ? 220 : 120)],
            ),
          ),
        for (final e in dosyalar)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: SohbetDosyasi(ek: e, benim: benim),
          ),
      ],
    );
  }
}

class SohbetResmi extends StatelessWidget {
  const SohbetResmi({super.key, required this.ek, this.boyut = 160});
  final SohbetEki ek;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Semantics(
      button: true,
      label: 'Resim: ${ek.ad}. Büyütmek için dokunun.',
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => ResimGorunumu(ek: ek))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: boyut,
            height: boyut * .75,
            color: r.ic,
            child: FutureBuilder<Uint8List>(
              future: _kucukResim(ek),
              builder: (_, s) {
                if (s.hasData) return Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true);
                if (s.hasError) return Icon(Simge.bozukGorsel, color: r.silik);
                return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Tam ekran resim: yakınlaştırma, paylaş / kaydet.
class ResimGorunumu extends StatelessWidget {
  const ResimGorunumu({super.key, required this.ek});
  final SohbetEki ek;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(ek.ad, style: const TextStyle(color: Colors.white, fontSize: 15)),
      actions: [IconButton(tooltip: 'Paylaş / kaydet', icon: const Icon(Simge.paylas), onPressed: () => sohbetEkiPaylas(ek))],
    ),
    body: FutureBuilder<Uint8List>(
      future: Sohbet.ekIndir(ek.url),
      builder: (_, s) {
        if (s.hasError) return const Durum.hata('Resim yüklenemedi.');
        if (!s.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
        return InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(s.data!)));
      },
    ),
  );
}

bool get _masaustu => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

Future<File> _dosya(SohbetEki ek, {void Function(int, int)? ilerleme}) async {
  final dizin = await getTemporaryDirectory();
  final d = Directory('${dizin.path}/sohbet/${ek.id}');
  final f = File('${d.path}/${guvenliDosyaAdi(ek.ad.isEmpty ? 'dosya' : ek.ad)}');
  if (await f.exists() && await f.length() > 0) return f;
  final b = await Sohbet.ekIndir(ek.url, ilerleme: ilerleme);
  await d.create(recursive: true);
  await f.writeAsBytes(b, flush: true);
  return f;
}

Future<void> sohbetEkiAc(SohbetEki ek, {void Function(int, int)? ilerleme}) async {
  try {
    final f = await _dosya(ek, ilerleme: ilerleme);
    if (_masaustu) {
      if (!await launchUrl(Uri.file(f.path))) bildir('Dosya açılamadı', tur: MesajTur.uyari);
      return;
    }
    final r = await OpenFilex.open(f.path, type: ek.tur.isEmpty ? null : ek.tur);
    if (r.type == ResultType.noAppToOpen) bildir('Dosya açılamadı', mesaj: 'Bu türü açacak uygulama yok; Paylaş ile gönderebilirsiniz.', tur: MesajTur.uyari);
  } catch (e) {
    bildir('Ek indirilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
  }
}

Future<void> sohbetEkiPaylas(SohbetEki ek) async {
  try {
    if (_masaustu) {
      final b = await Sohbet.ekIndir(ek.url);
      final u = await FilePicker.saveFile(fileName: guvenliDosyaAdi(ek.ad), bytes: b, dialogTitle: 'Eki kaydet');
      if (u != null) bildir('Ek kaydedildi', tur: MesajTur.basari);
      return;
    }
    final f = await _dosya(ek);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: ek.tur.isEmpty ? null : ek.tur)]));
  } catch (e) {
    bildir('Paylaşılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
  }
}

/// Dosya kartı: aç (dokun), paylaş/kaydet (menü), indirme ilerlemesi.
class SohbetDosyasi extends StatefulWidget {
  const SohbetDosyasi({super.key, required this.ek, this.benim = false});
  final SohbetEki ek;
  final bool benim;
  @override
  State<SohbetDosyasi> createState() => _SohbetDosyasiState();
}

class _SohbetDosyasiState extends State<SohbetDosyasi> {
  double? _ilerleme;

  Future<void> _ac() async {
    if (_ilerleme != null) return;
    setState(() => _ilerleme = 0);
    await sohbetEkiAc(
      widget.ek,
      ilerleme: (a, t) {
        if (mounted && t > 0) setState(() => _ilerleme = a / t);
      },
    );
    if (mounted) setState(() => _ilerleme = null);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final e = widget.ek;
    final renk = ekRengi(e.tur, e.ad);
    final yazi = widget.benim ? Colors.white : r.metin;
    return Material(
      color: widget.benim ? Colors.white.withValues(alpha: .16) : r.ic,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _ac,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280, minWidth: 180),
          padding: const EdgeInsets.fromLTRB(8, 6, 0, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: (widget.benim ? Colors.white : renk).withValues(alpha: .18), borderRadius: BorderRadius.circular(9)),
                child: _ilerleme != null
                    ? Padding(
                        padding: const EdgeInsets.all(8),
                        child: CircularProgressIndicator(strokeWidth: 2.4, value: _ilerleme == 0 ? null : _ilerleme, color: widget.benim ? Colors.white : renk),
                      )
                    : Icon(ekSimgesi(e.tur, e.ad), color: widget.benim ? Colors.white : renk, size: 20),
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
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: yazi),
                    ),
                    Text(boyutYaz(e.boyut), style: TextStyle(fontSize: 11.5, color: yazi.withValues(alpha: .7))),
                  ],
                ),
              ),
              IconButton(
                tooltip: _masaustu ? 'Kaydet' : 'Paylaş / kaydet',
                visualDensity: VisualDensity.compact,
                icon: Icon(_masaustu ? Simge.indir : Simge.paylas, size: 18, color: yazi.withValues(alpha: .8)),
                onPressed: () => sohbetEkiPaylas(e),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tepki hapları: emoji + sayı; benimki vurgulu; dokununca aç/kapat; adlar ipucunda.
class TepkiHaplari extends StatelessWidget {
  const TepkiHaplari({super.key, required this.tepkiler, required this.degistir, this.ekle});
  final List<Tepki> tepkiler;
  final ValueChanged<String> degistir;
  final VoidCallback? ekle;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final t in tepkiler)
          Tooltip(
            message: t.adlar.isEmpty ? t.emoji : '${t.adlar.join(', ')}${t.sayi > t.adlar.length ? ' ve ${t.sayi - t.adlar.length} kişi' : ''}',
            child: Material(
              color: t.benim ? r.vurguYumusak : r.kart,
              shape: StadiumBorder(side: BorderSide(color: t.benim ? r.vurgu : r.kenar)),
              child: InkWell(
                key: ValueKey('tepki-${t.emoji}'),
                customBorder: const StadiumBorder(),
                onTap: () => degistir(t.emoji),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  child: Text(
                    '${t.emoji} ${t.sayi}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.benim ? r.vurgu : r.soluk),
                  ),
                ),
              ),
            ),
          ),
        if (ekle != null && tepkiler.isNotEmpty)
          Material(
            color: r.kart,
            shape: StadiumBorder(side: BorderSide(color: r.kenar)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: ekle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Icon(Simge.tepkiEkle, size: 16, color: r.silik),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tüm emojiler ızgarası; seçileni döndürür.
Future<String?> tepkiSec(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 8,
        children: [
          for (final e in tumTepkiler)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(c, e),
              child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
            ),
        ],
      ),
    ),
  ),
);
