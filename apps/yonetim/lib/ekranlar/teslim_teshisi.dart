import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import 'trafik_ortak.dart';

const _donemler = <(String, String)>[('24h', '24 saat'), ('7d', '7 gün'), ('30d', '30 gün')];

/// Sınıf başına bir renk (yığılmış eğilim çubukları + gösterge).
Color _sinifRengi(String k) => switch (k) {
  'unknown_user' => Marka.gul,
  'mailbox_full' => const Color(0xFFF97316),
  'blocked_spam' => const Color(0xFFDB2777),
  'policy_dmarc' => Marka.mor,
  'greylist' => const Color(0xFFCBD5E1),
  'dns' => Marka.gok,
  'tls' => Marka.mavi,
  'timeout' => Marka.kehribar,
  'size' => Marka.lavanta,
  _ => const Color(0xFF94A3B8),
};

const _sahipEtiketleri = {'sender': 'gönderen düzeltir', 'admin': 'yönetici düzeltir', 'recipient': 'alıcıya bağlı', 'none': 'kendiliğinden düzelir'};

String _dilimEtiketi(DateTime? d, String donem) {
  if (d == null) return '';
  String iki(int n) => n.toString().padLeft(2, '0');
  const aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
  final g = '${iki(d.day)} ${aylar[d.month - 1]}';
  return donem == '30d' ? g : '$g ${iki(d.hour)}:${iki(d.minute)}';
}

/// Teslim Teşhisi: geri dönen / ertelenen iletilerin nedenleri, eğilimi ve çözümü (GET /deliverability/bounces?range=)
/// ve gönderim yapmadan teslimat ön kontrolü (POST /deliverability/precheck).
class TeslimTeshisiEkrani extends StatefulWidget {
  const TeslimTeshisiEkrani({super.key});
  @override
  State<TeslimTeshisiEkrani> createState() => _TeslimTeshisiEkraniState();
}

class _TeslimTeshisiEkraniState extends State<TeslimTeshisiEkrani> {
  String _donem = '7d';
  var _anahtar = GlobalKey<TekYuklemeState<Map<String, dynamic>>>();

  void _donemSec(String d) => setState(() {
    _donem = d;
    _anahtar = GlobalKey();
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Iskelet(
      baslik: 'Teslim Teşhisi',
      alt: 'Geri dönme nedenleri ve gönderimsiz teslimat ön kontrolü',
      yenile: () => _anahtar.currentState?.yenile(),
      sekmeler: const TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [Tab(text: 'Geri dönme analizi'), Tab(text: 'Teslimat ön kontrolü')],
      ),
      govde: TabBarView(
        children: [
          TekYukleme<Map<String, dynamic>>(
            key: _anahtar,
            getir: () async => harita(await Uyg.api.get('/api/v1/deliverability/bounces', q: {'range': _donem})),
            icerik: (c, v, _) => _GeriDonmeler(v: v, donem: _donem, donemSec: _donemSec),
          ),
          const _OnKontrol(),
        ],
      ),
    ),
  );
}

class _GeriDonmeler extends StatefulWidget {
  const _GeriDonmeler({required this.v, required this.donem, required this.donemSec});
  final Map<String, dynamic> v;
  final String donem;
  final ValueChanged<String> donemSec;
  @override
  State<_GeriDonmeler> createState() => _GeriDonmelerState();
}

class _GeriDonmelerState extends State<_GeriDonmeler> {
  int _alanSayisi = 10, _yanitSayisi = 10;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final v = widget.v;
    final siniflar = haritalar(v['categories']);
    final etiketler = {for (final c in siniflar) metin(c['key']): metin(c['label'])};
    final etkin = siniflar.where((c) => tamsayi(c['count']) > 0).toList()..sort((a, b) => tamsayi(b['count']) - tamsayi(a['count']));
    final alanlar = haritalar(v['domains']);
    final yanitlar = haritalar(v['responses']);
    final egilim = haritalar(v['trend']);
    final toplam = tamsayi(v['total']);
    return IcerikListesi(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text('IP ve alan adı itibarı için İtibar sayfasına bakın.', style: TextStyle(color: r.silik, fontSize: 12.5))),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [for (final (k, e) in _donemler) ButtonSegment(value: k, label: Text(e))],
              selected: {widget.donem},
              onSelectionChanged: (s) => widget.donemSec(s.first),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (toplam == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Durum.bos(
              'Geri dönme yok. Bu dönemde uzak sunuculardan kalıcı veya geçici hata yanıtı kaydedilmedi. (Dış gönderim kapalıyken yazılan ertelemeler sayılmaz.)',
              ikon: Icons.check_circle_outline_rounded,
            ),
          )
        else ...[
          Izgara(
            enAz: 160,
            children: [
              KpiKarti(ikon: Icons.mark_email_unread_outlined, etiket: 'Toplam yanıt', deger: sayiYaz(toplam)),
              KpiKarti(ikon: Icons.cancel_outlined, etiket: 'Kalıcı (5xx)', deger: sayiYaz(tamsayi(v['hard'])), renk: Marka.gul),
              KpiKarti(ikon: Icons.schedule_rounded, etiket: 'Geçici (4xx)', deger: sayiYaz(tamsayi(v['soft'])), renk: Marka.kehribar),
            ],
          ),
          const SizedBox(height: 14),
          BolumKarti(
            baslik: 'Eğilim',
            ikon: Icons.stacked_bar_chart_rounded,
            altBaslik: 'Sınıflara göre hata yanıtları (yanıt sayısı; bir alıcı birden çok deneme alabilir).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final c in etkin)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: _sinifRengi(metin(c['key'])), borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 6),
                          Text(metin(c['label']), style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _EgilimGrafigi(dilimler: egilim, etiketler: etiketler, donem: widget.donem),
              ],
            ),
          ),
          AltBaslik('Hata teşhisi'),
          Izgara(
            enAz: 300,
            children: [
              for (final c in etkin)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(color: _sinifRengi(metin(c['key'])), borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(metin(c['label']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text(sayiYaz(tamsayi(c['count'])), style: gosterim(18, agirlik: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tamsayi(c['hard'])} kalıcı · ${tamsayi(c['soft'])} geçici · ${tamsayi(c['domains'])} alan adı'
                        '${metinYa(c['top_domain']) != null ? ' (en çok ${metin(c['top_domain'])})' : ''} · ${_sahipEtiketleri[metin(c['owner'])] ?? metin(c['owner'])}',
                        style: TextStyle(color: r.silik, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      AciklamaMetni(Aciklama(ozet: metin(c['explain']), oneri: metin(c['fix']))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          BolumKarti(
            baslik: 'Alıcı alan adlarına göre',
            ikon: Icons.language_rounded,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              children: [
                for (final (i, d) in alanlar.take(_alanSayisi).indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar),
                  _AlanSatiri(d: d, etiketler: etiketler),
                ],
                if (alanlar.length > _alanSayisi)
                  TextButton(onPressed: () => setState(() => _alanSayisi += 10), child: Text('Daha fazla göster (${alanlar.length - _alanSayisi} kaldı)')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BolumKarti(
            baslik: 'En sık uzak sunucu yanıtları',
            ikon: Icons.forum_outlined,
            altBaslik: 'Adresler maskelenir (ör. a***@alan.com).',
            child: Column(
              children: [
                for (final (i, y) in yanitlar.take(_yanitSayisi).indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(sayiYaz(tamsayi(y['count'])), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Rozet(etiketler[metin(y['category'])] ?? metin(y['category']), renk: _sinifRengi(metin(y['category']))),
                                  Text(metin(y['code']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 3),
                              SelectableText(metinYa(y['text']) ?? '—', style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: r.soluk)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (yanitlar.length > _yanitSayisi)
                  TextButton(onPressed: () => setState(() => _yanitSayisi += 10), child: Text('Daha fazla göster (${yanitlar.length - _yanitSayisi} kaldı)')),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AlanSatiri extends StatelessWidget {
  const _AlanSatiri({required this.d, required this.etiketler});
  final Map<String, dynamic> d;
  final Map<String, String> etiketler;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final sayilar = harita(d['counts']).entries.map((e) => (e.key, tamsayi(e.value))).toList()..sort((a, b) => b.$2 - a.$2);
    final siniflar = sayilar.map((e) => '${etiketler[e.$1] ?? e.$1} ${e.$2}').join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: metin(d['domain']), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (metinYa(d['provider']) != null)
                        TextSpan(text: '  ${metin(d['provider'])}', style: TextStyle(color: r.silik, fontSize: 12)),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(siniflar, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${sayiYaz(tamsayi(d['total']))} yanıt', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('${sayiYaz(tamsayi(d['hard']))} kalıcı', style: TextStyle(color: r.silik, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Yığılmış çubuk eğilim grafiği; dokununca dilim ayrıntısı.
class _EgilimGrafigi extends StatelessWidget {
  const _EgilimGrafigi({required this.dilimler, required this.etiketler, required this.donem});
  final List<Map<String, dynamic>> dilimler;
  final Map<String, String> etiketler;
  final String donem;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (dilimler.isEmpty) return SizedBox(height: 120, child: Center(child: Text('Veri yok.', style: TextStyle(color: r.silik))));
    final enFazla = dilimler.fold<int>(1, (a, b) => tamsayi(b['total']) > a ? tamsayi(b['total']) : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in dilimler)
                Expanded(
                  child: Tooltip(
                    message: [
                      '${_dilimEtiketi(tarihOku(b['at']), donem)}: ${tamsayi(b['total'])} yanıt',
                      for (final e in harita(b['counts']).entries) '${etiketler[e.key] ?? e.key}: ${tamsayi(e.value)}',
                    ].join('\n'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: .6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (final e in harita(b['counts']).entries)
                            Container(height: 130 * tamsayi(e.value) / enFazla, color: _sinifRengi(e.key)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_dilimEtiketi(tarihOku(dilimler.first['at']), donem), style: TextStyle(color: r.silik, fontSize: 10.5)),
            Text('şimdi', style: TextStyle(color: r.silik, fontSize: 10.5)),
          ],
        ),
      ],
    );
  }
}

/// Teslimat ön kontrolü: ileti gönderilmez; içerik denetimi ve DNS kimlik doğrulama kontrolleri gerçek gönderimdeki gibi çalışır.
class _OnKontrol extends StatefulWidget {
  const _OnKontrol();
  @override
  State<_OnKontrol> createState() => _OnKontrolState();
}

class _OnKontrolState extends State<_OnKontrol> with AutomaticKeepAliveClientMixin {
  PostaKutusu? _kutu;
  final _alicilar = TextEditingController(), _konu = TextEditingController(), _metin = TextEditingController(), _abonelik = TextEditingController();
  bool _mesgul = false;
  String? _hata;
  Map<String, dynamic>? _sonuc;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    for (final k in [_alicilar, _konu, _metin, _abonelik]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kutuSec() async {
    final k = await araVeSec<PostaKutusu>(
      context,
      baslik: 'Gönderen posta kutusu',
      ipucu: 'Kutu ara…',
      yukle: (q) async => Sayfa.coz(
        await Uyg.api.get('/api/v1/mailboxes', q: {'page_size': '50', 'sort': 'address', 'order': 'asc', if (q.isNotEmpty) 'q': q}),
        PostaKutusu.coz,
      ).ogeler,
      ad: (k) => k.adres,
      alt: (k) => k.gorunenAd.isEmpty ? null : k.gorunenAd,
    );
    if (k != null && mounted) setState(() => _kutu = k);
  }

  Future<void> _calistir() async {
    final alicilar = _alicilar.text.split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty).toList();
    if (_kutu == null) return setState(() => _hata = 'Gönderen posta kutusunu seçin');
    if (alicilar.isEmpty || alicilar.length > 200) return setState(() => _hata = '1–200 alıcı girin');
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final v = harita(
        await Uyg.api.post('/api/v1/deliverability/precheck', {
          'mailbox_id': _kutu!.id,
          'recipients': alicilar,
          'subject': _konu.text,
          'text': _metin.text,
          'list_unsubscribe': [if (_abonelik.text.trim().isNotEmpty) _abonelik.text.trim()],
        }),
      );
      if (mounted) setState(() => _sonuc = v);
    } catch (e) {
      if (mounted) {
        setState(() {
          _hata = hataMetni(e);
          _sonuc = null;
        });
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final form = BolumKarti(
      baslik: 'Test iletisi',
      ikon: Icons.edit_note_rounded,
      altBaslik: 'İleti gönderilmez: giden içerik denetimi ve DNS kimlik doğrulama kontrolleri gerçek gönderimdeki gibi çalışır.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SecimAlani(etiket: 'Gönderen posta kutusu', deger: _kutu?.adres, onTap: _kutuSec),
          const SizedBox(height: 12),
          TextField(
            controller: _alicilar,
            decoration: const InputDecoration(labelText: 'Alıcılar', hintText: 'ornek@gmail.com, diger@outlook.com'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _konu, decoration: const InputDecoration(labelText: 'Konu')),
          const SizedBox(height: 12),
          TextField(
            controller: _metin,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'İçerik (düz metin)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _abonelik,
            decoration: const InputDecoration(labelText: 'List-Unsubscribe (bülten ise)', hintText: '<https://ornek.com/abonelik-iptal>'),
          ),
          if (_hata != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13))),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _mesgul || _kutu == null ? null : _calistir,
              icon: _mesgul
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('Ön kontrolü çalıştır'),
            ),
          ),
        ],
      ),
    );
    final sonuc = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [..._sonucParcalari(context), const SizedBox(height: 12), _seedKarti(context)]);
    return LayoutBuilder(
      builder: (c, k) {
        if (k.maxWidth >= 1100) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: form),
                const SizedBox(width: 16),
                Expanded(flex: 3, child: sonuc),
              ],
            ),
          );
        }
        return IcerikListesi(children: [const SizedBox(height: 8), form, const SizedBox(height: 12), sonuc]);
      },
    );
  }

  Widget _seedKarti(BuildContext context) => BolumKarti(
    baslik: 'Dış gelen kutusu testi (seed)',
    ikon: Icons.inbox_outlined,
    sag: const Rozet('Onay bekliyor (dış gönderim)', renk: Marka.kehribar),
    child: Text(
      'Gmail, Outlook gibi dış test kutularına gerçek ileti gönderip gelen kutusu / spam yerleşimini ölçen testler gerçek dış gönderim gerektirir; '
      'sahip onayı olmadan çalıştırılmaz.',
      style: TextStyle(color: context.r.soluk, fontSize: 13),
    ),
  );

  List<Widget> _sonucParcalari(BuildContext context) {
    final r = context.r;
    final s = _sonuc;
    if (s == null) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: r.kenar)),
          child: Center(child: Text('Sonuçlar burada görünür.', style: TextStyle(color: r.silik))),
        ),
      ];
    }
    final hukum = metin(s['verdict']);
    final (baslik, renk, ikon) = switch (hukum) {
      'ok' => ('Gönderime hazır', Marka.zumrut, Icons.check_circle_outline_rounded),
      'fail' => ('Gönderilemez / reddedilir', Marka.gul, Icons.cancel_outlined),
      _ => ('Riskli — iyileştirin', Marka.kehribar, Icons.gpp_maybe_outlined),
    };
    final icerik = s['content'] is Map ? harita(s['content']) : null;
    final bulgular = haritalar(icerik?['findings']);
    final denetimler = haritalar(s['checks']);
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: renk.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: renk.withValues(alpha: .4))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikon, color: renk),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    'İçerik puanı ${icerik == null ? '—' : ondalik(icerik['score']).toStringAsFixed(1)} / eşik ${icerik == null ? '—' : metin(icerik['threshold'])}'
                    '${mantik(icerik?['bulk']) ? ' · toplu gönderim' : ''} · ${mantik(s['external']) ? 'dış alıcı var' : 'yalnızca platform içi'} · ileti gönderilmedi',
                    style: TextStyle(color: r.soluk, fontSize: 12.5),
                  ),
                  if (metin(s['refusal']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(metin(s['refusal']), style: const TextStyle(fontSize: 12.5))),
                ],
              ),
            ),
          ],
        ),
      ),
      if (bulgular.isNotEmpty) ...[
        const SizedBox(height: 12),
        BolumKarti(
          baslik: 'İçerik bulguları',
          ikon: Icons.rule_rounded,
          child: Column(
            children: [
              for (final (i, f) in bulgular.indexed) ...[
                if (i > 0) Divider(height: 1, color: r.kenar),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(metin(f['rule']), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          if (mantik(f['block']))
                            const Rozet('engeller', renk: Marka.gul)
                          else
                            Rozet('+${ondalik(f['score']).toStringAsFixed(1)}', renk: Marka.kehribar),
                        ],
                      ),
                      const SizedBox(height: 3),
                      AciklamaMetni(Aciklama(ozet: metin(f['detail']), oneri: metin(f['fix']))),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      BolumKarti(
        baslik: 'Kimlik doğrulama, alıcılar ve IP',
        ikon: Icons.verified_user_outlined,
        child: Column(
          children: [
            for (final (i, c) in denetimler.indexed) ...[
              if (i > 0) Divider(height: 1, color: r.kenar),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(metin(c['label']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        IzlemeRozeti(metin(c['status'])),
                      ],
                    ),
                    if (metin(c['detail']).isNotEmpty) Text(metin(c['detail']), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                    if (metin(c['fix']).isNotEmpty && metin(c['status']) != 'ok') Text(metin(c['fix']), style: const TextStyle(fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }
}
