import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'kutu_detay.dart';
import 'kutu_formlari.dart';
import 'kutu_islemleri.dart';
import 'takma_adlar.dart';
import 'taklit_islemleri.dart';
import '../ortak/simgeler.dart';

/// Posta kutuları (web: mailboxes/page.tsx): geniş ekranda sıralanabilir tablo (adres, kullanım, son giriş,
/// oluşturma), telefonda kartlar; arama, alan adı ve durum filtreleri (etkin filtre çipleriyle), satır menüsünde
/// "Posta kutusuna gir", şifre, düzenleme, limitler, taşıma, geri yükleme, dışa aktarma, askıya alma ve silme.
class PostaKutulariEkrani extends StatefulWidget {
  const PostaKutulariEkrani({super.key, this.orgId, this.orgAdi, this.alanId, this.alanAdi});
  final String? orgId, orgAdi, alanId, alanAdi;
  @override
  State<PostaKutulariEkrani> createState() => _PostaKutulariEkraniState();
}

class _PostaKutulariEkraniState extends State<PostaKutulariEkrani> {
  String _q = '';
  String _durum = '';
  String _sirala = 'address';
  bool _artan = true;
  late String? _alanId = widget.alanId;
  late String? _alanAdi = widget.alanAdi;
  PostaKutusu? _secili;

  late final _y = SayfaYukleyici<PostaKutusu>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/mailboxes',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _sirala,
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (_durum.isNotEmpty) 'status': _durum,
          if (_alanId != null) 'domain_id': _alanId,
          if (widget.orgId != null) 'organization_id': widget.orgId,
        },
      ),
      PostaKutusu.coz,
    ),
  )..yenile();

  bool get _yonetir => Uyg.yetki('mailboxes.manage');

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  bool get _yanPanel => MediaQuery.sizeOf(context).width >= 1400;

  void _ac(PostaKutusu k) {
    if (_yanPanel) {
      setState(() => _secili = k);
    } else {
      sayfaAc(context, k.adres, KutuDetay(kutu: k, degisti: (y) => _degisti(k.id, y), tamSayfa: true));
    }
  }

  void _degisti(String id, PostaKutusu? y) {
    _y.degistir((x) => x.id == id, y);
    if (_secili?.id == id) setState(() => _secili = y);
  }

  Future<void> _yeni() async {
    final k = await showDialog<PostaKutusu>(
      context: context,
      builder: (_) => KutuOlusturDialog(orgId: widget.orgId, alanId: _alanId, alanAdi: _alanAdi),
    );
    if (k == null || !mounted) return;
    await _y.yenile();
    if (mounted) _ac(k);
  }

  Future<void> _alanSec() async {
    final d = await alanSec(context, orgId: widget.orgId);
    if (d == null) return;
    setState(() {
      _alanId = d.id;
      _alanAdi = d.gorunenAd;
    });
    _y.yenile();
  }

  void _alanKaldir() {
    setState(() => _alanId = _alanAdi = null);
    _y.yenile();
  }

  Future<void> _duzenle(PostaKutusu k) async {
    final y = await showDialog<PostaKutusu>(context: context, builder: (_) => KutuDuzenleDialog(kutu: k));
    if (y != null && mounted) _degisti(k.id, y);
  }

  Future<void> _durumDegistir(PostaKutusu k) async {
    final askiya = k.aktif;
    if (askiya &&
        !await onayla(
          context,
          '${k.adres} askıya alınsın mı?',
          mesaj: 'Kullanıcı giriş yapamaz ve posta gönderemez. Gelen posta kabul edilmeye devam eder.',
          evet: 'Askıya al',
          tehlikeli: true,
        )) {
      return;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/mailboxes/${k.id}', {'status': askiya ? 'suspended' : 'active'}),
      tamam: askiya ? 'Posta kutusu askıya alındı' : 'Posta kutusu etkinleştirildi',
    );
    if (v != null && mounted) _degisti(k.id, PostaKutusu.coz(harita(v)));
  }

  Future<void> _sil(PostaKutusu k) async {
    final ok = await yazarakOnayla(
      context,
      baslik: '${k.adres} silinsin mi?',
      mesaj: 'Hesap kalıcı olarak silinir ve bu adrese gelen posta reddedilir. İçinde ileti bulunan kutular silinemez. Bu işlem geri alınamaz.',
      beklenen: k.adres,
    );
    if (!ok) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/mailboxes/${k.id}').then((_) => true), tamam: 'Posta kutusu silindi');
    if (v == true && mounted) _degisti(k.id, null);
  }

  List<SatirEylemi> _eylemler(PostaKutusu k) => [
    SatirEylemi(Simgeler.openInFull, 'Ayrıntılar', () => _ac(k)),
    if (_yonetir) ...[
      if (k.aktif) SatirEylemi(Simgeler.markEmailUnread, 'Posta kutusuna gir', () => postaKutusunaGir(context, id: k.id, adres: k.adres)),
      SatirEylemi(Simgeler.edit, 'Düzenle', () => _duzenle(k)),
      SatirEylemi(Simgeler.key, 'Şifreyi sıfırla', () => sifreSifirla(context, k)),
      SatirEylemi(Simgeler.straighten, 'Boyut limitleri', () => boyutLimitleri(context, k)),
      SatirEylemi(Simgeler.moveDown, 'IMAP ile taşı', () => imapTasima(context, k)),
      SatirEylemi(Simgeler.history, 'Yedekten geri yükle', () => yedektenGeriYukle(context, k)),
      SatirEylemi(Simgeler.download, 'Dışa aktar (.zip)', () => kutuyuDisariAktar(context, k)),
      SatirEylemi(k.aktif ? Simgeler.pauseCircleOutline : Simgeler.playCircleOutline, k.aktif ? 'Askıya al' : 'Etkinleştir', () => _durumDegistir(k)),
      SatirEylemi(Simgeler.deleteOutline, 'Sil', () => _sil(k), tehlikeli: true),
    ],
  ];

  Widget _kullanim(PostaKutusu k) {
    final oran = kullanimOrani(k.kullanilan, k.kota);
    final r = context.r;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${boyutYaz(k.kullanilan)} / ${sinirsizMi(k.kota) ? 'sınırsız' : boyutYaz(k.kota)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: (oran ?? 0) >= .9 ? Marka.gul : r.metin),
        ),
        const SizedBox(height: 4),
        SizedBox(width: 140, child: KullanimCubugu(kullanilan: k.kullanilan, toplam: k.kota, yazi: false, kalinlik: 5)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final baslik = widget.alanAdi != null && widget.alanId == _alanId ? widget.alanAdi! : (widget.orgAdi != null ? '${widget.orgAdi} · Posta kutuları' : 'Posta Kutuları');
    final ust = FiltreCubugu(
      arama: AramaAlani(
        ipucu: 'Adres veya ad ara…',
        degisti: (v) {
          setState(() => _q = v);
          _y.yenile();
        },
      ),
      filtreler: [
        ActionChip(
          avatar: Icon(SimgelerKalin.language, size: 16, color: _alanId != null ? r.vurgu : r.soluk),
          label: Text(_alanAdi ?? 'Alan adı'),
          onPressed: _alanSec,
        ),
        FiltreDugmesi<String>(
          etiket: 'Durum',
          ikon: Simgeler.toggleOn,
          secenekler: const [('', 'Tümü'), ('active', 'Aktif'), ('suspended', 'Askıda')],
          secili: _durum,
          secildi: (d) {
            setState(() => _durum = d);
            _y.yenile();
          },
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TakmaAdlarEkrani(orgId: widget.orgId, alanId: _alanId, alanAdi: _alanAdi)),
          ),
          icon: const Icon(Simgeler.alternateEmail, size: 18),
          label: const Text('Takma adlar'),
        ),
      ],
      etkinler: [
        if (_alanId != null) EtkinFiltre('Alan: $_alanAdi', _alanKaldir, ikon: Simgeler.language),
        if (_durum.isNotEmpty)
          EtkinFiltre('Durum: ${durumEtiketi(_durum)}', () {
            setState(() => _durum = '');
            _y.yenile();
          }),
      ],
    );
    final tablo = VeriTablosu<PostaKutusu>(
      yukleyici: _y,
      ust: ust,
      tabloEnAz: 640,
      bosMetin: _q.isEmpty && _durum.isEmpty && _alanId == null ? 'Henüz posta kutusu yok.' : 'Eşleşen posta kutusu yok.',
      bosIkon: Simgeler.inbox,
      siralama: _sirala,
      artan: _artan,
      siralamaDegisti: (a, b) {
        setState(() {
          _sirala = a;
          _artan = b;
        });
        _y.yenile();
      },
      secili: (k) => _secili?.id == k.id,
      onTap: _ac,
      eylemler: _eylemler,
      sutunlar: [
        Sutun(
          'Posta kutusu',
          esnek: 5,
          siralama: 'address',
          hucre: (_, k) => IkiSatir(
            k.adres,
            alt: [if (k.gorunenAd.isNotEmpty) k.gorunenAd, if (!Uyg.musteri && widget.orgId == null) k.orgAdi].join(' · '),
            sol: Avatar(k.gorunenAd.isEmpty ? k.adres : k.gorunenAd, tohum: k.adres, boyut: 34),
          ),
        ),
        Sutun('Kullanım', esnek: 3, siralama: 'used', hucre: (_, k) => _kullanim(k)),
        Sutun('Son giriş', esnek: 2, siralama: 'last_login', hucre: (_, k) => SolukMetin(k.sonGiris == null ? 'Hiç' : goreliZaman(k.sonGiris))),
        Sutun('Durum', genislik: 110, hucre: (_, k) => DurumRozeti(k.durum)),
        Sutun('Oluşturma', esnek: 2, siralama: 'created_at', hucre: (_, k) => SolukMetin(kisaZaman(k.eklenme))),
      ],
      kart: (c, k) => VeriKarti(
        baslik: k.adres,
        alt: [if (k.gorunenAd.isNotEmpty) k.gorunenAd, if (!Uyg.musteri && widget.orgId == null) k.orgAdi].join(' · '),
        sol: Avatar(k.gorunenAd.isEmpty ? k.adres : k.gorunenAd, tohum: k.adres),
        rozetler: [if (!k.aktif) DurumRozeti(k.durum)],
        alanlar: [('Son giriş', k.sonGiris == null ? 'Hiç' : goreliZaman(k.sonGiris)), ('Oluşturma', kisaZaman(k.eklenme))],
        ek: KullanimCubugu(kullanilan: k.kullanilan, toplam: k.kota, kalinlik: 5),
        eylemler: _eylemler(k),
        onTap: () => _ac(k),
      ),
    );
    return Iskelet(
      baslik: baslik,
      alt: 'Kullanıcı hesapları, kotalar ve durumları',
      yenile: _y.yenile,
      birincil: _yonetir ? BirincilEylem(Simgeler.personAddAlt, 'Posta kutusu', _yeni) : null,
      govde: _secili == null || !_yanPanel
          ? tablo
          : Row(
              children: [
                Expanded(child: tablo),
                VerticalDivider(width: 1, color: r.kenar.withValues(alpha: .6)),
                SizedBox(
                  width: 460,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(tooltip: 'Kapat', onPressed: () => setState(() => _secili = null), icon: const Icon(Simgeler.close)),
                      ),
                      Expanded(
                        child: KutuDetay(key: ValueKey(_secili!.id), kutu: _secili!, degisti: (y) => _degisti(_secili!.id, y)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
