import 'dart:async';
import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'koruma_ortak.dart';

/// Test sandbox gelen kutusu (GET /api/v1/sandboxes → items).
class SandboxKutusu {
  SandboxKutusu(this.m);
  final Map<String, dynamic> m;
  static SandboxKutusu coz(Map<String, dynamic> m) => SandboxKutusu(m);

  String get id => metin(m['id']);
  String get ad => metin(m['name']);
  String get orgAdi => metin(m['organization_name']);
  String get kullanici => metin(m['smtp_username']);
  String get anahtarOnEki => metin(m['api_token_prefix']);
  int get saklamaGun => tamsayi(m['retention_days']);
  int get enCokIleti => tamsayi(m['max_messages']);
  int get kota => tamsayi(m['quota_bytes']);
  int get ileti => tamsayi(m['messages']);
  int get kullanilan => tamsayi(m['used_bytes']);
  bool get ozellik => mantik(m['feature'], true);
  DateTime? get olusturma => tarihOku(m['created_at']);
  DateTime? get sonIleti => tarihOku(m['last_message_at']);
}

/// Test Sandbox: geliştirici test gelen kutuları (yakalanan iletiler teslim edilmez).
class SandboxEkrani extends StatefulWidget {
  const SandboxEkrani({super.key});
  @override
  State<SandboxEkrani> createState() => _SandboxEkraniState();
}

class _SandboxEkraniState extends State<SandboxEkrani> {
  Map<String, dynamic> _bilgi = {};

  late final _y = SayfaYukleyici.yerel<SandboxKutusu>(() async {
    final v = harita(await Uyg.api.get('/api/v1/sandboxes'));
    if (mounted) setState(() => _bilgi = v);
    return haritalar(v['items']).map(SandboxKutusu.coz).toList();
  })..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  bool get _ozellikKapali => Uyg.musteri && _bilgi['feature'] == false;
  bool get _yonetir => Uyg.yetki('mailboxes.manage');

  String get _smtpOzet {
    final s = harita(_bilgi['smtp']);
    final portlar = haritalar(s['ports']).map((p) => '${metin(p['port'])} ${metin(p['security'])}').join(' / ');
    return '${metin(s['host'])} · $portlar';
  }

  Future<void> _yeni() async {
    final s = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _SandboxFormu());
    if (s == null || !mounted) return;
    await _y.yenile();
    if (mounted) await _gizliGoster('Sandbox oluşturuldu', s);
  }

  Future<void> _gizliGoster(String baslik, Map<String, dynamic> s) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bu bilgiler yalnızca şimdi gösterilir; sunucuda yalnızca özetleri saklanır. Kaybederseniz yenileyin.',
                style: TextStyle(color: c.r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 10),
              _GizliSatir('SMTP sunucusu', _smtpOzet),
              if (metinYa(s['smtp_username']) != null) _GizliSatir('SMTP kullanıcı adı', metin(s['smtp_username'])),
              if (metinYa(s['smtp_password']) != null) _GizliSatir('SMTP parolası', metin(s['smtp_password'])),
              if (metinYa(s['api_token']) != null) _GizliSatir('CI API anahtarı', metin(s['api_token'])),
            ],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Kaydettim, kapat'))],
    ),
  );

  Future<void> _duzenle(SandboxKutusu s) async {
    final ok = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SandboxFormu(mevcut: s),
    );
    if (ok != null) await _y.yenile();
  }

  Future<void> _yenileGizli(SandboxKutusu s, String ne) async {
    final parola = ne == 'password';
    final evet = await onayla(
      context,
      parola ? 'SMTP parolası yenilensin mi?' : 'CI API anahtarı yenilensin mi?',
      mesaj: parola ? 'Eski parola hemen geçersiz olur; yenisi bir kez gösterilir.' : 'Eski anahtar hemen geçersiz olur; yenisi bir kez gösterilir.',
      evet: 'Yenile',
    );
    if (!evet) return;
    final v = await islem(() => Uyg.api.post('/api/v1/sandboxes/${s.id}/rotate', {'what': ne}));
    if (v == null || !mounted) return;
    await _y.yenile();
    if (mounted) await _gizliGoster(parola ? 'Yeni SMTP parolası' : 'Yeni CI API anahtarı', harita(v));
  }

  Future<void> _sil(SandboxKutusu s) async {
    final evet = await onayla(
      context,
      '"${s.ad}" silinsin mi?',
      mesaj: 'Sandbox ve yakalanan ${s.ileti} ileti kalıcı olarak silinecek. SMTP bilgileri geçersiz olur.',
      evet: 'Sil',
      tehlikeli: true,
    );
    if (!evet) return;
    await islem(() => Uyg.api.delete('/api/v1/sandboxes/${s.id}'), tamam: 'Sandbox silindi');
    await _y.yenile();
  }

  void _ac(SandboxKutusu s) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SandboxIletileri(kutu: s)));

  void _ciYardim() {
    final kok = Uyg.api.sunucu;
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('CI / otomatik test API\'si', style: gosterim(19, agirlik: FontWeight.w700)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Her sandbox\'ın kendi API anahtarı (sbxt_…) vardır; yalnızca o sandbox\'ın iletilerini okur. Testinizde gönderimden sonra '
                  'son iletiyi çekip konu, alıcı ve analiz sonuçlarını doğrulayabilirsiniz.',
                  style: TextStyle(color: c.r.soluk, fontSize: 13),
                ),
                const SizedBox(height: 8),
                KopyaKutusu('curl -H "Authorization: Bearer sbxt_…" "$kok/api/v1/sandbox-api/messages?page_size=5"'),
                KopyaKutusu('curl -H "Authorization: Bearer sbxt_…" "$kok/api/v1/sandbox-api/messages/<id>"'),
                KopyaKutusu('curl -H "Authorization: Bearer sbxt_…" "$kok/api/v1/sandbox-api/messages/<id>/raw"'),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    );
  }

  List<SatirEylemi> _eylemler(SandboxKutusu s) => [
    SatirEylemi(Icons.inbox_rounded, 'İletileri aç', () => _ac(s)),
    if (_yonetir) ...[
      SatirEylemi(Icons.tune_rounded, 'Ayarları düzenle', () => _duzenle(s)),
      SatirEylemi(Icons.key_rounded, 'SMTP parolasını yenile', () => _yenileGizli(s, 'password')),
      SatirEylemi(Icons.autorenew_rounded, 'CI API anahtarını yenile', () => _yenileGizli(s, 'token')),
      SatirEylemi(Icons.delete_outline_rounded, 'Sandbox\'ı sil', () => _sil(s), tehlikeli: true),
    ],
  ];

  Widget _ust() {
    if (_bilgi.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ozellikKapali)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Bant(
                'E-posta test sandbox\'ı paketinizde yok. Kurumsal Mail 3/4, Business ve Enterprise paketlerinde bulunur; Paketim bölümünden yükseltme isteyebilirsiniz.',
                renk: Marka.kehribar,
                ikon: Icons.lock_outline_rounded,
              ),
            ),
          Bant('SMTP sunucusu $_smtpOzet · kimlik doğrulama PLAIN/LOGIN.', ikon: Icons.dns_outlined),
          if (_bilgi['submission_enabled'] == false)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Bant('Gönderim (587) dinleyicisi bu düğümde kapalı: yakalama yapılamaz.', renk: Marka.kehribar, ikon: Icons.warning_amber_rounded),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Test Sandbox',
      alt: 'Yakalanan iletiler alıcılara asla teslim edilmez',
      yenile: _y.yenile,
      eylemler: [IconButton(tooltip: 'CI API\'si', onPressed: _ciYardim, icon: const Icon(Icons.terminal_rounded))],
      birincil: _yonetir && !_ozellikKapali ? BirincilEylem(Icons.add_rounded, 'Yeni sandbox', _yeni) : null,
      govde: VeriTablosu<SandboxKutusu>(
        yukleyici: _y,
        ust: _ust(),
        bosMetin: 'Henüz sandbox yok. Bir sandbox oluşturun; SMTP kullanıcı adı, parola ve CI API anahtarı bir kez gösterilir.',
        bosIkon: Icons.science_outlined,
        onTap: _ac,
        eylemler: _eylemler,
        sutunlar: [
          Sutun('Sandbox', esnek: 4, hucre: (c, s) => IkiSatir(s.ad, alt: s.kullanici, mono: true)),
          if (!Uyg.musteri)
            Sutun(
              'Müşteri',
              esnek: 3,
              hucre: (c, s) => Row(
                children: [
                  Flexible(child: Text(s.orgAdi, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (!s.ozellik) ...[const SizedBox(width: 6), const Rozet('özellik kapalı', renk: Marka.kehribar)],
                ],
              ),
            ),
          Sutun(
            'İletiler',
            esnek: 2,
            hucre: (c, s) => IkiSatir('${sayiYaz(s.ileti)} / ${sayiYaz(s.enCokIleti)}', alt: '${s.saklamaGun} gün saklanır', kalin: false),
          ),
          Sutun(
            'Kota',
            esnek: 3,
            hucre: (c, s) => KullanimCubugu(kullanilan: s.kullanilan, toplam: s.kota, kalinlik: 6),
          ),
          Sutun('Son ileti', esnek: 2, hucre: (c, s) => SolukMetin(s.sonIleti == null ? '—' : goreliZaman(s.sonIleti))),
        ],
        kart: (c, s) => VeriKarti(
          baslik: s.ad,
          alt: s.kullanici,
          sol: const Icon(Icons.science_outlined),
          rozetler: [if (!s.ozellik) const Rozet('özellik kapalı', renk: Marka.kehribar)],
          alanlar: [
            if (!Uyg.musteri) ('Müşteri', s.orgAdi),
            ('İletiler', '${s.ileti} / ${s.enCokIleti}'),
            ('Saklama', '${s.saklamaGun} gün'),
            ('Son ileti', s.sonIleti == null ? '—' : goreliZaman(s.sonIleti)),
          ],
          ek: KullanimCubugu(kullanilan: s.kullanilan, toplam: s.kota, kalinlik: 6),
          eylemler: _eylemler(s),
          onTap: () => _ac(s),
        ),
      ),
    );
  }
}

class _GizliSatir extends StatelessWidget {
  const _GizliSatir(this.etiket, this.deger);
  final String etiket, deger;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          etiket,
          style: TextStyle(color: context.r.silik, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        KopyaKutusu(deger),
      ],
    ),
  );
}

/// Sandbox oluşturma / ayar düzenleme formu (POST /sandboxes, PATCH /sandboxes/{id}).
class _SandboxFormu extends StatefulWidget {
  const _SandboxFormu({this.mevcut});
  final SandboxKutusu? mevcut;
  @override
  State<_SandboxFormu> createState() => _SandboxFormuState();
}

class _SandboxFormuState extends State<_SandboxFormu> {
  late final _ad = TextEditingController(text: widget.mevcut?.ad ?? '');
  late final _saklama = TextEditingController(text: '${widget.mevcut?.saklamaGun ?? 7}');
  late final _enCok = TextEditingController(text: '${widget.mevcut?.enCokIleti ?? 200}');
  late final _kota = TextEditingController(text: '${widget.mevcut == null ? 50 : (widget.mevcut!.kota / 1048576).round()}');
  String? _orgId, _orgAdi, _hata, _alan;
  bool _mesgul = false;

  bool get _yeni => widget.mevcut == null;

  @override
  void dispose() {
    _ad.dispose();
    _saklama.dispose();
    _enCok.dispose();
    _kota.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final ad = _ad.text.trim();
    final saklama = aralikta(_saklama.text, 1, 90), enCok = aralikta(_enCok.text, 1, 5000), kota = aralikta(_kota.text, 1, 1024);
    String? alan, hata;
    if (ad.isEmpty || ad.runes.length > 80) {
      (alan, hata) = ('name', 'Ad 1–80 karakter olmalı');
    } else if (saklama == null) {
      (alan, hata) = ('retention_days', 'Saklama süresi 1–90 gün');
    } else if (enCok == null) {
      (alan, hata) = ('max_messages', 'İleti sınırı 1–5000');
    } else if (kota == null) {
      (alan, hata) = ('quota_mb', 'Kota 1–1024 MB');
    }
    if (hata != null) {
      setState(() {
        _alan = alan;
        _hata = hata;
      });
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    final govde = {'name': ad, 'retention_days': saklama, 'max_messages': enCok, 'quota_mb': kota};
    try {
      final dynamic v;
      if (_yeni) {
        v = await Uyg.api.post('/api/v1/sandboxes', {if (!Uyg.musteri) 'organization_id': _orgId, ...govde});
      } else {
        v = await Uyg.api.patch('/api/v1/sandboxes/${widget.mevcut!.id}', govde);
        bildir('Kaydedildi', tur: MesajTur.basari);
      }
      if (mounted) Navigator.pop(context, v is Map ? harita(v) : <String, dynamic>{});
    } on ApiHata catch (e) {
      setState(() {
        _alan = e.alan;
        _hata = e.mesaj;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? _h(String a) => _alan == a ? _hata : null;

  @override
  Widget build(BuildContext context) {
    final orgGerek = _yeni && !Uyg.musteri;
    final hazir = !_mesgul && _ad.text.trim().isNotEmpty && (!orgGerek || _orgId != null);
    return AlertDialog(
      title: Text(_yeni ? 'Yeni test sandbox\'ı' : widget.mevcut!.ad, style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _yeni
                    ? 'Yakalanan iletiler teslim edilmez; saklama süresi ve ileti/kota sınırı dolunca en eskiler silinir.'
                    : '${widget.mevcut!.kullanici} · API anahtarı ${widget.mevcut!.anahtarOnEki}… · oluşturma ${tamZaman(widget.mevcut!.olusturma)}',
                style: TextStyle(color: context.r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (orgGerek) ...[
                SecimAlani(
                  etiket: 'Müşteri',
                  deger: _orgAdi,
                  hata: _h('organization_id'),
                  onTap: () async {
                    final o = await musteriSec(context);
                    if (o != null) {
                      setState(() {
                        _orgId = o.id;
                        _orgAdi = o.ad;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _ad,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Ad', hintText: 'Staging uygulaması', errorText: _h('name')),
              ),
              const SizedBox(height: 4),
              YanYana(
                esik: 380,
                children: [
                  SayiAlani(denetleyici: _saklama, etiket: 'Saklama', sonEk: 'gün', hata: _h('retention_days')),
                  SayiAlani(denetleyici: _enCok, etiket: 'En çok ileti', hata: _h('max_messages')),
                  SayiAlani(denetleyici: _kota, etiket: 'Kota', sonEk: 'MB', hata: _h('quota_mb')),
                ],
              ),
              if (_hata != null && !{'name', 'retention_days', 'max_messages', 'quota_mb', 'organization_id'}.contains(_alan)) ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: hazir ? _kaydet : null, child: mesgulYazi(_mesgul, _yeni ? 'Oluştur' : 'Kaydet')),
      ],
    );
  }
}

/// Sandbox'ta yakalanan ileti (GET /sandboxes/{id}/messages → items).
class SandboxIletisi {
  SandboxIletisi(this.m);
  final Map<String, dynamic> m;
  static SandboxIletisi coz(Map<String, dynamic> m) => SandboxIletisi(m);

  String get id => metin(m['id']);
  String get konu => metinYa(m['subject']) ?? '(konu yok)';
  String get gonderen => metinYa(m['from_header']) ?? metinYa(m['mail_from']) ?? '<>';
  String get zarfGonderen => metinYa(m['mail_from']) ?? '<>';
  List<String> get alicilar => metinler(m['rcpts']);
  int get boyut => tamsayi(m['size_bytes']);
  int get ekSayisi => tamsayi(m['attachments']);
  bool get tls => mantik(m['tls']);
  String? get ip => metinYa(m['remote_ip']);
  DateTime? get zaman => tarihOku(m['received_at']);
  Map<String, dynamic> get analiz => harita(m['analysis']);
  Map<String, dynamic>? get spam => analiz['spam'] is Map ? harita(analiz['spam']) : null;
  List<Map<String, dynamic>> get sorunlar => haritalar(analiz['issues']);
  int get onemliSorun => sorunlar.where((i) => metin(i['level']) != 'info').length;
}

/// Bir sandbox'ın yakalanan iletileri: arama, sayfalama, ayrıntı, silme.
class SandboxIletileri extends StatefulWidget {
  const SandboxIletileri({super.key, required this.kutu});
  final SandboxKutusu kutu;
  @override
  State<SandboxIletileri> createState() => _SandboxIletileriState();
}

class _SandboxIletileriState extends State<SandboxIletileri> {
  String _q = '';
  SandboxIletisi? _secili;
  String get _yol => '/api/v1/sandboxes/${widget.kutu.id}/messages';

  late final _y = SayfaYukleyici<SandboxIletisi>(
    (s, b) async => Sayfa.coz(await Uyg.api.get(_yol, q: {'page': '$s', 'page_size': '$b', if (_q.isNotEmpty) 'q': _q}), SandboxIletisi.coz),
  )..yenile();

  /// Web paneli gibi 5 saniyede bir yeni yakalanan iletileri getirir (yalnızca ilk sayfadayken, gezintiyi bozmadan).
  Timer? _canli;

  @override
  void initState() {
    super.initState();
    _canli = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _y.yukleniyor || _y.sayfa > 1) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      if (TickerMode.valuesOf(context).enabled == false) return;
      _y.yenile();
    });
  }

  @override
  void dispose() {
    _canli?.cancel();
    _y.dispose();
    super.dispose();
  }

  Future<void> _tumunuSil() async {
    final evet = await onayla(
      context,
      'Tüm iletiler silinsin mi?',
      mesaj: 'Bu sandbox\'taki tüm yakalanan iletiler kalıcı olarak silinir.',
      evet: 'Tümünü sil',
      tehlikeli: true,
    );
    if (!evet) return;
    await islem(() => Uyg.api.delete(_yol), tamam: 'İletiler silindi');
    if (!mounted) return;
    setState(() => _secili = null);
    await _y.yenile();
  }

  void _silindi(SandboxIletisi m) {
    _y.degistir((x) => x.id == m.id, null);
    if (_secili?.id == m.id) setState(() => _secili = null);
  }

  void _ac(SandboxIletisi m) {
    if (bolunmus(context)) {
      setState(() => _secili = m);
    } else {
      sayfaAc(
        context,
        m.konu,
        SandboxIletiDetay(
          kutuId: widget.kutu.id,
          ileti: m,
          silindi: () {
            _silindi(m);
            Navigator.of(context).maybePop();
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kutu;
    final yonetir = Uyg.yetki('mailboxes.manage');
    final liste = VeriTablosu<SandboxIletisi>(
      yukleyici: _y,
      tabloEnAz: 100000,
      bosMetin: 'Yakalanan ileti yok. Uygulamanızı sandbox SMTP bilgileriyle yapılandırıp bir test iletisi gönderin.',
      bosIkon: Icons.inbox_outlined,
      onTap: _ac,
      secili: (m) => m.id == _secili?.id,
      ust: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: AramaAlani(
          ipucu: 'Konu, gönderen veya alıcı ara…',
          degisti: (v) {
            _q = v.trim();
            _y.yenile();
          },
        ),
      ),
      sutunlar: [Sutun('İleti', hucre: (c, m) => IkiSatir(m.konu, alt: m.gonderen))],
      kart: (c, m) => VeriKarti(
        baslik: m.konu,
        alt: m.gonderen,
        secili: m.id == _secili?.id,
        rozetler: [
          if (m.onemliSorun > 0) Rozet('${m.onemliSorun} sorun', renk: Marka.kehribar),
          if (m.spam != null) Rozet('spam ${ondalik(m.spam!['score']).toStringAsFixed(1)}', renk: mantik(m.spam!['refused']) ? Marka.gul : Marka.mavi),
        ],
        alanlar: [
          ('Alıcılar', m.alicilar.join(', ')),
          ('Boyut', '${boyutYaz(m.boyut)}${m.ekSayisi > 0 ? ' · ${m.ekSayisi} ek' : ''}'),
          ('Zaman', goreliZaman(m.zaman)),
        ],
        onTap: () => _ac(m),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k.ad, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              '${k.kullanici} · ${k.saklamaGun} gün saklanır · teslim edilmez',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.r.silik, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Yenile', onPressed: _y.yenile, icon: const Icon(Icons.refresh_rounded)),
          if (yonetir) IconButton(tooltip: 'Tümünü sil', onPressed: _tumunuSil, icon: const Icon(Icons.delete_sweep_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: AnaDetay(
        listeGenisligi: 440,
        liste: liste,
        bosMetin: 'Ayrıntı için bir ileti seçin',
        detay: _secili == null ? null : SandboxIletiDetay(key: ValueKey(_secili!.id), kutuId: k.id, ileti: _secili!, silindi: () => _silindi(_secili!)),
      ),
    );
  }
}

/// Yakalanan iletinin ayrıntısı: analiz kutuları, sorunlar, önizleme / metin / başlıklar / ham MIME / ekler / spam ayrıntısı.
class SandboxIletiDetay extends StatefulWidget {
  const SandboxIletiDetay({super.key, required this.kutuId, required this.ileti, required this.silindi});
  final String kutuId;
  final SandboxIletisi ileti;
  final VoidCallback silindi;
  @override
  State<SandboxIletiDetay> createState() => _SandboxIletiDetayState();
}

class _SandboxIletiDetayState extends State<SandboxIletiDetay> {
  String _sekme = 'onizleme';
  Future<String>? _ham;
  String get _yol => '/api/v1/sandboxes/${widget.kutuId}/messages/${widget.ileti.id}';

  /// Ham iletiyi .eml olarak indirir (GET …/raw?download=1).
  Future<void> _emlIndir() async {
    final konu = widget.ileti.konu.trim().isEmpty ? 'ileti' : widget.ileti.konu.trim();
    final ad = '${konu.length > 60 ? konu.substring(0, 60) : konu}.eml';
    await dosyaIndir('$_yol/raw', ad, q: {'download': '1'}, baslik: '.eml indiriliyor', tur: 'message/rfc822');
  }

  Future<void> _sil() async {
    final evet = await onayla(context, 'İleti silinsin mi?', evet: 'Sil', tehlikeli: true);
    if (!evet) return;
    final v = await islem(() async {
      await Uyg.api.delete(_yol);
      return true;
    }, tamam: 'İleti silindi');
    if (v == true) widget.silindi();
  }

  Widget _sekmeIcerigi(Map<String, dynamic> veri) {
    final r = context.r;
    final gorunum = harita(veri['view']);
    final analiz = harita(harita(veri['message'])['analysis']);
    final ekler = haritalar(gorunum['attachments']);
    Widget bos(String s) => Padding(
      padding: const EdgeInsets.all(8),
      child: Text(s, style: TextStyle(color: r.soluk)),
    );
    switch (_sekme) {
      case 'onizleme':
        final html = metin(gorunum['html']);
        if (html.trim().isEmpty) return bos('Bu iletide HTML bölümü yok.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              htmlGorunumuVar
                  ? 'Güvenli önizleme: betikler çalışmaz, uzak görseller ve bağlantılı içerik yüklenmez.'
                  : 'HTML bölümünün metin görünümü (bu platformda gömülü tarayıcı yok; uzak içerik ve betikler yüklenmez).',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
            const SizedBox(height: 6),
            HtmlOnizleme(html: html, yukseklik: 560),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('HTML kaynağı', style: TextStyle(fontSize: 14)),
              children: [KodBlogu(html, enFazlaYukseklik: 360)],
            ),
          ],
        );
      case 'metin':
        final t = metin(gorunum['text']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t.trim().isEmpty) bos('Düz metin bölümü yok; bazı istemciler ve erişilebilirlik araçları metin bölümü bekler.') else KodBlogu(t),
            if (mantik(gorunum['truncated']))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('İçerik kısaltıldı.', style: TextStyle(color: r.silik, fontSize: 12)),
              ),
          ],
        );
      case 'basliklar':
        final b = haritalar(veri['headers']);
        if (b.isEmpty) return bos('Başlık yok.');
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: r.kenar),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final (i, h) in b.indexed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    border: i == 0 ? null : Border(top: BorderSide(color: r.kenar)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          metin(h['name']),
                          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.soluk, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(metin(h['value']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'ham':
        _ham ??= Uyg.api.indir('$_yol/raw').then((b) => utf8.decode(b, allowMalformed: true));
        return FutureBuilder<String>(
          future: _ham,
          builder: (c, s) {
            if (s.hasError) return Bant(hataMetni(s.error!), renk: Marka.gul, ikon: Icons.error_outline_rounded);
            if (!s.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(onPressed: () => kopyala(s.data!), icon: const Icon(Icons.copy_rounded, size: 17), label: const Text('Kopyala')),
                      TextButton.icon(onPressed: _emlIndir, icon: const Icon(Icons.download_rounded, size: 17), label: const Text('.eml indir')),
                    ],
                  ),
                ),
                KodBlogu(s.data!),
              ],
            );
          },
        );
      case 'ekler':
        if (ekler.isEmpty) return bos('Ek yok.');
        return Column(
          children: [
            for (final (i, f) in ekler.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                trailing: IconButton(
                  tooltip: 'İndir',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () => dosyaIndir(
                    '$_yol/attachments/${f['index'] ?? i}',
                    metinYa(f['filename']) ?? 'ek-${f['index'] ?? i}',
                    baslik: 'Ek indiriliyor',
                    tur: metinYa(f['content_type']),
                  ),
                ),
                leading: const Icon(Icons.attach_file_rounded),
                title: Text(metinYa(f['filename']) ?? '(adsız)', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${metin(f['content_type'])} · ${boyutYaz(tamsayi(f['size']))}${mantik(f['inline']) ? ' · satır içi' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        );
      default:
        final sp = analiz['spam'] is Map ? harita(analiz['spam']) : null;
        if (sp == null) return bos('Spam analizi yapılamadı.');
        final bulgular = haritalar(sp['findings']);
        if (bulgular.isEmpty) return bos('Giden spam filtresi hiçbir kurala takılmadı.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in bulgular)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: r.kenar),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(metin(f['rule']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        mantik(f['block'])
                            ? const Rozet('engeller', renk: Marka.gul)
                            : Rozet('+${ondalik(f['score']).toStringAsFixed(1)}', renk: Marka.kehribar),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(metin(f['detail'])),
                    if (metinYa(f['fix']) != null) Text('Öneri: ${metin(f['fix'])}', style: TextStyle(color: r.silik, fontSize: 12)),
                  ],
                ),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TekYukleme<Map<String, dynamic>>(
      getir: () async => harita(await Uyg.api.get(_yol)),
      icerik: (c, veri, yenile) {
        final r = c.r;
        final m = SandboxIletisi(harita(veri['message']));
        final a = m.analiz;
        final sp = m.spam;
        final dkim = harita(a['dkim']);
        final html = harita(a['html']);
        final ekSay = haritalar(harita(veri['view'])['attachments']).length;
        return IcerikListesi(
          enFazla: 1000,
          children: [
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    m.konu,
                    style: gosterim(19, agirlik: FontWeight.w700, renk: r.metin),
                  ),
                ),
                if (Uyg.yetki('mailboxes.manage')) IconButton(tooltip: 'Sil', onPressed: _sil, icon: const Icon(Icons.delete_outline_rounded)),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              'MAIL FROM ${m.zarfGonderen} → ${m.alicilar.join(', ')} · ${tamZaman(m.zaman)} · ${m.tls ? 'TLS' : 'TLS yok'}${m.ip != null ? ' · ${m.ip}' : ''}',
              style: TextStyle(color: r.soluk, fontSize: 13),
            ),
            const SizedBox(height: 14),
            Izgara(
              enAz: 180,
              bosluk: 10,
              children: [
                KorumaKutusu(etiket: 'Boyut', deger: boyutYaz(tamsayi(a['size_bytes'], m.boyut)), alt: '${tamsayi(a['attachments'])} ek'),
                KorumaKutusu(
                  etiket: 'Spam puanı',
                  deger: sp == null ? '—' : '${ondalik(sp['score']).toStringAsFixed(1)} / ${metin(sp['threshold'])}',
                  alt: mantik(sp?['refused']) ? 'Giden filtre reddederdi' : 'Giden filtre geçer',
                  kotu: mantik(sp?['refused']),
                ),
                KorumaKutusu(
                  etiket: 'DKIM',
                  deger: mantik(dkim['signed']) ? 'İmzalı' : 'İmzasız',
                  alt: mantik(dkim['signed']) ? 'd=${metin(dkim['domain'])} s=${metin(dkim['selector'])}' : 'Gerçek gönderimde sunucu imzalar',
                ),
                KorumaKutusu(
                  etiket: 'HTML',
                  deger: mantik(html['has_html']) ? boyutYaz(tamsayi(html['html_bytes'])) : 'Yok',
                  alt: '${tamsayi(html['images'])} resim · ${tamsayi(html['links'])} bağlantı',
                ),
              ],
            ),
            if (m.sorunlar.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final i in m.sorunlar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      switch (metin(i['level'])) {
                        'error' => const Rozet('Hata', renk: Marka.gul),
                        'warn' => const Rozet('Uyarı', renk: Marka.kehribar),
                        _ => const Rozet('Bilgi', renk: Marka.mavi),
                      },
                      const SizedBox(width: 8),
                      Expanded(child: Text(metin(i['text']), style: const TextStyle(fontSize: 13.5))),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            SecimCipleri<String>(
              secenekler: [
                ('onizleme', 'Önizleme'),
                ('metin', 'Metin'),
                ('basliklar', 'Başlıklar'),
                ('ham', 'Ham MIME'),
                ('ekler', 'Ekler ($ekSay)'),
                ('spam', 'Spam ayrıntısı'),
              ],
              secili: _sekme,
              secildi: (v) => setState(() => _sekme = v),
            ),
            const SizedBox(height: 12),
            _sekmeIcerigi(veri),
          ],
        );
      },
    );
  }
}
