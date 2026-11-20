import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import 'liste_ortak.dart';

// Alarm kuralları ve bildirim kanalları (GET/POST/PUT/DELETE /alerts/rules, GET/POST/PATCH/DELETE /alerts/channels,
// POST /alerts/channels/{id}/test, POST /alerts/channels/{id}/rotate-secret, GET /alerts/kinds).

/// Uyarı türü (GET /alerts/kinds → items).
class AlarmTuru {
  const AlarmTuru({required this.anahtar, required this.ad, required this.birim, required this.varsayilan, required this.altinda, required this.ipucu});
  final String anahtar, ad, birim, ipucu;
  final double varsayilan;

  /// Değer eşiğe eşit ya da altındaysa tetiklenir (sertifika kalan gün gibi).
  final bool altinda;

  factory AlarmTuru.coz(Map<String, dynamic> m) => AlarmTuru(
    anahtar: metin(m['key']),
    ad: metin(m['label']),
    birim: metin(m['unit']),
    varsayilan: ondalik(m['default_threshold'], 1),
    altinda: mantik(m['below']),
    ipucu: metin(m['hint']),
  );
}

/// GET /alerts/kinds yanıtı.
class AlarmTurleri {
  const AlarmTurleri(this.ogeler, {this.cikisModu = '', this.disEposta = true});
  final List<AlarmTuru> ogeler;
  final String cikisModu;
  final bool disEposta;

  factory AlarmTurleri.coz(Object? v) {
    final m = harita(v);
    return AlarmTurleri(haritalar(m['items']).map(AlarmTuru.coz).toList(), cikisModu: metin(m['outbound_mode']), disEposta: mantik(m['external_email'], true));
  }

  AlarmTuru? bul(String k) => ogeler.where((x) => x.anahtar == k).firstOrNull;
  String ad(String k) => bul(k)?.ad ?? k;
}

class AlarmKurali {
  const AlarmKurali({
    required this.id,
    required this.orgId,
    required this.orgAdi,
    required this.tur,
    required this.ad,
    required this.esik,
    required this.onem,
    required this.beklemeDk,
    required this.duzelinceBildir,
    required this.kanallar,
    required this.etkin,
    required this.guncelleme,
    required this.tetiklenen,
    required this.tetiklenmeZamani,
  });
  final String id, orgAdi, tur, ad, onem;
  final String? orgId;
  final double esik;
  final int beklemeDk, tetiklenen;
  final bool duzelinceBildir, etkin;
  final List<String> kanallar;
  final DateTime? guncelleme, tetiklenmeZamani;

  factory AlarmKurali.coz(Map<String, dynamic> m) => AlarmKurali(
    id: metin(m['id']),
    orgId: metinYa(m['organization_id']),
    orgAdi: metin(m['organization_name']),
    tur: metin(m['kind']),
    ad: metin(m['name']),
    esik: ondalik(m['threshold']),
    onem: metin(m['severity'], 'warning'),
    beklemeDk: tamsayi(m['cooldown_minutes'], 60),
    duzelinceBildir: mantik(m['notify_resolved'], true),
    kanallar: metinler(m['channel_ids']),
    etkin: mantik(m['enabled'], true),
    guncelleme: tarihOku(m['updated_at']),
    tetiklenen: tamsayi(m['firing']),
    tetiklenmeZamani: tarihOku(m['firing_since']),
  );
}

class AlarmKanali {
  const AlarmKanali({
    required this.id,
    required this.orgId,
    required this.orgAdi,
    required this.tur,
    required this.ad,
    required this.adresler,
    required this.url,
    required this.etkin,
    required this.sonDurum,
    required this.sonHata,
    required this.sonZaman,
  });
  final String id, orgAdi, tur, ad, url, sonDurum, sonHata;
  final String? orgId;
  final List<String> adresler;
  final bool etkin;
  final DateTime? sonZaman;

  factory AlarmKanali.coz(Map<String, dynamic> m) {
    final cfg = harita(m['config']);
    return AlarmKanali(
      id: metin(m['id']),
      orgId: metinYa(m['organization_id']),
      orgAdi: metin(m['organization_name']),
      tur: metin(m['kind']),
      ad: metin(m['name']),
      adresler: metinler(cfg['addresses']),
      url: metin(cfg['url']),
      etkin: mantik(m['enabled'], true),
      sonDurum: metin(m['last_status']),
      sonHata: metin(m['last_error']),
      sonZaman: tarihOku(m['last_at']),
    );
  }

  String get hedef => switch (tur) {
    'email' => adresler.join(', '),
    'webhook' => url,
    _ => 'Panel üst çubuğundaki zil',
  };
}

const kanalTurleri = {'email': 'E-posta', 'webhook': 'Webhook', 'panel': 'Panel'};

String alarmDegeri(double v, String birim) {
  final n = v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');
  return birim.isEmpty ? n : '$n $birim';
}

/// Kuralları / kanalları düzenleyebilir mi: süper yönetici ya da (yetkili) müşteri yöneticisi; bayi yalnızca görür.
bool get alarmYonetebilir => Uyg.platformYoneticisi || (Uyg.musteri && (Uyg.yetki('settings.manage') || Uyg.yetki('domains.manage')));

/// Bir kuralın / kanalın sahibi değiştirebilir: süper yönetici hepsini, müşteri yalnızca kendi kuruluşununkini.
bool alarmSahibi(String? orgId) => alarmYonetebilir && (Uyg.platformYoneticisi || orgId != null);

// ---- kurallar -----------------------------------------------------------------------------------------------------

class AlarmKurallari extends StatefulWidget {
  const AlarmKurallari({super.key, required this.turler, required this.kanallar, this.yenileme});
  final AlarmTurleri? turler;
  final List<AlarmKanali> kanallar;
  final Listenable? yenileme;
  @override
  State<AlarmKurallari> createState() => AlarmKurallariState();
}

class AlarmKurallariState extends State<AlarmKurallari> with AutomaticKeepAliveClientMixin {
  String _q = '', _durum = '';
  late final _y = SayfaYukleyici.yerel<AlarmKurali>(() async {
    final l = haritalar(harita(await Uyg.api.get('/api/v1/alerts/rules'))['items']).map(AlarmKurali.coz);
    final q = _q.toLowerCase();
    return [
      for (final k in l)
        if ((q.isEmpty || k.ad.toLowerCase().contains(q) || k.orgAdi.toLowerCase().contains(q)) &&
            switch (_durum) {
              'firing' => k.tetiklenen > 0,
              'off' => !k.etkin,
              _ => true,
            })
          k,
    ];
  }, sayfaBoyu: 25)..yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.yenileme?.addListener(_y.yenile);
  }

  @override
  void dispose() {
    widget.yenileme?.removeListener(_y.yenile);
    _y.dispose();
    super.dispose();
  }

  String _kanalAdi(String id) => widget.kanallar.where((c) => c.id == id).firstOrNull?.ad ?? '—';
  String _kanallar(AlarmKurali k) => k.kanallar.isEmpty ? 'kanal yok' : k.kanallar.map(_kanalAdi).join(', ');
  String _esik(AlarmKurali k) {
    final t = widget.turler?.bul(k.tur);
    return '${t?.altinda == true ? '≤' : '≥'} ${alarmDegeri(k.esik, t?.birim ?? '')}';
  }

  Future<void> yeni() => _duzenle(null);

  Future<void> _duzenle(AlarmKurali? k) async {
    final t = widget.turler;
    if (t == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlarmKuraliDialog(turler: t, kanallar: widget.kanallar, kural: k),
    );
    if (ok == true) _y.yenile();
  }

  Future<void> _etkinlik(AlarmKurali k) async {
    final v = await islem(
      () => Uyg.api.put('/api/v1/alerts/rules/${k.id}', {'kind': k.tur, 'enabled': !k.etkin}),
      tamam: k.etkin ? 'Kural kapatıldı' : 'Kural etkinleştirildi',
    );
    if (v != null) _y.degistir((x) => x.id == k.id, AlarmKurali.coz(harita(harita(v)['rule'])));
  }

  Future<void> _sil(AlarmKurali k) async {
    if (!await onayla(context, 'Kural silinsin mi?', mesaj: '${k.ad} artık değerlendirilmez. Geçmiş kayıtları korunur.', evet: 'Sil', tehlikeli: true)) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/alerts/rules/${k.id}').then((_) => true), tamam: 'Kural silindi');
    if (v == true) _y.degistir((x) => x.id == k.id, null);
  }

  List<SatirEylemi> _eylemler(AlarmKurali k) => [
    SatirEylemi(Icons.info_outline_rounded, 'Ayrıntı', () => _ayrinti(k)),
    if (alarmSahibi(k.orgId)) ...[
      SatirEylemi(Icons.edit_outlined, 'Düzenle', () => _duzenle(k)),
      SatirEylemi(k.etkin ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, k.etkin ? 'Kapat' : 'Etkinleştir', () => _etkinlik(k)),
      SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(k), tehlikeli: true),
    ],
  ];

  void _ayrinti(AlarmKurali k) => yonetimPenceresi(
    context,
    baslik: k.ad,
    alt: '${k.orgAdi.isEmpty ? 'Platform kuralı' : k.orgAdi} · güncellendi ${tamZaman(k.guncelleme)}',
    ozet: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BilgiSatiri('Tür', widget.turler?.ad(k.tur) ?? k.tur),
        BilgiSatiri('Eşik', _esik(k)),
        BilgiSatiri('Önem', onemEtiketleri[k.onem] ?? k.onem),
        BilgiSatiri('Bekleme', '${k.beklemeDk} dk${k.duzelinceBildir ? ' · düzelince bildir' : ''}'),
        BilgiSatiri('Kanallar', _kanallar(k)),
        BilgiSatiri(
          'Durum',
          k.tetiklenen > 0 ? 'Tetiklendi${k.tetiklenmeZamani != null ? ' (${goreliZaman(k.tetiklenmeZamani)})' : ''}' : (k.etkin ? 'Normal' : 'Kapalı'),
        ),
        if (!alarmSahibi(k.orgId))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Bu kuralı değiştirme yetkiniz yok.', style: TextStyle(color: context.r.silik, fontSize: 12)),
          ),
      ],
    ),
    eylemler: alarmSahibi(k.orgId)
        ? [
            SatirEylemiDugmesi(Icons.edit_outlined, 'Düzenle', () => _duzenle(k), ipucu: 'Eşik, kanallar, bekleme süresi'),
            SatirEylemiDugmesi(Icons.delete_outline_rounded, 'Sil', () => _sil(k), ipucu: 'Kural ve durumu kaldırılır', tehlikeli: true),
          ]
        : const [],
  );

  Widget _durumRozeti(BuildContext c, AlarmKurali k) {
    if (k.tetiklenen > 0) return Rozet('Tetiklendi${k.tetiklenen > 1 ? ' (${k.tetiklenen})' : ''}', renk: Marka.gul, ikon: Icons.notifications_active_rounded);
    if (!k.etkin) return Rozet('Kapalı', renk: c.r.silik);
    return const Rozet('Normal', renk: Marka.zumrut);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    const durumlar = {'firing': 'Tetiklenen', 'off': 'Kapalı'};
    return VeriTablosu<AlarmKurali>(
      yukleyici: _y,
      onTap: _ayrinti,
      eylemler: _eylemler,
      vurgulu: (k) => k.tetiklenen > 0,
      bosIkon: Icons.rule_rounded,
      bosMetin: _q.isEmpty && _durum.isEmpty
          ? 'Kural yok. Örneğin kuyruk boyutu, geri dönme oranı veya alan adı denetimi için bir kural ekleyin.'
          : 'Eşleşen kural yok.',
      ust: FiltreCubugu(
        arama: AramaAlani(
          ipucu: 'Kural ara…',
          degisti: (v) {
            _q = v;
            _y.yenile();
          },
        ),
        filtreler: [
          FiltreDugmesi<String>(
            etiket: 'Durum',
            ikon: Icons.flag_outlined,
            secenekler: [('', 'Tümü'), for (final e in durumlar.entries) (e.key, e.value)],
            secili: _durum,
            secildi: (v) {
              setState(() => _durum = v);
              _y.yenile();
            },
          ),
        ],
        etkinler: [
          if (_durum.isNotEmpty)
            EtkinFiltre('Durum: ${durumlar[_durum]}', () {
              setState(() => _durum = '');
              _y.yenile();
            }),
        ],
      ),
      sutunlar: [
        Sutun(
          'Kural',
          esnek: 4,
          hucre: (c, k) => IkiSatir(
            k.etkin ? k.ad : '${k.ad} (kapalı)',
            alt: [widget.turler?.ad(k.tur) ?? k.tur, if (!Uyg.musteri) (k.orgAdi.isEmpty ? 'Platform' : k.orgAdi)].join(' · '),
          ),
        ),
        Sutun(
          'Eşik',
          genislik: 120,
          hucre: (c, k) => Text(_esik(k), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Sutun('Önem', genislik: 90, hucre: (c, k) => Sigdir(Rozet(onemEtiketleri[k.onem] ?? k.onem, renk: k.onem == 'critical' ? Marka.gul : Marka.kehribar))),
        Sutun('Kanallar', esnek: 3, hucre: (c, k) => SolukMetin(_kanallar(k))),
        Sutun('Durum', genislik: 140, hucre: (c, k) => Sigdir(_durumRozeti(c, k))),
      ],
      kart: (c, k) => VeriKarti(
        baslik: k.ad,
        alt: [widget.turler?.ad(k.tur) ?? k.tur, if (!Uyg.musteri) (k.orgAdi.isEmpty ? 'Platform' : k.orgAdi)].join(' · '),
        rozetler: [
          _durumRozeti(c, k),
          Rozet(onemEtiketleri[k.onem] ?? k.onem, renk: k.onem == 'critical' ? Marka.gul : Marka.kehribar),
        ],
        alanlar: [('Eşik', _esik(k)), ('Kanallar', _kanallar(k))],
        vurgulu: k.tetiklenen > 0,
        eylemler: _eylemler(k),
        onTap: () => _ayrinti(k),
      ),
    );
  }
}

/// Kural oluşturma / düzenleme (POST /alerts/rules, PUT /alerts/rules/{id}).
class AlarmKuraliDialog extends StatefulWidget {
  const AlarmKuraliDialog({super.key, required this.turler, required this.kanallar, this.kural});
  final AlarmTurleri turler;
  final List<AlarmKanali> kanallar;
  final AlarmKurali? kural;
  @override
  State<AlarmKuraliDialog> createState() => _AlarmKuraliDialogState();
}

class _AlarmKuraliDialogState extends State<AlarmKuraliDialog> {
  late String _tur = widget.kural?.tur ?? widget.turler.ogeler.firstOrNull?.anahtar ?? '';
  late final _ad = TextEditingController(text: widget.kural?.ad ?? '');
  late final _esik = TextEditingController(text: _sayiMetni(widget.kural?.esik ?? widget.turler.bul(_tur)?.varsayilan ?? 1));
  late final _bekleme = TextEditingController(text: '${widget.kural?.beklemeDk ?? 60}');
  late String _onem = widget.kural?.onem ?? 'warning';
  late bool _duzelince = widget.kural?.duzelinceBildir ?? true;
  late bool _etkin = widget.kural?.etkin ?? true;
  late final Set<String> _secili = {...?widget.kural?.kanallar};
  bool _mesgul = false;
  String? _hata, _alan;

  /// Kuralın sahibinin kanalları (platform kuralı → platform kanalları; müşteri → kendi kanalları).
  late final String? _sahip = widget.kural != null ? widget.kural!.orgId : (Uyg.platformYoneticisi ? null : metinYa(Uyg.ben.value?['organization_id']));
  List<AlarmKanali> get _kullanilabilir => widget.kanallar.where((c) => c.orgId == _sahip).toList();

  static String _sayiMetni(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void initState() {
    super.initState();
    if (widget.kural == null) _secili.addAll(_kullanilabilir.where((c) => c.tur == 'panel').map((c) => c.id));
  }

  @override
  void dispose() {
    _ad.dispose();
    _esik.dispose();
    _bekleme.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final t = widget.turler.bul(_tur);
    final esik = double.tryParse(_esik.text.trim().replaceAll(',', '.'));
    final bekleme = int.tryParse(_bekleme.text.trim());
    if (esik == null) {
      setState(() => _ata('Eşik geçersiz', 'threshold'));
      return;
    }
    if (bekleme == null || bekleme < 0 || bekleme > 10080) {
      setState(() => _ata('Tekrar aralığı 0–10080 dakika olmalı', 'cooldown_minutes'));
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    final govde = {
      'kind': _tur,
      'name': _ad.text.trim().isEmpty ? (t?.ad ?? '') : _ad.text.trim(),
      'threshold': esik,
      'severity': _onem,
      'cooldown_minutes': bekleme,
      'notify_resolved': _duzelince,
      'channel_ids': _secili.toList(),
      'enabled': _etkin,
    };
    try {
      final k = widget.kural;
      if (k == null) {
        await Uyg.api.post('/api/v1/alerts/rules', govde);
      } else {
        await Uyg.api.put('/api/v1/alerts/rules/${k.id}', govde);
      }
      bildir('Kural kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() => _ata(e.mesaj, e.alan));
    } catch (e) {
      setState(() => _ata(hataMetni(e), null));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String? _hataFor(String alan) => _alan == alan ? _hata : null;

  void _ata(String? hata, String? alan) {
    _hata = hata;
    _alan = alan;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final t = widget.turler.bul(_tur);
    final kanallar = _kullanilabilir;
    return AlertDialog(
      title: Text(widget.kural == null ? 'Yeni uyarı kuralı' : 'Kuralı düzenle', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (t != null && t.ipucu.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(t.ipucu, style: TextStyle(color: r.silik, fontSize: 13)),
                ),
              DropdownButtonFormField<String>(
                initialValue: _tur.isEmpty ? null : _tur,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Tür', errorText: _hataFor('kind')),
                items: [
                  for (final x in widget.turler.ogeler)
                    DropdownMenuItem(
                      value: x.anahtar,
                      child: Text(x.ad, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: widget.kural != null
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _tur = v;
                          final y = widget.turler.bul(v);
                          if (y != null) _esik.text = _sayiMetni(y.varsayilan);
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ad,
                maxLength: 80,
                decoration: InputDecoration(labelText: 'Ad', hintText: t?.ad, errorText: _hataFor('name')),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _esik,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Eşik${t != null && t.birim.isNotEmpty ? ' (${t.birim})' : ''}',
                        helperText: t?.altinda == true ? 'Eşit veya altındaysa tetiklenir' : 'Bu eşiğe ulaşınca tetiklenir',
                        helperMaxLines: 2,
                        errorText: _hataFor('threshold'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _bekleme,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: 'Tekrar bekleme (dk)', errorText: _hataFor('cooldown_minutes')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'warning', icon: Icon(Icons.warning_amber_rounded), label: Text('Uyarı')),
                  ButtonSegment(value: 'critical', icon: Icon(Icons.error_outline_rounded), label: Text('Kritik')),
                ],
                selected: {_onem},
                onSelectionChanged: (s) => setState(() => _onem = s.first),
              ),
              const SizedBox(height: 14),
              Text(
                'Kanallar',
                style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (kanallar.isEmpty) Text('Önce "Kanallar" sekmesinden bir kanal ekleyin.', style: TextStyle(color: r.silik, fontSize: 12.5)),
              for (final c in kanallar)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _secili.contains(c.id),
                  onChanged: (v) => setState(() => v == true ? _secili.add(c.id) : _secili.remove(c.id)),
                  title: Text('${c.ad} (${kanalTurleri[c.tur] ?? c.tur})', overflow: TextOverflow.ellipsis),
                ),
              if (_hataFor('channel_ids') != null) Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _duzelince,
                onChanged: (v) => setState(() => _duzelince = v),
                title: const Text('Durum düzelince bildir'),
              ),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _etkin, onChanged: (v) => setState(() => _etkin = v), title: const Text('Etkin')),
              if (_hata != null && !{'kind', 'name', 'threshold', 'cooldown_minutes', 'channel_ids'}.contains(_alan))
                Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul || _tur.isEmpty ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}

// ---- kanallar -----------------------------------------------------------------------------------------------------

class AlarmKanallari extends StatefulWidget {
  const AlarmKanallari({super.key, required this.turler, required this.degisti, this.yenileme});
  final AlarmTurleri? turler;

  /// Kanal listesi yüklendi / değişti (kurallar sekmesi kanal adlarını kullanır).
  final ValueChanged<List<AlarmKanali>> degisti;
  final Listenable? yenileme;
  @override
  State<AlarmKanallari> createState() => AlarmKanallariState();
}

class AlarmKanallariState extends State<AlarmKanallari> with AutomaticKeepAliveClientMixin {
  late final _y = SayfaYukleyici.yerel<AlarmKanali>(() async {
    final l = haritalar(harita(await Uyg.api.get('/api/v1/alerts/channels'))['items']).map(AlarmKanali.coz).toList();
    widget.degisti(l);
    return l;
  }, sayfaBoyu: 25)..yenile();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.yenileme?.addListener(_y.yenile);
  }

  @override
  void dispose() {
    widget.yenileme?.removeListener(_y.yenile);
    _y.dispose();
    super.dispose();
  }

  Future<void> yeni() => _duzenle(null);

  Future<void> _duzenle(AlarmKanali? k) async {
    final gizli = await showDialog<String>(
      context: context,
      builder: (_) => AlarmKanaliDialog(kanal: k, turler: widget.turler),
    );
    if (gizli == null) return;
    _y.yenile();
    if (gizli.isNotEmpty && mounted) await gizliAnahtariGoster(context, gizli);
  }

  Future<void> _test(AlarmKanali k) async {
    final v = await islem(() => Uyg.api.post('/api/v1/alerts/channels/${k.id}/test'));
    if (v == null) return;
    final d = harita(harita(v)['delivery']);
    if (mantik(d['ok'])) {
      bildir('Test bildirimi gönderildi', tur: MesajTur.basari);
    } else {
      bildir('Gönderilemedi', mesaj: metin(d['error'], 'bilinmeyen hata'), tur: MesajTur.hata);
    }
    _y.yenile();
  }

  Future<void> _anahtarYenile(AlarmKanali k) async {
    if (!await onayla(
      context,
      'Gizli anahtar yenilensin mi?',
      mesaj: 'Eski anahtar hemen geçersiz olur; alıcı sistemi yeni anahtarla güncelleyin.',
      evet: 'Yenile',
    )) {
      return;
    }
    final v = await islem(() => Uyg.api.post('/api/v1/alerts/channels/${k.id}/rotate-secret'));
    if (v != null && mounted) await gizliAnahtariGoster(context, metin(harita(v)['secret']));
  }

  Future<void> _etkinlik(AlarmKanali k) async {
    final v = await islem(
      () => Uyg.api.patch('/api/v1/alerts/channels/${k.id}', {'enabled': !k.etkin}),
      tamam: k.etkin ? 'Kanal kapatıldı' : 'Kanal etkinleştirildi',
    );
    if (v != null) _y.yenile();
  }

  Future<void> _sil(AlarmKanali k) async {
    if (!await onayla(
      context,
      'Kanal silinsin mi?',
      mesaj: '${k.ad} kanalına artık bildirim gönderilmez; kurallardan da çıkarılır.',
      evet: 'Sil',
      tehlikeli: true,
    )) {
      return;
    }
    final v = await islem(() => Uyg.api.delete('/api/v1/alerts/channels/${k.id}').then((_) => true), tamam: 'Kanal silindi');
    if (v == true) _y.yenile();
  }

  List<SatirEylemiDugmesi> _dugmeler(AlarmKanali k) => !alarmSahibi(k.orgId)
      ? const []
      : [
          SatirEylemiDugmesi(Icons.send_outlined, 'Test gönder', () => _test(k), ipucu: 'Bu kanala örnek bildirim'),
          SatirEylemiDugmesi(Icons.edit_outlined, 'Düzenle', () => _duzenle(k), ipucu: 'Ad, adresler, URL'),
          SatirEylemiDugmesi(k.etkin ? Icons.toggle_off_outlined : Icons.toggle_on_outlined, k.etkin ? 'Kapat' : 'Etkinleştir', () => _etkinlik(k)),
          if (k.tur == 'webhook')
            SatirEylemiDugmesi(Icons.key_rounded, 'Gizli anahtarı yenile', () => _anahtarYenile(k), ipucu: 'Eski anahtar hemen geçersiz olur'),
          if (k.tur != 'panel' || k.orgId != null)
            SatirEylemiDugmesi(Icons.delete_outline_rounded, 'Sil', () => _sil(k), ipucu: 'Kurallardan da çıkarılır', tehlikeli: true),
        ];

  void _ayrinti(AlarmKanali k) => yonetimPenceresi(
    context,
    baslik: k.ad,
    alt: '${kanalTurleri[k.tur] ?? k.tur} · ${k.orgAdi.isEmpty ? 'Platform' : k.orgAdi}',
    ozet: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BilgiSatiri('Hedef', k.hedef),
        BilgiSatiri('Durum', k.etkin ? 'Etkin' : 'Kapalı'),
        BilgiSatiri(
          'Son gönderim',
          k.sonZaman == null ? '—' : '${tamZaman(k.sonZaman)} · ${k.sonDurum == 'ok' ? 'başarılı' : (k.sonHata.isEmpty ? 'başarısız' : k.sonHata)}',
        ),
        if (!alarmSahibi(k.orgId))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Bu kanalı değiştirme yetkiniz yok.', style: TextStyle(color: context.r.silik, fontSize: 12)),
          ),
      ],
    ),
    eylemler: _dugmeler(k),
  );

  String _son(AlarmKanali k) => k.sonZaman == null ? 'Henüz yok' : '${k.sonDurum == 'ok' ? 'Başarılı' : 'Başarısız'} · ${goreliZaman(k.sonZaman)}';

  IconData _ikon(String tur) => switch (tur) {
    'email' => Icons.mail_outline_rounded,
    'webhook' => Icons.webhook_rounded,
    _ => Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = context.r;
    final t = widget.turler;
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<AlarmKanali>(
      yukleyici: _y,
      onTap: _ayrinti,
      eylemler: (k) => [
        SatirEylemi(Icons.info_outline_rounded, 'Ayrıntı', () => _ayrinti(k)),
        for (final d in _dugmeler(k)) SatirEylemi(d.ikon, d.baslik, d.calistir, tehlikeli: d.tehlikeli),
      ],
      bosIkon: Icons.send_outlined,
      bosMetin: 'Kanal yok. E-posta, webhook veya panel kanalı ekleyin.',
      ust: Padding(
        padding: EdgeInsets.fromLTRB(yatay, 8, yatay, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t != null)
              Bant(
                t.disEposta
                    ? 'Dış gönderim açık (${t.cikisModu}): e-posta kanalları platform dışındaki adreslere de bildirim gönderebilir.'
                    : 'Dış gönderim kapalı (${t.cikisModu}): e-posta bildirimleri yalnızca bu sunucudaki posta kutularına teslim edilir; webhook ve panel kanalları etkilenmez.',
                renk: t.disEposta ? Marka.mavi : Marka.kehribar,
              ),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: Icon(Icons.key_rounded, color: r.soluk, size: 20),
                title: const Text('Webhook imzası', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: [
                  Text(
                    'Her istek HTTPS POST ile JSON gövde taşır ve imzalanır; alıcı imzayı doğrulamalı ve 5 dakikadan eski zaman damgalarını reddetmelidir.',
                    style: TextStyle(color: r.soluk, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  const SelectableText(
                    'X-BogaMail-Timestamp: Unix zamanı (saniye)\n'
                    'X-BogaMail-Signature: sha256=hex(HMAC-SHA256(gizli_anahtar, zaman + "." + gövde))\n'
                    'X-BogaMail-Event: firing, repeat, resolved veya test',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Yalnızca genel internetteki adreslere gönderilir (özel/yerel IP\'ler ve yönlendirmeler engellenir).',
                    style: TextStyle(color: r.silik, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      sutunlar: [
        Sutun(
          'Kanal',
          esnek: 3,
          hucre: (c, k) => IkiSatir(
            k.etkin ? k.ad : '${k.ad} (kapalı)',
            alt: [kanalTurleri[k.tur] ?? k.tur, if (!Uyg.musteri) (k.orgAdi.isEmpty ? 'Platform' : k.orgAdi)].join(' · '),
            sol: Icon(_ikon(k.tur), size: 20, color: r.birincil),
          ),
        ),
        Sutun('Hedef', esnek: 4, hucre: (c, k) => SolukMetin(k.hedef, mono: k.tur == 'webhook')),
        Sutun(
          'Son gönderim',
          esnek: 2,
          hucre: (c, k) => Tooltip(
            message: k.sonHata,
            child: Text(
              _son(k),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: k.sonDurum == 'error' ? Marka.gul : r.soluk),
            ),
          ),
        ),
      ],
      kart: (c, k) => VeriKarti(
        baslik: k.ad,
        alt: k.hedef,
        sol: Icon(_ikon(k.tur), color: r.birincil),
        rozetler: [
          Rozet(kanalTurleri[k.tur] ?? k.tur, renk: r.birincil),
          if (!k.etkin) Rozet('Kapalı', renk: r.silik),
        ],
        alanlar: [if (!Uyg.musteri) ('Sahip', k.orgAdi.isEmpty ? 'Platform' : k.orgAdi), ('Son gönderim', _son(k))],
        eylemler: [for (final d in _dugmeler(k)) SatirEylemi(d.ikon, d.baslik, d.calistir, tehlikeli: d.tehlikeli)],
        onTap: () => _ayrinti(k),
      ),
    );
  }
}

/// Webhook gizli anahtarı yalnızca bir kez gösterilir.
Future<void> gizliAnahtariGoster(BuildContext context, String gizli) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text('Webhook gizli anahtarı', style: gosterim(18, agirlik: FontWeight.w700)),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bu anahtar yalnızca şimdi gösterilir. Alıcı sistemde imza doğrulaması için saklayın.', style: TextStyle(color: c.r.soluk, fontSize: 13)),
          KopyaKutusu(gizli),
        ],
      ),
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
  ),
);

/// Kanal oluşturma / düzenleme (POST /alerts/channels, PATCH /alerts/channels/{id}). Sonuç: kaydedildiyse webhook gizli
/// anahtarı (yeni webhook) ya da boş metin; vazgeçilirse null.
class AlarmKanaliDialog extends StatefulWidget {
  const AlarmKanaliDialog({super.key, this.kanal, this.turler});
  final AlarmKanali? kanal;
  final AlarmTurleri? turler;
  @override
  State<AlarmKanaliDialog> createState() => _AlarmKanaliDialogState();
}

class _AlarmKanaliDialogState extends State<AlarmKanaliDialog> {
  late String _tur = widget.kanal?.tur ?? 'email';
  late final _ad = TextEditingController(text: widget.kanal?.ad ?? '');
  late final _adresler = TextEditingController(text: widget.kanal?.adresler.join('\n') ?? '');
  late final _url = TextEditingController(text: widget.kanal?.url ?? 'https://');
  late bool _etkin = widget.kanal?.etkin ?? true;
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void dispose() {
    _ad.dispose();
    _adresler.dispose();
    _url.dispose();
    super.dispose();
  }

  void _ata(String? hata, String? alan) {
    _hata = hata;
    _alan = alan;
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    final govde = <String, Object>{
      'kind': _tur,
      'name': _ad.text.trim(),
      'enabled': _etkin,
      if (_tur == 'email') 'addresses': _adresler.text.split(RegExp(r'[\n,;\s]+')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList(),
      if (_tur == 'webhook') 'url': _url.text.trim(),
    };
    try {
      final k = widget.kanal;
      final v = k == null ? await Uyg.api.post('/api/v1/alerts/channels', govde) : await Uyg.api.patch('/api/v1/alerts/channels/${k.id}', govde);
      bildir('Kanal kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, metin(harita(v)['secret']));
    } on ApiHata catch (e) {
      setState(() => _ata(e.mesaj, e.alan));
    } catch (e) {
      setState(() => _ata(hataMetni(e), null));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    String? h(String a) => _alan == a ? _hata : null;
    return AlertDialog(
      title: Text(widget.kanal == null ? 'Yeni bildirim kanalı' : 'Kanalı düzenle', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kurallar tetiklendiğinde ve düzeldiğinde bu kanala bildirim gönderilir.', style: TextStyle(color: r.silik, fontSize: 13)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tur,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Tür', errorText: h('kind')),
                items: const [
                  DropdownMenuItem(value: 'email', child: Text('E-posta')),
                  DropdownMenuItem(value: 'webhook', child: Text('Webhook (HTTPS, imzalı)')),
                  DropdownMenuItem(value: 'panel', child: Text('Panel (üst çubuktaki zil)')),
                ],
                onChanged: widget.kanal != null ? null : (v) => setState(() => _tur = v ?? _tur),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ad,
                maxLength: 80,
                decoration: InputDecoration(labelText: 'Ad', errorText: h('name')),
              ),
              if (_tur == 'email')
                TextField(
                  controller: _adresler,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: 'Alıcılar (satır başına bir adres, en fazla 10)',
                    alignLabelWithHint: true,
                    helperText:
                        'Müşteri hesaplarında yalnızca kendi alan adlarınızdaki adresler kabul edilir.${widget.turler != null && !widget.turler!.disEposta ? ' Dış gönderim kapalı olduğundan yalnızca bu sunucudaki posta kutularına teslim edilir.' : ''}',
                    helperMaxLines: 3,
                    errorText: h('addresses'),
                  ),
                ),
              if (_tur == 'webhook')
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'URL',
                    helperText: 'Yalnızca https. Gizli imza anahtarı kayıttan sonra bir kez gösterilir.',
                    helperMaxLines: 2,
                    errorText: h('url'),
                  ),
                ),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _etkin, onChanged: (v) => setState(() => _etkin = v), title: const Text('Etkin')),
              if (_hata != null && !{'kind', 'name', 'addresses', 'url'}.contains(_alan)) Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}
