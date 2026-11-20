import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show baytlariKaydet;
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import 'tehdit_ortak.dart';
import '../ortak/simgeler.dart';

// Platform kurulum sihirbazı (web: admin/setup, yalnızca süper yönetici): DNS kayıtları ve sunucu ayarlarının canlı
// doğrulaması, platform alan adı / MTA-STS ayarı, DKIM anahtarı, güvenlik kontrol listesi, durum değişiklikleri, dışa aktarma.

const kurulumDurumEtiketleri = <String, String>{
  'ok': 'OK',
  'missing': 'Eksik',
  'wrong': 'Hatalı',
  'warn': 'Uyarı',
  'unknown': 'Kontrol edilemedi',
  'info': 'Bilgi',
};

Color kurulumDurumRengi(String d) => switch (d) {
  'ok' => Marka.zumrut,
  'missing' || 'wrong' => Marka.gul,
  'warn' => Marka.kehribar,
  _ => Colors.blueGrey,
};

/// Kurulum durumu hapı.
class KurulumDurumu extends StatelessWidget {
  const KurulumDurumu(this.durum, {super.key});
  final String durum;
  @override
  Widget build(BuildContext context) => Rozet(kurulumDurumEtiketleri[durum] ?? durum, renk: kurulumDurumRengi(durum));
}

/// Kurulum ekranı.
class KurulumEkrani extends StatefulWidget {
  const KurulumEkrani({super.key});
  @override
  State<KurulumEkrani> createState() => _KurulumEkraniState();
}

class _KurulumEkraniState extends State<KurulumEkrani> {
  Map<String, dynamic>? _v;
  String? _hata;
  bool _dogruluyor = false, _dkimMesgul = false, _otomatik = false;

  @override
  void initState() {
    super.initState();
    if (Uyg.platformYoneticisi) _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/platform-setup'));
      if (!mounted) return;
      setState(() {
        _v = v;
        _hata = null;
      });
      // Canlı görünüm: son sonuç 5 dakikadan eskiyse hemen yeniden denetle (web ile aynı).
      final at = tarihOku(harita(v['run'])['checked_at']);
      if (!_otomatik && (at == null || DateTime.now().difference(at) > const Duration(minutes: 5))) {
        _otomatik = true;
        _dogrula(sessiz: true);
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _dogrula({bool sessiz = false}) async {
    setState(() => _dogruluyor = true);
    try {
      final d = harita(await Uyg.api.post('/api/v1/platform-setup/verify'));
      if (!mounted) return;
      setState(() => _v = d);
      final run = harita(d['run']);
      if (!sessiz) bildir('Doğrulama tamamlandı: ${tamsayi(run['ok'])}/${tamsayi(run['total'])}', tur: MesajTur.basari);
    } catch (e) {
      if (!sessiz) bildir('Doğrulama başarısız', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _dogruluyor = false);
    }
  }

  Future<void> _dkim() async {
    setState(() => _dkimMesgul = true);
    final d = await islem(() => Uyg.api.post('/api/v1/platform-setup/dkim'), tamam: 'DKIM anahtarı üretildi; kaydı görmek için "Tümünü doğrula"yı çalıştırın');
    if (!mounted) return;
    setState(() {
      _dkimMesgul = false;
      if (d != null) _v = harita(d);
    });
  }

  Future<void> _isaretle(String id, bool tamam) async {
    final d = await islem(() => Uyg.api.put('/api/v1/platform-setup/checklist', {'id': id, 'done': tamam}));
    if (d != null && mounted) setState(() => _v = harita(d));
  }

  void _disaAktar(String bicim) => showDialog<void>(context: context, builder: (_) => _DisaAktar(bicim: bicim));

  @override
  Widget build(BuildContext context) {
    if (!Uyg.platformYoneticisi) {
      return const Iskelet(baslik: 'Kurulum', govde: Kapali('Bu bölüm yalnızca platform yöneticisine açıktır.'));
    }
    final v = _v;
    final run = v?['run'] is Map ? harita(v!['run']) : null;
    return Iskelet(
      baslik: 'Kurulum',
      alt: 'Platform posta sisteminin DNS kayıtları ve sunucu ayarları',
      eylemler: [
        IconButton(tooltip: 'BIND bölge kaydı', onPressed: run == null ? null : () => _disaAktar('bind'), icon: const Icon(Simgeler.description)),
        IconButton(tooltip: 'Kayıt tablosu', onPressed: run == null ? null : () => _disaAktar('table'), icon: const Icon(Simgeler.tableChart)),
      ],
      yenile: _yukle,
      birincil: BirincilEylem(Simgeler.factCheck, _dogruluyor ? 'Doğrulanıyor…' : 'Tümünü doğrula', _dogruluyor ? () {} : _dogrula),
      govde: v == null
          ? (_hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor())
          : Stack(
              children: [
                Positioned.fill(child: RefreshIndicator.adaptive(onRefresh: _yukle, child: _govde(context, v, run))),
                if (_dogruluyor) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
              ],
            ),
    );
  }

  Widget _govde(BuildContext context, Map<String, dynamic> v, Map<String, dynamic>? run) {
    final r = context.r;
    final ok = tamsayi(run?['ok']), toplam = tamsayi(run?['total']);
    final kontroller = haritalar(run?['checks']);
    final dkim = harita(v['dkim']);
    return IcerikListesi(
      children: [
        const SizedBox(height: 12),
        if (metin(v['dns_note']).isNotEmpty) ...[Bant(metin(v['dns_note']), renk: Marka.kehribar), const SizedBox(height: 16)],
        BolumKarti(
          baslik: 'Genel ilerleme',
          ikon: Simgeler.donutLarge,
          sag: Text(run == null ? '—' : '$ok/$toplam', style: gosterim(18, agirlik: FontWeight.w600, renk: r.metin)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: toplam == 0 ? 0 : ok / toplam, minHeight: 9, backgroundColor: r.ic, color: Marka.zumrut),
              ),
              const SizedBox(height: 8),
              Text(
                '${run == null ? 'Henüz doğrulanmadı' : 'Son doğrulama: ${tamZaman(tarihOku(run['checked_at']))} (${metin(run['trigger']) == 'schedule' ? 'otomatik' : 'elle'})'} · ${metin(v['schedule'])}',
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
              for (final n in metinler(v['notes'])) Padding(padding: const EdgeInsets.only(top: 4), child: Aciklama('•  $n')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AyarKarti(key: ValueKey('${v['domain']}|${v['mta_sts_mode']}'), v: v, kaydedildi: (d) => setState(() => _v = d)),
        const SizedBox(height: 16),
        if (run == null)
          BolumKarti(
            baslik: 'Henüz doğrulama yapılmadı',
            ikon: Simgeler.hourglassEmpty,
            child: const Aciklama('"Tümünü doğrula" ile tüm kayıtları ve sunucu ayarlarını şimdi denetleyin.'),
          )
        else
          for (final s in haritalar(v['steps']).where((s) => kontroller.any((c) => tamsayi(c['step']) == tamsayi(s['step']))))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AdimKarti(
                key: ValueKey('${run['id']}-${s['step']}'),
                adim: s,
                kontroller: kontroller.where((c) => tamsayi(c['step']) == tamsayi(s['step'])).toList(),
                ek: tamsayi(s['step']) == 3
                    ? (c) {
                        if (metin(c['id']) != 'dkim') return null;
                        if (mantik(dkim['can_generate'])) {
                          return OutlinedButton.icon(
                            onPressed: _dkimMesgul ? null : _dkim,
                            icon: const Icon(Simgeler.key, size: 18),
                            label: Text(dkim['key'] is Map ? 'Yeni DKIM anahtarı üret (döndür)' : 'DKIM anahtarı üret'),
                          );
                        }
                        if (mantik(dkim['hosted_domain'])) {
                          return const Aciklama('Bu alan adı platformda barındırılıyor; anahtar Alan Adları sayfasından yönetilir.');
                        }
                        return null;
                      }
                    : null,
              ),
            ),
        const SizedBox(height: 4),
        BolumKarti(
          baslik: 'Güvenlik kontrol listesi — Aşama B',
          ikon: Simgeler.checklist,
          altBaslik:
              'Port 25 ve istemci portlarını herkese açmadan önce (${metin(v['checklist_doc'])}). Canlı denetimden gelen maddeler otomatik, diğerleri sahip onayıyla elle işaretlenir.',
          child: Column(
            children: [
              for (final it in haritalar(v['checklist']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: mantik(it['manual'])
                      ? Checkbox(value: mantik(it['done']), onChanged: (b) => _isaretle(metin(it['id']), b ?? false))
                      : const SizedBox(width: 48),
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${metin(it['id'])}  ', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.silik)),
                        TextSpan(text: metin(it['title'])),
                      ],
                    ),
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  subtitle: metinYa(it['hint']) == null ? null : Text(metin(it['hint']), style: TextStyle(color: r.silik, fontSize: 12)),
                  trailing: KurulumDurumu(mantik(it['manual']) ? (mantik(it['done']) ? 'ok' : 'info') : metin(it['status'])),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Durum değişiklikleri',
          ikon: Simgeler.history,
          altBaslik: 'Doğrulamalar arasında durumu değişen kalemler (ilk gözlem dahil).',
          child: haritalar(v['changes']).isEmpty
              ? Text('Henüz kayıt yok.', style: TextStyle(color: r.silik))
              : Column(
                  children: [
                    for (final c in haritalar(v['changes']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(metin(c['label']), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(tamZaman(tarihOku(c['at'])), style: TextStyle(color: r.silik, fontSize: 11.5)),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (metin(c['from']).isEmpty) const Rozet('ilk', renk: Colors.blueGrey) else KurulumDurumu(metin(c['from'])),
                            Icon(SimgelerKalin.arrowForward, size: 14, color: r.silik),
                            KurulumDurumu(metin(c['to'])),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Sunucu ve platform alan adı ayarları (PUT /platform-setup/settings).
class _AyarKarti extends StatefulWidget {
  const _AyarKarti({super.key, required this.v, required this.kaydedildi});
  final Map<String, dynamic> v;
  final ValueChanged<Map<String, dynamic>> kaydedildi;
  @override
  State<_AyarKarti> createState() => _AyarKartiState();
}

class _AyarKartiState extends State<_AyarKarti> {
  late final _alan = TextEditingController(text: mantik(widget.v['domain_configured']) ? metin(widget.v['domain']) : '');
  late String _kip = const {'testing', 'enforce', 'none'}.contains(metin(widget.v['mta_sts_mode'])) ? metin(widget.v['mta_sts_mode']) : 'testing';
  String? _hata;
  bool _mesgul = false;

  @override
  void dispose() {
    _alan.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final d = harita(await Uyg.api.put('/api/v1/platform-setup/settings', {'domain': _alan.text.trim(), 'mta_sts_mode': _kip}));
      bildir('Kaydedildi', mesaj: 'Değişikliği görmek için "Tümünü doğrula"yı çalıştırın.', tur: MesajTur.basari);
      widget.kaydedildi(d);
    } on ApiHata catch (e) {
      if (e.alan != null) {
        setState(() => _hata = e.mesaj);
      } else {
        bildir('Kaydedilemedi', mesaj: e.mesaj, tur: MesajTur.hata);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final varsayilan = metin(v['domain_default']);
    return BolumKarti(
      baslik: 'Sunucu ve platform alan adı',
      ikon: Simgeler.dns,
      altBaslik: 'Kayıtlar bu bilgilere göre üretilir. Sunucu adı ve IP yapılandırmadan gelir.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EtiketDeger('Sunucu adı', metinYa(v['hostname']) ?? '—', mono: true),
          EtiketDeger('Genel IP', metinler(v['ips']).isEmpty ? '—' : metinler(v['ips']).join(', '), mono: true),
          EtiketDeger('DMARC rapor', metin(v['dmarc_report']), mono: true),
          EtiketDeger('TLS-RPT', metin(v['tls_rpt_report']), mono: true),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 340,
                child: TextField(
                  controller: _alan,
                  decoration: InputDecoration(
                    labelText: 'Platform alan adı',
                    hintText: '$varsayilan (varsayılan)',
                    errorText: _hata,
                    helperText: 'Rapor adresleri, MTA-STS ve otomatik yapılandırma bu alan adına göre. Boş bırakılırsa '
                        '${varsayilan.isEmpty ? 'sunucu adının üst alanı' : varsayilan} kullanılır.',
                    helperMaxLines: 3,
                  ),
                ),
              ),
              SizedBox(
                width: 340,
                child: DropdownButtonFormField<String>(
                  initialValue: _kip,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'MTA-STS kipi',
                    helperText: 'Genel sertifika kurulmadan "enforce" seçmeyin: gönderenler postayı teslim edemez.',
                    helperMaxLines: 3,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'testing', child: Text('testing — yalnızca raporla (önerilen)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'enforce', child: Text('enforce — TLS zorunlu', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'none', child: Text('none — politikayı kaldır', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (k) => setState(() => _kip = k ?? _kip),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(onPressed: _mesgul ? null : _kaydet, icon: const Icon(Simgeler.save, size: 18), label: const Text('Kaydet')),
          ),
        ],
      ),
    );
  }
}

/// Bir kurulum adımı ve denetimleri (açılır).
class _AdimKarti extends StatefulWidget {
  const _AdimKarti({super.key, required this.adim, required this.kontroller, this.ek});
  final Map<String, dynamic> adim;
  final List<Map<String, dynamic>> kontroller;
  final Widget? Function(Map<String, dynamic>)? ek;
  @override
  State<_AdimKarti> createState() => _AdimKartiState();
}

class _AdimKartiState extends State<_AdimKarti> {
  late bool _acik = metin(widget.adim['status']) != 'ok';

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final a = widget.adim;
    final ok = tamsayi(a['ok']), toplam = tamsayi(a['total']);
    return Kutu(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _acik = !_acik),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(radius: 14, backgroundColor: r.ic, child: Text('${tamsayi(a['step'])}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(metin(a['title']), maxLines: 2, overflow: TextOverflow.ellipsis, style: gosterim(15, agirlik: FontWeight.w600)),
                            Text(toplam > 0 ? '$ok/$toplam tamam' : 'Denetim yok', style: TextStyle(color: r.silik, fontSize: 12)),
                          ],
                        ),
                      ),
                      KurulumDurumu(metin(a['status'])),
                      Icon(_acik ? Simgeler.expandLess : Simgeler.expandMore, color: r.soluk),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: toplam == 0 ? 0 : ok / toplam, minHeight: 5, backgroundColor: r.ic, color: kurulumDurumRengi(metin(a['status']))),
                  ),
                ],
              ),
            ),
          ),
          if (_acik) ...[
            const Divider(height: 1),
            for (final (i, c) in widget.kontroller.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              _KontrolSatiri(c: c, ek: widget.ek?.call(c)),
            ],
          ],
        ],
      ),
    );
  }
}

class _KontrolSatiri extends StatefulWidget {
  const _KontrolSatiri({required this.c, this.ek});
  final Map<String, dynamic> c;
  final Widget? ek;
  @override
  State<_KontrolSatiri> createState() => _KontrolSatiriState();
}

class _KontrolSatiriState extends State<_KontrolSatiri> {
  late bool _acik = !const {'ok', 'info'}.contains(metin(widget.c['status']));

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final c = widget.c;
    final kayitlar = haritalar(c['records']);
    final bulunan = metinler(c['found']);
    final dahaFazla = kayitlar.isNotEmpty || bulunan.isNotEmpty || metinYa(c['cause']) != null || metinYa(c['fix']) != null || metinYa(c['note']) != null || widget.ek != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: dahaFazla ? () => setState(() => _acik = !_acik) : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                KurulumDurumu(metin(c['status'])),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: metin(c['label']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (mantik(c['optional'])) TextSpan(text: '  (isteğe bağlı)', style: TextStyle(color: r.silik, fontSize: 12)),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      Text(metin(c['detail']), style: TextStyle(color: r.silik, fontSize: 12)),
                    ],
                  ),
                ),
                if (dahaFazla) Icon(_acik ? Simgeler.expandLess : Simgeler.expandMore, size: 20, color: r.soluk),
              ],
            ),
          ),
          if (_acik && dahaFazla)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (metinYa(c['cause']) != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Neden: ${metin(c['cause'])}', style: const TextStyle(fontSize: 13))),
                  if (metinYa(c['fix']) != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Düzeltme: ${metin(c['fix'])}', style: const TextStyle(fontSize: 13))),
                  for (final k in kayitlar) _KayitKutusu(k),
                  if (bulunan.isNotEmpty) ...[
                    Text('Şu an bulunan:', style: TextStyle(color: r.silik, fontSize: 12)),
                    for (final f in bulunan) SelectableText(f, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    const SizedBox(height: 8),
                  ],
                  if (metinYa(c['note']) != null) Aciklama(metin(c['note'])),
                  if (widget.ek != null) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerLeft, child: widget.ek)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KayitKutusu extends StatelessWidget {
  const _KayitKutusu(this.k);
  final Map<String, dynamic> k;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final tur = metin(k['type']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10), border: Border.all(color: r.kenar)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EtiketDeger('Ad (host)', metin(k['host']), mono: true),
          EtiketDeger('Tür', '$tur${tur == 'MX' && k['priority'] != null ? ' · öncelik ${tamsayi(k['priority'])}' : ''}', mono: true),
          EtiketDeger('Değer', metin(k['value']), mono: true),
          EtiketDeger('Nerede', metin(k['provider']) == 'hosting' ? 'Sunucu sağlayıcısının paneli (ters DNS)' : 'Alan adı sağlayıcısının DNS paneli'),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(onPressed: () => kopyala(metin(k['value'])), icon: const Icon(SimgelerKalin.copy, size: 16), label: const Text('Değeri kopyala')),
              TextButton.icon(onPressed: () => kopyala(metin(k['host'])), icon: const Icon(SimgelerKalin.copy, size: 16), label: const Text('Adı kopyala')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dışa aktarma (GET /platform-setup/export?format=bind|table).
class _DisaAktar extends StatelessWidget {
  const _DisaAktar({required this.bicim});
  final String bicim;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(bicim == 'bind' ? 'BIND bölge kaydı' : 'Kayıt tablosu', style: gosterim(19, agirlik: FontWeight.w600)),
    content: SizedBox(
      width: 760,
      height: 420,
      child: FutureBuilder<dynamic>(
        future: Uyg.api.get('/api/v1/platform-setup/export', q: {'format': bicim}),
        builder: (c, s) {
          if (s.hasError) return Text(hataMetni(s.error!), style: const TextStyle(color: Marka.gul));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final metinV = metin(harita(s.data)['text']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Aciklama('Son doğrulamaya göre eklenmesi gereken kayıtlar. PTR, sunucu sağlayıcısında ayarlanır.'),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: c.r.ic, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.r.kenar)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(child: SelectableText(metinV, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(onPressed: () => kopyala(metinV), icon: const Icon(Simgeler.copy, size: 18), label: const Text('Tümünü kopyala')),
                    OutlinedButton.icon(
                      onPressed: () => baytlariKaydet(bicim == 'bind' ? 'bogamail-dns.zone' : 'bogamail-dns-kayitlari.txt', utf8.encode(metinV), tur: 'text/plain'),
                      icon: const Icon(Simgeler.download, size: 18),
                      label: const Text('Dosya olarak kaydet'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
  );
}
