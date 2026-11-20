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
import 'ekip_imza.dart';
import 'ekip_kural_formu.dart';
import '../ortak/simgeler.dart';

const _imzaModlari = {'off': 'Kapalı', 'default': 'Varsayılan', 'locked': 'Zorunlu'};
const _gorevDurumlari = {'todo': 'Yapılacak', 'doing': 'Devam ediyor', 'done': 'Bitti'};
const _sosyalAlanlar = [('linkedin', 'LinkedIn'), ('x', 'X (Twitter)'), ('instagram', 'Instagram'), ('facebook', 'Facebook'), ('youtube', 'YouTube')];

Color _gorevRengi(String d) => switch (d) {
  'done' => Marka.zumrut,
  'doing' => Marka.mavi,
  _ => Marka.grafitAcik,
};

String _kisi(Object? p) {
  final m = harita(p);
  if (m.isEmpty) return '—';
  return metinYa(m['name']) ?? metin(m['address'], '—');
}

/// Ekip Çalışması (müşteri paneli): kurum imza şablonu, imza profil bilgileri, kurum geneli otomatik yanıt kuralları
/// ve görevler (salt okunur). Platform / bayi yöneticisi müşteri seçerek görür (?organization_id=).
class EkipCalismasiEkrani extends StatefulWidget {
  const EkipCalismasiEkrani({super.key});
  @override
  State<EkipCalismasiEkrani> createState() => _EkipCalismasiEkraniState();
}

class _EkipCalismasiEkraniState extends State<EkipCalismasiEkrani> {
  String? _orgId;
  String? _orgAdi;
  Map<String, dynamic>? _ov;
  String? _hata;
  int _surum = 0;

  bool get _ortak => !Uyg.musteri;
  Map<String, String> get _q => _ortak && _orgId != null ? {'organization_id': _orgId!} : const {};

  @override
  void initState() {
    super.initState();
    if (!_ortak) _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final v = harita(await Uyg.api.get('/api/v1/workplace', q: _q));
      if (mounted) setState(() => _ov = v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _musteriSec() async {
    final o = await musteriSec(context);
    if (o == null) return;
    setState(() {
      _orgId = o.id;
      _orgAdi = o.ad;
      _ov = null;
      _surum++;
    });
    _yukle();
  }

  void _hepsiniYenile() {
    setState(() => _surum++);
    _yukle();
  }

  Widget _sayaclar(Map<String, dynamic> ov) {
    final c = harita(ov['counts']);
    final f = harita(ov['features']);
    final r = context.r;
    Widget hap(IconData i, String e, String v) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: r.kart,
        border: Border.all(color: r.kenar),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 17, color: r.birincil),
          const SizedBox(width: 8),
          Text(e, style: TextStyle(color: r.soluk, fontSize: 12.5)),
          const SizedBox(width: 8),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 8, context.genis ? 16 : 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            hap(Simgeler.taskAlt, 'Açık görev', mantik(f['tasks']) ? sayiYaz(tamsayi(c['open_tasks'])) : '—'),
            const SizedBox(width: 8),
            hap(Simgeler.accountTree, 'Kurum kuralı', sayiYaz(tamsayi(c['org_rules']))),
            const SizedBox(width: 8),
            hap(Simgeler.badge, 'Profili dolu kutu', '${sayiYaz(tamsayi(c['profiles_filled']))} / ${sayiYaz(tamsayi(c['mailboxes']))}'),
            const SizedBox(width: 8),
            hap(Simgeler.draw, 'İmza şablonu', _imzaModlari[metin(ov['signature_mode'])] ?? '—'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ov = _ov;
    Widget govde;
    if (_ortak && _orgId == null) {
      govde = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Kapali('Bir müşterinin ekip çalışması ayarlarını görmek için müşteri seçin.', ikon: Simgeler.groups),
            FilledButton.icon(onPressed: _musteriSec, icon: const Icon(Simgeler.apartment), label: const Text('Müşteri seçin')),
          ],
        ),
      );
    } else if (ov == null) {
      govde = _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor();
    } else {
      final yonetir = mantik(ov['can_manage']);
      final departmanlar = metinler(ov['departments']);
      govde = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sayaclar(ov),
          Expanded(
            child: TabBarView(
              children: [
                _ImzaSekmesi(key: ValueKey('i$_surum'), q: _q, yonetir: yonetir, kaydedildi: _yukle),
                _ProfilSekmesi(key: ValueKey('p$_surum'), q: _q, yonetir: yonetir, departmanlar: departmanlar),
                _KuralSekmesi(key: ValueKey('k$_surum'), q: _q, yonetir: yonetir, departmanlar: departmanlar, degisti: _yukle),
                _GorevSekmesi(key: ValueKey('g$_surum'), q: _q, acik: mantik(harita(ov['features'])['tasks'])),
              ],
            ),
          ),
        ],
      );
    }
    return DefaultTabController(
      length: 4,
      child: Iskelet(
        baslik: 'Ekip Çalışması',
        alt: _ortak ? (_orgAdi ?? 'Müşteri seçilmedi') : 'İmza şablonu, profiller, otomatik yanıt kuralları ve görevler',
        yenile: _ortak && _orgId == null ? null : _hepsiniYenile,
        eylemler: [if (_ortak) IconButton(tooltip: 'Müşteri seç', onPressed: _musteriSec, icon: const Icon(Simgeler.apartment))],
        sekmeler: ov == null
            ? null
            : const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'İmza şablonu'),
                  Tab(text: 'Profil alanları'),
                  Tab(text: 'Otomatik yanıt kuralları'),
                  Tab(text: 'Görevler'),
                ],
              ),
        govde: govde,
      ),
    );
  }
}

// ---- imza şablonu ----

class _ImzaSekmesi extends StatefulWidget {
  const _ImzaSekmesi({super.key, required this.q, required this.yonetir, required this.kaydedildi});
  final Map<String, String> q;
  final bool yonetir;
  final VoidCallback kaydedildi;
  @override
  State<_ImzaSekmesi> createState() => _ImzaSekmesiState();
}

class _ImzaSekmesiState extends State<_ImzaSekmesi> {
  Map<String, dynamic>? _v;
  String? _hata;
  String _mod = 'off';
  final _sirket = TextEditingController();
  final _web = TextEditingController();
  final _sablon = TextEditingController();
  bool _profilDuzenlenir = false;
  bool _degisti = false;
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
    for (final k in [_sirket, _web, _sablon]) {
      k.addListener(_isaretle);
    }
  }

  void _isaretle() {
    if (!_degisti && mounted) setState(() => _degisti = true);
  }

  @override
  void dispose() {
    _sirket.dispose();
    _web.dispose();
    _sablon.dispose();
    super.dispose();
  }

  void _doldur() {
    final p = harita(_v?['policy']);
    _mod = metin(p['mode'], 'off');
    _sirket.text = metin(p['company']);
    _web.text = metin(p['web']);
    _sablon.text = metin(p['template_html']);
    _profilDuzenlenir = mantik(p['profile_user_editable']);
    _degisti = false;
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/workplace/signature', q: widget.q));
      if (!mounted) return;
      setState(() {
        _v = v;
        _hata = null;
        _doldur();
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _kaydet() async {
    setState(() => _mesgul = true);
    final v = await islem(
      () => Uyg.api.put(_yol('/api/v1/workplace/signature', widget.q), {
        'mode': _mod,
        'template_html': _sablon.text,
        'company': _sirket.text.trim(),
        'web': _web.text.trim(),
        'profile_user_editable': _profilDuzenlenir,
      }),
      tamam: 'İmza şablonu kaydedildi',
    );
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (v != null) {
      await _yukle();
      widget.kaydedildi();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    if (v == null) return _hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor();
    final r = context.r;
    final orgAdi = metin(v['organization_name']);
    final degiskenler = haritalar(v['variables']);
    final ornek = {
      ...imzaOrnekDegerleri,
      'sirket': _sirket.text.trim().isEmpty ? orgAdi : _sirket.text.trim(),
      if (_web.text.trim().isNotEmpty) 'web': _web.text.trim(),
    };
    final on = htmldenMetin(imzaDoldur(_sablon.text, ornek));
    final y = widget.yonetir;
    return IcerikListesi(
      children: [
        const SizedBox(height: 8),
        BolumKarti(
          baslik: 'Kurum imza şablonu',
          ikon: Simgeler.draw,
          altBaslik:
              '"Zorunlu" modda tüm kullanıcılar bu imzayı kullanır ve kendi imzalarını değiştiremez; "Varsayılan" modda imzası boş olanlara uygulanır. '
              'Değişkenler her kullanıcının profil bilgileriyle doldurulur.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'off', label: Text('Kapalı')),
                    ButtonSegment(value: 'default', label: Text('Varsayılan')),
                    ButtonSegment(value: 'locked', label: Text('Zorunlu')),
                  ],
                  selected: {_mod},
                  onSelectionChanged: y
                      ? (s) => setState(() {
                          _mod = s.first;
                          _degisti = true;
                        })
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _sirket,
                      enabled: y,
                      maxLength: 150,
                      decoration: InputDecoration(labelText: 'Şirket adı ({{sirket}})', hintText: orgAdi, counterText: ''),
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _web,
                      enabled: y,
                      maxLength: 200,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Kurum web adresi ({{web}})', hintText: 'https://firma.com.tr', counterText: ''),
                    ),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _profilDuzenlenir,
                onChanged: y
                    ? (b) => setState(() {
                        _profilDuzenlenir = b ?? false;
                        _degisti = true;
                      })
                    : null,
                title: const Text('Kullanıcılar kendi unvan / telefon / departman bilgilerini düzenleyebilsin'),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Hazır düzen:', style: TextStyle(color: r.soluk, fontSize: 12.5)),
                  for (final (ad, html) in imzaDuzenleri) OutlinedButton(onPressed: y ? () => _sablon.text = html : null, child: Text(ad)),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sablon,
                enabled: y,
                minLines: 6,
                maxLines: 14,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: const InputDecoration(labelText: 'Şablon (HTML)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final d in degiskenler)
                    Tooltip(
                      message: metin(d['Label']),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('{{${metin(d['Key'])}}}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        onPressed: !y
                            ? null
                            : () {
                                final s = _sablon.selection;
                                final ek = '{{${metin(d['Key'])}}}';
                                final t = _sablon.text;
                                final bas = s.isValid ? s.start : t.length, son = s.isValid ? s.end : t.length;
                                _sablon.value = TextEditingValue(
                                  text: t.replaceRange(bas, son, ek),
                                  selection: TextSelection.collapsed(offset: bas + ek.length),
                                );
                              },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Bir satırı boşken gizlemek için data-optional="unvan" ekleyin. Boyut sınırı posta kutularının imza sınırıdır '
                '(${boyutYaz(tamsayi(v['max_signature_bytes']))}).',
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Text(
                'Önizleme (örnek değerlerle, düz metin)',
                style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: r.ic,
                  border: Border.all(color: r.kenar),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(on.isEmpty ? 'Şablon boş.' : on, style: const TextStyle(fontSize: 13)),
              ),
              if (y) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_degisti) TextButton(onPressed: () => setState(_doldur), child: const Text('Vazgeç')),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: !_degisti || _mesgul ? null : _kaydet, child: const Text('Kaydet')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _yol(String yol, Map<String, String> q) => q.isEmpty ? yol : '$yol?${Uri(queryParameters: q).query}';

// ---- profil alanları ----

class _ProfilSekmesi extends StatefulWidget {
  const _ProfilSekmesi({super.key, required this.q, required this.yonetir, required this.departmanlar});
  final Map<String, String> q;
  final bool yonetir;
  final List<String> departmanlar;
  @override
  State<_ProfilSekmesi> createState() => _ProfilSekmesiState();
}

class _ProfilSekmesiState extends State<_ProfilSekmesi> {
  String _ara = '';
  String _departman = '';
  String _sira = 'address';
  bool _artan = true;

  late final _y = SayfaYukleyici<Map<String, dynamic>>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/workplace/profiles',
        q: {
          ...widget.q,
          'page': '$s',
          'page_size': '$b',
          'sort': _sira,
          'order': _artan ? 'asc' : 'desc',
          if (_ara.isNotEmpty) 'q': _ara,
          if (_departman.isNotEmpty) 'department': _departman,
        },
      ),
      (m) => m,
    ),
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _duzenle(Map<String, dynamic> x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ProfilDialog(kayit: x, q: widget.q, yonetir: widget.yonetir),
    );
    if (ok == true) _y.yenile();
  }

  String _ozet(Map<String, dynamic> p) => [metin(p['title']), metin(p['department']), metin(p['phone'])].where((x) => x.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Aramanıza uyan posta kutusu bulunamadı.',
      bosIkon: Simgeler.badge,
      onTap: _duzenle,
      siralama: _sira,
      artan: _artan,
      siralamaDegisti: (a, b) {
        setState(() {
          _sira = a;
          _artan = b;
        });
        _y.yenile();
      },
      eylemler: (x) => [SatirEylemi(Simgeler.edit, widget.yonetir ? 'İmza bilgilerini düzenle' : 'Görüntüle', () => _duzenle(x))],
      ust: FiltreCubugu(
        arama: AramaAlani(
          ipucu: 'Adres, ad, unvan ara',
          degisti: (v) {
            _ara = v.trim();
            _y.yenile();
          },
        ),
        filtreler: [
          if (widget.departmanlar.isNotEmpty)
            FiltreDugmesi<String>(
              etiket: 'Departman',
              ikon: Simgeler.workspaces,
              secenekler: [('', 'Tüm departmanlar'), for (final d in widget.departmanlar) (d, d)],
              secili: _departman,
              secildi: (v) {
                setState(() => _departman = v);
                _y.yenile();
              },
            ),
        ],
        etkinler: [
          if (_departman.isNotEmpty)
            EtkinFiltre('Departman: $_departman', () {
              setState(() => _departman = '');
              _y.yenile();
            }),
        ],
      ),
      sutunlar: [
        Sutun(
          'Posta kutusu',
          esnek: 4,
          siralama: 'address',
          hucre: (c, x) => IkiSatir(metinYa(x['display_name']) ?? metin(x['address']), alt: metin(x['address'])),
        ),
        Sutun('Unvan', esnek: 2, hucre: (c, x) => SolukMetin(metinYa(harita(x['profile'])['title']) ?? '—')),
        Sutun('Departman', esnek: 2, siralama: 'department', hucre: (c, x) => SolukMetin(metinYa(harita(x['profile'])['department']) ?? '—')),
        Sutun('Telefon', esnek: 2, hucre: (c, x) => SolukMetin(metinYa(harita(x['profile'])['phone']) ?? '—')),
      ],
      kart: (c, x) {
        final o = _ozet(harita(x['profile']));
        return VeriKarti(
          baslik: metinYa(x['display_name']) ?? metin(x['address']),
          alt: metin(x['address']),
          alanlar: [('Profil', o.isEmpty ? 'Profil boş' : o)],
          onTap: () => _duzenle(x),
        );
      },
    );
  }
}

class _ProfilDialog extends StatefulWidget {
  const _ProfilDialog({required this.kayit, required this.q, required this.yonetir});
  final Map<String, dynamic> kayit;
  final Map<String, String> q;
  final bool yonetir;
  @override
  State<_ProfilDialog> createState() => _ProfilDialogState();
}

class _ProfilDialogState extends State<_ProfilDialog> {
  late final Map<String, dynamic> _p = harita(widget.kayit['profile']);
  late final Map<String, TextEditingController> _k = {
    for (final a in ['title', 'department', 'phone', 'mobile', 'web']) a: TextEditingController(text: metin(_p[a])),
    for (final (a, _) in _sosyalAlanlar) 's.$a': TextEditingController(text: metin(harita(_p['social'])[a])),
  };
  bool _mesgul = false;

  @override
  void dispose() {
    for (final k in _k.values) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() => _mesgul = true);
    final sosyal = <String, String>{
      for (final (a, _) in _sosyalAlanlar)
        if (_k['s.$a']!.text.trim().isNotEmpty) a: _k['s.$a']!.text.trim(),
    };
    final v = await islem(
      () => Uyg.api.put(_yol('/api/v1/workplace/profiles/${metin(widget.kayit['mailbox_id'])}', widget.q), {
        for (final a in ['title', 'department', 'phone', 'mobile', 'web']) a: _k[a]!.text.trim(),
        'social': sosyal,
      }),
      tamam: 'Profil kaydedildi',
    );
    if (!mounted) return;
    if (v != null) {
      Navigator.pop(context, true);
    } else {
      setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final y = widget.yonetir;
    Widget alan(String a, String e, String ipucu, {int uzun = 100}) => SizedBox(
      width: 250,
      child: TextField(
        controller: _k[a],
        enabled: y,
        maxLength: uzun,
        decoration: InputDecoration(labelText: e, hintText: ipucu, counterText: ''),
      ),
    );
    final adres = metin(widget.kayit['address']);
    return AlertDialog(
      title: Text(metinYa(widget.kayit['display_name']) ?? adres, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(adres, style: TextStyle(color: context.r.soluk)),
              const SizedBox(height: 4),
              Text(
                'Unvan, departman ve telefon imzalardaki {{unvan}}, {{departman}}, {{telefon}} değişkenlerini doldurur. Departman, kurum kurallarında da kullanılır.',
                style: TextStyle(color: context.r.silik, fontSize: 12),
              ),
              if (!y) ...[const SizedBox(height: 8), const Bant('Bu işlem için posta kutusu yönetme yetkisi gerekir.', renk: Marka.kehribar)],
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  alan('title', 'Unvan', 'ör. Satış Müdürü'),
                  alan('department', 'Departman', 'ör. Satış'),
                  alan('phone', 'Telefon', '0212 000 00 00'),
                  alan('mobile', 'Cep telefonu', '0532 000 00 00'),
                  alan('web', 'Web adresi (boş: kurum adresi)', 'https://firma.com.tr', uzun: 200),
                  for (final (a, e) in _sosyalAlanlar) alan('s.$a', e, 'https://…', uzun: 200),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: Text(y ? 'Vazgeç' : 'Kapat')),
        if (y) FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

// ---- kurum geneli otomatik yanıt kuralları ----

class _KuralSekmesi extends StatefulWidget {
  const _KuralSekmesi({super.key, required this.q, required this.yonetir, required this.departmanlar, required this.degisti});
  final Map<String, String> q;
  final bool yonetir;
  final List<String> departmanlar;
  final VoidCallback degisti;
  @override
  State<_KuralSekmesi> createState() => _KuralSekmesiState();
}

class _KuralSekmesiState extends State<_KuralSekmesi> {
  bool _yanitlayici = true;

  late final _y = SayfaYukleyici.yerel<Map<String, dynamic>>(() async {
    final v = harita(await Uyg.api.get('/api/v1/workplace/autoreply-rules', q: widget.q));
    final o = mantik(v['autoresponder'], true);
    if (o != _yanitlayici && mounted) setState(() => _yanitlayici = o);
    return haritalar(v['items']);
  })..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _kaydet(Map<String, dynamic> k) async {
    final id = metin(k['id']);
    if (id.isEmpty) {
      await Uyg.api.post(_yol('/api/v1/workplace/autoreply-rules', widget.q), k);
    } else {
      await Uyg.api.patch(_yol('/api/v1/workplace/autoreply-rules/$id', widget.q), k);
    }
    bildir('Kural kaydedildi', tur: MesajTur.basari);
  }

  Future<void> _duzenle(Map<String, dynamic> k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => EkipKuralDialog(kural: k, departmanlar: widget.departmanlar, kaydet: _kaydet),
    );
    if (ok == true) {
      await _y.yenile();
      widget.degisti();
    }
  }

  Future<void> _degistir(Map<String, dynamic> k) async {
    final ac = !mantik(k['enabled']);
    final v = await islem(
      () => Uyg.api.patch(_yol('/api/v1/workplace/autoreply-rules/${metin(k['id'])}', widget.q), {...k, 'enabled': ac}),
      tamam: ac ? 'Kural etkinleştirildi' : 'Kural kapatıldı',
    );
    if (v != null) await _y.yenile();
  }

  Future<void> _sil(Map<String, dynamic> k) async {
    final ok = await onayla(context, 'Kural silinsin mi?', mesaj: '"${metin(k['name'])}" kuralı kalıcı olarak silinecek.', evet: 'Sil', tehlikeli: true);
    if (!ok) return;
    await islem(() => Uyg.api.delete(_yol('/api/v1/workplace/autoreply-rules/${metin(k['id'])}', widget.q)), tamam: 'Kural silindi');
    await _y.yenile();
    widget.degisti();
  }

  List<SatirEylemi> _eylemler(Map<String, dynamic> k) => !widget.yonetir
      ? const []
      : [
          SatirEylemi(Simgeler.edit, 'Düzenle', () => _duzenle(k)),
          SatirEylemi(Simgeler.powerSettingsNew, mantik(k['enabled']) ? 'Kapat' : 'Etkinleştir', () => _degistir(k)),
          SatirEylemi(Simgeler.deleteOutline, 'Sil', () => _sil(k), tehlikeli: true),
        ];

  Widget _durum(Map<String, dynamic> k) => mantik(k['enabled']) ? const Rozet('Etkin', renk: Marka.zumrut) : Rozet('Kapalı', renk: context.r.soluk);

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Henüz kurum geneli otomatik yanıt kuralı tanımlanmadı.',
      bosIkon: Simgeler.accountTree,
      onTap: widget.yonetir ? _duzenle : null,
      eylemler: widget.yonetir ? _eylemler : null,
      ust: Padding(
        padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tüm kurum veya bir departman için (ör. mesai dışı yanıtı). Kullanıcının kendi kuralları önce denenir. Toplu postalar, listeler ve otomatik '
              'iletiler RFC 3834\'e göre yanıtlanmaz; aynı gönderene kural başına belirlenen günde en fazla bir yanıt gider.',
              style: TextStyle(color: r.soluk, fontSize: 12.5),
            ),
            if (!_yanitlayici) ...[
              const SizedBox(height: 8),
              const Bant('Paketinizde otomatik yanıt yok; kurallar kaydedilebilir ama yanıt gönderilmez.', renk: Marka.kehribar),
            ],
            if (widget.yonetir) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(onPressed: () => _duzenle(ekipYeniKural()), icon: const Icon(Simgeler.add), label: const Text('Kural ekle')),
              ),
            ],
            if (!widget.yonetir) ...[
              const SizedBox(height: 8),
              Text('Kuralları değiştirmek için posta kutusu yönetme yetkisi gerekir.', style: TextStyle(color: r.silik, fontSize: 12)),
            ],
          ],
        ),
      ),
      sutunlar: [
        Sutun('Kural', esnek: 5, hucre: (c, k) => IkiSatir(metin(k['name']), alt: ekipKuralOzeti(k))),
        Sutun('Kapsam', esnek: 2, hucre: (c, k) => SolukMetin(metinYa(k['department']) ?? 'Tüm kurum')),
        Sutun(
          'Durum',
          esnek: 1,
          hucre: (c, k) => Align(alignment: Alignment.centerLeft, child: _durum(k)),
        ),
      ],
      kart: (c, k) => VeriKarti(
        baslik: metin(k['name']),
        alt: ekipKuralOzeti(k),
        rozetler: [_durum(k)],
        alanlar: [('Kapsam', metinYa(k['department']) ?? 'Tüm kurum')],
        eylemler: _eylemler(k),
        onTap: widget.yonetir ? () => _duzenle(k) : null,
      ),
    );
  }
}

// ---- görevler (salt okunur) ----

class _GorevSekmesi extends StatefulWidget {
  const _GorevSekmesi({super.key, required this.q, required this.acik});
  final Map<String, String> q;
  final bool acik;
  @override
  State<_GorevSekmesi> createState() => _GorevSekmesiState();
}

class _GorevSekmesiState extends State<_GorevSekmesi> {
  String _ara = '';
  String _durum = 'open';
  String _sira = 'created';
  bool _artan = false;

  late final _y = SayfaYukleyici<Map<String, dynamic>>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/workplace/tasks',
        q: {...widget.q, 'page': '$s', 'page_size': '$b', 'status': _durum, 'sort': _sira, 'order': _artan ? 'asc' : 'desc', if (_ara.isNotEmpty) 'q': _ara},
      ),
      (m) => m,
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.acik) _y.yenile();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Widget _durumRozeti(Map<String, dynamic> t) {
    final d = metin(t['status']);
    return Rozet(_gorevDurumlari[d] ?? d, renk: _gorevRengi(d));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.acik) {
      return const Kapali(
        'Görevler paketinizde yok. Görevler modülü Kurumsal Mail 2, 3, 4, İş ve Kurumsal paketlerinde bulunur.',
        ikon: Simgeler.taskAlt,
      );
    }
    const durumlar = [('open', 'Açık'), ('todo', 'Yapılacak'), ('doing', 'Devam ediyor'), ('done', 'Bitti'), ('all', 'Tümü')];
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Bu filtreye uyan görev bulunamadı.',
      bosIkon: Simgeler.taskAlt,
      siralama: _sira,
      artan: _artan,
      siralamaDegisti: (a, b) {
        setState(() {
          _sira = a;
          _artan = b;
        });
        _y.yenile();
      },
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'Başlık veya kişi ara',
              degisti: (v) {
                _ara = v.trim();
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Durum',
                ikon: Simgeler.filterList,
                secenekler: durumlar,
                secili: _durum,
                secildi: (v) {
                  setState(() => _durum = v);
                  _y.yenile();
                },
              ),
            ],
            etkinler: [
              if (_durum != 'open')
                EtkinFiltre('Durum: ${durumlar.firstWhere((x) => x.$1 == _durum).$2}', () {
                  setState(() => _durum = 'open');
                  _y.yenile();
                }),
            ],
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.genis ? 16 : 12, vertical: 4),
            child: Text(
              'Salt okunur. Görev notları, yorumlar ve bağlı e-postalar gizlilik gereği yalnızca ilgili kullanıcılara görünür.',
              style: TextStyle(color: context.r.silik, fontSize: 12),
            ),
          ),
        ],
      ),
      sutunlar: [
        Sutun(
          'Görev',
          esnek: 4,
          siralama: 'title',
          hucre: (c, t) => Row(
            children: [
              Flexible(child: IkiSatir(metin(t['title']), alt: tamsayi(t['comments']) > 0 ? '${tamsayi(t['comments'])} yorum' : null)),
              if (t['priority'] == 'high') ...[const SizedBox(width: 8), const Rozet('Yüksek öncelik', renk: Marka.gul)],
            ],
          ),
        ),
        Sutun('Oluşturan', esnek: 2, hucre: (c, t) => SolukMetin(_kisi(t['creator']))),
        Sutun('Atanan', esnek: 2, hucre: (c, t) => SolukMetin(_kisi(t['assignee']))),
        Sutun('Son tarih', esnek: 2, siralama: 'due', hucre: (c, t) => SolukMetin(tarihOku(t['due_at']) == null ? '—' : tamZaman(tarihOku(t['due_at'])))),
        Sutun(
          'Durum',
          esnek: 2,
          hucre: (c, t) => Align(alignment: Alignment.centerLeft, child: _durumRozeti(t)),
        ),
      ],
      kart: (c, t) => VeriKarti(
        baslik: metin(t['title']),
        alt: '${_kisi(t['creator'])} → ${_kisi(t['assignee'])}',
        rozetler: [
          _durumRozeti(t),
          if (t['priority'] == 'high') const Rozet('Yüksek öncelik', renk: Marka.gul),
        ],
        alanlar: [if (tarihOku(t['due_at']) != null) ('Son tarih', tamZaman(tarihOku(t['due_at'])))],
      ),
    );
  }
}
