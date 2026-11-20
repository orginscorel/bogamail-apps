import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import '../ortak/ek_listesi.dart';
import '../ortak/html_govde.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../ortak/simgeler.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/tercihler.dart';
import '../veri/yazma_hazirla.dart';
import '../veri/yardimci.dart';
import 'yazma.dart';

/// Telefonda okuyucuyu ayrı sayfa olarak açar.
Future<void> okuyucuAc(BuildContext context, String id) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (c) => Okuyucu(id: id, sayfa: true, kaldirildi: () => Navigator.of(c).maybePop()),
  ),
);

/// mailto: bağlantısından yeni ileti.
YazmaBaslangic mailtoBaslangic(Uri u) {
  final kime = adresListesiCoz(Uri.decodeComponent(u.path)).where((a) => gecerliEposta(a.eposta)).toList();
  final q = u.queryParameters;
  return YazmaBaslangic(
    kime: kime,
    bilgi: adresListesiCoz(q['cc'] ?? '').where((a) => gecerliEposta(a.eposta)).toList(),
    konu: q['subject'] ?? '',
    metin: q['body'] ?? '',
  );
}

class Okuyucu extends StatefulWidget {
  const Okuyucu({super.key, required this.id, this.sayfa = false, this.kaldirildi});
  final String id;

  /// true: kendi AppBar'ı olan tam sayfa (telefon); false: üç bölmeli görünümün sağ bölmesi.
  final bool sayfa;

  /// İleti bu görünümden çıktı (silindi, taşındı, okunmadı yapıldı…).
  final VoidCallback? kaldirildi;

  @override
  State<Okuyucu> createState() => OkuyucuState();
}

class OkuyucuState extends State<Okuyucu> {
  IletiDetay? _d;
  String? _hata;
  bool _mesgul = false;
  bool _gitti = false;
  bool _isaretlendi = false;
  bool _html = true;
  bool _ayrinti = false;
  bool _daralt = false;

  @override
  void initState() {
    super.initState();
    _yukle();
    PostaDurum.ben.surum.addListener(_canli);
  }

  @override
  void didUpdateWidget(Okuyucu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      setState(() {
        _d = null;
        _hata = null;
        _gitti = false;
        _isaretlendi = false;
        _html = true;
        _ayrinti = false;
        _daralt = false;
      });
      _yukle();
    }
  }

  @override
  void dispose() {
    PostaDurum.ben.surum.removeListener(_canli);
    super.dispose();
  }

  void _canli() {
    if (!_mesgul && !_gitti && _d != null) _yukle(sessiz: true);
  }

  Future<void> _yukle({bool sessiz = false}) async {
    if (!sessiz) setState(() => _hata = null);
    final id = widget.id;
    try {
      final d = await Posta.ileti(id);
      if (!mounted || id != widget.id) return;
      setState(() => _d = d);
      if (!d.ozet.okundu && !_isaretlendi) {
        _isaretlendi = true;
        try {
          await Posta.guncelle(widget.id, {'seen': true});
          d.ozet.okundu = true;
          PostaDurum.ben.sayilariYenile();
        } catch (_) {}
      }
    } on ApiHata catch (e) {
      if (!mounted || id != widget.id) return;
      if (sessiz && e.durum == 404) {
        _kaldir();
      } else if (!sessiz) {
        setState(() => _hata = e.durum == 404 ? 'İleti bulunamadı; silinmiş veya taşınmış olabilir.' : e.mesaj);
      }
    } catch (_) {
      if (mounted && !sessiz) setState(() => _hata = 'İleti açılamadı.');
    }
  }

  void _kaldir() {
    if (_gitti) return;
    _gitti = true;
    PostaDurum.ben.sayilariYenile();
    widget.kaldirildi?.call();
  }

  Future<void> _eylem(Future<void> Function() f, String tamam, {bool kaldir = false}) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await f();
      bildir(tamam, tur: MesajTur.basari);
      if (kaldir) {
        _kaldir();
      } else {
        PostaDurum.ben.sayilariYenile();
        await _yukle(sessiz: true);
      }
    } catch (e) {
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? get _rol => PostaDurum.ben.klasor(_d?.ozet.klasorId)?.rol ?? _d?.ozet.klasorRolu;
  bool get _taslak => _rol == 'drafts' || _rol == 'templates';

  // ---- dışarıdan çağrılan eylemler (klavye kısayolları) ----

  void yanitla({bool tumu = false}) {
    final d = _d;
    if (d == null || _taslak) return;
    yazmaAc(context, yanitHazirla(d, ben: Uyg.adres, tumu: tumu));
  }

  void ilet() {
    final d = _d;
    if (d == null) return;
    yazmaAc(context, iletHazirla(d));
  }

  Future<void> sil() async {
    final d = _d;
    if (d == null) return;
    final kalici = _rol == 'trash';
    if (kalici && !await onayla(context, 'Kalıcı olarak silinsin mi?', mesaj: 'Bu ileti geri getirilemez.', evet: 'Kalıcı sil', tehlikeli: true)) return;
    await _eylem(() => Posta.sil(d.ozet.id), kalici ? 'İleti kalıcı olarak silindi' : 'Çöp Kutusu\'na taşındı', kaldir: true);
  }

  Future<void> arsivle() => _eylem(() => Posta.toplu([widget.id], 'archive'), 'Arşivlendi', kaldir: true);

  Future<void> _tasi() async {
    final k = await klasorSec(context, haricId: _d?.ozet.klasorId);
    if (k == null) return;
    await _eylem(() => Posta.toplu([widget.id], 'move', klasorId: k.id), '${k.gorunenAd} klasörüne taşındı', kaldir: true);
  }

  Future<void> _etiketle() async {
    final d = _d;
    if (d == null) return;
    final s = await etiketSec(context, d.ozet.etiketler.toSet());
    if (s == null || (s.ekle.isEmpty && s.cikar.isEmpty)) return;
    await _eylem(() async {
      for (final e in s.ekle) {
        await Posta.guncelle(widget.id, {'add_label': e});
      }
      for (final e in s.cikar) {
        await Posta.guncelle(widget.id, {'remove_label': e});
      }
    }, 'Etiketler güncellendi');
  }

  Future<void> _ertele() async {
    final z = await ertelemeSec(context);
    if (z == null) return;
    await _eylem(() => Posta.guncelle(widget.id, {'snooze_until': z.toUtc().toIso8601String()}), 'İleti ertelendi', kaldir: true);
  }

  Future<void> _disaAktar() async {
    try {
      final b = await Uyg.api.indir('/api/v1/mail/messages/${widget.id}/raw');
      final ad = guvenliDosyaAdi('${(_d?.gorunum.konu ?? '').trim().isEmpty ? 'ileti' : _d!.gorunum.konu.trim()}.eml');
      final u = await FilePicker.saveFile(fileName: ad, bytes: b, mimeType: 'message/rfc822', dialogTitle: 'İletiyi kaydet');
      if (u != null) bildir('İleti kaydedildi', tur: MesajTur.basari);
    } catch (e) {
      bildir('İleti indirilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  void _menu(String v) {
    final d = _d!;
    switch (v) {
      case 'okunmadi':
        _eylem(() => Posta.guncelle(widget.id, {'seen': false}), 'Okunmadı olarak işaretlendi', kaldir: true);
      case 'yildiz':
        _eylem(() => Posta.guncelle(widget.id, {'flagged': !d.ozet.yildizli}), d.ozet.yildizli ? 'Yıldız kaldırıldı' : 'Yıldızlandı');
      case 'onemli':
        _eylem(() => Posta.guncelle(widget.id, {'important': !d.ozet.onemli}), d.ozet.onemli ? 'Önemli işareti kaldırıldı' : 'Önemli olarak işaretlendi');
      case 'tasi':
        _tasi();
      case 'etiket':
        _etiketle();
      case 'ertele':
        _ertele();
      case 'spam':
        _eylem(() => Posta.toplu([widget.id], 'spam'), 'Gereksiz olarak işaretlendi; gönderen engellendi', kaldir: true);
      case 'spamDegil':
        _eylem(() => Posta.toplu([widget.id], 'notspam'), 'Gelen Kutusu\'na taşındı; gönderen güvenilir listesine eklendi', kaldir: true);
      case 'yanitTumu':
        yanitla(tumu: true);
      case 'disa':
        _disaAktar();
      case 'duzenle':
        yazmaAc(context, taslakHazirla(d, taslakId: _rol == 'drafts' ? d.ozet.id : null));
    }
  }

  List<PopupMenuEntry<String>> _menuOgeleri() {
    final d = _d!;
    PopupMenuItem<String> o(String v, IconData i, String t) => PopupMenuItem(
      value: v,
      child: ListTile(leading: Icon(i), title: Text(t)),
    );
    return [
      if (!_taslak && !widget.sayfa) o('yanitTumu', Icons.reply_all_rounded, 'Tümünü yanıtla'),
      o('okunmadi', Icons.mark_email_unread_outlined, 'Okunmadı yap'),
      o('yildiz', d.ozet.yildizli ? Icons.star_rounded : Icons.star_border_rounded, d.ozet.yildizli ? 'Yıldızı kaldır' : 'Yıldızla'),
      o('onemli', Icons.label_important_outline_rounded, d.ozet.onemli ? 'Önemli değil' : 'Önemli olarak işaretle'),
      o('tasi', Icons.drive_file_move_outline, 'Taşı…'),
      o('etiket', Icons.label_outline_rounded, 'Etiketle…'),
      if (_rol != 'snoozed' && !_taslak && _rol != 'sent') o('ertele', Icons.snooze_rounded, 'Ertele…'),
      if (_rol == 'junk')
        o('spamDegil', Icons.thumb_up_alt_outlined, 'Gereksiz değil')
      else if (!_taslak && _rol != 'sent')
        o('spam', Icons.report_outlined, 'Gereksiz (spam)'),
      o('disa', Icons.download_rounded, 'İletiyi indir (.eml)'),
    ];
  }

  List<Widget> _eylemDugmeleri() {
    if (_d == null) return const [];
    return [
      if (_taslak) IconButton(icon: const Icon(Icons.edit_rounded), tooltip: 'Taslağı düzenle', onPressed: () => _menu('duzenle')),
      if (_rol != 'archive' && !_taslak) IconButton(icon: const Icon(Icons.archive_outlined), tooltip: 'Arşivle', onPressed: _mesgul ? null : arsivle),
      IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: _rol == 'trash' ? 'Kalıcı sil' : 'Sil', onPressed: _mesgul ? null : sil),
      if (!widget.sayfa && !_taslak) ...[
        IconButton(icon: const Icon(Icons.reply_rounded), tooltip: 'Yanıtla (R)', onPressed: yanitla),
        IconButton(icon: const Icon(Icons.forward_rounded), tooltip: 'İlet', onPressed: ilet),
      ],
      PopupMenuButton<String>(tooltip: 'Diğer işlemler', onSelected: _menu, itemBuilder: (_) => _menuOgeleri()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final govde = _govde();
    if (widget.sayfa) {
      return Scaffold(
        appBar: AppBar(
          actions: _eylemDugmeleri(),
          bottom: _mesgul ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        ),
        body: SafeArea(top: false, child: govde),
      );
    }
    return Material(
      color: context.r.kart,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 8),
                if (_d != null) Expanded(child: _klasorRozeti()) else const Spacer(),
                ..._eylemDugmeleri(),
                const SizedBox(width: 6),
              ],
            ),
          ),
          if (_mesgul) const LinearProgressIndicator(minHeight: 2) else const Divider(),
          Expanded(child: govde),
        ],
      ),
    );
  }

  Widget _klasorRozeti() {
    final k = PostaDurum.ben.klasor(_d!.ozet.klasorId);
    if (k == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Rozet(k.gorunenAd, ikon: klasorSimgesi(k.rol)),
    );
  }

  Widget _govde() {
    if (_hata != null) return Durum.hata(_hata!, tekrar: _yukle);
    final d = _d;
    if (d == null) return const OkuyucuIskeleti();
    final v = d.gorunum;
    final htmlVar = v.html.trim().isNotEmpty;
    final htmlGoster = htmlVar && (_html || v.metin.trim().isEmpty);
    final tehlikeli = _rol == 'junk' || d.tehditler.isNotEmpty;
    final ust = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _baslik(d),
        for (final t in d.tehditler) _uyari(t, Marka.gul, Icons.gpp_maybe_outlined),
        if (_rol == 'junk')
          _uyari('Bu ileti gereksiz (spam) olarak sınıflandırıldı. Bağlantılara ve eklere dikkat edin.', Marka.kehribar, Icons.report_outlined),
        if (v.kesik) _uyari('İleti çok uzun olduğu için kısaltıldı. Tamamı için iletiyi indirin.', Marka.kehribar, Icons.content_cut_rounded),
        if (htmlVar && v.metin.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: true, label: Text('Biçimli')),
                  ButtonSegment(value: false, label: Text('Düz metin')),
                ],
                selected: {htmlGoster},
                onSelectionChanged: (s) => setState(() => _html = s.first),
              ),
            ),
          ),
        if (v.dosyaEkleri.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: EkListesi(iletiId: d.ozet.id, ekler: v.dosyaEkleri),
          ),
      ],
    );
    final alt = (!widget.sayfa || _taslak) ? null : _yanitCubugu();
    if (htmlGoster) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _daralt
                ? _darBaslik(d)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5),
                    child: SingleChildScrollView(child: ust),
                  ),
          ),
          const Divider(),
          Expanded(
            child: HtmlGovde(
              key: ValueKey('${d.ozet.id}-html'),
              iletiId: d.ozet.id,
              html: v.html,
              ekler: v.ekler,
              baglantilar: d.baglantilar,
              otomatikGorsel: Tercihler.uzakGorseller.value && !tehlikeli,
              kaydirma: (y) {
                final dar = y > 120;
                if (dar != _daralt && mounted) setState(() => _daralt = dar);
              },
              epostaBaglantisi: (u) => yazmaAc(context, mailtoBaslangic(u)),
            ),
          ),
          ?alt,
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _yukle(sessiz: true),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                ust,
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: v.metin.trim().isEmpty
                      ? Text('(Bu iletinin gövdesi boş.)', style: TextStyle(color: context.r.silik))
                      : _DuzMetin(metin: v.metin, baglantilar: d.baglantilar, eposta: (u) => yazmaAc(context, mailtoBaslangic(u))),
                ),
              ],
            ),
          ),
        ),
        ?alt,
      ],
    );
  }

  Widget _uyari(String metin, Color renk, IconData ikon) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: renk.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: renk.withValues(alpha: .3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(ikon, color: renk, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(metin, style: TextStyle(fontSize: 13, color: context.r.metin)),
        ),
      ],
    ),
  );

  Widget _darBaslik(IletiDetay d) => InkWell(
    onTap: () => setState(() => _daralt = false),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              d.gorunum.konu.isEmpty ? '(konu yok)' : d.gorunum.konu,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gosterim(16, agirlik: FontWeight.w700),
            ),
          ),
          Icon(Icons.expand_more_rounded, color: context.r.silik),
        ],
      ),
    ),
  );

  Widget _baslik(IletiDetay d) {
    final r = context.r;
    final v = d.gorunum;
    final gonderen = v.kimden.isNotEmpty ? v.kimden.first : adresCoz(d.ozet.kimden);
    final tarih = v.tarih ?? d.ozet.tarih;
    final etiketler = d.ozet.etiketler.map(PostaDurum.ben.etiket).whereType<Etiket>().toList();
    final alicilar = [...v.kime, ...v.bilgi].map((a) => a.eposta.toLowerCase() == Uyg.adres.toLowerCase() ? 'bana' : a.gorunen).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(v.konu.isEmpty ? '(konu yok)' : v.konu, style: gosterim(21, agirlik: FontWeight.w700, satir: 1.25)),
              ),
              IconButton(
                tooltip: d.ozet.yildizli ? 'Yıldızı kaldır' : 'Yıldızla',
                onPressed: _mesgul ? null : () => _menu('yildiz'),
                icon: Icon(d.ozet.yildizli ? Icons.star_rounded : Icons.star_border_rounded, color: d.ozet.yildizli ? Marka.kehribar : r.silik),
              ),
            ],
          ),
          if (etiketler.isNotEmpty || d.ozet.onemli)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (d.ozet.onemli) const Rozet('Önemli', renk: Marka.kehribar, ikon: Icons.label_important_rounded),
                  for (final e in etiketler) Rozet(e.ad, renk: etiketRengi(e.renk), ikon: Icons.label_rounded),
                ],
              ),
            ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _ayrinti = !_ayrinti),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Avatar(gonderen.gorunen, boyut: 42, tohum: gonderen.eposta),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                gonderen.gorunen,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: tamZaman(tarih),
                              child: Text(kisaZaman(tarih), style: TextStyle(color: r.silik, fontSize: 12.5)),
                            ),
                          ],
                        ),
                        if (gonderen.ad.isNotEmpty)
                          Text(
                            gonderen.eposta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.soluk, fontSize: 13),
                          ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Alıcı: ${alicilar.isEmpty ? '—' : alicilar}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: r.silik, fontSize: 12.5),
                              ),
                            ),
                            Icon(_ayrinti ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: r.silik),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_ayrinti)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _satir('Kimden', v.kimden.map(adresYaz).join(', ')),
                  _satir('Kime', v.kime.map(adresYaz).join(', ')),
                  if (v.bilgi.isNotEmpty) _satir('Bilgi', v.bilgi.map(adresYaz).join(', ')),
                  if (v.yanitAdresi.isNotEmpty) _satir('Yanıt', v.yanitAdresi.map(adresYaz).join(', ')),
                  _satir('Tarih', tamZaman(tarih)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _satir(String e, String d) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(e, style: TextStyle(color: context.r.silik, fontSize: 12.5)),
        ),
        Expanded(child: SelectableText(d.isEmpty ? '—' : d, style: const TextStyle(fontSize: 12.5))),
      ],
    ),
  );

  Widget _yanitCubugu() {
    final r = context.r;
    Widget dugme(IconData i, String t, VoidCallback f) => Expanded(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 6)),
        onPressed: f,
        icon: Icon(i, size: 18),
        label: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          dugme(Icons.reply_rounded, 'Yanıtla', yanitla),
          const SizedBox(width: 8),
          dugme(Icons.reply_all_rounded, 'Tümünü', () => yanitla(tumu: true)),
          const SizedBox(width: 8),
          dugme(Icons.forward_rounded, 'İlet', ilet),
        ],
      ),
    );
  }
}

/// Düz metin gövdesi: bağlantılar tıklanabilir, alıntılanan geçmiş "•••" ile katlanır.
class _DuzMetin extends StatefulWidget {
  const _DuzMetin({required this.metin, required this.baglantilar, required this.eposta});
  final String metin;
  final Map<String, String> baglantilar;
  final ValueChanged<Uri> eposta;
  @override
  State<_DuzMetin> createState() => _DuzMetinState();
}

class _DuzMetinState extends State<_DuzMetin> {
  final _tanicilar = <TapGestureRecognizer>[];
  bool _alinti = false;
  static final _url = RegExp(r'''(https?://[^\s"'<>()]+|mailto:[^\s"'<>()]+)''', caseSensitive: false);

  @override
  void dispose() {
    for (final t in _tanicilar) {
      t.dispose();
    }
    super.dispose();
  }

  List<InlineSpan> _parcalar(String metin, Color renk) {
    final out = <InlineSpan>[];
    var son = 0;
    for (final m in _url.allMatches(metin)) {
      final url = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
      if (m.start > son) out.add(TextSpan(text: metin.substring(son, m.start)));
      final hedef = widget.baglantilar[url] ?? url;
      final t = TapGestureRecognizer()
        ..onTap = () {
          final u = Uri.tryParse(hedef.startsWith('/') ? '${Uyg.api.sunucu}$hedef' : hedef);
          if (u == null) return;
          if (u.scheme == 'mailto') {
            widget.eposta(u);
          } else {
            launchUrl(u, mode: LaunchMode.externalApplication);
          }
        };
      _tanicilar.add(t);
      out.add(
        TextSpan(
          text: url,
          style: TextStyle(color: renk, decoration: TextDecoration.underline),
          recognizer: t,
        ),
      );
      son = m.start + url.length;
    }
    if (son < metin.length) out.add(TextSpan(text: metin.substring(son)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _tanicilar) {
      t.dispose();
    }
    _tanicilar.clear();
    final r = context.r;
    final p = alintiAyir(widget.metin);
    final stil = TextStyle(fontSize: 15, height: 1.55, color: r.metin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText.rich(TextSpan(style: stil, children: _parcalar(p.ana, r.birincil))),
        if (p.alinti.isNotEmpty) ...[
          const SizedBox(height: 10),
          Tooltip(
            message: _alinti ? 'Önceki iletileri gizle' : 'Önceki iletileri göster',
            child: Material(
              color: r.ic,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _alinti = !_alinti),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Text(
                    '•••',
                    style: TextStyle(color: r.silik, fontWeight: FontWeight.w700, letterSpacing: 2),
                  ),
                ),
              ),
            ),
          ),
          if (_alinti)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: r.kenar, width: 2)),
              ),
              child: SelectableText.rich(
                TextSpan(
                  style: stil.copyWith(color: r.soluk),
                  children: _parcalar(p.alinti, r.birincil),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
