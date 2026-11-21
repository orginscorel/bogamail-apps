import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../oturum.dart';
import '../ortak/yazdir.dart';
import '../ortak/ek_listesi.dart';
import '../ortak/html_govde.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../ortak/simgeler.dart';
import '../veri/durum.dart';
import '../veri/hesap_servisi.dart';
import '../veri/modeller.dart';
import '../veri/onbellek.dart';
import '../veri/posta_servisi.dart';
import '../veri/tercihler.dart';
import '../veri/yazma_hazirla.dart';
import '../veri/yardimci.dart';
import 'gorevler/gorevler_ekrani.dart';
import 'konusma.dart';
import 'okuyucu_parcalari.dart';
import 'takvim/davet_karti.dart';
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
  const Okuyucu({super.key, required this.id, this.sayfa = false, this.kaldirildi, this.onceki, this.sonraki, this.geri});

  /// Okuma alanı Altta / Kapalı: araç çubuğunun başında geri oku (listeye dön; Esc de aynı).
  final VoidCallback? geri;
  final String id;

  /// true: kendi AppBar'ı olan tam sayfa (telefon); false: üç bölmeli görünümün sağ bölmesi.
  final bool sayfa;

  /// İleti bu görünümden çıktı (silindi, taşındı, okunmadı yapıldı…).
  final VoidCallback? kaldirildi;

  /// Listede önceki / sonraki ileti (web: K / J). null ise düğme pasif.
  final VoidCallback? onceki;
  final VoidCallback? sonraki;

  @override
  State<Okuyucu> createState() => OkuyucuState();
}

class OkuyucuState extends State<Okuyucu> {
  /// Ekranda açık ileti (öndeyken aynı iletinin bildirimi gösterilmez).
  static String? acikIleti;

  IletiDetay? _d;
  String? _hata;
  bool _mesgul = false;
  bool _gitti = false;
  bool _isaretlendi = false;
  bool _html = true;
  bool _ayrinti = false;

  /// Konuşmadaki iletiler (eskiden yeniye). 2+ ileti varsa konuşma görünümü kullanılır.
  List<IletiOzet>? _konusma;

  /// Masaüstü konuşma: gövdesi bölmede gösterilen (etkin) ileti; null → açılan ileti.
  String? _etkin;
  final _etkinDetaylar = <String, IletiDetay>{};

  /// Etkin iletinin ayrıntısı gelene kadar önceki gösterilir (boş bölme yok).
  IletiDetay? _sonEtkin;
  bool _oncekilerAcik = false;

  @override
  void initState() {
    super.initState();
    acikIleti = widget.id;
    _konusma = Posta.konusmaHemen(widget.id);
    _yukle();
    unawaited(_konusmaYukle());
    PostaDurum.ben.surum.addListener(_canli);
  }

  @override
  void didUpdateWidget(Okuyucu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      acikIleti = widget.id;
      setState(() {
        // Önyüklenmiş ileti bellekteyse ilk karede gösterilir (yükleniyor çarkı yok). Masaüstünde yoksa yenisi
        // gelene kadar önceki ileti görünür kalır (boş / beyaz bölme yok; üstte ince gösterge).
        _d = Posta.iletiHemen(widget.id) ?? (masaustuDuzeni ? _d : null);
        _hata = null;
        _gitti = false;
        _isaretlendi = false;
        _html = true;
        _ayrinti = false;
        _konusma = Posta.konusmaHemen(widget.id);
        _etkin = null;
        _etkinDetaylar.clear();
        _sonEtkin = null;
        _oncekilerAcik = false;
      });
      _yukle();
      unawaited(_konusmaYukle());
    }
  }

  @override
  void dispose() {
    if (acikIleti == widget.id) acikIleti = null;
    PostaDurum.ben.surum.removeListener(_canli);
    super.dispose();
  }

  /// Canlı tazeleme: yalnız bu ileti (ya da toplu/bilinmeyen bir değişiklik) için yeniden yüklenir.
  void _canli() {
    final x = PostaDurum.ben.sonDegisen;
    if (!_mesgul && !_gitti && _d != null && (x == null || x == widget.id)) _yukle(sessiz: true);
  }

  Future<void> _konusmaYukle() async {
    final id = widget.id;
    try {
      if (_konusma == null) {
        final o = await Posta.konusmaOnbellek(id).catchError((_) => null);
        if (o != null && mounted && id == widget.id && _konusma == null) setState(() => _konusma = o);
      }
      final l = await Posta.konusma(id);
      if (!mounted || id != widget.id) return;
      final eski = _konusma;
      // Konuşmayı sunucu kurar (otomatik postalar gruplanmaz; konu yedeği yalnız yanıtladığınız Re: dizileri).
      final degisti = eski == null || eski.length != l.length || !Iterable.generate(l.length).every((i) => eski[i].id == l[i].id);
      if (degisti) {
        setState(() => _konusma = l);
      }
    } catch (_) {
      // Konuşma alınamazsa tek ileti görünümü kalır.
    }
  }

  /// Okundu işareti iyimserdir: gösterimi bekletmez, ileti yeniden indirilmez (listeler yerinde güncellenir).
  void _okundu(IletiDetay d) {
    if (d.ozet.okundu || _isaretlendi) return;
    _isaretlendi = true;
    d.ozet.okundu = true;
    PostaDurum.ben.okunduIsaretle(d.ozet.id);
  }

  /// Önce önbellek (bellek → disk) anında gösterilir, ağdan gelen sürüm farklıysa yerine konur.
  Future<void> _yukle({bool sessiz = false}) async {
    final id = widget.id;
    final sw = Stopwatch()..start();
    if (!sessiz) {
      setState(() => _hata = null);
      final o = _d?.ozet.id == id ? _d : (Posta.iletiHemen(id) ?? await Posta.iletiOnbellek(id).catchError((_) => null));
      if (!mounted || id != widget.id) return;
      if (o != null) {
        zamanLogu('ileti (önbellek)', sw);
        if (!identical(o, _d)) setState(() => _d = o);
        _okundu(o);
      }
    }
    try {
      var degisti = true;
      final v = await Posta.iletiHam(id, degisti: (x) => degisti = x);
      if (!mounted || id != widget.id) return;
      zamanLogu('ileti (ağ)', sw);
      if (degisti || _d?.ozet.id != id) {
        final d = IletiDetay.json(v);
        if (_isaretlendi) d.ozet.okundu = true;
        setState(() => _d = d);
      }
      _okundu(_d!);
    } on ApiHata catch (e) {
      if (!mounted || id != widget.id) return;
      final buIleti = _d?.ozet.id == id;
      if ((sessiz || buIleti) && e.durum == 404) {
        _kaldir();
      } else if (!sessiz && !buIleti) {
        setState(() => _hata = e.durum == 404 ? 'İleti bulunamadı; silinmiş veya taşınmış olabilir.' : e.mesaj);
      }
    } catch (_) {
      // Ağ yoksa önbellekteki sürüm gösterilmeye devam eder.
      if (mounted && !sessiz && _d?.ozet.id != id && id == widget.id) setState(() => _hata = 'İleti açılamadı.');
    }
  }

  void _kaldir() {
    if (_gitti) return;
    _gitti = true;
    PostaDurum.ben.sayilariYenile();
    widget.kaldirildi?.call();
  }

  /// [yerel]: bayrak değişikliği (seen/flagged/important): önbellek ve listeler yerinde güncellenir, ileti
  /// yeniden indirilmez.
  Future<void> _eylem(Future<void> Function() f, String tamam, {bool kaldir = false, Map<String, dynamic>? yerel}) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await f();
      bildir(tamam, tur: MesajTur.basari);
      if (yerel != null) PostaDurum.ben.yerelGuncelle(widget.id, yerel);
      if (kaldir) {
        _kaldir();
      } else if (yerel != null) {
        final d = _d;
        if (d != null && mounted) {
          setState(() {
            if (yerel['flagged'] is bool) d.ozet.yildizli = yerel['flagged'] as bool;
            if (yerel['important'] is bool) d.ozet.onemli = yerel['important'] as bool;
          });
        }
        PostaDurum.ben.sayilariYenile(listeler: false);
      } else {
        PostaDurum.ben.sayilariYenile();
        await _yukle(sessiz: true);
        unawaited(_konusmaYukle());
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

  /// Yanıt / iletme hedefi: masaüstü konuşmada etkin ileti, yoksa açılan.
  IletiDetay? get _hedef => masaustuDuzeni && _konusmaVar ? (_etkinDetaylar[_etkin] ?? _sonEtkin ?? _d) : _d;

  void yanitla({bool tumu = false}) {
    final d = _hedef;
    if (d == null || _taslak) return;
    yazmaAc(context, yanitHazirla(d, ben: Uyg.adres, tumu: tumu));
  }

  void ilet() {
    final d = _hedef;
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

  Adres get _gonderen {
    final d = _d!;
    return d.gorunum.kimden.isNotEmpty ? d.gorunum.kimden.first : adresCoz(d.ozet.kimden);
  }

  Future<void> _engelle() async {
    final a = _gonderen.eposta;
    if (a.isEmpty) return;
    final alan = a.contains('@') ? '@${a.split('@').last}' : '';
    final sec = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Gönderen engellensin mi?', style: gosterim(17, agirlik: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Engellenen gönderenlerin yeni iletileri doğrudan Gereksiz klasörüne gider.', style: TextStyle(color: c.r.soluk)),
            ),
            ListTile(leading: const Icon(Simge.kisiYok), title: Text('Yalnızca $a'), onTap: () => Navigator.pop(c, a)),
            if (alan.length > 1) ListTile(leading: const Icon(Simge.alanYok), title: Text('Tüm $alan alan adı'), onTap: () => Navigator.pop(c, alan)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (sec == null) return;
    final ok = await islem(() async {
      await Hesap.gondericiEkle('block', sec);
      return true;
    }, tamam: '$sec engellendi');
    if (ok == true && _rol != 'junk' && mounted && await onayla(context, 'Bu ileti Gereksiz klasörüne taşınsın mı?', evet: 'Taşı')) {
      await _eylem(() => Posta.toplu([widget.id], 'move', klasorId: PostaDurum.ben.rolu('junk')?.id), 'Gereksiz klasörüne taşındı', kaldir: true);
    }
  }

  Future<void> _kisiyeEkle() async {
    final g = _gonderen;
    if (g.eposta.isEmpty) return;
    await islem(
      () => Hesap.kisiKaydet(Kisi(ad: g.ad, eposta: g.eposta)),
      tamam: '${g.gorunen} kişilerinize eklendi',
    );
  }

  Future<void> _oltaBildir() async {
    if (!await onayla(
      context,
      'Oltalama (phishing) olarak bildirilsin mi?',
      mesaj: 'İleti güvenlik ekibinize iletilir. Şüpheli bağlantılara tıklamayın, ekleri açmayın.',
      evet: 'Bildir',
      tehlikeli: true,
    )) {
      return;
    }
    final m = await islem(() => Hesap.oltaBildir(widget.id));
    if (m != null) bildir('Bildiriminiz alındı', mesaj: m.isEmpty ? null : m, tur: MesajTur.basari);
  }

  Future<void> _takip() async {
    final d = _d!;
    final gunler = [(1, 'Yarın'), (2, '2 gün sonra'), (3, '3 gün sonra'), (7, '1 hafta sonra'), (14, '2 hafta sonra')];
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Takip hatırlatıcısı', style: gosterim(17, agirlik: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Yanıt gelmezse ileti seçtiğiniz zamanda Gelen Kutusu\'nun en üstünde "Takip" işaretiyle yeniden görünür.',
                style: TextStyle(color: c.r.soluk),
              ),
            ),
            for (final g in gunler) ListTile(leading: const Icon(Simge.hatirlatma), title: Text(g.$2), onTap: () => Navigator.pop(c, g.$1)),
            if (d.ozet.takip)
              ListTile(
                leading: const Icon(Simge.bildirimKapali, color: Marka.gul),
                title: const Text('Hatırlatıcıyı kaldır'),
                onTap: () => Navigator.pop(c, 0),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (v == null) return;
    if (v == 0) {
      await _eylem(() => Hesap.takipKaldir(widget.id), 'Takip hatırlatıcısı kaldırıldı');
    } else {
      await _eylem(() => Hesap.takipKur(widget.id, v), 'Takip hatırlatıcısı kuruldu');
    }
  }

  void _menu(String v) {
    final d = _d!;
    switch (v) {
      case 'engelle':
        _engelle();
      case 'kisi':
        _kisiyeEkle();
      case 'olta':
        _oltaBildir();
      case 'takip':
        _takip();
      case 'gorev':
        GorevDuzenleyici.ac(context, iletiId: widget.id, ilkBaslik: d.ozet.konu);
      case 'okunmadi':
        _eylem(() => Posta.guncelle(widget.id, {'seen': false}), 'Okunmadı olarak işaretlendi', kaldir: true, yerel: {'seen': false});
      case 'yildiz':
        _eylem(
          () => Posta.guncelle(widget.id, {'flagged': !d.ozet.yildizli}),
          d.ozet.yildizli ? 'Yıldız kaldırıldı' : 'Yıldızlandı',
          yerel: {'flagged': !d.ozet.yildizli},
        );
      case 'onemli':
        _eylem(
          () => Posta.guncelle(widget.id, {'important': !d.ozet.onemli}),
          d.ozet.onemli ? 'Önemli işareti kaldırıldı' : 'Önemli olarak işaretlendi',
          yerel: {'important': !d.ozet.onemli},
        );
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
      case 'yazdir':
        iletiYazdir(context, d);
      case 'duzenle':
        yazmaAc(context, taslakHazirla(d, taslakId: _rol == 'drafts' ? d.ozet.id : null));
      case 'bicimli':
        setState(() => _html = true);
      case 'duz':
        setState(() => _html = false);
    }
  }

  List<PopupMenuEntry<String>> _menuOgeleri() {
    final d = _d!;
    PopupMenuItem<String> o(String v, IconData i, String t) => PopupMenuItem(
      value: v,
      child: ListTile(leading: Icon(i), title: Text(t)),
    );
    return [
      if (!_taslak && !widget.sayfa) o('yanitTumu', Simge.tumuneYanitla, 'Tümünü yanıtla'),
      o('okunmadi', Simge.okunmadiYap, 'Okunmadı yap'),
      o('yildiz', d.ozet.yildizli ? Simge.yildizDolu : Simge.yildiz, d.ozet.yildizli ? 'Yıldızı kaldır' : 'Yıldızla'),
      o('onemli', Simge.onemli, d.ozet.onemli ? 'Önemli değil' : 'Önemli olarak işaretle'),
      o('tasi', Simge.tasi, 'Taşı…'),
      o('etiket', Simge.etiket, 'Etiketle…'),
      if (_rol != 'snoozed' && !_taslak && _rol != 'sent') o('ertele', Simge.ertele, 'Ertele…'),
      if (_rol == 'junk') o('spamDegil', Simge.begen, 'Gereksiz değil') else if (!_taslak && _rol != 'sent') o('spam', Simge.bildir, 'Gereksiz (spam)'),
      if (!_taslak && (PostaDurum.ben.ayarlar?.ozellik('tasks') ?? true)) o('gorev', Simge.gorevEkle, 'Göreve dönüştür…'),
      if (!_taslak) o('takip', Simge.hatirlatma, d.ozet.takip ? 'Takip hatırlatıcısı…' : 'Takip hatırlatıcısı kur…'),
      if (!_taslak && _rol != 'sent') ...[
        const PopupMenuDivider(),
        o('kisi', Simge.kisiEkle, 'Göndereni kişilere ekle'),
        o('engelle', Simge.engelle, 'Göndereni engelle…'),
        o('olta', Simge.oltalama, 'Oltalama olarak bildir'),
      ],
      const PopupMenuDivider(),
      // Biçimli / düz metin görünümü (eskiden gövdenin üstünde ayrı bir düğme grubuydu).
      if (d.gorunum.html.trim().isNotEmpty && d.gorunum.metin.trim().isNotEmpty)
        _html ? o('duz', Simge.duzMetin, 'Düz metin olarak göster') : o('bicimli', Simge.duzMetin, 'Biçimli göster'),
      o('yazdir', Simge.yazdir, 'Yazdır'),
      o('disa', Simge.indir, 'İletiyi indir (.eml)'),
    ];
  }

  /// Web araç çubuğu düğmesi (ghost, 32 px yüksek, 16 px simge; etiket yalnız ipucunda).
  Widget _cubukDugmesi(IconData i, String ipucu, VoidCallback? f, {Key? key, Color? renk}) => SizedBox(
    width: 34,
    height: 32,
    child: IconButton(
      key: key,
      padding: EdgeInsets.zero,
      iconSize: 17,
      tooltip: ipucu,
      onPressed: f,
      icon: Icon(i, color: renk ?? context.r.metin.withValues(alpha: .85)),
    ),
  );

  Widget _ayrac() => Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: context.r.kenar);

  /// Web (reader.tsx) h-12 araç çubuğu: Yanıtla · Tümünü yanıtla · İlet | Arşivle · Spam · Sil | Etiketle · Taşı ·
  /// Ertele · ⋮ … sağda önceki/sonraki.
  List<Widget> _eylemDugmeleri() {
    if (_d == null) return const [];
    final yanitVar = !widget.sayfa && !_taslak;
    return [
      if (_taslak) _cubukDugmesi(Simge.duzenle, 'Taslağı düzenle', () => _menu('duzenle')),
      if (yanitVar) ...[
        _cubukDugmesi(Simge.yanitla, 'Yanıtla (R)', yanitla),
        _cubukDugmesi(Simge.tumuneYanitla, 'Tümünü yanıtla (A)', () => yanitla(tumu: true)),
        _cubukDugmesi(Simge.ilet, 'İlet (F)', ilet),
        _ayrac(),
      ],
      if (_rol != 'archive' && !_taslak) _cubukDugmesi(Simge.arsiv, 'Arşivle (E)', _mesgul ? null : arsivle),
      if (_rol == 'junk')
        _cubukDugmesi(Simge.begen, 'Gereksiz değil', _mesgul ? null : () => _menu('spamDegil'))
      else if (!_taslak && _rol != 'sent')
        _cubukDugmesi(Simge.bildir, 'Gereksiz (spam)', _mesgul ? null : () => _menu('spam')),
      _cubukDugmesi(Simge.sil, _rol == 'trash' ? 'Kalıcı sil' : 'Sil', _mesgul ? null : sil, renk: Marka.gul),
      if (context.genis) ...[
        _ayrac(),
        _cubukDugmesi(Simge.etiket, 'Etiketle', () => _menu('etiket')),
        _cubukDugmesi(Simge.tasi, 'Taşı', () => _menu('tasi')),
        if (_rol != 'snoozed' && !_taslak && _rol != 'sent') _cubukDugmesi(Simge.ertele, 'Ertele', () => _menu('ertele')),
      ],
      SizedBox(
        width: 34,
        height: 32,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          iconSize: 17,
          tooltip: 'Diğer işlemler',
          onSelected: _menu,
          itemBuilder: (_) => _menuOgeleri(),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final govde = _govde();
    final r = context.r;
    if (widget.sayfa) {
      return Scaffold(
        backgroundColor: r.kart,
        appBar: AppBar(
          backgroundColor: r.kart,
          toolbarHeight: 48,
          shape: Border(bottom: BorderSide(color: r.kenar)),
          actions: [..._eylemDugmeleri(), const SizedBox(width: 4)],
          bottom: _mesgul ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
        ),
        body: SafeArea(top: false, child: govde),
        // Telefonda tek iletide alt yanıt çubuğu (1.4'teki gibi; uzun iletinin sonuna kaydırmadan yanıtlanır).
        // Konuşmada kendi hızlı yanıt çubuğu var.
        bottomNavigationBar: _d == null || _taslak || _konusmaVar
            ? null
            : YanitCubugu(yanitla: yanitla, tumunu: () => yanitla(tumu: true), ilet: ilet, tumuGoster: _d!.gorunum.kime.length + _d!.gorunum.bilgi.length > 1),
      );
    }
    return Material(
      color: r.kart,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: r.kenar)),
            ),
            child: Row(
              children: [
                if (widget.geri != null) ...[_cubukDugmesi(Simge.geri, 'Listeye dön (Esc)', widget.geri, key: const ValueKey('okuyucu-geri')), _ayrac()],
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _eylemDugmeleri()),
                  ),
                ),
                _cubukDugmesi(Simge.geriOk, 'Önceki ileti (K)', widget.onceki, key: const ValueKey('onceki-ileti')),
                _cubukDugmesi(Simge.ileri, 'Sonraki ileti (J)', widget.sonraki, key: const ValueKey('sonraki-ileti')),
              ],
            ),
          ),
          // İşlem sürüyor ya da yeni ileti yükleniyor (önceki görünür): içeriği itmeyen ince çizgi.
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: govde),
                if (_mesgul || (_d != null && _d!.ozet.id != widget.id))
                  const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Masaüstünde gövde avatar hizasından başlar (web md:pl-[3.75rem]); yan dolgu 24 (telefonda 16).
  double get _yan => context.genis ? 24 : 16;
  // Outlook/Gmail gibi tek hiza: başlık, ekler, gövde aynı sol kenardan (_yan) başlar.
  double get _girinti => _yan;

  /// İletiyi ve konuşmayı sessizce tazeler (aşağı çekme; görünüm durumu korunur).
  Future<void> yenileKonusma() async {
    await _yukle(sessiz: true);
    await _konusmaYukle();
  }

  bool get _konusmaVar {
    final d = _d, k = _konusma;
    return d != null && k != null && k.length > 1 && !_taslak && k.any((m) => m.id == d.ozet.id);
  }

  Widget _govde() {
    if (_hata != null) return Durum.hata(_hata!, tekrar: _yukle);
    final d = _d;
    if (d == null) return const OkuyucuIskeleti();
    if (masaustuDuzeni) return _masaustuGovde(d);
    final r = context.r;
    final v = d.gorunum;
    final htmlVar = v.html.trim().isNotEmpty;
    final htmlGoster = htmlVar && (_html || v.metin.trim().isEmpty);
    final tehlikeli = _rol == 'junk' || d.tehditler.isNotEmpty;
    final k = _konusma;
    if (_konusmaVar) {
      return KonusmaGorunumu(key: ValueKey('konusma-${d.ozet.id}'), acilan: d, ogeler: k!, yenile: yenileKonusma);
    }
    Widget yanli(Widget c, {double ust = 0, double alt = 0}) => Padding(padding: EdgeInsets.fromLTRB(_yan, ust, _yan, alt), child: c);
    return RefreshIndicator(
      onRefresh: () => _yukle(sessiz: true),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _baslik(d),
          ..._ustParcalar(d),
          // Gövde: HTML belge kendi 16 px yan dolgusunu taşır, bu yüzden girinti 16 px az.
          Padding(
            // HTML gövdenin kendi 16 px dolgusu var: başlıkla aynı hizadan (_yan) başlar.
            padding: EdgeInsets.fromLTRB(htmlGoster ? _yan - 16 : _girinti, 12, htmlGoster ? _yan - 16 : _yan, 12),
            child: htmlGoster
                ? HtmlGovde(
                    key: ValueKey('ileti-html-${d.ozet.id}'),
                    iletiId: d.ozet.id,
                    html: v.html,
                    ekler: v.ekler,
                    baglantilar: d.baglantilar,
                    otomatikGorsel: Tercihler.uzakGorseller.value && !tehlikeli,
                    otomatikYukseklik: true,
                    epostaBaglantisi: (u) => yazmaAc(context, mailtoBaslangic(u)),
                  )
                : v.metin.trim().isEmpty
                ? Text('(Bu iletinin gövdesi boş.)', style: TextStyle(color: r.silik))
                : DuzMetin(metin: v.metin, baglantilar: d.baglantilar, eposta: (u) => yazmaAc(context, mailtoBaslangic(u))),
          ),
          // Web: gövdenin sonunda çerçeveli Yanıtla / Tümünü yanıtla / İlet düğmeleri.
          if (!_taslak)
            yanli(
              Wrap(
                key: const ValueKey('yanit-dugmeleri'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: yanitla, icon: const Icon(Simge.yanitla, size: 16), label: const Text('Yanıtla')),
                  OutlinedButton.icon(
                    onPressed: () => yanitla(tumu: true),
                    icon: const Icon(Simge.tumuneYanitla, size: 16),
                    label: const Text('Tümünü yanıtla'),
                  ),
                  OutlinedButton.icon(onPressed: ilet, icon: const Icon(Simge.ilet, size: 16), label: const Text('İlet')),
                ],
              ),
              ust: 12,
            ),
        ],
      ),
    );
  }

  /// Başlık ile gövde arasındaki bloklar: güvenlik bantları, spam denetimi, erteleme, davet, ekler, biçim seçimi.
  List<Widget> _ustParcalar(IletiDetay d) {
    final r = context.r;
    final v = d.gorunum;
    final htmlVar = v.html.trim().isNotEmpty;
    final htmlGoster = htmlVar && (_html || v.metin.trim().isEmpty);
    Widget yanli(Widget c, {double ust = 0, double alt = 0}) => Padding(padding: EdgeInsets.fromLTRB(_yan, ust, _yan, alt), child: c);
    // Web: Biçimli / Düz metin küçük düğmeleri (h-7; seçili olan ikincil zeminli; aynı kalınlık, kaymaz).
    Widget bicim(String t, bool secili, VoidCallback f) => TextButton(
      onPressed: f,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: secili ? r.ic : null,
        foregroundColor: r.metin,
        textStyle: TextStyle(fontFamily: govdeYaziTipi, fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(t),
    );
    return [
      for (final t in d.tehditler) GuvenlikBandi(tur: BantTuru.tehlike, baslik: 'Güvenlik uyarısı', metin: t, ikon: Simge.gereksiz),
      ...sezgiselUyarilar(d),
      if (_rol == 'junk')
        GuvenlikBandi(
          tur: BantTuru.uyari,
          baslik: d.spamPuani == null ? 'Gereksiz (spam) ileti' : 'Gereksiz (spam) ileti (puan ${d.spamPuani!.toStringAsFixed(1)})',
          metin: 'Bu ileti gereksiz olarak sınıflandırıldı. Bağlantılara ve eklere dikkat edin; görseller kendiliğinden yüklenmez.',
          ikon: Simge.bildir,
        ),
      // Web: temiz iletide açılır "Spam denetimi: puan -0.7 (temiz)" + kurallar.
      if (_rol != 'junk' && d.spamPuani != null && d.spamKurallari.isNotEmpty) yanli(SpamDenetimi(puan: d.spamPuani!, kurallar: d.spamKurallari), ust: 4),
      if (d.ozet.ertelemeBitis != null)
        yanli(
          Container(
            key: const ValueKey('erteleme-bandi'),
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: .1), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Simge.ertele, size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(child: Text("${tamZaman(d.ozet.ertelemeBitis)} tarihinde Gelen Kutusu'na geri gelecek.", style: const TextStyle(fontSize: 13))),
                TextButton(
                  onPressed: _mesgul ? null : () => _eylem(() => Posta.guncelle(widget.id, {'snooze_until': null}), "Gelen Kutusu'na taşındı", kaldir: true),
                  child: const Text('Şimdi geri al'),
                ),
              ],
            ),
          ),
          ust: 8,
        ),
      if (v.kesik)
        const GuvenlikBandi(
          tur: BantTuru.bilgi,
          baslik: 'İleti kısaltıldı',
          metin: 'İleti çok uzun olduğu için kısaltıldı. Tamamı için iletiyi indirin.',
          ikon: Simge.kes,
        ),
      if (v.ekler.any((e) => e.davetiye)) DavetKarti(key: ValueKey('davet-${d.ozet.id}'), iletiId: d.ozet.id),
      // Ekler gövdeden önce (uzun HTML gövdenin altında kaybolmasın): kart, dokununca açılır/önizlenir, menüden
      // paylaş / kaydet.
      if (v.dosyaEkleri.isNotEmpty)
        Padding(
          key: const ValueKey('okuyucu-ekler'),
          padding: EdgeInsets.fromLTRB(_girinti, 12, _yan, 0),
          child: EkListesi(iletiId: d.ozet.id, ekler: v.dosyaEkleri),
        ),
      if (htmlVar && v.metin.trim().isNotEmpty)
        yanli(
          Row(
            key: const ValueKey('bicim-secimi'),
            children: [
              bicim('Biçimli', htmlGoster, () => setState(() => _html = true)),
              const SizedBox(width: 4),
              bicim('Düz metin', !htmlGoster, () => setState(() => _html = false)),
            ],
          ),
          ust: 12,
        ),
    ];
  }

  // ---- masaüstü (macOS / Windows / Linux): Outlook gibi sabit başlık + bölmeyi dolduran tek gövde ----

  /// Konuşmada etkin iletiyi seçer; ayrıntı bellekte değilse yüklenir (bu arada önceki gösterilir).
  Future<void> _etkinSec(IletiOzet o) async {
    final id = o.id;
    setState(() {
      _etkin = id;
      final h = id == _d?.ozet.id ? _d : (_etkinDetaylar[id] ?? Posta.iletiHemen(id));
      if (h != null) _etkinDetaylar[id] = h;
    });
    if (!o.okundu) {
      o.okundu = true;
      PostaDurum.ben.okunduIsaretle(id);
    }
    if (_etkinDetaylar.containsKey(id)) return;
    try {
      final yerel = await Posta.iletiOnbellek(id).catchError((_) => null);
      if (yerel != null && mounted && !_etkinDetaylar.containsKey(id)) setState(() => _etkinDetaylar[id] = yerel);
      final d = await Posta.ileti(id);
      if (mounted) setState(() => _etkinDetaylar[id] = d);
    } catch (_) {
      if (mounted && !_etkinDetaylar.containsKey(id)) bildir('İleti açılamadı', tur: MesajTur.hata);
    }
  }

  /// Düz metin ileti masaüstünde de aynı web görünümünde gösterilir (tek görüntüleyici; bağlantılar tıklanır).
  static String duzMetinHtml(String metin) {
    final k = metindenHtml(metin).replaceAllMapped(_baglantiKalibi, (m) {
      final u = m[0]!.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
      return '<a href="$u">$u</a>${m[0]!.substring(u.length)}';
    });
    return '<div style="font-size:15px;line-height:1.55;white-space:pre-wrap">$k</div>';
  }

  static final _baglantiKalibi = RegExp(r'(https?://[^\s<>"]+|mailto:[^\s<>"]+)', caseSensitive: false);

  Widget _masaustuGovde(IletiDetay d) {
    final r = context.r;
    final konusma = _konusmaVar ? _konusma! : null;
    var a = d;
    if (konusma != null && _etkin != null && _etkin != d.ozet.id) {
      a = _etkinDetaylar[_etkin] ?? _sonEtkin ?? d;
    }
    _sonEtkin = a;
    final v = a.gorunum;
    final htmlVar = v.html.trim().isNotEmpty;
    final htmlGoster = htmlVar && (_html || v.metin.trim().isEmpty);
    final tehlikeli = _rol == 'junk' || a.tehditler.isNotEmpty;
    final govdeHtml = htmlGoster ? v.html : (v.metin.trim().isEmpty ? '<p style="color:#888">(Bu iletinin gövdesi boş.)</p>' : duzMetinHtml(v.metin));
    final etkinId = a.ozet.id;
    return LayoutBuilder(
      builder: (context, k) {
        final ust = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (konusma != null) ...[_baslik(d, gonderenGoster: false), _konusmaSatirlari(konusma, etkinId), _baslik(a, konuGoster: false)] else _baslik(d),
            ..._ustParcalar(a),
            const SizedBox(height: 10),
          ],
        );
        return Column(
          key: const ValueKey('masaustu-okuyucu'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Başlık bloğu: en çok bölmenin %55'i (uzun konuşmada kendi içinde kayar); gövde hep hemen altında.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: k.maxHeight * .55),
              child: SingleChildScrollView(key: const ValueKey('okuyucu-ust'), child: ust),
            ),
            Divider(height: 1, color: r.kenar),
            // Gövde: bölmenin geri kalanını dolduran tek web görünümü; kendi içinde kayar (tekerlek / iz paneli).
            // Anahtar sabit: ileti değişince görüntüleyici korunur, yalnız belge değişir.
            Expanded(
              key: const ValueKey('okuyucu-govde-alani'),
              child: HtmlGovde(
                key: const ValueKey('okuyucu-html'),
                iletiId: htmlGoster ? etkinId : '$etkinId-duz',
                html: govdeHtml,
                ekler: v.ekler,
                baglantilar: a.baglantilar,
                otomatikGorsel: htmlGoster && Tercihler.uzakGorseller.value && !tehlikeli,
                alintiyiKatla: htmlGoster,
                epostaBaglantisi: (u) => yazmaAc(context, mailtoBaslangic(u)),
              ),
            ),
            if (!_taslak)
              Container(
                key: const ValueKey('masaustu-yanit-cubugu'),
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: r.kart,
                  border: Border(top: BorderSide(color: r.kenar)),
                ),
                child: Row(
                  children: [
                    TextButton.icon(onPressed: yanitla, icon: const Icon(Simge.yanitla, size: 16), label: const Text('Yanıtla')),
                    TextButton.icon(onPressed: () => yanitla(tumu: true), icon: const Icon(Simge.tumuneYanitla, size: 16), label: const Text('Tümünü yanıtla')),
                    TextButton.icon(onPressed: ilet, icon: const Icon(Simge.ilet, size: 16), label: const Text('İlet')),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  /// Masaüstü konuşma: iletiler sıkı satırlar (gönderen, zaman, tek satır önizleme, okundu); etkin olan vurgulu.
  /// Eski ve okunmuş iletiler "▸ N önceki ileti" arkasında.
  Widget _konusmaSatirlari(List<IletiOzet> l, String etkinId) {
    final gizli = <String>{
      for (var i = 0; i < l.length - 3; i++)
        if (l[i].id != etkinId && l[i].okundu) l[i].id,
    };
    final katla = gizli.length >= 2 && !_oncekilerAcik;
    return Column(
      key: const ValueKey('konusma-satirlari'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gizli.length >= 2)
          OncekiDenetimi(
            key: const ValueKey('konusma-daha'),
            sayi: gizli.length,
            acik: _oncekilerAcik,
            degistir: () => setState(() => _oncekilerAcik = !_oncekilerAcik),
          ),
        for (final o in l)
          if (!katla || !gizli.contains(o.id))
            KonusmaSatiri(
              key: ValueKey('konusma-satir-${o.id}'),
              ozet: o,
              detay: _etkinDetaylar[o.id] ?? (o.id == _d?.ozet.id ? _d : Posta.iletiHemen(o.id)),
              secili: o.id == etkinId,
              ac: () => _etkinSec(o),
            ),
        Divider(height: 1, color: context.r.kenar),
      ],
    );
  }

  /// Web gibi "Kime: bana, Ali" (+ "Bilgi: N kişi").
  String _aliciOzeti(IletiGorunum v) {
    final ben = Uyg.adres.toLowerCase();
    final kime = [for (final a in v.kime) a.eposta.toLowerCase() == ben ? 'bana' : (a.ad.isNotEmpty ? a.ad : a.eposta)].join(', ');
    return 'Kime: ${kime.isEmpty ? '—' : kime}${v.bilgi.isNotEmpty ? ', Bilgi: ${v.bilgi.length} kişi' : ''}';
  }

  /// Web başlığı: konu (text-lg font-semibold) + önemli / yıldız; klasör ve etiket çipleri; gönderen satırı (32 px
  /// avatar, ad kalın + `<adres>` soluk, "Kime: bana ▾" ayrıntıyı açar, sağda tarih).
  Widget _baslik(IletiDetay d, {bool konuGoster = true, bool gonderenGoster = true}) {
    final r = context.r;
    final v = d.gorunum;
    final gonderen = v.kimden.isNotEmpty ? v.kimden.first : adresCoz(d.ozet.kimden);
    final tarih = v.tarih ?? d.ozet.tarih;
    final etiketler = d.ozet.etiketler.map(PostaDurum.ben.etiket).whereType<Etiket>().toList();
    final klasor = PostaDurum.ben.klasor(d.ozet.klasorId);
    final konu = v.konu.isEmpty ? '(konu yok)' : v.konu;
    Widget isaret(IconData i, String ipucu, Color renk, VoidCallback? f) => SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        tooltip: ipucu,
        onPressed: f,
        icon: Icon(i, color: renk),
      ),
    );
    Widget cip(String t, {Color? renk}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: renk == null ? r.ic : renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        t,
        style: TextStyle(fontSize: 12, height: 16 / 12, color: renk ?? r.silik, fontWeight: renk == null ? FontWeight.w400 : FontWeight.w500),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (konuGoster)
          Padding(
            padding: EdgeInsets.fromLTRB(_yan, 12, _yan - 6, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        konu,
                        key: const ValueKey('okuyucu-konu'),
                        style: TextStyle(fontSize: 18, height: 1.375, fontWeight: FontWeight.w600, color: r.metin),
                      ),
                    ),
                    isaret(
                      Simge.uyari,
                      d.ozet.onemli ? 'Önemli işaretini kaldır' : 'Önemli',
                      d.ozet.onemli ? const Color(0xFFF97316) : r.silik.withValues(alpha: .5),
                      _mesgul ? null : () => _menu('onemli'),
                    ),
                    isaret(
                      d.ozet.yildizli ? Simge.yildizDolu : Simge.yildiz,
                      d.ozet.yildizli ? 'Yıldızı kaldır' : 'Yıldızla',
                      d.ozet.yildizli ? yildizRengi : r.silik.withValues(alpha: .5),
                      _mesgul ? null : () => _menu('yildiz'),
                    ),
                  ],
                ),
                if (klasor != null || etiketler.isNotEmpty || d.ozet.takip || v.dosyaEkleri.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (klasor != null) cip(klasor.gorunenAd),
                        if (d.ozet.takip) cip('Takipte', renk: const Color(0xFFF43F5E)),
                        if (v.dosyaEkleri.isNotEmpty) cip('${v.dosyaEkleri.length} ek'),
                        for (final e in etiketler) cip(e.ad, renk: etiketRengi(e.renk)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (gonderenGoster)
          Padding(
            padding: EdgeInsets.fromLTRB(_yan, 12, _yan, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(gonderen.gorunen, boyut: 32, tohum: gonderen.eposta),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: gonderen.gorunen,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: r.metin),
                            ),
                            if (gonderen.ad.isNotEmpty)
                              TextSpan(
                                text: '  <${gonderen.eposta}>',
                                style: TextStyle(fontSize: 14, color: r.silik),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      InkWell(
                        key: const ValueKey('gonderen-karti'),
                        onTap: () => setState(() => _ayrinti = !_ayrinti),
                        borderRadius: BorderRadius.circular(4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                _aliciOzeti(v),
                                key: const ValueKey('okuyucu-kime'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, height: 16 / 12, color: r.silik),
                              ),
                            ),
                            const SizedBox(width: 4),
                            AnimatedRotation(
                              turns: _ayrinti ? .5 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: Icon(Simge.asagi, size: 14, color: r.silik),
                            ),
                          ],
                        ),
                      ),
                      if (_ayrinti)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: r.ic.withValues(alpha: .3),
                            border: Border.all(color: r.kenar),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _satir('Kimden', v.kimden.map(adresYaz).join(', ')),
                              if (v.yanitAdresi.isNotEmpty) _satir('Yanıt adresi', v.yanitAdresi.map(adresYaz).join(', ')),
                              _satir('Kime', v.kime.map(adresYaz).join(', ')),
                              if (v.bilgi.isNotEmpty) _satir('Bilgi', v.bilgi.map(adresYaz).join(', ')),
                              _satir('Tarih', tamZaman(tarih)),
                              if (d.ozet.boyut > 0) _satir('Boyut', boyutYaz(d.ozet.boyut)),
                              if (d.dogrulama.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 84,
                                        child: Text('Doğrulama', style: TextStyle(color: r.silik, fontSize: 12)),
                                      ),
                                      Expanded(child: DogrulamaCipleri(sonuclar: d.dogrulama)),
                                    ],
                                  ),
                                ),
                              if (d.spamPuani != null) _satir('Spam puanı', d.spamPuani!.toStringAsFixed(1)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: tamZaman(tarih),
                  child: Text(tamZaman(tarih), style: TextStyle(color: r.silik, fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _satir(String e, String d) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(e, style: TextStyle(color: context.r.silik, fontSize: 12)),
        ),
        Expanded(child: SelectableText(d.isEmpty ? '—' : d, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}

/// Düz metin gövdesi: bağlantılar tıklanabilir, alıntılanan geçmiş "•••" ile katlanır.
class DuzMetin extends StatefulWidget {
  const DuzMetin({super.key, required this.metin, required this.baglantilar, required this.eposta, this.imzayiKatla = false, this.boyut = 15});
  final String metin;

  /// Konuşmada tekrarlanan imza da "•••" arkasına katlanır.
  final bool imzayiKatla;
  final double boyut;
  final Map<String, String> baglantilar;
  final ValueChanged<Uri> eposta;
  @override
  State<DuzMetin> createState() => _DuzMetinState();
}

class _DuzMetinState extends State<DuzMetin> {
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
    final p = alintiVeImzaAyir(widget.metin, imza: widget.imzayiKatla);
    final stil = TextStyle(fontSize: widget.boyut, height: 1.55, color: r.metin);
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
                key: const ValueKey('alinti-ac'),
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _alinti = !_alinti),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: Text(
                    '•••',
                    style: TextStyle(color: r.silik, fontWeight: FontWeight.w600, letterSpacing: 2),
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
