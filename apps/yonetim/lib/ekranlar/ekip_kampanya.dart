import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'ekip_kampanya_ortak.dart';

const _canli = {'pending_approval', 'scheduled', 'sending'};

int _ilerleme(Map<String, dynamic> c) {
  final s = harita(c['stats']);
  final t = tamsayi(s['total']);
  return t == 0 ? 0 : ((t - tamsayi(s['pending'])) * 100 / t).round();
}

/// Toplu Gönderim → Kampanyalar: liste (canlı durum), yönetim (rapor, duraklat/devam/iptal, düzenle/sil) ve adım adım sihirbaz.
class KampanyalarSekmesi extends StatefulWidget {
  const KampanyalarSekmesi({super.key, required this.b});
  final KampanyaBaglami b;
  @override
  State<KampanyalarSekmesi> createState() => _KampanyalarSekmesiState();
}

class _KampanyalarSekmesiState extends State<KampanyalarSekmesi> {
  Timer? _zamanlayici;

  late final _y = SayfaYukleyici.yerel<Map<String, dynamic>>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/campaigns', q: widget.b.q))['items']),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_y.ogeler.any((c) => _canli.contains(metin(c['status'])))) _y.sayfaGit(_y.sayfa < 1 ? 1 : _y.sayfa);
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _y.dispose();
    super.dispose();
  }

  void _yenile() {
    _y.yenile();
    widget.b.yenile();
  }

  Future<void> _eylem(Map<String, dynamic> c, String e) async {
    const basliklar = {'pause': 'Kampanya duraklatılsın mı?', 'cancel': 'Kampanya iptal edilsin mi?', 'delete': 'Kampanya silinsin mi?'};
    const evetler = {'pause': 'Duraklat', 'cancel': 'İptal et', 'delete': 'Sil'};
    final mesajlar = {
      'pause': 'Henüz kuyruğa alınmamış alıcılar bekletilir. Daha sonra devam ettirebilirsiniz.',
      'cancel': 'Henüz gönderilmemiş alıcılara ileti gitmez. Bu işlem geri alınamaz.',
      'delete': '"${metin(c['name'])}" kalıcı olarak silinir.',
    };
    if (basliklar.containsKey(e)) {
      final ok = await onayla(context, basliklar[e]!, mesaj: mesajlar[e], evet: evetler[e]!, tehlikeli: e != 'pause');
      if (!ok) return;
    }
    const tamam = {
      'pause': 'Kampanya duraklatıldı',
      'resume': 'Kampanya devam ediyor',
      'cancel': 'Kampanya iptal edildi; bekleyen alıcılara gönderilmeyecek',
      'delete': 'Kampanya silindi',
    };
    try {
      if (e == 'delete') {
        await Uyg.api.delete('/api/v1/campaigns/c/${metin(c['id'])}');
      } else {
        await Uyg.api.post('/api/v1/campaigns/c/${metin(c['id'])}/$e', <String, dynamic>{});
      }
      bildir(tamam[e]!, tur: MesajTur.basari);
      _yenile();
    } on ApiHata catch (x) {
      bildir(
        'İşlem tamamlanamadı',
        mesaj: x.kod == 'paused_by_admin' ? 'Bu kampanya platform yöneticisi tarafından duraklatıldı; yalnızca o devam ettirebilir.' : x.mesaj,
        tur: MesajTur.hata,
      );
    } catch (x) {
      bildir('İşlem tamamlanamadı', mesaj: hataMetni(x), tur: MesajTur.hata);
    }
  }

  void _rapor(Map<String, dynamic> c) => ekipPencere<void>(context, metin(c['name'], 'Kampanya raporu'), KampanyaRaporu(id: metin(c['id'])), genislik: 960);

  Future<void> _sihirbaz(Map<String, dynamic>? c) async {
    await ekipPencere<void>(
      context,
      c == null ? 'Yeni kampanya' : 'Kampanyayı düzenle',
      KampanyaSihirbazi(b: widget.b, ilk: c, degisti: _yenile),
      genislik: 720,
    );
    _yenile();
  }

  List<SatirEylemi> _eylemler(Map<String, dynamic> c) {
    final d = metin(c['status']);
    return [
      if (d != 'draft') SatirEylemi(Icons.bar_chart_rounded, 'Rapor', () => _rapor(c)),
      if (d == 'draft') SatirEylemi(Icons.edit_outlined, 'Düzenle', () => _sihirbaz(c)),
      if (d == 'sending' || d == 'scheduled') SatirEylemi(Icons.pause_rounded, 'Duraklat', () => _eylem(c, 'pause')),
      if (d == 'paused')
        SatirEylemi(Icons.play_arrow_rounded, mantik(c['paused_by_admin']) ? 'Devam ettir (yönetici duraklattı)' : 'Devam ettir', () => _eylem(c, 'resume')),
      if (const {'pending_approval', 'scheduled', 'sending', 'paused'}.contains(d))
        SatirEylemi(Icons.block_rounded, 'İptal et', () => _eylem(c, 'cancel'), tehlikeli: true),
      if (d == 'draft' || d == 'rejected') SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _eylem(c, 'delete'), tehlikeli: true),
    ];
  }

  String _tarih(Map<String, dynamic> c) {
    final d = metin(c['status']);
    if (d == 'draft') return 'Oluşturuldu ${tamZaman(tarihOku(c['created_at']))}';
    if (d == 'scheduled' && tarihOku(c['scheduled_at']) != null) return 'Plan: ${tamZaman(tarihOku(c['scheduled_at']))}';
    return tamZaman(tarihOku(c['started_at']) ?? tarihOku(c['submitted_at']));
  }

  Widget _ilerlemeHucresi(Map<String, dynamic> c) {
    final s = harita(c['stats']);
    if (s.isEmpty) return const SolukMetin('—');
    final t = tamsayi(s['total']);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: _ilerleme(c) / 100, minHeight: 6),
        ),
        const SizedBox(height: 4),
        SolukMetin('${sayiYaz(t - tamsayi(s['pending']))} / ${sayiYaz(t)}'),
      ],
    );
  }

  String _teslim(Map<String, dynamic> c) {
    final s = harita(c['stats']);
    if (s.isEmpty) return '—';
    return '${sayiYaz(tamsayi(s['delivered']))} / %${yuzdeOrani(tamsayi(s['bounced_hard']), tamsayi(s['queued']))}';
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.b;
    final r = context.r;
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Henüz kampanya yok. Önce bir kişi listesi ve bir şablon oluşturun, ardından ilk kampanyanızı hazırlayın.',
      bosIkon: Icons.campaign_outlined,
      onTap: (c) => metin(c['status']) == 'draft' ? _sihirbaz(c) : _rapor(c),
      eylemler: _eylemler,
      ust: Padding(
        padding: EdgeInsets.fromLTRB(yatay, 10, yatay, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                'Kampanyalar yalnızca onaylı (abone) kişilere gönderilir; her iletiye tek tıkla abonelikten çıkma bağlantısı ve zorunlu alt bilgi eklenir.'
                '${mantik(b.ov['next_campaign_needs_approval']) ? ' Sonraki kampanyanız gönderilmeden önce platform onayından geçecek.' : ''}',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
            ),
            FilledButton.icon(onPressed: b.acik ? () => _sihirbaz(null) : null, icon: const Icon(Icons.add_rounded), label: const Text('Yeni kampanya')),
          ],
        ),
      ),
      sutunlar: [
        Sutun(
          'Kampanya',
          esnek: 4,
          hucre: (c, x) {
            final neden = metinYa(x['status_reason']) ?? metinYa(x['wait_reason']);
            return IkiSatir(
              metin(x['name']),
              alt: [
                '${metin(x['subject']).isEmpty ? 'Konu yok' : metin(x['subject'])} · ${x['kind'] == 'commercial' ? 'Ticari' : 'Bilgilendirme'}',
                ?neden,
              ].join('\n'),
            );
          },
        ),
        Sutun(
          'Durum',
          esnek: 2,
          hucre: (c, x) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KampanyaRozeti(metin(x['status'])),
              if (mantik(x['paused_by_admin'])) Text('yönetici duraklattı', style: TextStyle(color: r.silik, fontSize: 11.5)),
            ],
          ),
        ),
        Sutun('İlerleme', esnek: 2, hucre: (c, x) => _ilerlemeHucresi(x)),
        Sutun('Teslim / geri dönüş', esnek: 2, hucre: (c, x) => SolukMetin(_teslim(x))),
        Sutun('Tarih', esnek: 2, hucre: (c, x) => SolukMetin(_tarih(x))),
      ],
      kart: (c, x) {
        final s = harita(x['stats']);
        return VeriKarti(
          baslik: metin(x['name']),
          alt: '${metin(x['subject']).isEmpty ? 'Konu yok' : metin(x['subject'])} · ${x['kind'] == 'commercial' ? 'Ticari' : 'Bilgilendirme'}',
          rozetler: [KampanyaRozeti(metin(x['status']))],
          alanlar: [
            if (s.isNotEmpty) ('İlerleme', '${sayiYaz(tamsayi(s['total']) - tamsayi(s['pending']))} / ${sayiYaz(tamsayi(s['total']))}'),
            if (s.isNotEmpty) ('Teslim', sayiYaz(tamsayi(s['delivered']))),
            ('Tarih', _tarih(x)),
          ],
          eylemler: _eylemler(x),
          onTap: () => metin(x['status']) == 'draft' ? _sihirbaz(x) : _rapor(x),
        );
      },
    );
  }
}

const _adimlar = ['Kitle', 'Gönderen', 'İçerik', 'Şablon', 'Zamanlama', 'Kontrol'];

/// ISO → TSİ (UTC+3) DateTime (yerel saat dilimi kullanılmaz).
DateTime? _tsi(Object? iso) {
  final d = iso is String ? DateTime.tryParse(iso) : null;
  return d?.toUtc().add(const Duration(hours: 3));
}

String _tsiMetni(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _tsiIso(DateTime d) => '${_tsiMetni(d).replaceFirst(' ', 'T')}:00+03:00';

/// Kampanya sihirbazı: kitle → gönderen → içerik → şablon → zamanlama → gönderim öncesi kontrol. Her adımda taslak kaydedilir.
class KampanyaSihirbazi extends StatefulWidget {
  const KampanyaSihirbazi({super.key, required this.b, this.ilk, required this.degisti});
  final KampanyaBaglami b;
  final Map<String, dynamic>? ilk;
  final VoidCallback degisti;
  @override
  State<KampanyaSihirbazi> createState() => _KampanyaSihirbaziState();
}

class _KampanyaSihirbaziState extends State<KampanyaSihirbazi> {
  late String _id = metin(widget.ilk?['id']);
  int _adim = 0;
  late final _ad = TextEditingController(text: metin(widget.ilk?['name']));
  late List<String> _listeler = metinler(widget.ilk?['list_ids']);
  late String _segAlan = metin(harita(widget.ilk?['segment'])['field']);
  late final _segDeger = TextEditingController(text: metin(harita(widget.ilk?['segment'])['value']));
  late String _kutu = metin(widget.ilk?['mailbox_id']);
  late final _gonderenAdi = TextEditingController(text: metin(widget.ilk?['from_name']));
  late final _konu = TextEditingController(text: metin(widget.ilk?['subject']));
  late final _onMetin = TextEditingController(text: metin(widget.ilk?['preheader']));
  late String _tur = metin(widget.ilk?['kind'], 'informational');
  late final bool _iys = mantik(widget.ilk?['iys_acknowledged']);
  late String _sablon = metin(widget.ilk?['template_id']);
  late bool _ileri = tarihOku(widget.ilk?['scheduled_at']) != null;
  late DateTime? _zaman = _tsi(widget.ilk?['scheduled_at']);
  late final _hiz = TextEditingController(text: tamsayi(widget.ilk?['rate_per_hour']) > 0 ? '${tamsayi(widget.ilk?['rate_per_hour'])}' : '');

  List<Map<String, dynamic>>? _tumListeler;
  List<Map<String, dynamic>>? _sablonlar;
  Map<String, dynamic>? _kontrol;
  bool _mesgul = false;
  String? _hata;

  @override
  void initState() {
    super.initState();
    _kaynaklar();
  }

  @override
  void dispose() {
    for (final k in [_ad, _segDeger, _gonderenAdi, _konu, _onMetin, _hiz]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kaynaklar() async {
    try {
      final s = await Future.wait([Uyg.api.get('/api/v1/campaigns/lists', q: widget.b.q), Uyg.api.get('/api/v1/campaigns/templates', q: widget.b.q)]);
      if (!mounted) return;
      setState(() {
        _tumListeler = haritalar(harita(s[0])['items']);
        _sablonlar = haritalar(harita(s[1])['items']);
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Map<String, dynamic> _yama(int s) => switch (s) {
    0 => {
      'name': _ad.text.trim(),
      'list_ids': _listeler,
      'segment': {'field': _segAlan, 'value': _segAlan.isEmpty ? '' : _segDeger.text.trim()},
    },
    1 => {if (_kutu.isNotEmpty) 'mailbox_id': _kutu, 'from_name': _gonderenAdi.text.trim()},
    2 => {'subject': _konu.text.trim(), 'preheader': _onMetin.text.trim(), 'kind': _tur, 'iys_acknowledged': _tur == 'commercial' && _iys},
    3 => {if (_sablon.isNotEmpty) 'template_id': _sablon},
    4 => {if (!_ileri || _zaman == null) 'send_now': true else 'scheduled_at': _tsiIso(_zaman!), 'rate_per_hour': int.tryParse(_hiz.text.trim()) ?? 0},
    _ => {},
  };

  Future<bool> _kaydet() async {
    setState(() => _hata = null);
    if (_adim == 0 && _ad.text.trim().isEmpty) {
      setState(() => _hata = 'Kampanya adı gerekli');
      return false;
    }
    setState(() => _mesgul = true);
    try {
      if (_id.isEmpty) {
        final c = harita(await Uyg.api.post('/api/v1/campaigns', {'organization_id': widget.b.orgId, 'name': _ad.text.trim()}));
        _id = metin(c['id']);
      }
      await Uyg.api.patch('/api/v1/campaigns/c/$_id', _yama(_adim));
      widget.degisti();
      return true;
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
      return false;
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _kontrolYukle() async {
    setState(() => _kontrol = null);
    try {
      final v = harita(await Uyg.api.get('/api/v1/campaigns/c/$_id/checklist'));
      if (mounted) setState(() => _kontrol = v);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _ileriGit() async {
    if (!await _kaydet()) return;
    setState(() => _adim++);
    if (_adim == 5) _kontrolYukle();
  }

  Future<void> _gonder() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final c = harita(await Uyg.api.post('/api/v1/campaigns/c/$_id/send'));
      final d = metin(c['status']);
      bildir(
        d == 'pending_approval'
            ? 'Kampanya onaya gönderildi'
            : (d == 'scheduled' && tarihOku(c['scheduled_at']) != null
                  ? 'Kampanya planlandı: ${tamZaman(tarihOku(c['scheduled_at']))}'
                  : 'Kampanya gönderime alındı'),
        tur: MesajTur.basari,
      );
      widget.degisti();
      if (mounted) Navigator.maybePop(context);
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() => _hata = e.mesaj);
      if (e.kod == 'checklist_failed') _kontrolYukle();
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _zamanSec() async {
    final simdi = DateTime.now().toUtc().add(const Duration(hours: 3));
    final ilk = _zaman ?? simdi.add(const Duration(hours: 1));
    final g = await showDatePicker(
      context: context,
      initialDate: ilk,
      firstDate: DateTime(simdi.year, simdi.month, simdi.day),
      lastDate: DateTime(simdi.year + 1, 12, 31),
    );
    if (g == null || !mounted) return;
    final s = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: ilk.hour, minute: ilk.minute),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
    );
    if (s == null) return;
    setState(() => _zaman = DateTime(g.year, g.month, g.day, s.hour, s.minute));
  }

  Widget _secimKutusu({required bool secili, required VoidCallback onTap, required Widget child}) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: secili ? r.vurguYumusak : r.kart,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: secili ? r.vurgu : r.kenar),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: child),
        ),
      ),
    );
  }

  Widget _dogrulama(bool ok, String e) => Rozet('${ok ? '✓' : '✗'} $e', renk: ok ? Marka.zumrut : Marka.gul);

  Widget _icerik() {
    final r = context.r;
    final soluk = TextStyle(color: r.silik, fontSize: 12);
    switch (_adim) {
      case 0:
        final l = _tumListeler;
        final alanlar = <String>{
          for (final x in l ?? const <Map<String, dynamic>>[])
            if (_listeler.contains(metin(x['id']))) ...metinler(x['fields']),
        }.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ad,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Kampanya adı', hintText: 'Kasım bülteni', counterText: ''),
            ),
            const SizedBox(height: 12),
            Text(
              'Kişi listeleri',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (l == null)
              const LinearProgressIndicator()
            else if (l.isEmpty)
              Text('Önce "Kişi listeleri" sekmesinden bir liste oluşturun.', style: TextStyle(color: r.soluk))
            else
              for (final x in l)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _listeler.contains(metin(x['id'])),
                  onChanged: (v) =>
                      setState(() => _listeler = v == true ? [..._listeler, metin(x['id'])] : _listeler.where((i) => i != metin(x['id'])).toList()),
                  title: Text(metin(x['name']), overflow: TextOverflow.ellipsis),
                  secondary: Text('${sayiYaz(tamsayi(x['subscribed']))} abone', style: soluk),
                ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('seg${alanlar.join()}'),
                    initialValue: alanlar.contains(_segAlan) ? _segAlan : '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Segment alanı (isteğe bağlı)'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Tüm aboneler')),
                      for (final f in alanlar) DropdownMenuItem(value: f, child: Text(f)),
                    ],
                    onChanged: (v) => setState(() => _segAlan = v ?? ''),
                  ),
                ),
                if (_segAlan.isNotEmpty)
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _segDeger,
                      decoration: const InputDecoration(labelText: 'Değer', hintText: 'ör. İstanbul'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Yalnızca "Abone" durumundaki kişilere gönderilir; çıkmış, geri dönmüş ve bastırılmış adresler otomatik atlanır.', style: soluk),
          ],
        );
      case 1:
        final g = widget.b.gondericiler;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gönderen posta kutusu',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (g.isEmpty) Text('Bu müşterinin gönderime uygun posta kutusu yok.', style: TextStyle(color: r.soluk)),
            for (final s in g)
              _secimKutusu(
                secili: _kutu == metin(s['mailbox_id']),
                onTap: () => setState(() {
                  _kutu = metin(s['mailbox_id']);
                  if (_gonderenAdi.text.isEmpty) _gonderenAdi.text = metin(s['display_name']);
                }),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metin(s['address']), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _dogrulama(mantik(s['domain_verified']), 'Alan adı doğrulandı'),
                        _dogrulama(mantik(s['dkim']), 'DKIM'),
                        _dogrulama(mantik(s['spf']), 'SPF'),
                        _dogrulama(mantik(s['dmarc']), 'DMARC'),
                        _dogrulama(mantik(s['bulk_allowed']), 'Toplu gönderim izni'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saatlik sınır ${sayiYaz(tamsayi(s['hourly_limit']))}${tamsayiYa(s['daily_limit']) != null ? ' · günlük ${sayiYaz(tamsayi(s['daily_limit']))}' : ''}',
                      style: soluk,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _gonderenAdi,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Gönderen adı', hintText: 'Şirket adı', counterText: ''),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _konu,
              maxLength: 250,
              decoration: const InputDecoration(labelText: 'Konu', hintText: 'Merhaba {{ad}}, kasım fırsatları', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _onMetin,
              maxLength: 250,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Ön izleme metni (preheader)',
                hintText: 'Gelen kutusunda konunun yanında görünen kısa metin',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'İleti türü',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (final (v, e, i) in const [
              ('informational', 'Bilgilendirme', 'Hizmet, sipariş, duyuru vb. (ticari amaç taşımayan)'),
              ('commercial', 'Ticari ileti', 'Kampanya, indirim, tanıtım'),
            ])
              _secimKutusu(
                secili: _tur == v,
                onTap: () => setState(() => _tur = v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(i, style: soluk),
                  ],
                ),
              ),
          ],
        );
      case 3:
        final l = _sablonlar;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Şablon',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (l == null)
              const LinearProgressIndicator()
            else if (l.isEmpty)
              Text('Önce "Şablonlar" sekmesinden bir şablon oluşturun.', style: TextStyle(color: r.soluk))
            else
              for (final t in l)
                _secimKutusu(
                  secili: _sablon == metin(t['id']),
                  onTap: () => setState(() => _sablon = metin(t['id'])),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          metin(t['name']),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text('${(t['blocks'] is List ? (t['blocks'] as List).length : 0)} blok · ${kisaZaman(tarihOku(t['updated_at']))}', style: soluk),
                    ],
                  ),
                ),
            const SizedBox(height: 6),
            Text('Şablon gönderim anında kopyalanır; sonradan şablonu değiştirmek gönderilmiş kampanyayı etkilemez.', style: soluk),
          ],
        );
      case 4:
        final ust = tamsayiYa(widget.b.ayarlar['max_rate_per_hour']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (v, e, i) in const [(false, 'Hemen gönder', 'Onay gerekmiyorsa hemen başlar'), (true, 'İleri tarihe planla', 'Türkiye saati (TSİ)')])
              _secimKutusu(
                secili: _ileri == v,
                onTap: () => setState(() => _ileri = v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(i, style: soluk),
                  ],
                ),
              ),
            if (_ileri)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: OutlinedButton.icon(
                  onPressed: _zamanSec,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(_zaman == null ? 'Gönderim zamanı seçin (TSİ)' : '${_tsiMetni(_zaman!)} TSİ'),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _hiz,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Saatlik gönderim hızı', hintText: 'Boş = otomatik'),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Boş bırakılırsa gönderen posta kutusunun saatlik sınırına göre otomatik ayarlanır'
              '${ust != null ? '; bu müşteri için üst sınır saatte ${sayiYaz(ust)}' : ''}. Yavaş gönderim teslim oranını artırır.',
              style: soluk,
            ),
          ],
        );
      default:
        final k = _kontrol;
        if (k == null) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final alici = tamsayi(k['recipients']), hiz = tamsayi(k['effective_rate_per_hour']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final it in haritalar(k['items']))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Kutu(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      switch (metin(it['status'])) {
                        'ok' => const Icon(Icons.check_circle_rounded, color: Marka.zumrut, size: 20),
                        'warn' => const Icon(Icons.warning_amber_rounded, color: Marka.kehribar, size: 20),
                        _ => const Icon(Icons.cancel_rounded, color: Marka.gul, size: 20),
                      },
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(metin(it['label']), style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (metin(it['detail']).isNotEmpty) Text(metin(it['detail']), style: soluk),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Bant(
              '${sayiYaz(alici)} alıcı · saatte ${sayiYaz(hiz)} ileti'
              '${alici > 0 && hiz > 0 ? ' (~${(alici / hiz).ceil().clamp(1, 1 << 30)} saat)' : ''}'
              '${mantik(k['needs_approval']) ? '\nBu kampanya gönderilmeden önce platform yöneticisinin onayından geçecek.' : ''}',
            ),
            if (!mantik(k['ready'])) ...[
              const SizedBox(height: 8),
              const Text('Kırmızı maddeler düzeltilmeden gönderilemez. İlgili adıma dönüp düzeltebilirsiniz.', style: TextStyle(color: Marka.gul)),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final k = _kontrol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text('Adım ${_adim + 1}/${_adimlar.length}: ${_adimlar[_adim]}. Her adımda taslak kaydedilir.', style: TextStyle(color: r.soluk)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _adimlar.length; i++)
                    ChoiceChip(
                      label: Text('${i + 1}. ${_adimlar[i]}'),
                      selected: i == _adim,
                      showCheckmark: false,
                      onSelected: _id.isEmpty || i > _adim || _mesgul
                          ? null
                          : (_) {
                              setState(() => _adim = i);
                              if (i == 5) _kontrolYukle();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _icerik(),
              if (_hata != null) ...[const SizedBox(height: 12), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              if (_adim > 0)
                OutlinedButton(
                  onPressed: _mesgul
                      ? null
                      : () => setState(() {
                          _hata = null;
                          _adim--;
                        }),
                  child: const Text('Geri'),
                ),
              const Spacer(),
              if (_adim < 5)
                FilledButton(onPressed: _mesgul ? null : _ileriGit, child: const Text('Kaydet ve devam'))
              else
                FilledButton(
                  onPressed: _mesgul || k == null || !mantik(k['ready']) ? null : _gonder,
                  child: Text(mantik(k?['needs_approval']) ? 'Onaya gönder' : (_ileri ? 'Planla' : 'Gönder')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
