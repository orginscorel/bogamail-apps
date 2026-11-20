import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'bekletilenler.dart';
import 'tehdit_ortak.dart';

// Kötüye Kullanım Merkezi (web: admin/abuse): özet, olaylar (sinyaller, zaman çizelgesi, yanlış alarm / çözüldü /
// gönderimi aç), bekletilen iletiler, gönderimi durdurulan kutular ve risk puanı eşikleri.

const kotuyeEylemEtiketleri = <String, String>{
  'log': 'Kayıt',
  'notify': 'Yönetici bildirimi',
  'hold': 'Bekletme',
  'block': 'Gönderim durduruldu',
  'reset': 'Şifre sıfırlama',
  'warn': 'Göndereni uyar',
  'quarantine': 'Yönetici onayı',
};

const kotuyeDurumEtiketleri = <String, String>{'open': 'Açık', 'resolved': 'Çözüldü', 'false_positive': 'Yanlış alarm'};

const _olayTurleri = <String, String>{
  'detected': 'Tespit',
  'send_blocked': 'Gönderim durduruldu',
  'queue_held': 'Kuyruktaki iletiler bekletmeye alındı',
  'password_reset': 'Şifre sıfırlama zorunlu, oturumlar kapatıldı',
  'unblocked': 'Gönderim yeniden açıldı',
  'false_positive': 'Yanlış alarm olarak işaretlendi',
  'resolved': 'Çözüldü',
  'hold_released': 'Bekletilen ileti serbest bırakıldı',
  'hold_deleted': 'Bekletilen ileti silindi',
};

/// GET /abuse/incidents → öğe.
class KotuyeOlay {
  KotuyeOlay(this.m);
  final Map<String, dynamic> m;
  factory KotuyeOlay.coz(Map<String, dynamic> m) => KotuyeOlay(m);
  String get id => metin(m['id']);
  String get orgAdi => metin(m['organization_name']);
  String get kutuId => metin(m['mailbox_id']);
  String get kutu => metin(m['mailbox']);
  int get puan => tamsayi(m['score']);
  List<Map<String, dynamic>> get sinyaller => haritalar(m['signals']);
  List<String> get eylemler => metinler(m['actions']);
  String get durum => metin(m['status']);
  int get ileti => tamsayi(m['messages']);
  DateTime? get olusturma => tarihOku(m['created_at']);
  DateTime? get guncelleme => tarihOku(m['updated_at']);
  bool get gonderimKapali => mantik(m['send_blocked']);
  bool get sifreSifirlama => mantik(m['password_reset_required']);
  int get bekleyen => tamsayi(m['held']);
}

/// GET /abuse/blocked → öğe.
class DurdurulanKutu {
  DurdurulanKutu(this.m);
  final Map<String, dynamic> m;
  factory DurdurulanKutu.coz(Map<String, dynamic> m) => DurdurulanKutu(m);
  String get id => metin(m['id']);
  String get adres => metin(m['address']);
  String get orgAdi => metin(m['organization_name']);
  DateTime? get zaman => tarihOku(m['since']);
  String get neden => metin(m['reason']);
  bool get gonderimKapali => mantik(m['send_blocked']);
  bool get sifreSifirlama => mantik(m['password_reset_required']);
  int get bekleyen => tamsayi(m['held']);
}

Widget kotuyePuanRozeti(int p) => Rozet('$p', renk: p >= 75 ? Marka.gul : (p >= 50 ? Marka.kehribar : Colors.blueGrey));

/// Kötüye Kullanım Merkezi ekranı.
class KotuyeKullanimEkrani extends StatefulWidget {
  const KotuyeKullanimEkrani({super.key});
  @override
  State<KotuyeKullanimEkrani> createState() => _KotuyeKullanimEkraniState();
}

class _KotuyeKullanimEkraniState extends State<KotuyeKullanimEkrani> {
  Map<String, dynamic>? _ozet;
  int _nesil = 0;

  @override
  void initState() {
    super.initState();
    _ozetYukle();
  }

  Future<void> _ozetYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/abuse/summary'));
      if (mounted) setState(() => _ozet = v);
    } catch (_) {}
  }

  Widget _ozetSeridi(BuildContext context) {
    final o = _ozet;
    String d(String k) => o == null ? '–' : sayiYaz(tamsayi(o[k]));
    final bildirim = tamsayi(o?['notify']);
    final kartlar = [
      KpiKarti(
        ikon: Icons.report_outlined,
        etiket: 'Açık olay',
        deger: d('open'),
        renk: Marka.gul,
        alt: bildirim > 0 ? '$bildirim tanesi bildirim eşiğinde' : null,
      ),
      KpiKarti(ikon: Icons.block_rounded, etiket: 'Gönderimi durdurulan kutu', deger: d('blocked_mailboxes'), renk: Marka.kehribar),
      KpiKarti(ikon: Icons.pause_circle_outline_rounded, etiket: 'Bekletilen ileti', deger: d('held'), renk: Marka.mavi),
      KpiKarti(ikon: Icons.lock_person_outlined, etiket: 'DLP onayı bekleyen', deger: d('dlp_held'), renk: Marka.mor),
    ];
    if (context.genis) {
      return Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Izgara(enAz: 200, children: kartlar));
    }
    return SizedBox(
      height: 132,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        children: [for (final k in kartlar) Padding(padding: const EdgeInsets.only(right: 10), child: SizedBox(width: 190, child: k))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: Iskelet(
      baslik: 'Kötüye Kullanım Merkezi',
      alt: 'Ele geçirilmiş hesaplardan toplu gönderim tespiti',
      yenile: () {
        _ozetYukle();
        setState(() => _nesil++);
      },
      sekmeler: const TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [Tab(text: 'Olaylar'), Tab(text: 'Bekletilen iletiler'), Tab(text: 'Durdurulan kutular'), Tab(text: 'Eşikler')],
      ),
      govde: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ozetSeridi(context),
          Expanded(
            child: TabBarView(
              children: [
                _Olaylar(key: ValueKey('o$_nesil'), degisti: _ozetYukle),
                BekletilenlerListesi(key: ValueKey('b$_nesil')),
                _Durdurulanlar(key: ValueKey('d$_nesil'), degisti: _ozetYukle),
                _Esikler(key: ValueKey('e$_nesil')),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- olaylar ------------------------------------------------------------------------------------------------

class _Olaylar extends StatefulWidget {
  const _Olaylar({super.key, required this.degisti});
  final VoidCallback degisti;
  @override
  State<_Olaylar> createState() => _OlaylarState();
}

class _OlaylarState extends State<_Olaylar> {
  String _q = '', _durum = 'open';

  late final _y = SayfaYukleyici.yerel<KotuyeOlay>(
    () async => haritalar(
      harita(await Uyg.api.get('/api/v1/abuse/incidents', q: {'status': _durum, if (_q.isNotEmpty) 'q': _q}))['items'],
    ).map(KotuyeOlay.coz).toList(),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ac(KotuyeOlay o) async {
    final w = _OlayDetay(id: o.id);
    if (MediaQuery.sizeOf(context).width < 600) {
      await sayfaAc(context, o.kutu, w);
    } else {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(o.kutu, style: gosterim(18, agirlik: FontWeight.w700), overflow: TextOverflow.ellipsis),
          content: SizedBox(width: 640, child: w),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
        ),
      );
    }
    if (!mounted) return;
    _y.yenile();
    widget.degisti();
  }

  Widget _eylemRozetleri(KotuyeOlay o) {
    final l = o.eylemler.where((a) => a != 'log').toList();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final a in l) Rozet(kotuyeEylemEtiketleri[a] ?? a, renk: Colors.blueGrey),
        if (l.isEmpty) const SolukMetin('Yalnızca kayıt'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => VeriTablosu<KotuyeOlay>(
    yukleyici: _y,
    bosMetin: 'Olay yok. Şüpheli giden gönderim tespit edilmedi.',
    bosIkon: Icons.verified_user_outlined,
    onTap: _ac,
    ust: FiltreCubugu(
      arama: AramaAlani(
        ipucu: 'Posta kutusu veya müşteri…',
        degisti: (v) {
          _q = v;
          _y.yenile();
        },
      ),
      filtreler: [
        FiltreDugmesi<String>(
          etiket: 'Durum',
          ikon: Icons.flag_outlined,
          secenekler: const [('open', 'Açık'), ('false_positive', 'Yanlış alarm'), ('resolved', 'Çözüldü'), ('all', 'Tümü')],
          secili: _durum,
          secildi: (v) {
            setState(() => _durum = v);
            _y.yenile();
          },
        ),
      ],
    ),
    sutunlar: [
      Sutun('Posta kutusu', esnek: 4, hucre: (c, o) => IkiSatir(o.kutu, alt: '${o.orgAdi} · ${o.ileti} ileti')),
      Sutun('Puan', genislik: 70, hucre: (c, o) => Align(alignment: Alignment.centerLeft, child: kotuyePuanRozeti(o.puan))),
      Sutun('Uygulanan', esnek: 4, hucre: (c, o) => _eylemRozetleri(o)),
      Sutun('Durum', genislik: 110, hucre: (c, o) => SolukMetin(kotuyeDurumEtiketleri[o.durum] ?? o.durum)),
      Sutun('Son', genislik: 110, hucre: (c, o) => SolukMetin(goreliZaman(o.guncelleme))),
    ],
    kart: (c, o) => VeriKarti(
      baslik: o.kutu,
      alt: '${o.orgAdi} · ${o.ileti} ileti',
      onTap: () => _ac(o),
      rozetler: [
        kotuyePuanRozeti(o.puan),
        if (o.gonderimKapali) const Rozet('Gönderim durduruldu', renk: Marka.gul),
        Rozet(kotuyeDurumEtiketleri[o.durum] ?? o.durum, renk: Colors.blueGrey),
      ],
      alanlar: [('Son', goreliZaman(o.guncelleme))],
    ),
  );
}

/// Olay ayrıntısı (GET /abuse/incidents/{id}) ve işlemleri.
class _OlayDetay extends StatefulWidget {
  const _OlayDetay({required this.id});
  final String id;
  @override
  State<_OlayDetay> createState() => _OlayDetayState();
}

class _OlayDetayState extends State<_OlayDetay> {
  Map<String, dynamic>? _v;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/abuse/incidents/${widget.id}'));
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _calistir(String tur, KotuyeOlay o) async {
    final (baslik, evet, mesaj) = switch (tur) {
      'false-positive' => (
        'Yanlış alarm olarak işaretlensin mi?',
        'Yanlış alarm',
        'Olay kapanır, kutunun gönderimi açılır ve gözlenen hacim/alıcı/ağ değerleri kutunun tabanına eklenir; aynı davranış tekrar '
            'işaretlenmez. Bekletilen iletiler ayrıca serbest bırakılmalıdır.',
      ),
      'resolve' => ('Olay kapatılsın mı?', 'Kapat', 'Olay kapatılır; gönderim engeli varsa ayrıca açılmalıdır.'),
      _ => ('Gönderim açılsın mı?', 'Gönderimi aç', 'Kutu yeniden dışarıya posta gönderebilir. İşlem denetim kaydına yazılır.'),
    };
    if (!await onayla(context, baslik, mesaj: mesaj, evet: evet)) return;
    final yol = tur == 'unblock' ? '/api/v1/abuse/mailboxes/${o.kutuId}/unblock' : '/api/v1/abuse/incidents/${widget.id}/$tur';
    final tamam = switch (tur) {
      'unblock' => 'Gönderim yeniden açıldı',
      'resolve' => 'Olay kapatıldı',
      _ => 'Yanlış alarm olarak işaretlendi; kutunun tabanı güncellendi',
    };
    if (await islem(() => Uyg.api.post(yol), tamam: tamam) != null) _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = _v;
    if (v == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _hata != null ? Text(_hata!, style: const TextStyle(color: Marka.gul)) : const CircularProgressIndicator()),
      );
    }
    final o = KotuyeOlay(harita(v['item']));
    final yonetir = mantik(v['can_manage']);
    Widget baslik(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 6), child: Text(s, style: const TextStyle(fontWeight: FontWeight.w700)));
    return SingleChildScrollView(
      padding: MediaQuery.sizeOf(context).width < 600 ? const EdgeInsets.all(16) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${o.orgAdi} · puan ${o.puan} · ${kotuyeDurumEtiketleri[o.durum] ?? o.durum} · ilk tespit ${tamZaman(o.olusturma)}',
            style: TextStyle(color: r.silik, fontSize: 12.5),
          ),
          baslik('Sinyaller'),
          for (final s in o.sinyaller)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10), border: Border.all(color: r.kenar)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(metin(s['label']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                      Rozet('+${tamsayi(s['points'])}', renk: Marka.kehribar),
                    ],
                  ),
                  if (metin(s['detail']).isNotEmpty) Text(metin(s['detail']), style: TextStyle(color: r.silik, fontSize: 12)),
                ],
              ),
            ),
          baslik('Uygulanan eylemler'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in o.eylemler) Rozet(kotuyeEylemEtiketleri[a] ?? a, renk: Colors.blueGrey),
              if (o.gonderimKapali) const Rozet('Şu an gönderim kapalı', renk: Marka.gul),
              if (o.sifreSifirlama) const Rozet('Yönetici şifre vermeli', renk: Marka.gul),
              if (o.bekleyen > 0) Rozet('${o.bekleyen} ileti bekliyor', renk: Marka.mavi),
            ],
          ),
          baslik('Zaman çizelgesi'),
          for (final e in haritalar(v['timeline']))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 5), child: DurumNoktasi(r.vurgu, boyut: 7)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${tamZaman(tarihOku(e['at']))}  ', style: TextStyle(color: r.silik)),
                          TextSpan(text: _olayTurleri[metin(e['kind'])] ?? metin(e['kind']), style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (metin(e['kind']) == 'detected' && harita(e['detail'])['score'] is num)
                            TextSpan(text: ' · puan ${tamsayi(harita(e['detail'])['score'])}', style: TextStyle(color: r.silik)),
                          if (metin(e['kind']) == 'queue_held') TextSpan(text: ' · ${tamsayi(harita(e['detail'])['held'])} ileti', style: TextStyle(color: r.silik)),
                          TextSpan(text: ' · ${metin(e['actor']) == 'system' ? 'sistem' : metin(e['actor'])}', style: TextStyle(color: r.silik)),
                        ],
                      ),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (yonetir) ...[
            if (o.durum == 'open') ...[
              EylemSatiri(
                ikon: Icons.undo_rounded,
                baslik: 'Yanlış alarm',
                ipucu: 'Olayı kapat, gönderimi aç, bu davranışı kutunun tabanına ekle',
                onTap: () => _calistir('false-positive', o),
              ),
              const SizedBox(height: 8),
              EylemSatiri(
                ikon: Icons.check_circle_outline_rounded,
                baslik: 'Çözüldü olarak kapat',
                ipucu: 'Hesap güvenceye alındı (şifre değişti vb.)',
                onTap: () => _calistir('resolve', o),
              ),
              const SizedBox(height: 8),
            ],
            if (o.gonderimKapali)
              EylemSatiri(ikon: Icons.lock_open_rounded, baslik: 'Gönderimi aç', ipucu: 'Kutunun gönderim engelini kaldır', onTap: () => _calistir('unblock', o)),
          ] else
            Text(
              'Gönderimi açmak ve yanlış alarm bildirmek için platform/bayi yöneticinize başvurun. Bekletilen iletileri "Bekletilen iletiler" sekmesinden silebilirsiniz.',
              style: TextStyle(color: r.silik, fontSize: 12),
            ),
          if (o.sifreSifirlama) ...[
            const SizedBox(height: 10),
            const Bant(
              'Bu kutunun eski şifresi geçersiz kılındı. Posta Kutuları sayfasından yeni şifre verildiğinde kullanıcı tekrar giriş yapabilir.',
              renk: Marka.kehribar,
              ikon: Icons.key_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

// ---- durdurulan kutular ---------------------------------------------------------------------------------------

class _Durdurulanlar extends StatefulWidget {
  const _Durdurulanlar({super.key, required this.degisti});
  final VoidCallback degisti;
  @override
  State<_Durdurulanlar> createState() => _DurdurulanlarState();
}

class _DurdurulanlarState extends State<_Durdurulanlar> {
  bool _yonetir = false;

  late final _y = SayfaYukleyici.yerel<DurdurulanKutu>(() async {
    final v = harita(await Uyg.api.get('/api/v1/abuse/blocked'));
    final y = mantik(v['can_manage']);
    if (mounted && y != _yonetir) setState(() => _yonetir = y);
    return haritalar(v['items']).map(DurdurulanKutu.coz).toList();
  })..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ac(DurdurulanKutu k) async {
    if (!await onayla(
      context,
      'Gönderim açılsın mı?',
      mesaj: '${k.adres} yeniden dışarıya posta gönderebilir. Hesabın güvenceye alındığından (şifre değişikliği) emin olun.',
      evet: 'Gönderimi aç',
    )) {
      return;
    }
    if (await islem(() => Uyg.api.post('/api/v1/abuse/mailboxes/${k.id}/unblock'), tamam: 'Gönderim açıldı') != null) {
      _y.yenile();
      widget.degisti();
    }
  }

  List<SatirEylemi> _eylemler(DurdurulanKutu k) => [
    if (_yonetir && k.gonderimKapali) SatirEylemi(Icons.lock_open_rounded, 'Gönderimi aç', () => _ac(k)),
  ];

  List<Widget> _rozetler(DurdurulanKutu k) => [
    if (k.gonderimKapali) const Rozet('Gönderim kapalı', renk: Marka.gul),
    if (k.sifreSifirlama) const Rozet('Şifre sıfırlanmalı', renk: Marka.kehribar),
  ];

  @override
  Widget build(BuildContext context) => VeriTablosu<DurdurulanKutu>(
    yukleyici: _y,
    bosMetin: 'Gönderimi durdurulmuş veya şifre sıfırlaması bekleyen posta kutusu bulunmuyor.',
    bosIkon: Icons.verified_user_outlined,
    eylemler: _eylemler,
    sutunlar: [
      Sutun('Posta kutusu', esnek: 4, hucre: (c, k) => IkiSatir(k.adres, alt: k.orgAdi)),
      Sutun('Durum', esnek: 3, hucre: (c, k) => Wrap(spacing: 4, runSpacing: 4, children: _rozetler(k))),
      Sutun('Neden', esnek: 4, hucre: (c, k) => SolukMetin(k.neden)),
      Sutun('Bekleyen', genislik: 90, sagaYasla: true, hucre: (c, k) => Text(sayiYaz(k.bekleyen))),
      Sutun('Zaman', genislik: 110, hucre: (c, k) => SolukMetin(k.zaman == null ? '—' : goreliZaman(k.zaman))),
    ],
    kart: (c, k) => VeriKarti(
      baslik: k.adres,
      alt: k.orgAdi,
      rozetler: _rozetler(k),
      eylemler: _eylemler(k),
      alanlar: [('Neden', k.neden), ('Bekleyen', '${k.bekleyen}'), ('Zaman', k.zaman == null ? '—' : goreliZaman(k.zaman))],
    ),
  );
}

// ---- eşikler ------------------------------------------------------------------------------------------------

const _esikAlanlari = [
  ('log_at', 'Kayıt', 'Olay oluşturulur'),
  ('notify_at', 'Yönetici bildirimi', 'Panelde uyarı gösterilir'),
  ('hold_at', 'Bekletme', 'İleti kuyruğa değil bekletmeye alınır'),
  ('block_at', 'Gönderimi durdur', 'Kutu giriş yapabilir, gönderemez'),
  ('reset_at', 'Şifre sıfırlama', 'Eski şifre geçersiz, oturumlar kapanır'),
];

class _Esikler extends StatefulWidget {
  const _Esikler({super.key});
  @override
  State<_Esikler> createState() => _EsiklerState();
}

class _EsiklerState extends State<_Esikler> {
  String? _orgId, _orgAdi;
  Map<String, dynamic>? _v;
  String? _hata;
  bool _mesgul = false;
  final _alanlar = {for (final (k, _, _) in _esikAlanlari) k: TextEditingController()};
  bool _kuyruk = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final k in _alanlar.values) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() {
      _v = null;
      _hata = null;
    });
    try {
      final v = harita(await Uyg.api.get('/api/v1/abuse/policy', q: {'org': ?_orgId}));
      if (!mounted) return;
      final p = harita(v['policy']);
      for (final e in _alanlar.entries) {
        e.value.text = '${tamsayi(p[e.key])}';
      }
      setState(() {
        _v = v;
        _kuyruk = mantik(p['hold_queued']);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _kaydet() async {
    final govde = <String, dynamic>{'organization_id': _orgId, 'hold_queued': _kuyruk};
    for (final e in _alanlar.entries) {
      final n = int.tryParse(e.value.text.trim());
      if (n == null || n < 0 || n > 100) {
        bildir('Eşikler 0–100 arasında olmalı', tur: MesajTur.uyari);
        return;
      }
      govde[e.key] = n;
    }
    setState(() => _mesgul = true);
    final ok = await islem(() => Uyg.api.put('/api/v1/abuse/policy', govde), tamam: 'Eşikler kaydedildi');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok != null) _yukle();
  }

  Future<void> _sifirla() async {
    final org = _orgId;
    if (org == null) return;
    setState(() => _mesgul = true);
    final ok = await islem(() => Uyg.api.delete('/api/v1/abuse/policy/$org'), tamam: 'Müşteri ayarı kaldırıldı; platform varsayılanı geçerli');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok != null) _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = _v;
    final duzenler = v != null && mantik(v['can_edit']);
    final miras = v != null && mantik(harita(v['policy'])['inherited']);
    return IcerikListesi(
      children: [
        const SizedBox(height: 12),
        BolumKarti(
          baslik: 'Risk puanı eşikleri',
          ikon: Icons.tune_rounded,
          altBaslik: 'Puan 0–100; 0 o eylemi kapatır. Varsayılan: kayıt 20, bildirim ve bekletme 50, gönderimi durdurma 75, şifre sıfırlama kapalı.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (Uyg.ortak) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(Uyg.platformYoneticisi ? 'Platform varsayılanı' : 'Platform varsayılanı (salt okunur)'),
                      selected: _orgId == null,
                      showCheckmark: false,
                      onSelected: (_) {
                        _orgId = _orgAdi = null;
                        _yukle();
                      },
                    ),
                    MusteriFiltresi(
                      ad: _orgAdi,
                      degisti: (id, ad) {
                        _orgId = id;
                        _orgAdi = ad;
                        _yukle();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (v == null)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: _hata != null ? Text(_hata!, style: const TextStyle(color: Marka.gul)) : const CircularProgressIndicator()),
                )
              else ...[
                if (metin(v['scope']) == 'organization' && miras)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('Bu müşteri için özel ayar yok; platform varsayılanı gösteriliyor.', style: TextStyle(color: r.silik, fontSize: 12.5)),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (k, e, i) in _esikAlanlari)
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _alanlar[k],
                          enabled: duzenler,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: e, helperText: i, helperMaxLines: 2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _kuyruk,
                  onChanged: duzenler ? (b) => setState(() => _kuyruk = b ?? false) : null,
                  title: const Text('Gönderim durdurulduğunda kuyruktaki iletileri de beklet', style: TextStyle(fontSize: 13.5)),
                ),
                const SizedBox(height: 8),
                if (duzenler)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(onPressed: _mesgul ? null : _kaydet, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Kaydet')),
                      if (_orgId != null && !miras)
                        OutlinedButton(onPressed: _mesgul ? null : _sifirla, child: const Text('Platform varsayılanına dön')),
                    ],
                  )
                else
                  Text('Eşikleri platform/bayi yöneticisi değiştirebilir.', style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
