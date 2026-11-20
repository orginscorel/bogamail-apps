import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show SecilenDosya, dosyaSec;
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'koruma_ortak.dart';
import '../ortak/simgeler.dart';

/// Yüzde metni (web pct ile aynı: %98,5; null → —).
String dmarcYuzde(Object? v, {int basamak = 1}) {
  if (v == null || v is! num) return '—';
  var s = v.toDouble().toStringAsFixed(basamak);
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  return '%${s.replaceAll('.', ',')}';
}

Color puanRengi(BuildContext c, int? p) {
  if (p == null) return c.r.silik;
  if (p >= 85) return Marka.zumrut;
  if (p >= 60) return Marka.kehribar;
  return Marka.gul;
}

/// Puan rozeti: 92/100 ya da "denetlenmedi".
class PuanRozeti extends StatelessWidget {
  const PuanRozeti(this.puan, {super.key});
  final int? puan;
  @override
  Widget build(BuildContext context) => puan == null
      ? Text('denetlenmedi', style: TextStyle(color: context.r.silik, fontSize: 12))
      : Text(
          '$puan/100',
          style: TextStyle(color: puanRengi(context, puan), fontWeight: FontWeight.w600),
        );
}

/// DMARC listesindeki alan adı (GET /api/v1/dmarc/domains → items).
class DmarcAlani {
  DmarcAlani(this.m);
  final Map<String, dynamic> m;
  static DmarcAlani coz(Map<String, dynamic> m) => DmarcAlani(m);
  String get id => metin(m['id']);
  String get ad => metin(m['name']);
  String get mod => metin(m['mode']);
  String get orgAdi => metin(m['organization_name']);
  bool get ozellik => mantik(m['feature_enabled']);
  int get ileti30 => tamsayi(m['messages_30d']);
  num? get gecen30 => m['pass_rate_30d'] is num ? m['pass_rate_30d'] as num : null;
  DateTime? get sonRapor => tarihOku(m['last_report_at']);
  int? get puan => tamsayiYa(m['score']);
  bool get acilir => ozellik || Uyg.platformYoneticisi;
}

const _atilmaEtiketleri = {
  'unknown_domain': 'platformda olmayan alan adı',
  'unknown_token': 'bilinmeyen belirteç',
  'token_mismatch': 'belirteç uyuşmazlığı',
  'out_of_scope': 'yetki dışı yükleme',
  'parse_error': 'okunamayan',
  'duplicate': 'yinelenen',
  'forensic': 'adli (RUF) — saklanmadı',
  'too_large': 'boyut / bomba sınırı',
};

const _yuklemeDurumu = {
  'stored': 'Kaydedildi',
  'duplicate': 'Zaten kayıtlı',
  'unknown_domain': 'Alan adı platformda değil / yetkiniz yok — atıldı',
  'unknown_token': 'Bilinmeyen rapor belirteci — atıldı',
  'token_mismatch': 'Rapor bu alan adının belirtecine ait değil — atıldı',
};

/// DMARC Merkezi: alan adları, alan adı ayrıntısı (kaynaklar, politika, puan), platform rapor adresi, rapor yükleme.
class DmarcEkrani extends StatefulWidget {
  const DmarcEkrani({super.key});
  @override
  State<DmarcEkrani> createState() => _DmarcEkraniState();
}

class _DmarcEkraniState extends State<DmarcEkrani> {
  List<DmarcAlani> _hepsi = [];

  late final _y = SayfaYukleyici.yerel<DmarcAlani>(() async {
    final l = haritalar(harita(await Uyg.api.get('/api/v1/dmarc/domains'))['items']).map(DmarcAlani.coz).toList();
    if (mounted) setState(() => _hepsi = l);
    return l;
  }, sayfaBoyu: 25)..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  bool get _yonetir => Uyg.yetki('domains.manage');
  bool get _herhangiAcik => !Uyg.musteri || _hepsi.any((d) => d.ozellik);

  void _ac(DmarcAlani d) {
    if (!d.acilir) {
      bildir('Paketinizde yok', mesaj: 'DMARC Merkezi bu müşterinin paketinde açık değil (dmarc_center).', tur: MesajTur.uyari);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DmarcAlanDetay(id: d.id, ad: d.ad),
      ),
    );
  }

  Future<void> _yukle() async {
    final kaydedildi = await showDialog<bool>(context: context, builder: (_) => const DmarcYuklemeDialog());
    if (kaydedildi == true) await _y.yenile();
  }

  void _ayarlar() => sayfaAc(context, 'Platform rapor adresi', const _DmarcAyarlari());

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'DMARC Merkezi',
      alt: 'Toplu raporlar, hizalanma, yetkisiz göndericiler ve güvenlik puanı',
      yenile: _y.yenile,
      eylemler: [if (Uyg.platformYoneticisi) IconButton(tooltip: 'Platform rapor adresi', onPressed: _ayarlar, icon: const Icon(Simgeler.settings))],
      birincil: _yonetir && _herhangiAcik ? BirincilEylem(Simgeler.uploadFile, 'Rapor yükle', _yukle) : null,
      govde: VeriTablosu<DmarcAlani>(
        yukleyici: _y,
        bosMetin: 'Alan adı yok. DMARC raporları alan adlarınız için toplanır; önce Alan Adları bölümünden bir alan adı ekleyin.',
        bosIkon: Simgeler.markEmailRead,
        onTap: _ac,
        ust: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'Adli (RUF) raporlar kişisel veri içerdiği için saklanmaz. Raporlar ve kaynak IP\'leri yalnızca alan adının sahibi müşteriye ve onun bayisine görünür.',
            style: TextStyle(color: context.r.silik, fontSize: 12),
          ),
        ),
        sutunlar: [
          Sutun(
            'Alan adı',
            esnek: 4,
            hucre: (c, d) => IkiSatir(d.ad, alt: [if (!Uyg.musteri) d.orgAdi, d.mod == 'gateway' ? 'gateway' : 'barındırma'].join(' · ')),
          ),
          Sutun('İleti (30 gün)', esnek: 2, sagaYasla: true, hucre: (c, d) => Text(d.acilir ? sayiYaz(d.ileti30) : '—')),
          Sutun('DMARC geçen', esnek: 2, sagaYasla: true, hucre: (c, d) => Text(dmarcYuzde(d.gecen30))),
          Sutun('Son rapor', esnek: 2, hucre: (c, d) => SolukMetin(d.sonRapor == null ? 'rapor yok' : goreliZaman(d.sonRapor))),
          Sutun(
            'Güvenlik puanı',
            esnek: 2,
            sagaYasla: true,
            hucre: (c, d) => d.acilir ? PuanRozeti(d.puan) : const Rozet('Paketinizde yok', renk: Marka.kehribar),
          ),
        ],
        kart: (c, d) => VeriKarti(
          baslik: d.ad,
          alt: [if (!Uyg.musteri) d.orgAdi, d.mod == 'gateway' ? 'gateway' : 'barındırma'].join(' · '),
          sol: const Icon(Simgeler.markEmailRead),
          rozetler: [
            if (!d.acilir) const Rozet('Paketinizde yok', renk: Marka.kehribar) else if (d.puan != null) Rozet('${d.puan}/100', renk: puanRengi(c, d.puan)),
          ],
          alanlar: d.acilir
              ? [
                  ('İleti (30 gün)', sayiYaz(d.ileti30)),
                  ('DMARC geçen', dmarcYuzde(d.gecen30)),
                  ('Son rapor', d.sonRapor == null ? 'rapor yok' : goreliZaman(d.sonRapor)),
                ]
              : const [],
          onTap: () => _ac(d),
        ),
      ),
    );
  }
}

/// Platform rapor adresi ayarı (yalnızca süper yönetici; PUT /dmarc/settings).
class _DmarcAyarlari extends StatefulWidget {
  const _DmarcAyarlari();
  @override
  State<_DmarcAyarlari> createState() => _DmarcAyarlariState();
}

class _DmarcAyarlariState extends State<_DmarcAyarlari> {
  final _adres = TextEditingController();
  bool _mesgul = false, _dolu = false;
  String? _hata;

  @override
  void dispose() {
    _adres.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TekYukleme<Map<String, dynamic>>(
    getir: () async => harita(await Uyg.api.get('/api/v1/dmarc/settings')),
    icerik: (c, s, yenile) {
      if (!_dolu) {
        _adres.text = metin(s['configured']);
        _dolu = true;
      }
      final r = c.r;
      final yetki = harita(s['authorization_record']);
      final atilan = harita(s['drops_30d']);
      return IcerikListesi(
        enFazla: 820,
        children: [
          const SizedBox(height: 8),
          BolumKarti(
            baslik: 'Platform rapor adresi',
            ikon: Simgeler.alternateEmail,
            altBaslik:
                'Alıcılar toplu raporları bu adrese gönderir; her alan adı kendi belirteciyle (yerel+belirteç@alan) eşlenir. Boş bırakılırsa ${metin(s['default'])} kullanılır.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _adres,
                  autocorrect: false,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(labelText: 'Adres', hintText: metin(s['default']), errorText: _hata, errorMaxLines: 3),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _mesgul
                        ? null
                        : () async {
                            setState(() {
                              _mesgul = true;
                              _hata = null;
                            });
                            try {
                              await Uyg.api.put('/api/v1/dmarc/settings', {'address': _adres.text.trim()});
                              bildir('Kaydedildi', tur: MesajTur.basari);
                              _dolu = false;
                              await yenile();
                            } catch (e) {
                              setState(() => _hata = hataMetni(e));
                            } finally {
                              if (mounted) setState(() => _mesgul = false);
                            }
                          },
                    child: mesgulYazi(_mesgul, 'Kaydet'),
                  ),
                ),
                const SizedBox(height: 12),
                BilgiSatiri('Etkin adres', metin(s['address']), mono: true, kopyalanabilir: true),
                BilgiSatiri('Posta ile alım', mantik(s['smtp_listening']) ? 'SMTP dinleniyor' : 'SMTP dinlenmiyor (raporlar elle yüklenir)'),
                const SizedBox(height: 8),
                Text(
                  'Bu adres için MX/A kaydı ve genel 25 numaralı port gerekir. Dış rapor adresi yetkilendirmesi (RFC 7489 §7.1) için DNS\'e şu joker kayıt eklenmeli (sahip onayı gerekir):',
                  style: TextStyle(color: r.silik, fontSize: 12.5),
                ),
                KopyaKutusu('${metin(yetki['host'])} ${metin(yetki['type'])} "${metin(yetki['value'])}"'),
                if (s['drops_30d'] is Map) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Son 30 gün: ${tamsayi(s['reports_30d'])} rapor, ${tamsayi(s['records_30d'])} kayıt saklandı. Atılan: '
                    '${atilan.isEmpty ? 'yok' : atilan.entries.map((e) => '${_atilmaEtiketleri[e.key] ?? e.key} ${metin(e.value)}').join(' · ')}',
                    style: TextStyle(color: r.soluk, fontSize: 12.5),
                  ),
                ],
                if (metinYa(s['forensic']) != null) ...[
                  const SizedBox(height: 8),
                  Text('${metin(s['forensic'])}.', style: TextStyle(color: r.silik, fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Toplu (RUA) rapor yükleme: .xml, .xml.gz veya .zip dosyaları seçilir ya da XML yapıştırılır
/// (POST /dmarc/upload {files:[{name, data: base64}]}; en fazla 10 dosya, toplam 25 MB).
class DmarcYuklemeDialog extends StatefulWidget {
  const DmarcYuklemeDialog({super.key});
  @override
  State<DmarcYuklemeDialog> createState() => _DmarcYuklemeDialogState();
}

class _DmarcYuklemeDialogState extends State<DmarcYuklemeDialog> {
  final _xml = TextEditingController();
  final _dosyalar = <SecilenDosya>[];
  bool _mesgul = false, _kaydedildi = false;
  Map<String, dynamic>? _sonuc;

  static const _enFazlaDosya = 10;
  static const _enFazlaBayt = 25 * 1024 * 1024;

  int get _adet => _dosyalar.length + (_xml.text.trim().isEmpty ? 0 : 1);
  int get _toplam => _dosyalar.fold(0, (a, f) => a + f.bayt.length) + utf8.encode(_xml.text.trim()).length;

  Future<void> _sec() async {
    final l = await dosyaSec(baslik: 'DMARC raporlarını seç', uzantilar: const ['xml', 'gz', 'zip'], coklu: true);
    if (l.isEmpty || !mounted) return;
    var atlanan = 0;
    setState(() {
      for (final f in l) {
        if (_dosyalar.any((x) => x.ad == f.ad)) continue;
        if (_dosyalar.length >= _enFazlaDosya) {
          atlanan++;
          continue;
        }
        _dosyalar.add(f);
      }
      _sonuc = null;
    });
    if (atlanan > 0) bildir('En fazla $_enFazlaDosya dosya yüklenebilir', mesaj: '$atlanan dosya eklenmedi.', tur: MesajTur.uyari);
  }

  @override
  void dispose() {
    _xml.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    setState(() => _mesgul = true);
    final v = await islem(
      () => Uyg.api.post('/api/v1/dmarc/upload', {
        'files': [
          for (final f in _dosyalar) {'name': f.ad, 'data': base64.encode(f.bayt)},
          if (_xml.text.trim().isNotEmpty) {'name': 'rapor.xml', 'data': base64.encode(utf8.encode(_xml.text.trim()))},
        ],
      }),
    );
    if (!mounted) return;
    setState(() {
      _mesgul = false;
      if (v != null) {
        _sonuc = harita(v);
        if (tamsayi(_sonuc!['stored']) > 0) {
          _kaydedildi = true;
          bildir('${tamsayi(_sonuc!['stored'])} rapor kaydedildi', tur: MesajTur.basari);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AlertDialog(
      title: Text('DMARC raporu yükle', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Alıcıların (Google, Microsoft, Yahoo…) gönderdiği toplu (RUA) raporları yükleyin: .xml, .xml.gz veya .zip dosyası seçin '
                '(en fazla $_enFazlaDosya dosya, toplam 25 MB) ya da XML içeriğini yapıştırın. Yalnızca platformdaki ve yetkiniz olan alan adlarının '
                'raporları kaydedilir. Adli (RUF) raporlar kabul edilmez.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _mesgul || _dosyalar.length >= _enFazlaDosya ? null : _sec,
                  icon: const Icon(Simgeler.attachFile, size: 18),
                  label: const Text('Dosya seç'),
                ),
              ),
              for (final f in _dosyalar)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(f.ad.toLowerCase().endsWith('.xml') ? Simgeler.description : Simgeler.folderZip),
                  title: Text(f.ad, overflow: TextOverflow.ellipsis),
                  subtitle: Text(boyutYaz(f.bayt.length)),
                  trailing: IconButton(
                    tooltip: 'Çıkar',
                    icon: const Icon(Simgeler.close, size: 18),
                    onPressed: _mesgul ? null : () => setState(() => _dosyalar.remove(f)),
                  ),
                ),
              if (_toplam > _enFazlaBayt)
                Bant('Toplam boyut 25 MB sınırını aşıyor (${boyutYaz(_toplam)}).', renk: Marka.gul, ikon: Simgeler.errorOutline),
              const SizedBox(height: 12),
              TextField(
                controller: _xml,
                minLines: 6,
                maxLines: 12,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(labelText: 'Rapor XML (isteğe bağlı)', hintText: '<?xml version="1.0"?>\n<feedback>…</feedback>', alignLabelWithHint: true),
              ),
              if (_sonuc != null) ...[
                const SizedBox(height: 12),
                for (final f in haritalar(_sonuc!['files']))
                  if (metinYa(f['error']) != null)
                    Bant(metin(f['error']), renk: Marka.gul, ikon: Simgeler.errorOutline)
                  else
                    for (final rp in haritalar(f['reports']))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${metin(rp['reporter'])} · ${metin(rp['domain'])} · ${tamsayi(rp['messages'])} ileti — ${_yuklemeDurumu[metin(rp['status'])] ?? metin(rp['status'])}',
                          style: TextStyle(color: metin(rp['status']) == 'stored' ? Marka.zumrut : r.soluk, fontSize: 12.5),
                        ),
                      ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, _kaydedildi), child: const Text('Kapat')),
        FilledButton(
          onPressed: _mesgul || _adet == 0 || _adet > _enFazlaDosya || _toplam > _enFazlaBayt ? null : _gonder,
          child: mesgulYazi(_mesgul, _adet > 1 ? '$_adet dosyayı yükle' : 'Yükle'),
        ),
      ],
    );
  }
}

const _sinifEtiketi = {'platform': 'BogaMail platformu', 'own': 'Bizim gönderici', 'provider': 'Bilinen sağlayıcı', 'unknown': 'Tanınmayan'};

(String, Color) _hukum(String v) => switch (v) {
  'ok' => ('Uyumlu', Marka.zumrut),
  'misconfig' => ('Yapılandırma sorunu', Marka.kehribar),
  'unauthorized' => ('Yetkisiz gönderici', Marka.gul),
  'forwarded' => ('Yönlendirme', Marka.mavi),
  'partial' => ('Kısmen başarısız', Marka.kehribar),
  _ => (v, Marka.mavi),
};

/// DMARC alan adı ayrıntısı (GET /dmarc/domains/{id}?range=7d|30d|90d).
class DmarcAlanDetay extends StatefulWidget {
  const DmarcAlanDetay({super.key, required this.id, required this.ad});
  final String id, ad;
  @override
  State<DmarcAlanDetay> createState() => _DmarcAlanDetayState();
}

class _DmarcAlanDetayState extends State<DmarcAlanDetay> {
  String _aralik = '30d';
  bool _yalnizSorunlu = false, _denetleniyor = false, _otoDenetim = false;
  int _kaynakSiniri = 25;
  final _yukleme = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();

  bool get _yonetir => Uyg.yetki('domains.manage');

  Future<Map<String, dynamic>> _getir() async {
    final d = harita(await Uyg.api.get('/api/v1/dmarc/domains/${widget.id}', q: {'range': _aralik}));
    _otomatikDenetle(d);
    return d;
  }

  /// Eski (10 dakikadan eski) ya da hiç yapılmamış güvenlik denetimini sayfa açılınca bir kez yeniler (web ile aynı).
  void _otomatikDenetle(Map<String, dynamic> d) {
    if (_otoDenetim) return;
    _otoDenetim = true;
    final t = tarihOku(d['score_checked_at']);
    if (t != null && DateTime.now().difference(t) < const Duration(minutes: 10)) return;
    Uyg.api.post('/api/v1/dmarc/domains/${widget.id}/score').then((_) => _yukleme.currentState?.yenile()).catchError((_) {});
  }

  Future<void> _denetle() async {
    setState(() => _denetleniyor = true);
    await islem(() => Uyg.api.post('/api/v1/dmarc/domains/${widget.id}/score'));
    if (!mounted) return;
    setState(() => _denetleniyor = false);
    await _yukleme.currentState?.yenile();
  }

  Future<void> _kaynakAc(Map<String, dynamic> s) async {
    final degisti = await showDialog<bool>(
      context: context,
      builder: (_) => _KaynakDialog(kaynak: s, alanId: widget.id, yonetir: _yonetir),
    );
    if (degisti == true) await _yukleme.currentState?.yenile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ad, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'Yenile', onPressed: () => _yukleme.currentState?.yenile(), icon: const Icon(Simgeler.refresh)),
          const SizedBox(width: 8),
        ],
      ),
      body: TekYukleme<Map<String, dynamic>>(key: _yukleme, getir: _getir, icerik: _icerik),
    );
  }

  Widget _icerik(BuildContext c, Map<String, dynamic> d, Future<void> Function() yenile) {
    final r = c.r;
    final t = harita(d['totals']);
    final ileti = tamsayi(t['messages']);
    final gecen = d['pass_rate'] is num ? d['pass_rate'] as num : null;
    final kaynaklar = haritalar(d['sources']).where((s) => !_yalnizSorunlu || metin(s['verdict']) != 'ok').toList();
    final raporlayanlar = haritalar(d['reporters']);
    final raporlar = haritalar(d['reports']);
    final yetkisiz = tamsayi(d['unauthorized_sources']);
    return IcerikListesi(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                metin(harita(d['domain'])['organization_name']),
                style: TextStyle(color: r.soluk, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SecimCipleri<String>(
              secenekler: const [('7d', '7 gün'), ('30d', '30 gün'), ('90d', '90 gün')],
              secili: _aralik,
              secildi: (v) {
                setState(() {
                  _aralik = v;
                  _kaynakSiniri = 25;
                });
                yenile();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Izgara(
          enAz: 160,
          bosluk: 10,
          children: [
            KorumaKutusu(etiket: 'Raporlanan ileti', deger: sayiYaz(ileti), alt: '${raporlar.isEmpty ? 0 : raporlayanlar.length} raporlayıcı'),
            KorumaKutusu(
              etiket: 'DMARC geçen',
              deger: dmarcYuzde(gecen),
              alt: '${sayiYaz(tamsayi(t['pass']))} ileti',
              renk: gecen != null && gecen < 90 ? Marka.kehribar : null,
            ),
            KorumaKutusu(etiket: 'DKIM hizalı', deger: dmarcYuzde(ileti == 0 ? null : tamsayi(t['dkim_aligned']) * 100 / ileti)),
            KorumaKutusu(etiket: 'SPF hizalı', deger: dmarcYuzde(ileti == 0 ? null : tamsayi(t['spf_aligned']) * 100 / ileti)),
            KorumaKutusu(etiket: 'Yetkisiz gönderici', deger: '$yetkisiz', alt: '${tamsayi(d['unauthorized_messages'])} başarısız ileti', kotu: yetkisiz > 0),
            KorumaKutusu(etiket: 'Karantina / ret', deger: '${tamsayi(t['quarantined'])} / ${tamsayi(t['rejected'])}', alt: 'alıcı politikası uyguladı'),
          ],
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Hacim (günlük, UTC)',
          ikon: Simgeler.barChart,
          altBaslik: 'Alıcıların toplu raporlarındaki, sizin alan adınızla gönderilmiş iletiler.',
          child: DmarcHacimGrafigi(seri: haritalar(d['series'])),
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Gönderen kaynaklar',
          ikon: Simgeler.dns,
          altBaslik: 'IP → ters DNS (PTR) → ASN → bilinen gönderici (platform, bizim göndericiler, tanınan sağlayıcılar).',
          sag: FilterChip(
            label: const Text('Yalnızca sorunlu'),
            selected: _yalnizSorunlu,
            onSelected: (v) => setState(() {
              _yalnizSorunlu = v;
              _kaynakSiniri = 25;
            }),
          ),
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: kaynaklar.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Bu dönemde kaynak yok.', style: TextStyle(color: r.soluk)),
                )
              : Column(
                  children: [
                    for (final s in kaynaklar.take(_kaynakSiniri)) _kaynakSatiri(c, s),
                    if (kaynaklar.length > _kaynakSiniri)
                      TextButton(
                        onPressed: () => setState(() => _kaynakSiniri += 25),
                        child: Text('Daha fazla göster (${kaynaklar.length - _kaynakSiniri} kaldı)'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        YanYana(
          esik: 900,
          bosluk: 16,
          children: [
            _politikaKarti(c, harita(d['recommendation'])),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ruaKarti(c, d),
                const SizedBox(height: 16),
                _DmarcGondericileri(alanId: widget.id, yonetir: _yonetir, degisti: yenile),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _puanKarti(c, d['score'] is Map ? harita(d['score']) : null, tarihOku(d['score_checked_at'])),
        const SizedBox(height: 16),
        YanYana(
          esik: 900,
          bosluk: 16,
          children: [
            BolumKarti(
              baslik: 'Raporlayan alıcılar',
              ikon: Simgeler.business,
              child: raporlayanlar.isEmpty
                  ? Text('Bu dönemde rapor yok.', style: TextStyle(color: r.soluk))
                  : Column(
                      children: [
                        for (final x in raporlayanlar.take(30))
                          _ikiliSatir(
                            c,
                            metin(x['name']),
                            '${tamsayi(x['reports'])} rapor · ${sayiYaz(tamsayi(x['messages']))} ileti · '
                            '${dmarcYuzde(tamsayi(x['messages']) == 0 ? null : tamsayi(x['pass']) * 100 / tamsayi(x['messages']))}',
                          ),
                      ],
                    ),
            ),
            BolumKarti(
              baslik: 'Son raporlar',
              ikon: Simgeler.receiptLong,
              child: raporlar.isEmpty
                  ? Text('Henüz rapor alınmadı.', style: TextStyle(color: r.soluk))
                  : Column(
                      children: [
                        for (final x in raporlar.take(30))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(metin(x['reporter']), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${_tarih(x['begin'])} – ${_tarih(x['end'])} · p=${metinYa(x['policy_p']) ?? '?'} · '
                              '${metin(x['source']) == 'upload' ? 'elle yüklendi' : 'e-posta'} · ${tamZaman(tarihOku(x['received_at']))}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text('${sayiYaz(tamsayi(x['messages']))} ileti', style: TextStyle(color: r.soluk, fontSize: 12)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  static String _tarih(Object? v) {
    final t = tarihOku(v);
    return t == null ? '—' : DateFormat('d.MM.y', 'tr_TR').format(t);
  }

  Widget _ikiliSatir(BuildContext c, String a, String b) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Text(a, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(b, style: TextStyle(color: c.r.soluk, fontSize: 12)),
      ],
    ),
  );

  Widget _kaynakSatiri(BuildContext c, Map<String, dynamic> s) {
    final ptr = metinler(s['ptr']);
    final (h, renk) = _hukum(metin(s['verdict']));
    final asn = tamsayi(s['asn']);
    final alt = [
      ptr.isNotEmpty ? ptr.first : (mantik(s['ptr_resolved']) ? 'PTR yok' : 'PTR bekleniyor'),
      if (metinYa(s['label']) != null) metin(s['label']),
      if (asn > 0) 'AS$asn ${metin(s['as_name'])}'.trim(),
    ].join(' · ');
    return ListeSatiri(
      baslik: metin(s['ip']),
      alt: alt,
      alt2: '${_sinifEtiketi[metin(s['class'])] ?? metin(s['class'])} · ${sayiYaz(tamsayi(s['messages']))} ileti · ${dmarcYuzde(s['pass_rate'])} geçti',
      vurgulu: metin(s['verdict']) == 'unauthorized',
      sag: Rozet(h, renk: renk),
      onTap: () => _kaynakAc(s),
    );
  }

  Widget _politikaKarti(BuildContext c, Map<String, dynamic> p) {
    final r = c.r;
    final adimlar = haritalar(p['steps']);
    final hazir = mantik(p['ready']);
    return BolumKarti(
      baslik: 'Politika yol haritası',
      ikon: Simgeler.route,
      altBaslik:
          'p=none → quarantine → reject. Sonraki adım, meşru kaynaklarınızın iletileri ${tamsayi(p['window_days'])} gün boyunca %${metin(p['threshold'])} ve üzeri DMARC hizalı olduğunda önerilir.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in adimlar)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: metin(a['state']) == 'current' ? r.vurguYumusak : null,
                    border: Border.all(color: {'current', 'next'}.contains(metin(a['state'])) ? r.vurgu : r.kenar),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        metin(a['state']) == 'done' ? Simgeler.checkCircle : Simgeler.radioButtonUnchecked,
                        size: 17,
                        color: metin(a['state']) == 'done' ? Marka.zumrut : r.silik,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metin(a['label']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            const {'done': 'tamamlandı', 'current': 'yayında', 'next': 'sıradaki adım', 'todo': 'sonra'}[metin(a['state'])] ??
                                metin(a['state']),
                            style: TextStyle(color: r.silik, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          BilgiSatiri('Yayındaki politika', metinYa(p['current']) ?? 'kayıt yok'),
          BilgiSatiri('Meşru kaynak hizalanması', dmarcYuzde(p['aligned_rate'])),
          BilgiSatiri('Veri olan gün', '${tamsayi(p['days_with_data'])}/${tamsayi(p['window_days'])} (eşikte: ${tamsayi(p['days_compliant'])})'),
          const SizedBox(height: 8),
          Bant(
            '${hazir ? 'Hazır. ' : (metinYa(p['next']) != null ? 'Henüz hazır değil. ' : '')}${metin(p['reason'])}',
            renk: hazir ? Marka.zumrut : Marka.mavi,
            ikon: hazir ? Simgeler.checkCircleOutline : Simgeler.infoOutline,
          ),
          if (metinYa(p['record']) != null) ...[
            const SizedBox(height: 8),
            Text(
              metinYa(p['next']) != null ? 'Yayınlanacak kayıt (p=${metin(p['next'])})' : 'Yayındaki kayıt',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            DnsKaydi(host: metin(p['host']), tur: 'TXT', deger: metin(p['record'])),
          ],
        ],
      ),
    );
  }

  Widget _ruaKarti(BuildContext c, Map<String, dynamic> d) {
    final r = c.r;
    final yetki = harita(d['rua_authorization']);
    return BolumKarti(
      baslik: 'Raporları bu panele yönlendirin',
      ikon: Simgeler.forwardToInbox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Alan adınızın rapor adresi (yalnızca ${widget.ad} raporlarını kabul eder):', style: TextStyle(color: r.soluk, fontSize: 12.5)),
          KopyaKutusu(metin(d['rua_address'])),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              mantik(d['rua_published'])
                  ? const Rozet('DMARC kaydında rua var', renk: Marka.zumrut)
                  : const Rozet('DMARC kaydında bu rua yok', renk: Marka.kehribar),
              if (d['rua_authorized'] == false) const Rozet('Dış rapor adresi yetkilendirmesi DNS\'te yok', renk: Marka.kehribar),
              if (d['smtp_listening'] == false) const Rozet('Posta ile rapor alımı: SMTP dinlenmiyor', renk: Marka.mavi),
            ],
          ),
          if (d['rua_authorized'] == false) ...[
            const SizedBox(height: 8),
            Text(
              'RFC 7489 §7.1: rapor adresi başka bir alan adında olduğu için alıcılar şu kaydı arar (platform yöneticisi yayınlar):',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
            KopyaKutusu('${metin(yetki['host'])} TXT "${metin(yetki['value'])}"'),
          ],
          const SizedBox(height: 8),
          Text('Genel SMTP (25) henüz açık değilse raporları "Rapor yükle" ile elle yükleyebilirsiniz.', style: TextStyle(color: r.silik, fontSize: 12)),
          if (metinYa(d['dns_error']) != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(metin(d['dns_error']), style: const TextStyle(color: Marka.gul, fontSize: 12)),
            ),
          if (tamsayi(d['record_count']) > 1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Birden fazla DMARC kaydı yayında; alıcılar hiçbirini uygulamaz.', style: TextStyle(color: Marka.gul, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _puanKarti(BuildContext c, Map<String, dynamic>? rp, DateTime? zaman) {
    final r = c.r;
    final puan = rp == null ? null : tamsayiYa(rp['score']);
    final sorunlar = rp == null ? const <String>[] : metinler(rp['problems']);
    return BolumKarti(
      baslik: 'Alan adı güvenlik puanı',
      ikon: Simgeler.shield,
      altBaslik:
          'SPF, DKIM, DMARC, MTA-STS, TLS-RPT, DNSSEC ve MX için canlı DNS denetimi. Ölçülemeyen kalemler puana katılmaz.${zaman != null ? ' Son denetim: ${tamZaman(zaman)}.' : ''}',
      sag: OutlinedButton.icon(
        onPressed: _denetleniyor ? null : _denetle,
        icon: _denetleniyor
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Simgeler.refresh, size: 18),
        label: const Text('Şimdi denetle'),
      ),
      child: rp == null
          ? Text('Henüz denetlenmedi. "Şimdi denetle" ile canlı DNS sorguları yapılır.', style: TextStyle(color: r.soluk))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(puan == null ? '—' : '$puan', style: gosterim(40, agirlik: FontWeight.w600, renk: puanRengi(c, puan))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '/ 100 · not ${metinYa(rp['grade']) ?? '—'} · ölçülen ağırlık %${metin(rp['coverage'])}',
                          style: TextStyle(color: r.silik, fontSize: 12.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final f in haritalar(rp['factors'])) _faktor(c, f),
                if (sorunlar.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Marka.gul.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Marka.gul.withValues(alpha: .3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Açık sorunlar', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        for (final p in sorunlar) Text('• $p', style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _faktor(BuildContext c, Map<String, dynamic> f) {
    final r = c.r;
    final durum = metin(f['status']);
    final (etiket, renk) = switch (durum) {
      'ok' => ('Tamam', Marka.zumrut),
      'warn' => ('Uyarı', Marka.kehribar),
      'fail' => ('Eksik', Marka.gul),
      'info' => ('Bilgi', Marka.mavi),
      _ => ('Bilinmiyor', r.silik),
    };
    final agirlik = tamsayi(f['weight']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(metin(f['label']), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (agirlik > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${durum == 'unknown' ? '—' : ondalik(f['points']).toStringAsFixed(0)} / $agirlik',
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                ),
              Rozet(etiket, renk: renk),
            ],
          ),
          const SizedBox(height: 4),
          Text(metin(f['detail']), style: TextStyle(color: r.soluk, fontSize: 12.5)),
          if (metinYa(f['fix']) != null) Text('Çözüm: ${metin(f['fix'])}', style: const TextStyle(fontSize: 12.5)),
          if (metinYa(f['host']) != null && metinYa(f['value']) != null)
            DnsKaydi(host: metin(f['host']), tur: metinYa(f['type']) ?? 'TXT', deger: metin(f['value'])),
        ],
      ),
    );
  }
}

/// Yayınlanacak DNS kaydı: ad, tür ve değer (kopyalanabilir).
class DnsKaydi extends StatelessWidget {
  const DnsKaydi({super.key, required this.host, required this.tur, required this.deger});
  final String host, tur, deger;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KopyaKutusu(host, etiket: 'Ad'),
        KopyaKutusu(tur, etiket: 'Tür'),
        KopyaKutusu(deger, etiket: 'Değer'),
      ],
    ),
  );
}

/// Günlük DMARC hacmi: geçen ve başarısız iletiler, yığılmış çubuk.
class DmarcHacimGrafigi extends StatelessWidget {
  const DmarcHacimGrafigi({super.key, required this.seri, this.yukseklik = 170});
  final List<Map<String, dynamic>> seri;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final toplam = seri.fold<int>(0, (a, d) => a + tamsayi(d['messages']));
    if (seri.isEmpty || toplam == 0) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text('Bu dönemde rapor yok.', style: TextStyle(color: r.silik)),
        ),
      );
    }
    final enCok = seri.fold<int>(1, (a, d) => tamsayi(d['messages']) > a ? tamsayi(d['messages']) : a);
    final bicim = DateFormat('d MMM', 'tr_TR');
    String gun(int i) {
      final t = DateTime.tryParse(metin(seri[i]['day']));
      return t == null ? '' : bicim.format(t);
    }

    final adim = (seri.length / 6).ceil().clamp(1, 1000);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: yukseklik,
          child: BarChart(
            BarChartData(
              maxY: enCok * 1.1,
              alignment: BarChartAlignment.spaceBetween,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: r.kenar, strokeWidth: 1, dashArray: const [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, m) => Text(sayiYaz(v.round()), style: TextStyle(color: r.silik, fontSize: 10.5)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, m) {
                      final i = v.round();
                      if (i < 0 || i >= seri.length || i % adim != 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(gun(i), style: TextStyle(color: r.silik, fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Marka.grafit,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (g, gi, rod, ri) {
                    final d = seri[g.x];
                    final m = tamsayi(d['messages']), p = tamsayi(d['pass']);
                    final kr = tamsayi(d['quarantined']) + tamsayi(d['rejected']);
                    return BarTooltipItem(
                      '${gun(g.x)}\n$m ileti · geçen $p · başarısız ${m - p}${kr > 0 ? '\nkarantina ${tamsayi(d['quarantined'])} · ret ${tamsayi(d['rejected'])}' : ''}',
                      const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
              barGroups: [
                for (final (i, d) in seri.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: tamsayi(d['messages']).toDouble(),
                        width: (300 / seri.length).clamp(2, 14).toDouble(),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        rodStackItems: [
                          BarChartRodStackItem(0, tamsayi(d['pass']).toDouble(), Marka.zumrut),
                          BarChartRodStackItem(tamsayi(d['pass']).toDouble(), tamsayi(d['messages']).toDouble(), Marka.gul),
                        ],
                        color: Colors.transparent,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _lejant(context, Marka.zumrut, 'DMARC geçti'),
            _lejant(context, Marka.gul, 'DMARC başarısız'),
            Text('en yüksek gün: ${sayiYaz(enCok)} ileti', style: TextStyle(color: r.silik, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _lejant(BuildContext c, Color renk, String ad) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(3)),
      ),
      const SizedBox(width: 8),
      Text(ad, style: TextStyle(color: c.r.soluk, fontSize: 12.5)),
    ],
  );
}

/// Kaynak ayrıntısı ve "bizim gönderici" işaretleme (POST /dmarc/senders).
class _KaynakDialog extends StatefulWidget {
  const _KaynakDialog({required this.kaynak, required this.alanId, required this.yonetir});
  final Map<String, dynamic> kaynak;
  final String alanId;
  final bool yonetir;
  @override
  State<_KaynakDialog> createState() => _KaynakDialogState();
}

class _KaynakDialogState extends State<_KaynakDialog> {
  final _not = TextEditingController();
  bool _mesgul = false;

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  Future<void> _isaretle(String tur, String deger) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    final v = await islem(() async {
      await Uyg.api.post('/api/v1/dmarc/senders', {'domain_id': widget.alanId, 'kind': tur, 'value': deger, 'note': _not.text.trim()});
      return true;
    }, tamam: 'Bizim gönderici olarak işaretlendi');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (v == true) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.kaynak;
    final ptr = metinler(s['ptr']);
    final sinif = metin(s['class']);
    final parcalar = ptr.isEmpty ? const <String>[] : ptr.first.split('.');
    final sonek = parcalar.length >= 2 ? parcalar.sublist(parcalar.length - 2).join('.') : '';
    final asn = tamsayi(s['asn']);
    String liste(String k) {
      final l = metinler(s[k]);
      return l.isEmpty ? '—' : l.join(', ');
    }

    return AlertDialog(
      title: Text(
        metin(s['ip']),
        style: gosterim(18, agirlik: FontWeight.w600).copyWith(fontFamily: 'monospace'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${ptr.isNotEmpty ? 'PTR: ${ptr.join(', ')}' : (mantik(s['ptr_resolved']) ? 'PTR kaydı yok' : 'PTR henüz çözülmedi')} · '
                '${_sinifEtiketi[sinif] ?? sinif}${metinYa(s['label']) != null ? ' (${metin(s['label'])})' : ''}',
                style: TextStyle(color: context.r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 8),
              BilgiSatiri('ASN', asn > 0 ? 'AS$asn ${metin(s['as_name'])}${metinYa(s['country']) != null ? ' (${metin(s['country'])})' : ''}' : 'bilinmiyor'),
              BilgiSatiri('İleti', sayiYaz(tamsayi(s['messages']))),
              BilgiSatiri('DMARC geçen', '${tamsayi(s['pass'])} (${dmarcYuzde(s['pass_rate'])})'),
              BilgiSatiri('DKIM / SPF hizalı', '${tamsayi(s['dkim_aligned'])} / ${tamsayi(s['spf_aligned'])}'),
              BilgiSatiri('Karantina / ret', '${tamsayi(s['quarantined'])} / ${tamsayi(s['rejected'])}'),
              BilgiSatiri('Header From', liste('header_from')),
              BilgiSatiri('Envelope From', liste('envelope_from')),
              BilgiSatiri('DKIM imza alanları', liste('dkim_domains')),
              BilgiSatiri('Raporlayan', liste('reporters')),
              if (widget.yonetir && sinif != 'platform' && sinif != 'own') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _not,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', hintText: 'ör. CRM sistemi, bülten aracı'),
                ),
                EylemSatiri(
                  ikon: Simgeler.howToReg,
                  baslik: 'Bu IP bizim gönderici',
                  ipucu: 'Yalnızca bu IP adresi meşru kaynak sayılır.',
                  onTap: _mesgul ? null : () => _isaretle('ip', metin(s['ip'])),
                ),
                if (sonek.isNotEmpty)
                  EylemSatiri(
                    ikon: Simgeler.verifiedUser,
                    baslik: '*.$sonek bizim gönderici',
                    ipucu: 'Bu ters DNS son ekiyle biten tüm sunucular meşru kaynak sayılır.',
                    onTap: _mesgul ? null : () => _isaretle('ptr', sonek),
                  ),
                const SizedBox(height: 8),
                Text(
                  'İşaretlemek yalnızca sınıflandırmayı ve politika önerisini etkiler; bu kaynağın DMARC\'tan geçmesi için yine SPF\'ye eklenmesi veya alan adınızla DKIM imzalaması gerekir.',
                  style: TextStyle(color: context.r.silik, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}

/// Bizim göndericiler (GET /dmarc/senders?domain_id=, DELETE /dmarc/senders/{id}).
class _DmarcGondericileri extends StatefulWidget {
  const _DmarcGondericileri({required this.alanId, required this.yonetir, required this.degisti});
  final String alanId;
  final bool yonetir;
  final Future<void> Function() degisti;
  @override
  State<_DmarcGondericileri> createState() => _DmarcGondericileriState();
}

class _DmarcGondericileriState extends State<_DmarcGondericileri> {
  late Future<List<Map<String, dynamic>>> _f = _getir();

  Future<List<Map<String, dynamic>>> _getir() async => haritalar(harita(await Uyg.api.get('/api/v1/dmarc/senders', q: {'domain_id': widget.alanId}))['items']);

  @override
  void didUpdateWidget(covariant _DmarcGondericileri old) {
    super.didUpdateWidget(old);
    _f = _getir();
  }

  Future<void> _kaldir(Map<String, dynamic> s) async {
    final evet = await onayla(context, '"${metin(s['value'])}" kaldırılsın mı?', evet: 'Kaldır', tehlikeli: true);
    if (!evet) return;
    final v = await islem(() async {
      await Uyg.api.delete('/api/v1/dmarc/senders/${metin(s['id'])}');
      return true;
    }, tamam: 'Kaldırıldı');
    if (v == true) await widget.degisti();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return BolumKarti(
      baslik: 'Bizim göndericiler',
      ikon: Simgeler.howToReg,
      altBaslik: 'Meşru olarak işaretlediğiniz kaynaklar (kaynaklar listesinden eklenir).',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (c, s) {
          if (s.hasError) return Text(hataMetni(s.error!), style: const TextStyle(color: Marka.gul));
          if (!s.hasData) return const LinearProgressIndicator(minHeight: 2);
          final l = s.data!;
          if (l.isEmpty) return Text('Henüz işaretlenmiş gönderici yok.', style: TextStyle(color: r.soluk));
          return Column(
            children: [
              for (final g in l)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(metin(g['value']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                  subtitle: Text(
                    [
                      const {'ip': 'IP', 'cidr': 'Ağ', 'ptr': 'PTR son eki'}[metin(g['kind'])] ?? metin(g['kind']),
                      if (metinYa(g['note']) != null) metin(g['note']),
                      if (metinYa(g['domain_id']) == null) 'tüm alan adları',
                    ].join(' · '),
                  ),
                  trailing: widget.yonetir
                      ? IconButton(tooltip: 'Kaldır', onPressed: () => _kaldir(g), icon: const Icon(Simgeler.deleteOutline, size: 20))
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }
}
