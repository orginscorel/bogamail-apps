import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import '../ortak/simgeler.dart';

/// Exchange ActiveSync cihazı (GET /api/v1/activesync/devices → items).
class EasCihaz {
  const EasCihaz(this.m);
  final Map<String, dynamic> m;
  factory EasCihaz.coz(Map<String, dynamic> m) => EasCihaz(m);

  String get id => metin(m['id']);
  String get cihazKimligi => metin(m['device_id']);
  String get tur => metin(m['device_type']);
  String get model => metin(m['model']);
  String get takmaAd => metin(m['friendly_name']);
  String get isletim => metin(m['os']);
  String get protokol => metin(m['protocol_version']);
  String get durum => metin(m['status']);
  bool get engelli => durum == 'blocked';
  bool get kuruldu => mantik(m['provisioned']);
  DateTime? get ilkGorulme => tarihOku(m['first_seen_at']);
  DateTime? get sonGorulme => tarihOku(m['last_seen_at']);
  DateTime? get sonEsitleme => tarihOku(m['last_sync_at']);
  String get sonIp => metin(m['last_ip']);
  DateTime? get silmeIstendi => tarihOku(m['wipe_requested_at']);
  String get silmeIsteyen => metin(m['wipe_requested_by']);
  String get silmeTuru => metin(m['wipe_type']);
  DateTime? get silmeOnaylandi => tarihOku(m['wipe_acked_at']);
  String get kutu => metin(m['mailbox']);
  String get orgAdi => metin(m['organization']);

  /// Görünen ad: takma ad, yoksa model, yoksa cihaz türü.
  String get ad => takmaAd.isNotEmpty ? takmaAd : (model.isNotEmpty ? model : (tur.isNotEmpty ? tur : 'Bilinmeyen cihaz'));

  String get ayrinti =>
      [if (model.isNotEmpty && model != tur) model, isletim, tur, if (protokol.isNotEmpty) 'EAS $protokol'].where((x) => x.isNotEmpty).join(' · ');

  /// none | pending | done
  String get silmeDurumu => silmeIstendi == null ? 'none' : (silmeOnaylandi != null ? 'done' : 'pending');
  bool get hesapSilmeDestekli => protokol.startsWith('16.');
}

/// Cihazın kısa durum etiketi ve rengi (web: deviceStatusLabel).
(String, Color) cihazDurumu(EasCihaz d, Color soluk) => switch (d.silmeDurumu) {
  'pending' => ('Silme bekliyor', Marka.gul),
  'done' => ('Silindi', soluk),
  _ when d.engelli => ('Engelli', Marka.kehribar),
  _ when !d.kuruldu => ('Kurulum bekliyor', soluk),
  _ => ('İzinli', Marka.zumrut),
};

String _bosa(String s, [String d = '—']) => s.isEmpty ? d : s;

class _CihazRozeti extends StatelessWidget {
  const _CihazRozeti(this.d);
  final EasCihaz d;
  @override
  Widget build(BuildContext context) {
    final (e, r) = cihazDurumu(d, context.r.soluk);
    return Rozet(e, renk: r);
  }
}

/// Mobil cihazlar: Exchange ActiveSync ile eşitlenen telefon ve tabletler (engelleme, uzaktan silme, kaldırma).
class MobilCihazlarEkrani extends StatefulWidget {
  const MobilCihazlarEkrani({super.key});
  @override
  State<MobilCihazlarEkrani> createState() => _MobilCihazlarEkraniState();
}

class _MobilCihazlarEkraniState extends State<MobilCihazlarEkrani> {
  String _q = '';
  String _durum = '';
  Map<String, dynamic>? _ayar;
  String? _ayarHata;

  late final _y = SayfaYukleyici<EasCihaz>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get('/api/v1/activesync/devices', q: {'page': '$s', if (_q.isNotEmpty) 'q': _q, if (_durum.isNotEmpty) 'status': _durum}),
      EasCihaz.coz,
    ),
    sayfaBoyu: 50,
  )..yenile();

  bool get _yonetir => Uyg.yetki('mailboxes.manage');
  bool get _ortak => !Uyg.musteri;

  @override
  void initState() {
    super.initState();
    _ayarYukle();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _ayarYukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/activesync/settings'));
      if (mounted) {
        setState(() {
          _ayar = v;
          _ayarHata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _ayarHata = hataMetni(e));
    }
  }

  Future<void> _yenile() async {
    await Future.wait([_y.yenile(), _ayarYukle()]);
  }

  Future<void> _calistir(Future<dynamic> Function() f, String tamam) async {
    await islem(f, tamam: tamam);
    await _y.yenile();
  }

  Future<void> _engelle(EasCihaz d, bool engelle) => _calistir(
    () => Uyg.api.patch('/api/v1/activesync/devices/${d.id}', {'status': engelle ? 'blocked' : 'allowed'}),
    engelle ? 'Cihaz engellendi' : 'Cihaza izin verildi',
  );

  Future<void> _silmeIptal(EasCihaz d) => _calistir(() => Uyg.api.post('/api/v1/activesync/devices/${d.id}/wipe/cancel'), 'Silme isteği iptal edildi');

  Future<void> _uzaktanSil(EasCihaz d) async {
    final tamam = await showDialog<bool>(
      context: context,
      builder: (_) => EasSilmeDialog(cihaz: d),
    );
    if (tamam == true) await _y.yenile();
  }

  Future<void> _kaldir(EasCihaz d) async {
    final ok = await onayla(
      context,
      'Cihaz kaldırılsın mı?',
      mesaj: '${d.ad} (${d.kutu}) listeden kaldırılır. Engellemek için önce "Engelle"yi kullanın; kaldırılan cihaz doğru şifreyle yeniden bağlanabilir.',
      evet: 'Kaldır',
      tehlikeli: true,
    );
    if (ok) await _calistir(() => Uyg.api.delete('/api/v1/activesync/devices/${d.id}'), 'Cihaz kaldırıldı');
  }

  List<SatirEylemi> _eylemler(EasCihaz d) => !_yonetir
      ? const []
      : [
          if (d.engelli)
            SatirEylemi(Simgeler.checkCircleOutline, 'Eşitlemeye izin ver', () => _engelle(d, false))
          else
            SatirEylemi(Simgeler.block, 'Engelle', () => _engelle(d, true)),
          if (d.silmeDurumu == 'pending')
            SatirEylemi(Simgeler.undo, 'Silme isteğini iptal et', () => _silmeIptal(d))
          else
            SatirEylemi(Simgeler.phonelinkErase, 'Uzaktan sil', () => _uzaktanSil(d), tehlikeli: true),
          SatirEylemi(Simgeler.deleteOutline, 'Listeden kaldır', () => _kaldir(d), tehlikeli: true),
        ];

  void _ac(EasCihaz d) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(d.ad, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_ortak ? '${d.kutu} · ${d.orgAdi}' : d.kutu, style: TextStyle(color: c.r.soluk)),
                const SizedBox(height: 8),
                ..._bilgiler(d),
                const SizedBox(height: 12),
                if (_yonetir)
                  for (final e in _eylemler(d))
                    EylemSatiri(
                      ikon: e.ikon,
                      baslik: e.etiket,
                      tehlikeli: e.tehlikeli,
                      onTap: () {
                        Navigator.pop(c);
                        e.calistir();
                      },
                    )
                else
                  Text('Cihazları yönetmek için "Posta kutularını yönet" yetkisi gerekir.', style: TextStyle(color: c.r.soluk, fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    );
  }

  List<Widget> _bilgiler(EasCihaz d) => [
    BilgiSatiri('Model', [d.model, d.isletim].where((x) => x.isNotEmpty).join(' · ')),
    BilgiSatiri('Cihaz kimliği', '${d.tur} · ${d.cihazKimligi}', mono: true),
    BilgiSatiri('Protokol', d.protokol.isEmpty ? '' : 'EAS ${d.protokol}'),
    BilgiSatiri('İlk görülme', tamZaman(d.ilkGorulme)),
    BilgiSatiri('Son eşitleme', tamZaman(d.sonEsitleme)),
    BilgiSatiri('Son bağlantı', '${_bosa(tamZaman(d.sonGorulme))}${d.sonIp.isNotEmpty ? ' · ${d.sonIp}' : ''}'),
    BilgiSatiri('Güvenlik ilkesi', d.kuruldu ? 'Kabul edildi (asgari ilke)' : 'Henüz kabul edilmedi'),
    if (d.silmeIstendi != null)
      BilgiSatiri(
        'Uzaktan silme',
        '${tamZaman(d.silmeIstendi)} · ${_bosa(d.silmeIsteyen)} · ${d.silmeTuru == 'account' ? 'yalnızca hesap' : 'tam'} · '
            '${d.silmeOnaylandi != null ? 'cihaz onayladı ${tamZaman(d.silmeOnaylandi)}' : 'cihazın bağlanması bekleniyor'}',
      ),
  ];

  void _ayarlariAc() {
    showDialog<void>(
      context: context,
      builder: (_) => _EasAyarDialog(
        ilk: _ayar ?? const {},
        degisti: (v) {
          if (mounted) setState(() => _ayar = v);
        },
      ),
    );
  }

  Widget _durumBandi() {
    final a = _ayar;
    final yatay = context.genis ? 16.0 : 12.0;
    if (a == null) {
      if (_ayarHata == null) return const SizedBox(height: 4);
      return Padding(
        padding: EdgeInsets.fromLTRB(yatay, 4, yatay, 4),
        child: Bant(_ayarHata!, renk: Marka.gul, ikon: Simgeler.errorOutline),
      );
    }
    final acik = mantik(a['enabled']);
    final pakette = a['feature'] != false;
    final m = !pakette
        ? 'Exchange ActiveSync paketinizde yok.'
        : acik
        ? 'Exchange ActiveSync açık: kullanıcılar telefonlarına "Exchange" hesabı ekleyerek posta, takvim ve kişilerini eşitleyebilir.'
        : 'Exchange ActiveSync kapalı: platform yöneticisi açana kadar telefonlar bağlanamaz; mevcut cihazlar listede kalır.';
    return Padding(
      padding: EdgeInsets.fromLTRB(yatay, 4, yatay, 4),
      child: Bant(
        m,
        renk: acik && pakette ? Marka.zumrut : Marka.kehribar,
        ikon: Simgeler.verifiedUser,
        eylem: TextButton(onPressed: _ayarlariAc, child: const Text('Ayrıntılar')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final filtreli = _q.isNotEmpty || _durum.isNotEmpty;
    const durumlar = [('', 'Tüm cihazlar'), ('allowed', 'İzinli'), ('blocked', 'Engelli'), ('wipe', 'Silme istenmiş')];
    return Iskelet(
      baslik: 'Mobil Cihazlar',
      alt: 'Exchange ActiveSync ile eşitlenen telefon ve tabletler',
      yenile: _yenile,
      govde: VeriTablosu<EasCihaz>(
        yukleyici: _y,
        bosMetin: filtreli ? 'Eşleşen cihaz yok.' : 'Henüz eşitlenen cihaz yok. Bir kullanıcı telefonuna Exchange hesabı eklediğinde cihaz burada görünür.',
        bosIkon: Simgeler.smartphone,
        onTap: _ac,
        eylemler: _yonetir ? _eylemler : null,
        ust: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _durumBandi(),
            FiltreCubugu(
              arama: AramaAlani(
                ipucu: _ortak ? 'Posta kutusu, müşteri veya model ara…' : 'Posta kutusu veya model ara…',
                degisti: (v) {
                  _q = v.trim();
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
                if (_durum.isNotEmpty)
                  EtkinFiltre('Durum: ${durumlar.firstWhere((x) => x.$1 == _durum).$2}', () {
                    setState(() => _durum = '');
                    _y.yenile();
                  }),
              ],
            ),
          ],
        ),
        sutunlar: [
          Sutun(
            'Cihaz',
            esnek: 4,
            hucre: (c, d) => IkiSatir(
              d.ad,
              alt: _bosa(d.ayrinti, d.cihazKimligi),
              sol: Icon(Simgeler.smartphone, color: r.soluk),
            ),
          ),
          Sutun('Posta kutusu', esnek: 3, hucre: (c, d) => IkiSatir(d.kutu, alt: _ortak ? d.orgAdi : null, kalin: false)),
          Sutun('Son eşitleme', esnek: 2, hucre: (c, d) => SolukMetin(d.sonEsitleme == null ? '—' : goreliZaman(d.sonEsitleme))),
          Sutun(
            'Durum',
            esnek: 2,
            hucre: (c, d) => Align(alignment: Alignment.centerLeft, child: _CihazRozeti(d)),
          ),
        ],
        kart: (c, d) => VeriKarti(
          baslik: d.ad,
          alt: _bosa(d.ayrinti, d.cihazKimligi),
          sol: Icon(Simgeler.smartphone, color: r.soluk),
          rozetler: [_CihazRozeti(d)],
          alanlar: [
            ('Posta kutusu', d.kutu),
            if (_ortak) ('Müşteri', d.orgAdi),
            ('Son eşitleme', d.sonEsitleme == null ? 'eşitlenmedi' : goreliZaman(d.sonEsitleme)),
          ],
          eylemler: _eylemler(d),
          onTap: () => _ac(d),
        ),
      ),
    );
  }
}

/// ActiveSync durum ve ayarları (süper yönetici açıp kapatabilir: PUT /api/v1/activesync/settings).
class _EasAyarDialog extends StatefulWidget {
  const _EasAyarDialog({required this.ilk, required this.degisti});
  final Map<String, dynamic> ilk;
  final ValueChanged<Map<String, dynamic>> degisti;
  @override
  State<_EasAyarDialog> createState() => _EasAyarDialogState();
}

class _EasAyarDialogState extends State<_EasAyarDialog> {
  late Map<String, dynamic> _a = widget.ilk;

  Future<void> _kaydet(Map<String, dynamic> govde, String tamam) async {
    final v = await islem(() => Uyg.api.put('/api/v1/activesync/settings', govde), tamam: tamam);
    if (v == null || !mounted) return;
    setState(() => _a = harita(v));
    widget.degisti(_a);
  }

  Future<void> _sinir(int simdiki) async {
    final s = await metinSor(context, 'Cihaz sınırı', ilk: '$simdiki', ipucu: 'Posta kutusu başına 1–100');
    if (s == null) return;
    final n = int.tryParse(s.trim());
    if (n == null || n < 1 || n > 100) {
      bildir('Geçersiz değer', mesaj: 'Cihaz sınırı 1–100 arasında olmalı.', tur: MesajTur.hata);
      return;
    }
    await _kaydet({'max_devices': n}, 'Cihaz sınırı kaydedildi');
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    final r = context.r;
    final acik = mantik(a['enabled']);
    final duzenler = mantik(a['can_edit']) && Uyg.taklit == null;
    final sinir = tamsayiYa(a['max_devices']);
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Exchange ActiveSync')),
          Rozet(acik ? 'Açık' : 'Kapalı', renk: acik ? Marka.zumrut : r.soluk),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (a['feature'] == false) ...[const Bant('Bu özellik paketinizde yok.', renk: Marka.kehribar), const SizedBox(height: 8)],
              BilgiSatiri('Sunucu', _bosa(metin(a['url']), metin(a['path'])), mono: true, kopyalanabilir: true),
              const BilgiSatiri('Kullanıcı adı / şifre', 'Tam e-posta adresi ve posta kutusu şifresi (iki adımlı doğrulama açıksa uygulama şifresi)'),
              const BilgiSatiri('Güvenlik ilkesi', 'Asgari ilke: cihaz şifresi zorunlu tutulmaz; uzaktan silme yalnızca yönetici istediğinde gönderilir.'),
              BilgiSatiri('Protokol', 'EAS ${metin(a['versions']).replaceAll(',', ', ')}'),
              if (sinir != null)
                BilgiSatiri(
                  'Cihaz sınırı',
                  'Posta kutusu başına en fazla $sinir cihaz',
                  sag: duzenler ? IconButton(tooltip: 'Değiştir', icon: const Icon(Simgeler.edit, size: 18), onPressed: () => _sinir(sinir)) : null,
                ),
              const SizedBox(height: 8),
              Bant('${_bosa(metin(a['license_note']), 'Ticari kullanım için Microsoft EAS lisansı gerekebilir')}.', renk: Marka.kehribar),
              if (duzenler) ...[
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ActiveSync açık'),
                  subtitle: const Text('Kapalıyken telefonlar bağlanamaz.'),
                  value: acik,
                  onChanged: (v) => _kaydet({'enabled': v}, v ? 'ActiveSync açıldı' : 'ActiveSync kapatıldı'),
                ),
                if (a['eas16'] is bool)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('EAS 16.x protokolü'),
                    subtitle: const Text('Yalnızca hesap verilerini uzaktan silme EAS 16.1 gerektirir.'),
                    value: mantik(a['eas16']),
                    onChanged: (v) => _kaydet({'eas16': v}, 'Kaydedildi'),
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

/// Uzaktan silme onayı: "SİL" yazılır, tür seçilir (yalnızca hesap silme EAS 16.x). Başarılıysa true döner.
class EasSilmeDialog extends StatefulWidget {
  const EasSilmeDialog({super.key, required this.cihaz});
  final EasCihaz cihaz;
  @override
  State<EasSilmeDialog> createState() => _EasSilmeDialogState();
}

class _EasSilmeDialogState extends State<EasSilmeDialog> {
  final _metin = TextEditingController();
  String _tur = 'full';
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  /// tr-TR büyük harf (i → İ).
  String get _onay => _metin.text.trim().replaceAll('i', 'İ').toUpperCase();

  Future<void> _gonder() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/activesync/devices/${widget.cihaz.id}/wipe', {'type': _tur, 'confirm': _onay});
      bildir('Silme isteği kaydedildi', mesaj: 'Cihaz bağlandığında uygulanacak.', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.cihaz;
    final hesapOk = d.hesapSilmeDestekli;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Simgeler.warningAmber, color: Marka.gul),
          SizedBox(width: 8),
          Expanded(
            child: Text('Uzaktan silme', style: TextStyle(color: Marka.gul)),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${d.ad} (${d.kutu}) bir sonraki bağlantısında silme komutu alır. '
                '${_tur == 'full' ? 'Tam silmede telefon fabrika ayarlarına döner: tüm uygulamalar, fotoğraflar ve kişisel veriler silinir.' : 'Yalnızca bu e-posta hesabının verileri cihazdan kaldırılır.'} '
                'İstek denetim kaydına yazılır; cihaz bağlanmadan önce iptal edilebilir.',
                style: TextStyle(color: context.r.soluk, fontSize: 13.5),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _tur,
                onChanged: (v) => setState(() => _tur = v ?? 'full'),
                child: Column(
                  children: [
                    const RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'full', title: Text('Tam silme (cihazın tamamı)')),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'account',
                      enabled: hesapOk,
                      title: const Text('Yalnızca hesap verileri'),
                      subtitle: hesapOk ? null : const Text('Bu cihaz EAS 16.1 kullanmıyor; desteklenmiyor.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _metin,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Onaylamak için SİL yazın', errorText: _hata),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Marka.gul),
          onPressed: _mesgul || _onay != 'SİL' ? null : _gonder,
          child: const Text('Silme isteği gönder'),
        ),
      ],
    );
  }
}
