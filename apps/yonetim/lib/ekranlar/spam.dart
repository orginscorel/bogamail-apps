import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/secimler.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'koruma_ortak.dart';

const spamTurEtiketi = {'sender': 'Gönderen adresi', 'domain': 'Alan adı', 'ip': 'IP / ağ', 'asn': 'ASN', 'link': 'Bağlantı'};

/// Spam izin / engel listesi kaydı (GET /api/v1/spam/lists → items).
class SpamKaydi {
  SpamKaydi(this.m);
  final Map<String, dynamic> m;
  static SpamKaydi coz(Map<String, dynamic> m) => SpamKaydi(m);
  String get id => metin(m['id']);
  String? get orgId => metinYa(m['organization_id']);
  String? get orgAdi => metinYa(m['organization_name']);
  bool get izin => metin(m['kind']) == 'allow';
  String get tur => metin(m['type']);
  String get deger => metin(m['value']);
  String? get not => metinYa(m['note']);
  String get ekleyen => metin(m['created_by']);
  DateTime? get zaman => tarihOku(m['created_at']);
  String get kapsam => orgAdi ?? 'Tüm platform';
}

/// Spam Güvenliği: günlük özet, son kararlar, en sık kurallar; izin / engel listeleri.
class SpamEkrani extends StatefulWidget {
  const SpamEkrani({super.key});
  @override
  State<SpamEkrani> createState() => _SpamEkraniState();
}

class _SpamEkraniState extends State<SpamEkrani> {
  final _ozet = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();
  Timer? _zamanlayici;
  String _tur = '';

  late final _y = SayfaYukleyici.yerel<SpamKaydi>(
    () async =>
        haritalar(harita(await Uyg.api.get('/api/v1/spam/lists'))['items'])
            .map(SpamKaydi.coz)
            .where((k) => _tur.isEmpty || metin(k.m['kind']) == _tur)
            .toList(),
  )..yenile();

  @override
  void initState() {
    super.initState();
    _zamanlayici = Timer.periodic(const Duration(seconds: 30), (_) => _ozet.currentState?.yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _y.dispose();
    super.dispose();
  }

  bool get _yonetir => Uyg.yetki('spam.manage');

  Future<void> _ekle() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _SpamKayitFormu());
    if (ok == true) await _y.yenile();
  }

  Future<void> _sil(SpamKaydi k) async {
    final evet = await onayla(context, 'Kayıt silinsin mi?', mesaj: '${k.deger} listeden çıkarılacak.', evet: 'Sil', tehlikeli: true);
    if (!evet) return;
    final v = await islem(() async {
      await Uyg.api.delete('/api/v1/spam/lists/${k.id}');
      return true;
    }, tamam: 'Kayıt silindi');
    if (v == true) _y.degistir((x) => x.id == k.id, null);
  }

  List<SatirEylemi> _eylemler(SpamKaydi k) => [
    if (_yonetir && (Uyg.platformYoneticisi || k.orgId != null)) SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(k), tehlikeli: true),
  ];

  Widget _turRozeti(SpamKaydi k) =>
      k.izin ? const Rozet('İzin', renk: Marka.zumrut, ikon: Icons.verified_user_outlined) : const Rozet('Engel', renk: Marka.gul, ikon: Icons.block_rounded);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (c) => Iskelet(
          baslik: 'Spam Güvenliği',
          alt: 'Açıklanabilir kurallarla puanlama; izin ve engel listeleri',
          yenile: () {
            _ozet.currentState?.yenile();
            _y.yenile();
          },
          birincil: _yonetir ? BirincilEylem(Icons.add_rounded, 'Listeye ekle', _ekle) : null,
          sekmeler: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Özet'),
              Tab(text: 'İzin ve engel listeleri'),
            ],
          ),
          govde: TabBarView(children: [_ozetSekmesi(), _listeSekmesi()]),
        ),
      ),
    );
  }

  Widget _ozetSekmesi() => TekYukleme<Map<String, dynamic>>(
    key: _ozet,
    getir: () async => harita(await Uyg.api.get('/api/v1/spam/summary')),
    icerik: (c, s, yenile) {
      final r = c.r;
      final son = haritalar(s['recent']);
      final kurallar = haritalar(s['top_rules']);
      return IcerikListesi(
        children: [
          const SizedBox(height: 8),
          Text(
            'Her gelen ileti açıklanabilir kurallarla puanlanır (DNSBL, SPF, DKIM, DMARC, HELO, başlık, tehlikeli ek, bağlantı ve ifade kuralları). '
            'Eşikler Ayarlar\'dan değiştirilir.',
            style: TextStyle(color: r.silik, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Izgara(
            enAz: 200,
            children: [
              KpiKarti(ikon: Icons.manage_search_rounded, etiket: 'Bugün taranan', deger: sayiYaz(tamsayi(s['scanned_today']))),
              KpiKarti(ikon: Icons.report_outlined, etiket: 'Gereksiz\'e gönderilen', deger: sayiYaz(tamsayi(s['junked_today'])), renk: Marka.kehribar),
              KpiKarti(ikon: Icons.block_rounded, etiket: 'Reddedilen (puan)', deger: sayiYaz(tamsayi(s['rejected_today'])), renk: Marka.gul),
              KpiKarti(
                ikon: Icons.playlist_remove_rounded,
                etiket: 'Listeyle engellenen',
                deger: sayiYaz(tamsayi(s['blocked_by_list_today'])),
                renk: Marka.mavi,
              ),
            ],
          ),
          const SizedBox(height: 16),
          YanYana(
            esik: 1000,
            bosluk: 16,
            children: [
              BolumKarti(
                baslik: 'Son spam kararları',
                ikon: Icons.history_rounded,
                altBaslik: 'Puan ve eşleşen kurallar; içerik kaydedilmez',
                child: son.isEmpty
                    ? Text('Henüz spam kararı yok. Gereksiz ya da reddedilen iletiler burada listelenir.', style: TextStyle(color: r.soluk))
                    : Column(children: [for (final (i, e) in son.indexed) _kararSatiri(c, e, i == 0)]),
              ),
              BolumKarti(
                baslik: 'En sık eşleşen kurallar (7 gün)',
                ikon: Icons.rule_rounded,
                child: kurallar.isEmpty
                    ? Text('Veri yok', style: TextStyle(color: r.soluk))
                    : Column(
                        children: [
                          for (final k in kurallar)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(metin(k['rule']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                  ),
                                  Text(sayiYaz(tamsayi(k['count'])), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      );
    },
  );

  Widget _kararSatiri(BuildContext c, Map<String, dynamic> e, bool ilk) {
    final r = c.r;
    final ret = metin(e['spam_action']) == 'reject';
    final puan = ondalikYa(e['spam_score']);
    final kurallar = metinler(e['spam_rules']).join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: ilk ? null : Border(top: BorderSide(color: r.kenar)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 84),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Rozet('${ret ? 'Ret' : 'Gereksiz'}${puan != null ? ' ${puan.toStringAsFixed(1)}' : ''}', renk: ret ? Marka.gul : Marka.kehribar),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${metinYa(e['mail_from']) ?? '<>'} → ${metin(e['rcpt'])}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
                Text(tamZaman(tarihOku(e['at'])), style: TextStyle(color: r.silik, fontSize: 12)),
                if (kurallar.isNotEmpty)
                  Text(
                    kurallar,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: r.soluk),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listeSekmesi() => VeriTablosu<SpamKaydi>(
    yukleyici: _y,
    bosMetin: 'Liste boş.',
    bosIkon: Icons.playlist_add_check_rounded,
    eylemler: _eylemler,
    ust: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'İzin: puanı ne olursa olsun Gelen Kutusu\'na. Engel: gönderen/IP eşleşirse RCPT aşamasında 550 ile reddedilir (From başlığı eşleşirse Gereksiz). '
          'Müşteri listeleri yalnızca o müşterinin alıcılarını etkiler.${Uyg.musteri ? ' İzin kayıtlarını platform yöneticisi ekler; siz engel ekleyebilirsiniz.' : ''}',
          style: TextStyle(color: context.r.silik, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        SecimCipleri<String>(
          secenekler: const [('', 'Tümü'), ('allow', 'İzin'), ('block', 'Engel')],
          secili: _tur,
          secildi: (v) {
            setState(() => _tur = v);
            _y.yenile();
          },
        ),
        const SizedBox(height: 4),
      ],
    ),
    sutunlar: [
      Sutun(
        'Tür',
        esnek: 1,
        hucre: (c, k) => Align(alignment: Alignment.centerLeft, child: _turRozeti(k)),
      ),
      Sutun('Değer', esnek: 4, hucre: (c, k) => IkiSatir(k.deger, alt: [spamTurEtiketi[k.tur] ?? k.tur, ?k.not].join(' · '), mono: true)),
      Sutun(
        'Kapsam',
        esnek: 2,
        hucre: (c, k) => k.orgAdi == null ? const Rozet('Tüm platform', renk: Marka.mavi) : Text(k.orgAdi!, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      Sutun('Ekleyen', esnek: 3, hucre: (c, k) => IkiSatir(k.ekleyen, alt: tamZaman(k.zaman), kalin: false)),
    ],
    kart: (c, k) => VeriKarti(
      baslik: k.deger,
      alt: spamTurEtiketi[k.tur] ?? k.tur,
      rozetler: [_turRozeti(k)],
      alanlar: [('Kapsam', k.kapsam), ('Ekleyen', k.ekleyen), ('Tarih', tamZaman(k.zaman)), if (k.not != null) ('Not', k.not!)],
      eylemler: _eylemler(k),
    ),
  );
}

/// İzin / engel listesine kayıt ekleme (POST /api/v1/spam/lists).
class _SpamKayitFormu extends StatefulWidget {
  const _SpamKayitFormu();
  @override
  State<_SpamKayitFormu> createState() => _SpamKayitFormuState();
}

class _SpamKayitFormuState extends State<_SpamKayitFormu> {
  String _tur = 'block', _eslesme = 'domain';
  final _deger = TextEditingController();
  final _not = TextEditingController();
  String? _orgId, _orgAdi, _hata, _alan;
  bool _mesgul = false;

  @override
  void dispose() {
    _deger.dispose();
    _not.dispose();
    super.dispose();
  }

  // Müşteri kendi kapsamına ekler; bayi bir müşteri seçmeli; süper yönetici tüm platform ya da müşteri seçer.
  bool get _kapsamGerekli => Uyg.rol == 'reseller_admin';

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      await Uyg.api.post('/api/v1/spam/lists', {
        'kind': _tur,
        'type': _eslesme,
        'value': _deger.text.trim(),
        if (_not.text.trim().isNotEmpty) 'note': _not.text.trim(),
        'organization_id': ?_orgId,
      });
      bildir('Listeye eklendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      setState(() {
        _alan = e.alan;
        _hata = e.durum == 409 ? 'Bu kayıt zaten var.' : e.mesaj;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String get _ipucu => switch (_eslesme) {
    'asn' => 'AS64500',
    'ip' => '198.51.100.0/24',
    'sender' => 'kisi@ornek.com',
    'link' => 'ornek.com ya da https://ornek.com/yol',
    _ => 'ornek.com',
  };

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final hazir = !_mesgul && _deger.text.trim().isNotEmpty && (!_kapsamGerekli || _orgId != null);
    Widget etiket(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        s,
        style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
    return AlertDialog(
      title: Text('Listeye ekle', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              etiket('Liste'),
              SecimCipleri<String>(
                secenekler: [('block', 'Engel'), if (!Uyg.musteri) ('allow', 'İzin')],
                secili: _tur,
                secildi: (v) => setState(() => _tur = v),
              ),
              const SizedBox(height: 8),
              etiket('Eşleşme'),
              SecimCipleri<String>(
                secenekler: const [('domain', 'Alan adı'), ('sender', 'Gönderen adresi'), ('ip', 'IP / ağ (CIDR)'), ('asn', 'ASN'), ('link', 'Bağlantı')],
                secili: _eslesme,
                secildi: (v) => setState(() => _eslesme = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _deger,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Değer', hintText: _ipucu, errorText: _alan == 'value' ? _hata : null, errorMaxLines: 2),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _not,
                maxLength: 200,
                decoration: InputDecoration(labelText: 'Not (isteğe bağlı)', errorText: _alan == 'note' ? _hata : null),
              ),
              if (!Uyg.musteri) ...[
                SecimAlani(
                  etiket: _kapsamGerekli ? 'Müşteri' : 'Kapsam',
                  deger: _orgAdi ?? (_kapsamGerekli ? null : 'Tüm platform'),
                  hata: _alan == 'organization_id' ? _hata : null,
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
                if (_orgId != null && !_kapsamGerekli)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: () => setState(() => _orgId = _orgAdi = null), child: const Text('Tüm platforma uygula')),
                  ),
              ],
              if (_hata != null && !{'value', 'note', 'organization_id'}.contains(_alan)) ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: hazir ? _kaydet : null, child: mesgulYazi(_mesgul, 'Ekle')),
      ],
    );
  }
}
