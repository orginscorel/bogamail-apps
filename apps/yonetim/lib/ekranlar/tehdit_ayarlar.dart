import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../veri/json.dart';
import '../veri/tehdit_modeller.dart';
import 'tehdit_ortak.dart';

/// Tehdit Koruması platform ayarları (süper yönetici): denetimler, URI kara listeleri, ARC güvenilir ileticileri
/// (PATCH /threat/settings), gelişmiş tehdit koruması ve döngü tespiti (PATCH /security2/settings).
class TehditPlatformAyarlari extends StatelessWidget {
  const TehditPlatformAyarlari({super.key});

  @override
  Widget build(BuildContext context) => TekYukleme<(Map<String, dynamic>, Map<String, dynamic>)>(
    getir: () async {
      final t = harita(harita(await Uyg.api.get('/api/v1/threat/settings'))['settings']);
      final s = harita(await Uyg.api.get('/api/v1/security2/settings'));
      return (t, s);
    },
    icerik: (c, v, yenile) => _AyarGovdesi(tehdit: v.$1, guvenlik: v.$2),
  );
}

class _AyarGovdesi extends StatefulWidget {
  const _AyarGovdesi({required this.tehdit, required this.guvenlik});
  final Map<String, dynamic> tehdit, guvenlik;
  @override
  State<_AyarGovdesi> createState() => _AyarGovdesiState();
}

class _AyarGovdesiState extends State<_AyarGovdesi> {
  late Map<String, dynamic> _t = widget.tehdit;
  bool _mesgul = false;

  final _bolge = TextEditingController();
  final _puan = TextEditingController(text: '5');
  late final _arc = TextEditingController(text: metinler(_t['arc_trusted_sealers']).join('\n'));
  bool _arcDegisti = false;

  // Gelişmiş + döngü formu.
  late final Map<String, dynamic> _gelismis = Map.of(harita(widget.guvenlik['advanced']));
  late final _karantina = TextEditingController(text: _sayi(_gelismis['sandbox_quarantine_score']));
  late final _ttl = TextEditingController(text: _sayi(_gelismis['click_ttl_days']));
  late final _tekrar = TextEditingController(text: _sayi(harita(widget.guvenlik['loop'])['max_repeats']));
  late final _pencere = TextEditingController(text: _sayi(harita(widget.guvenlik['loop'])['window_minutes']));
  String? _formHata;

  static String _sayi(Object? v) {
    final d = ondalik(v);
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
  }

  @override
  void dispose() {
    for (final k in [_bolge, _puan, _arc, _karantina, _ttl, _tekrar, _pencere]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<bool> _kaydet(Map<String, dynamic> degisen) async {
    setState(() => _mesgul = true);
    final y = await islem(() => Uyg.api.patch('/api/v1/threat/settings', degisen), tamam: 'Ayarlar kaydedildi');
    if (!mounted) return false;
    setState(() {
      _mesgul = false;
      if (y != null) _t = harita(harita(y)['settings']);
    });
    return y != null;
  }

  Map<String, double> get _bolgeler => {for (final e in harita(_t['uribl_zones']).entries) e.key: ondalik(e.value)};

  Future<void> _bolgeEkle() async {
    final z = _bolge.text.trim().toLowerCase();
    final p = ondalik(_puan.text, double.nan);
    if (z.isEmpty) return;
    if (p.isNaN || p < .5 || p > 20) {
      bildir('Puan 0,5–20 arasında olmalı', tur: MesajTur.uyari);
      return;
    }
    if (await _kaydet({
      'uribl_zones': {..._bolgeler, z: p},
    })) {
      _bolge.clear();
    }
  }

  Future<void> _gelismisKaydet() async {
    final k = ondalik(_karantina.text, double.nan), ttl = tamsayiYa(_ttl.text.trim());
    final tekrar = tamsayiYa(_tekrar.text.trim()), pencere = tamsayiYa(_pencere.text.trim());
    if (k.isNaN || k < 3 || k > 100) return setState(() => _formHata = 'Karantina eşiği 3–100 arasında olmalı');
    if (ttl == null || ttl < 1) return setState(() => _formHata = 'Bağlantı geçerliliği gün olarak girilmeli');
    if (tekrar == null || pencere == null || tekrar < 2 || tekrar > 100 || pencere < 1 || pencere > 1440) {
      return setState(() => _formHata = 'Tekrar sayısı 2–100, pencere 1–1440 dakika olmalı');
    }
    setState(() {
      _formHata = null;
      _mesgul = true;
    });
    try {
      await Uyg.api.patch('/api/v1/security2/settings', {
        'advanced': {..._gelismis, 'sandbox_quarantine_score': k, 'click_ttl_days': ttl, 'click_rewrite_imap': false},
        'loop': {'max_repeats': tekrar, 'window_minutes': pencere},
      });
      bildir('Kaydedildi', tur: MesajTur.basari);
    } on ApiHata catch (e) {
      setState(() => _formHata = e.mesaj);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final g = widget.guvenlik;
    final patlatma = harita(g['detonation']);
    final denetimler = [
      ('dmarc_enforce', 'DMARC politikasını uygula',
          'p=reject → DATA sonunda 550 ret, p=quarantine → Önemsiz. Kapalıyken yalnızca puanlanır. Müşteri bazında geçersiz kılınabilir; izin listesindeki göndericiler reddedilmez.'),
      ('impersonation', 'Kimlik taklidi ve benzer alan adı denetimi', 'Paketinde özellik açık olan müşteriler için VIP/posta kutusu adı ve benzer alan adı denetimi.'),
      ('link_checks', 'Bağlantı denetimi', 'IP adresli, kısaltılmış, karışık alfabeli, görünen metni farklı, kurum alan adına benzeyen ve yeni görülen bağlantılar.'),
      ('asn_lookup', 'ASN sorgusu (Team Cymru DNS)', 'Ücretsiz DNS servisi; sonuçlar 24 saat saklanır. Kapalıyken ASN listeleri ve ASN itibarı kullanılmaz.'),
    ];
    final bolgeler = _bolgeler;
    return IcerikListesi(
      children: [
        const SizedBox(height: 12),
        BolumKarti(
          baslik: 'Denetimler',
          ikon: Icons.fact_check_outlined,
          altBaslik: 'Gelen her iletide uygulanır (Spam Güvenliği açıkken). ARC zinciri her iletide doğrulanır.',
          child: Column(
            children: [
              for (final (k, b, i) in denetimler)
                AyarAnahtari(baslik: b, ipucu: i, deger: mantik(_t[k]), degisti: _mesgul ? null : (v) => _kaydet({k: v})),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'DNS URI kara listeleri (DBL / URIBL / SURBL)',
          ikon: Icons.dns_outlined,
          altBaslik: 'Varsayılan kapalı. Bu listeler genellikle kayıt ister ve ticari kullanımda lisans gerektirir; kullanım koşullarını kabul '
              'ettiyseniz bölge adını ekleyin. 127.0.0.1 ve 127.255.255.x yanıtları hata kodu sayılır. En fazla 5 bölge.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (bolgeler.isEmpty)
                Text('Hiç bölge yok (kapalı).', style: TextStyle(color: r.soluk, fontSize: 13))
              else
                for (final e in bolgeler.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.public_rounded, size: 20),
                    title: Text(e.key, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text('+${puanYaz(e.value)} puan'),
                    trailing: IconButton(
                      tooltip: 'Kaldır',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: _mesgul ? null : () => _kaydet({'uribl_zones': Map.of(bolgeler)..remove(e.key)}),
                    ),
                  ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(controller: _bolge, decoration: const InputDecoration(labelText: 'Bölge', hintText: 'dbl.spamhaus.org')),
                  ),
                  SizedBox(
                    width: 100,
                    child: TextField(controller: _puan, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Puan')),
                  ),
                  FilledButton.tonalIcon(onPressed: _mesgul ? null : _bolgeEkle, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Ekle')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'ARC: güvenilir ileticiler',
          ikon: Icons.forward_to_inbox_outlined,
          altBaslik: 'DMARC başarısız olduğunda ARC zinciri geçerliyse ve son mühürleyen (ARC-Seal d=) bu listedeyse DMARC politikası uygulanmaz '
              '(ör. posta listeleri, yönlendirme servisleri). Alt alan adları da eşleşir. Yalnızca gerçekten güvendiğiniz ileticileri ekleyin.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _arc,
                minLines: 3,
                maxLines: 8,
                onChanged: (_) => setState(() => _arcDegisti = true),
                decoration: const InputDecoration(labelText: 'Alan adları (her satıra bir tane, en fazla 50)', hintText: 'google.com\noutlook.com'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _mesgul || !_arcDegisti
                      ? null
                      : () async {
                          final l = _arc.text.split(RegExp(r'[\s,]+')).map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
                          if (await _kaydet({'arc_trusted_sealers': l})) setState(() => _arcDegisti = false);
                        },
                  child: const Text('Kaydet'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Gelişmiş tehdit koruması',
          ikon: Icons.science_outlined,
          altBaslik: 'Yalnızca "Gelişmiş tehdit koruması" paket özelliği açık müşterilere uygulanır.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AyarAnahtari(
                baslik: 'QR kod oltalama koruması',
                ipucu: 'Gövdedeki görseller, ekler ve PDF içindeki görsellerde QR kod çözülür; hedef adres bağlantı kurallarıyla denetlenir.',
                deger: mantik(_gelismis['qr']),
                degisti: (v) => setState(() => _gelismis['qr'] = v),
              ),
              AyarAnahtari(
                baslik: 'Ek analizi (statik)',
                ipucu: 'Makro, DDE, dış şablon, OLE, PDF eylemleri, arşivler, uzantı uyumsuzluğu, HTML smuggling, ISO/IMG/LNK/ONE.',
                deger: mantik(_gelismis['sandbox']),
                degisti: (v) => setState(() => _gelismis['sandbox'] = v),
              ),
              AyarAnahtari(
                baslik: 'Tıklama anı bağlantı koruması (webmail)',
                ipucu: 'Bağlantılar imzalı yönlendirme adresinden geçer ve tıklandığı anda yeniden denetlenir.',
                deger: mantik(_gelismis['click_protection']),
                degisti: (v) => setState(() => _gelismis['click_protection'] = v),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _karantina,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Karantina puanı', helperText: 'Bu puan ve üstündeki ekler karantinaya alınır.'),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _ttl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Bağlantı geçerliliği (gün)', helperText: 'İmzalı bağlantının geçerli kaldığı süre.'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12), border: Border.all(color: r.kenar)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('Dinamik çalıştırma (detonation)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        Rozet(metin(patlatma['status'], '—'), renk: Marka.kehribar),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(metin(patlatma['detail']), style: TextStyle(color: r.silik, fontSize: 12)),
                    const SizedBox(height: 10),
                    const Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('IMAP bağlantı yeniden yazma', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        Rozet('Kapalı · Faz 2', renk: Colors.blueGrey),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(metin(g['imap_rewrite_note']), style: TextStyle(color: r.silik, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BolumKarti(
          baslik: 'Posta döngüsü tespiti',
          ikon: Icons.loop_rounded,
          altBaslik: '25\'ten fazla Received başlığı, kendi X-BogaMail-Loop işaretimiz veya aynı (gönderen, alıcı, Message-ID) üçlüsünün kısa '
              'sürede tekrar gelmesi 554 5.4.6 ile reddedilir.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _tekrar,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Aynı ileti en fazla', helperText: 'Bu sayıdan sonraki tekrar reddedilir.'),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(controller: _pencere, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Zaman aralığı (dakika)')),
                  ),
                ],
              ),
              if (_formHata != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_formHata!, style: const TextStyle(color: Marka.gul, fontSize: 12.5))),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _mesgul ? null : _gelismisKaydet,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Gelişmiş ayarları kaydet'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const BolumKarti(
          baslik: 'Puanlar ve yanlış pozitifler',
          ikon: Icons.gpp_maybe_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Aciklama(
                'Kendi alan adını taklit (doğrulamasız) +6 · VIP adı +5 · posta kutusu adı +1,5 · benzer From alan adı +5 · Reply-To ücretsiz posta +2 · DMARC başarısız (reject) +5.',
              ),
              SizedBox(height: 6),
              Aciklama(
                'Kurum adına dışarıdan gönderim yapan servisler (CRM, fatura, bülten) SPF/DKIM ile yetkilendirilmemişse "kendi alan adını taklit" sayılır: '
                'bu servisleri SPF/DKIM\'e ekleyin veya izin listesine alın.',
              ),
              SizedBox(height: 6),
              Aciklama(
                'Yönlendirilen (forward) iletiler SPF\'i bozar; DKIM imzası bozulmadıysa DMARC yine geçer. Posta listeleri imzayı bozabilir: önemli listeleri izin listesine ekleyin.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
