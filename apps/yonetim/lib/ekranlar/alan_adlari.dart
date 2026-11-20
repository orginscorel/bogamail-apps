import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'alan_detay.dart';
import 'bolumler.dart';
import 'liste_ortak.dart';
import 'posta_kutulari.dart';

/// Alan adları: sıralanabilir tablo (telefonda kartlar), mod / müşteri filtreleri, paket alan adı kotası,
/// satır menüsü ve sağdan açılan ayrıntı paneli (DNS, DKIM, gateway hedefi, posta programı ayarları).
class AlanAdlariEkrani extends StatefulWidget {
  const AlanAdlariEkrani({super.key, this.orgId, this.orgAdi});

  /// Belirli bir müşterinin alan adları (Müşteriler ekranından).
  final String? orgId, orgAdi;

  @override
  State<AlanAdlariEkrani> createState() => _AlanAdlariEkraniState();
}

class _AlanAdlariEkraniState extends State<AlanAdlariEkrani> {
  String _q = '';
  String _mod = '';
  late String? _orgId = widget.orgId;
  late String? _orgAdi = widget.orgAdi;
  String _sira = 'created_at';
  bool _artan = false;
  AlanKotasi? _kota;

  late final _y = SayfaYukleyici<AlanAdi>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/domains',
        q: {
          'page': '$s',
          'page_size': '$b',
          'sort': _sira,
          'order': _artan ? 'asc' : 'desc',
          if (_q.isNotEmpty) 'q': _q,
          if (_mod.isNotEmpty) 'mode': _mod,
          if (_orgId != null) 'organization_id': _orgId,
        },
      ),
      AlanAdi.coz,
    ),
  )..yenile();

  /// Kota gösterilen müşteri: müşteri yöneticisi için kendi kuruluşu, ortaklar için müşteri filtresi.
  String? get _kotaOrg => Uyg.musteri ? metinYa(Uyg.ben.value?['organization_id']) : _orgId;

  bool get _ikiMod => _kota == null ? (!Uyg.musteri || Uyg.paketTuru == 'hybrid' || Uyg.paketTuru.isEmpty) : _kota!.modlar.length > 1;

  @override
  void initState() {
    super.initState();
    _kotaYukle();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _kotaYukle() async {
    final org = _kotaOrg;
    if (org == null || org.isEmpty) {
      if (_kota != null) setState(() => _kota = null);
      return;
    }
    final k = await AlanKotasi.getir(org);
    if (mounted) setState(() => _kota = k);
  }

  void _yenile() {
    _y.yenile();
    _kotaYukle();
  }

  void _ac(AlanAdi a) => ayrintiAc(
    context,
    a.gorunenAd,
    AlanDetay(alan: a, degisti: (y) => _y.degistir((x) => x.id == a.id, y), tamSayfa: true),
  );

  Future<void> _ekle() async {
    final a = await showDialog<AlanAdi>(
      context: context,
      builder: (_) => AlanEkleDialog(orgId: _orgId, orgAdi: _orgAdi),
    );
    if (a == null || !mounted) return;
    _yenile();
    _ac(a);
  }

  Future<void> _durum(AlanAdi a, String durum) async {
    final askiya = durum == 'suspended';
    if (askiya && !await onayla(context, '${a.gorunenAd} askıya alınsın mı?', mesaj: 'Bu alan adına posta kabulü durur.', evet: 'Askıya al', tehlikeli: true)) {
      return;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/domains/${a.id}', {'status': durum}),
      tamam: askiya ? 'Alan adı askıya alındı' : 'Askı kaldırıldı (doğrulama bekliyor)',
    );
    if (v != null) _y.degistir((x) => x.id == a.id, AlanAdi.coz(harita(v)));
  }

  Future<void> _sil(AlanAdi a) async {
    if (a.kutuSayisi > 0) {
      bildir('Önce posta kutularını silin', mesaj: 'Alan adı yalnızca üzerinde posta kutusu kalmadığında silinebilir.', tur: MesajTur.uyari);
      return;
    }
    final ok = await yazarakOnayla(
      context,
      baslik: '${a.gorunenAd} silinsin mi?',
      mesaj: 'Alan adı, DKIM anahtarı ve DNS denetim kayıtları kalıcı olarak silinir. Bu işlem geri alınamaz.',
      beklenen: a.gorunenAd,
    );
    if (!ok) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/domains/${a.id}').then((_) => true), tamam: 'Alan adı silindi');
    if (v == true) {
      _y.degistir((x) => x.id == a.id, null);
      _kotaYukle();
    }
  }

  void _kutular(AlanAdi a) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PostaKutulariEkrani(alanId: a.id, alanAdi: a.gorunenAd)),
  );

  List<SatirEylemi> _eylemler(AlanAdi a) {
    final yonetir = Uyg.yetki('domains.manage');
    return [
      SatirEylemi(Icons.dns_outlined, 'DNS kayıtları ve ayrıntı', () => _ac(a)),
      if (a.hosting && Bolum.kutular.gorunur) SatirEylemi(Icons.inbox_rounded, 'Posta kutuları', () => _kutular(a)),
      if (!Uyg.musteri && _orgId == null) SatirEylemi(Icons.filter_alt_outlined, 'Bu müşteriye göre süz', () => _musteriSuz(a.orgId, a.orgAdi)),
      if (Uyg.ortak && yonetir)
        a.durum == 'suspended'
            ? SatirEylemi(Icons.play_circle_outline_rounded, 'Askıyı kaldır', () => _durum(a, 'pending'))
            : SatirEylemi(Icons.pause_circle_outline_rounded, 'Askıya al', () => _durum(a, 'suspended')),
      if (yonetir) SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(a), tehlikeli: true),
    ];
  }

  void _musteriSuz(String? id, String? ad) {
    setState(() {
      _orgId = id;
      _orgAdi = ad;
    });
    _yenile();
  }

  @override
  Widget build(BuildContext context) {
    final yonetir = Uyg.yetki('domains.manage');
    final dolu = _kota?.dolu ?? false;
    final etkin = <EtkinFiltre>[
      if (_mod.isNotEmpty)
        EtkinFiltre('Mod: ${_mod == 'hosting' ? 'Hosting' : 'Gateway'}', () {
          setState(() => _mod = '');
          _y.yenile();
        }),
      if (_orgId != null && !Uyg.musteri) EtkinFiltre('Müşteri: ${_orgAdi ?? 'seçili'}', () => _musteriSuz(null, null), ikon: Icons.business_rounded),
    ];
    return Iskelet(
      baslik: widget.orgAdi == null ? 'Alan Adları' : '${widget.orgAdi} · Alan adları',
      alt: _kota != null && _kota!.modlar.length == 1 && _kota!.modlar.first == 'hosting'
          ? 'Posta hizmeti verilen alan adları'
          : 'Barındırılan ve gateway modundaki alan adları',
      yenile: _yenile,
      birincil: yonetir
          ? BirincilEylem(Icons.add_rounded, 'Alan adı ekle', () {
              if (dolu) {
                bildir('Paket sınırına ulaşıldı', mesaj: 'Paketin alan adı sınırı dolu; yeni alan adı için paket yükseltilmeli.', tur: MesajTur.uyari);
                return;
              }
              _ekle();
            })
          : null,
      govde: VeriTablosu<AlanAdi>(
        yukleyici: _y,
        siralama: _sira,
        artan: _artan,
        siralamaDegisti: (a, b) {
          setState(() {
            _sira = a;
            _artan = b;
          });
          _y.yenile();
        },
        onTap: _ac,
        eylemler: _eylemler,
        bosMetin: _q.isEmpty && etkin.isEmpty ? 'Henüz alan adı yok. Bir müşteriye alan adı ekleyerek başlayın.' : 'Eşleşen alan adı yok.',
        bosIkon: Icons.language_rounded,
        ust: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_kota != null) Padding(padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 4, context.genis ? 16 : 12, 4), child: AlanKotaCubugu(_kota!)),
            FiltreCubugu(
              arama: AramaAlani(
                ipucu: 'Alan adı ara…',
                ilk: _q,
                degisti: (v) {
                  _q = v;
                  _y.yenile();
                },
              ),
              filtreler: [
                if (_ikiMod)
                  FiltreDugmesi<String>(
                    etiket: 'Mod',
                    ikon: Icons.alt_route_rounded,
                    secenekler: const [('', 'Tümü'), ('hosting', 'Hosting'), ('gateway', 'Gateway')],
                    secili: _mod,
                    secildi: (v) {
                      setState(() => _mod = v);
                      _y.yenile();
                    },
                  ),
                if (!Uyg.musteri)
                  ActionChip(
                    avatar: const Icon(Icons.business_rounded, size: 16),
                    label: Text(_orgId == null ? 'Müşteri seç' : 'Müşteriyi değiştir'),
                    onPressed: () async {
                      final o = await musteriSec(context);
                      if (o != null) _musteriSuz(o.id, o.ad);
                    },
                  ),
              ],
              etkinler: etkin,
            ),
          ],
        ),
        sutunlar: [
          Sutun(
            'Alan adı',
            esnek: 4,
            siralama: 'name',
            hucre: (c, a) => IkiSatir(a.gorunenAd, alt: a.unicodeAd != a.ad && a.unicodeAd.isNotEmpty ? a.ad : null, sol: _AlanIkonu(a)),
          ),
          if (!Uyg.musteri) Sutun('Müşteri', esnek: 3, siralama: 'organization', hucre: (c, a) => SolukMetin(a.orgAdi)),
          Sutun('Mod', genislik: 120, hucre: (c, a) => Sigdir(ModRozeti(a.hosting))),
          Sutun('Posta kutusu', genislik: 110, sagaYasla: true, hucre: (c, a) => Text(a.hosting ? sayiYaz(a.kutuSayisi) : '—', style: const TextStyle(fontWeight: FontWeight.w600))),
          Sutun('DNS', genislik: 140, hucre: (c, a) => Sigdir(DnsRozeti(a.dnsDurumu))),
          Sutun('Durum', genislik: 130, siralama: 'status', hucre: (c, a) => Sigdir(DurumRozeti(a.durum))),
          Sutun('Eklenme', genislik: 120, siralama: 'created_at', hucre: (c, a) => SolukMetin(kisaZaman(a.eklenme))),
        ],
        kart: (c, a) => VeriKarti(
          baslik: a.gorunenAd,
          alt: [if (!Uyg.musteri) a.orgAdi, if (a.unicodeAd != a.ad && a.unicodeAd.isNotEmpty) a.ad].join(' · '),
          sol: _AlanIkonu(a),
          rozetler: [DurumRozeti(a.durum), ModRozeti(a.hosting), DnsRozeti(a.dnsDurumu)],
          alanlar: [if (a.hosting) ('Posta kutusu', sayiYaz(a.kutuSayisi)), ('Eklenme', kisaZaman(a.eklenme))],
          eylemler: _eylemler(a),
          onTap: () => _ac(a),
        ),
      ),
    );
  }
}

/// Hosting / Gateway rozeti.
class ModRozeti extends StatelessWidget {
  const ModRozeti(this.hosting, {super.key});
  final bool hosting;
  @override
  Widget build(BuildContext context) =>
      Rozet(hosting ? 'Hosting' : 'Gateway', renk: hosting ? context.r.birincil : Marka.mavi, ikon: hosting ? Icons.dns_rounded : Icons.alt_route_rounded);
}

/// Müşterinin paket alan adı kotası (GET /organizations/{id}/entitlements): kullanılan, sınır, izinli modlar.
class AlanKotasi {
  const AlanKotasi({required this.kullanilan, required this.sinir, required this.modlar, required this.paket});
  final int kullanilan;
  final int? sinir;
  final List<String> modlar;
  final String paket;

  bool get dolu => sinir != null && kullanilan >= sinir!;

  static Future<AlanKotasi?> getir(String orgId) async {
    try {
      final e = harita(await Uyg.api.get('/api/v1/organizations/$orgId/entitlements'));
      final plan = harita(e['plan']);
      final tur = metin(plan['kind']);
      return AlanKotasi(
        kullanilan: tamsayi(harita(e['usage'])['domains']),
        sinir: tamsayiYa(harita(harita(e['effective'])['limits'])['max_domains']),
        modlar: tur == 'hosting' ? const ['hosting'] : (tur == 'gateway' ? const ['gateway'] : const ['hosting', 'gateway']),
        paket: metin(plan['name']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Alan adı kotası şeridi.
class AlanKotaCubugu extends StatelessWidget {
  const AlanKotaCubugu(this.k, {super.key});
  final AlanKotasi k;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = k.sinir;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
      child: Row(
        children: [
          Icon(Icons.language_rounded, size: 18, color: r.birincil),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: '${k.kullanilan}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ' / ${s ?? 'sınırsız'} alan adı${k.paket.isEmpty ? '' : ' · ${k.paket} paketi'}', style: TextStyle(color: r.soluk)),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (k.dolu)
                      Text(
                        Uyg.musteri ? 'Sınıra ulaşıldı — daha fazlası için paketinizi yükseltin' : 'Sınıra ulaşıldı',
                        style: const TextStyle(color: Marka.kehribar, fontSize: 12, fontWeight: FontWeight.w600),
                      )
                    else if (s != null)
                      Text('${s - k.kullanilan} hak kaldı', style: TextStyle(color: r.silik, fontSize: 12)),
                  ],
                ),
                if (s != null && s > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (k.kullanilan / s).clamp(0, 1).toDouble(),
                      minHeight: 5,
                      backgroundColor: r.ic,
                      color: k.dolu ? Marka.kehribar : r.birincil,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlanIkonu extends StatelessWidget {
  const _AlanIkonu(this.a);
  final AlanAdi a;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(12)),
      child: Icon(a.hosting ? Icons.dns_rounded : Icons.alt_route_rounded, color: r.birincil, size: 20),
    );
  }
}

class DnsRozeti extends StatelessWidget {
  const DnsRozeti(this.durum, {super.key});
  final String durum;
  @override
  Widget build(BuildContext context) => switch (durum) {
    'ok' => const Rozet('DNS tamam', renk: Marka.zumrut, ikon: Icons.check_circle_rounded),
    'issues' => const Rozet('DNS sorunu', renk: Marka.kehribar, ikon: Icons.warning_amber_rounded),
    _ => Rozet('Denetlenmedi', renk: context.r.silik, ikon: Icons.radio_button_unchecked_rounded),
  };
}

/// Alan adı ekleme (POST /domains). Türkçe karakterli alan adları sunucuda punycode'a çevrilir.
class AlanEkleDialog extends StatefulWidget {
  const AlanEkleDialog({super.key, this.orgId, this.orgAdi});
  final String? orgId, orgAdi;
  @override
  State<AlanEkleDialog> createState() => _AlanEkleDialogState();
}

class _AlanEkleDialogState extends State<AlanEkleDialog> {
  final _ad = TextEditingController();
  late String? _orgId = widget.orgId;
  late String? _orgAdi = widget.orgAdi;
  String _mod = 'hosting';
  bool _mesgul = false;
  String? _hata, _alan;

  AlanKotasi? _kota;

  List<String> get _modlar =>
      _kota?.modlar ??
      switch (Uyg.musteri ? Uyg.paketTuru : '') {
        'hosting' => ['hosting'],
        'gateway' => ['gateway'],
        _ => ['hosting', 'gateway'],
      };

  String get _etkinMod => _modlar.contains(_mod) ? _mod : _modlar.first;

  @override
  void initState() {
    super.initState();
    _mod = _modlar.first;
    _kotaYukle();
  }

  Future<void> _kotaYukle() async {
    final org = Uyg.musteri ? metinYa(Uyg.ben.value?['organization_id']) : _orgId;
    if (org == null || org.isEmpty) return;
    final k = await AlanKotasi.getir(org);
    if (mounted) setState(() => _kota = k);
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      final v = await Uyg.api.post('/api/v1/domains', {if (_orgId != null) 'organization_id': _orgId, 'name': _ad.text.trim(), 'mode': _etkinMod});
      final a = AlanAdi.coz(harita(v));
      bildir('${a.gorunenAd} eklendi', mesaj: 'Şimdi DNS kayıtlarını yayınlayın.', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, a);
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _alan = e.alan;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final musteriGerekli = !Uyg.musteri;
    final hazir = _ad.text.trim().isNotEmpty && (!musteriGerekli || _orgId != null) && !_mesgul && !(_kota?.dolu ?? false);
    return AlertDialog(
      title: Text('Alan adı ekle', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Türkçe karakterli (IDN) alan adları desteklenir ve otomatik olarak punycode biçimine çevrilir.',
                style: TextStyle(color: context.r.silik, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (musteriGerekli) ...[
                SecimAlani(
                  etiket: 'Müşteri',
                  deger: _orgAdi,
                  hata: _alan == 'organization_id' ? _hata : null,
                  onTap: () async {
                    final o = await musteriSec(context);
                    if (o != null) {
                      setState(() {
                        _orgId = o.id;
                        _orgAdi = o.ad;
                        _kota = null;
                      });
                      _kotaYukle();
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _ad,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: 'Alan adı', hintText: 'firma.com.tr', errorText: _alan == 'name' ? _hata : null),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => hazir ? _kaydet() : null,
              ),
              if (_kota != null) ...[
                const SizedBox(height: 10),
                if (_kota!.dolu)
                  Bant(
                    'Paketin alan adı sınırına ulaşıldı (${_kota!.kullanilan} / ${_kota!.sinir}). Yeni alan adı için paket yükseltilmeli.',
                    renk: Marka.kehribar,
                    ikon: Icons.warning_amber_rounded,
                  )
                else
                  Text(
                    '${_kota!.kullanilan} / ${_kota!.sinir ?? 'sınırsız'} alan adı kullanılıyor${_kota!.paket.isEmpty ? '' : ' · ${_kota!.paket} paketi'}.',
                    style: TextStyle(color: context.r.silik, fontSize: 12.5),
                  ),
              ],
              if (_modlar.length > 1) ...[
                const SizedBox(height: 14),
                Text(
                  'Kullanım modu',
                  style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'hosting', icon: Icon(Icons.dns_rounded), label: Text('Mail Hosting')),
                    ButtonSegment(value: 'gateway', icon: Icon(Icons.alt_route_rounded), label: Text('MX Gateway')),
                  ],
                  selected: {_etkinMod},
                  onSelectionChanged: (s) => setState(() => _mod = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _etkinMod == 'hosting' ? 'Posta kutuları bizde barınır.' : 'Gelen posta spam/virüs taramasından sonra müşterinin kendi sunucusuna iletilir. Hedef sunucuyu alan adı ayrıntısından veya Mail Gateway sayfasından girin; hedef tanımlanana kadar posta geçici hatayla (451) ertelenir, kaybolmaz.',
                  style: TextStyle(color: context.r.silik, fontSize: 12.5),
                ),
              ],
              if (_hata != null && _alan != 'name' && _alan != 'organization_id') ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: hazir ? _kaydet : null,
          child: _mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Ekle'),
        ),
      ],
    );
  }
}
