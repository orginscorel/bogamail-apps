import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/trafik_grafigi.dart';
import '../veri/bicim.dart';
import '../veri/denetim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import '../veri/operasyon.dart';
import 'bolumler.dart';
import '../ortak/simgeler.dart';

/// Gösterge paneli (web: admin/(panel)/page.tsx). Her değer canlı bir uç noktadan gelir: gösterge kartları (önceki
/// 24 saate göre değişimle), trafik grafiği, dikkat gerektirenler, kuyruk ve karantina özeti, sistem sağlığı, son
/// uyarılar, son işlemler ve hızlı işlemler. Platform genelindeki kartlar (sunucu, teslimat motoru) yalnızca süper
/// yöneticiye gösterilir. Geniş ekranda ızgara, telefonda alt alta.
class OzetEkrani extends StatefulWidget {
  const OzetEkrani({super.key});
  @override
  State<OzetEkrani> createState() => _OzetEkraniState();
}

class _OzetEkraniState extends State<OzetEkrani> {
  Ozet? _ozet;
  String? _hata;
  List<TrafikDilimi>? _trafik;
  int _saat = 24;

  /// Son 48 saatin saatlik trafiği: bugünkü değerleri önceki 24 saatle karşılaştırmak için.
  List<TrafikDilimi>? _iki;
  List<EtkinAlarm>? _alarmlar;
  List<AlarmOlayi>? _alarmGecmisi;
  List<Map<String, dynamic>>? _saglik;
  DateTime? _saglikZamani;
  Map<String, dynamic>? _sistem;
  Map<String, dynamic>? _motor;
  Map<String, dynamic>? _karantina;
  List<DenetimKaydi>? _islemler;
  bool _yukleniyor = false;

  bool get _platform => Uyg.platformYoneticisi && Uyg.taklit == null;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<Object?> _dene(Future<dynamic> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    final api = Uyg.api;
    final sonuc = await Future.wait<Object?>([
      api.get('/api/v1/stats/overview').then<Object?>((v) => v).catchError((Object e) => e),
      _dene(() => api.get('/api/v1/stats/traffic', q: {'hours': '$_saat'})),
      _dene(() => api.get('/api/v1/alerts/active')),
      _dene(() => api.get('/api/v1/health')),
      _platform ? _dene(() => api.get('/api/v1/system')) : Future.value(null),
      _platform ? _dene(() => api.get('/api/v1/outbound/engine')) : Future.value(null),
      Uyg.yetki('audit.view') ? _dene(() => api.get('/api/v1/audit-logs', q: {'page_size': '6'})) : Future.value(null),
      _dene(() => api.get('/api/v1/stats/traffic', q: {'hours': '48'})),
      Bolum.karantina.gorunur ? _dene(() => api.get('/api/v1/quarantine', q: {'status': 'held'})) : Future.value(null),
      _dene(() => api.get('/api/v1/alerts/history', q: {'limit': '5'})),
    ]);
    if (!mounted) return;
    setState(() {
      _yukleniyor = false;
      final o = sonuc[0];
      if (o is Map) {
        _ozet = Ozet(harita(o));
        _hata = null;
      } else {
        _hata = hataMetni(o ?? 'yok');
      }
      if (sonuc[1] != null) _trafik = TrafikDilimi.coz(sonuc[1]);
      if (sonuc[2] != null) _alarmlar = haritalar(harita(sonuc[2])['items']).map(EtkinAlarm.coz).toList();
      if (sonuc[3] != null) {
        _saglik = haritalar(harita(sonuc[3])['components']);
        _saglikZamani = tarihOku(harita(sonuc[3])['checked_at']);
      }
      final s = haritalar(harita(sonuc[4])['nodes']);
      _sistem = s.isEmpty ? null : s.first;
      _motor = sonuc[5] == null ? null : harita(sonuc[5]);
      if (sonuc[6] != null) _islemler = Sayfa.coz(sonuc[6], DenetimKaydi.coz).ogeler;
      if (sonuc[7] != null) _iki = TrafikDilimi.coz(sonuc[7]);
      _karantina = sonuc[8] == null ? null : harita(sonuc[8]);
      if (sonuc[9] != null) _alarmGecmisi = haritalar(harita(sonuc[9])['items']).map(AlarmOlayi.coz).toList();
      // Kabuk rozetlerini de tazele.
      final rozet = Map<Bolum, int>.from(bolumRozetleri.value);
      if (_alarmlar != null) rozet[Bolum.alarmlar] = _alarmlar!.length;
      if (_ozet?.kuyruk != null) rozet[Bolum.kuyruk] = _ozet!.kuyruk!;
      if (_karantina != null) rozet[Bolum.karantina] = tamsayi(harita(_karantina!['summary'])['held']);
      bolumRozetleri.value = rozet;
    });
  }

  Future<void> _trafikDegis(int saat) async {
    setState(() {
      _saat = saat;
      _trafik = null;
    });
    final v = await _dene(() => Uyg.api.get('/api/v1/stats/traffic', q: {'hours': '$saat'}));
    if (mounted && saat == _saat) setState(() => _trafik = v == null ? [] : TrafikDilimi.coz(v));
  }

  /// Son 24 saat ile önceki 24 saatin yüzde farkı ([f] ile seçilen sayaç).
  double? _degisim(int Function(TrafikDilimi) f) => ozetDegisimi(_iki, f);

  String _selam() {
    final h = DateTime.now().hour;
    final p = h < 6 ? 'İyi geceler' : (h < 12 ? 'Günaydın' : (h < 18 ? 'İyi günler' : 'İyi akşamlar'));
    final ad = Uyg.ad.trim().split(RegExp(r'\s+')).first;
    return ad.isEmpty ? p : '$p, $ad';
  }

  @override
  Widget build(BuildContext context) {
    return Iskelet(
      baslik: 'Özet',
      alt: '${Uyg.panelAdi} · ${DateFormat('d MMMM EEEE', 'tr_TR').format(DateTime.now())}',
      eylemler: [
        IconButton(
          tooltip: 'Yenile',
          onPressed: _yukleniyor ? null : _yukle,
          icon: _yukleniyor ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)) : const Icon(Simgeler.refresh),
        ),
      ],
      govde: _ozet == null && _hata == null
          ? const Durum.yukleniyor()
          : _ozet == null
          ? Durum.hata(_hata!, tekrar: _yukle)
          : RefreshIndicator.adaptive(
              onRefresh: _yukle,
              child: IcerikListesi(enFazla: 1500, children: _icerik(context, _ozet!)),
            ),
    );
  }

  List<Widget> _icerik(BuildContext context, Ozet o) {
    final genis = MediaQuery.sizeOf(context).width >= 1200;
    Widget ikili(Widget a, Widget? b, {int sol = 2}) => b == null
        ? a
        : genis
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: sol, child: a),
              const SizedBox(width: 16),
              Expanded(child: b),
            ],
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 16), b]);
    return [
      _karsilama(context),
      const SizedBox(height: 16),
      if (_hata != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Bant('Özet yenilenemedi: $_hata', renk: Marka.gul, ikon: Simgeler.cloudOff),
        ),
      _kpiIzgarasi(o),
      const SizedBox(height: 16),
      ikili(_trafikKarti(o), _dikkatKarti(o)),
      const SizedBox(height: 16),
      ikili(_kuyrukKarantinaKarti(o), _saglik == null ? null : _saglikKarti(), sol: 1),
      if (_platform && (_sistem != null || _motor != null)) ...[
        const SizedBox(height: 16),
        Izgara(enAz: 380, children: [if (_sistem != null) _sunucuKarti(_sistem!), if (_motor != null) _motorKarti(_motor!)]),
      ],
      const SizedBox(height: 16),
      Izgara(enAz: 380, children: [if (_alarmGecmisi != null) _sonUyarilarKarti(), if (_islemler != null) _islemlerKarti()]),
    ];
  }

  Widget _karsilama(BuildContext context) {
    final hizli = <(IconData, String, VoidCallback)>[
      if (Bolum.kutular.gorunur && Uyg.yetki('mailboxes.manage')) (Simgeler.personAddAlt, 'Posta kutuları', () => bolumeGit(Bolum.kutular)),
      if (Bolum.alanlar.gorunur) (Simgeler.addLink, 'Alan adları', () => bolumeGit(Bolum.alanlar)),
      if (Bolum.musteriler.gorunur) (Simgeler.apartment, 'Müşteriler', () => bolumeGit(Bolum.musteriler)),
      if (Bolum.takip.gorunur) (Simgeler.manageSearch, 'Mesaj takibi', () => bolumeGit(Bolum.takip)),
      if (Bolum.kuyruk.gorunur) (Simgeler.formatListNumbered, 'Kuyruk', () => bolumeGit(Bolum.kuyruk)),
      if (Bolum.denetim.gorunur) (Simgeler.receiptLong, 'Denetim', () => bolumeGit(Bolum.denetim)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_selam(), style: gosterim(22, agirlik: FontWeight.w600, renk: Colors.white)),
                    const SizedBox(height: 2),
                    Text('${Uyg.panelAdi} · canlı veri', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
              if ((_alarmlar ?? const []).isEmpty)
                const Rozet('Her şey yolunda', renk: Marka.yesil, ikon: Simgeler.checkCircle)
              else
                Rozet('${_alarmlar!.length} etkin uyarı', renk: Marka.kehribar, ikon: Simgeler.warningAmber),
            ],
          ),
          if (hizli.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, e, f) in hizli)
                  // Koyu bant üzerinde yarı saydam hap düğme (tema çip renklerinden bağımsız; yazı her zaman okunur).
                  Material(
                    color: Colors.white.withValues(alpha: .10),
                    shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: .24))),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: f,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(i, size: 17, color: Marka.yesil),
                          const SizedBox(width: 8),
                          Text(e, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kpiIzgarasi(Ozet o) {
    final alarmSay = _alarmlar?.length;
    final oran = o.teslimOrani;
    final karantina = _karantina == null ? null : tamsayi(harita(_karantina!['summary'])['held']);
    return Izgara(
      enAz: 210,
      children: [
        if (Uyg.ortak)
          KpiKarti(
            ikon: Simgeler.apartment,
            etiket: 'Müşteriler',
            deger: sayiYaz(o.musteriler),
            alt: 'kayıtlı müşteri',
            renk: Marka.mavi,
            onTap: Bolum.musteriler.gorunur ? () => bolumeGit(Bolum.musteriler) : null,
          ),
        KpiKarti(
          ikon: Simgeler.language,
          etiket: 'Alan adları',
          deger: sayiYaz(o.alanlar),
          alt: '${o.bekleyenAlanlar} doğrulama bekliyor · ${o.gatewayAlanlari} gateway',
          renk: Marka.gok,
          onTap: () => bolumeGit(Bolum.alanlar),
        ),
        if (Bolum.kutular.gorunur)
          KpiKarti(
            ikon: Simgeler.inbox,
            etiket: 'Posta kutuları',
            deger: sayiYaz(o.aktifKutular),
            alt: 'aktif · toplam ${sayiYaz(o.kutular)}',
            renk: Marka.zumrut,
            onTap: () => bolumeGit(Bolum.kutular),
          ),
        KpiKarti(
          ikon: Simgeler.storage,
          etiket: 'Depolama',
          deger: boyutYaz(o.kullanilan),
          ek: KullanimCubugu(kullanilan: o.kullanilan, toplam: o.ayrilan, yazi: false, kalinlik: 5),
          alt: '${boyutYaz(o.ayrilan)} tahsis edildi',
          renk: Marka.lavanta,
          onTap: Bolum.depolama.gorunur ? () => bolumeGit(Bolum.depolama) : null,
        ),
        KpiKarti(
          ikon: Simgeler.moveToInbox,
          etiket: 'Alınan (24 saat)',
          deger: sayiYaz(o.alinan),
          degisim: _degisim((d) => d.kabul),
          alt: '${sayiYaz(o.reddedilen)} reddedildi · ${sayiYaz(o.spam)} spam',
          renk: Marka.mavi,
          onTap: Bolum.takip.gorunur ? () => bolumeGit(Bolum.takip) : null,
        ),
        KpiKarti(
          ikon: Simgeler.markEmailRead,
          etiket: 'Teslim başarısı',
          deger: oran == null ? '—' : yuzdeYaz(oran),
          degisim: _degisim((d) => d.teslim),
          alt: oran == null ? (o.yok['delivery_success_rate'] ?? 'veri yok') : '${sayiYaz(o.teslim)} teslim · ${sayiYaz(o.basarisiz)} başarısız',
          renk: oran == null || oran >= 90 ? Marka.zumrut : Marka.kehribar,
          onTap: Bolum.teslimatSorunlari.gorunur ? () => bolumeGit(Bolum.teslimatSorunlari) : null,
        ),
        KpiKarti(
          ikon: Simgeler.formatListNumbered,
          etiket: 'Kuyruk',
          deger: o.kuyruk == null ? '—' : sayiYaz(o.kuyruk),
          alt: o.kuyruk == null ? (o.yok['queue_depth'] ?? 'veri yok') : 'teslim bekleyen ileti',
          renk: (o.kuyruk ?? 0) > 100 ? Marka.kehribar : Marka.grafitAcik,
          onTap: Bolum.kuyruk.gorunur ? () => bolumeGit(Bolum.kuyruk) : null,
        ),
        if (karantina != null)
          KpiKarti(
            ikon: Simgeler.shield,
            etiket: 'Karantina',
            deger: sayiYaz(karantina),
            alt: 'bekleyen ileti',
            renk: karantina > 0 ? Marka.kehribar : Marka.zumrut,
            onTap: () => bolumeGit(Bolum.karantina),
          ),
        KpiKarti(
          ikon: Simgeler.notificationsActive,
          etiket: 'Etkin uyarılar',
          deger: alarmSay == null ? '—' : sayiYaz(alarmSay),
          alt: 'eşiği aşan kural',
          renk: (alarmSay ?? 0) > 0 ? Marka.gul : Marka.zumrut,
          onTap: () => bolumeGit(Bolum.alarmlar),
        ),
      ],
    );
  }

  Widget _trafikKarti(Ozet o) {
    final r = context.r;
    Widget stat(String e, String d, {String? ipucu, Color? renk}) => Tooltip(
      message: ipucu ?? '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(e, style: TextStyle(color: r.silik, fontSize: 11.5)),
          Text(d, style: gosterim(18, agirlik: FontWeight.w600, renk: renk)),
        ],
      ),
    );
    return BolumKarti(
      baslik: 'Posta trafiği',
      ikon: Simgeler.showChart,
      sag: SegmentedButton<int>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(value: 24, label: Text('24 saat')),
          ButtonSegment(value: 168, label: Text('7 gün')),
        ],
        selected: {_saat},
        onSelectionChanged: (s) => _trafikDegis(s.first),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              stat('Teslim edilen', sayiYaz(o.teslim)),
              stat('Gönderilen', sayiYaz(o.gonderilen), ipucu: 'Kimlik doğrulamalı gönderim (alıcı sayısı)'),
              stat('Reddedilen', sayiYaz(o.reddedilen)),
              stat('Spam', sayiYaz(o.spam), ipucu: 'Gereksiz klasörüne düşen + reddedilen'),
              if ((o.gateway ?? 0) > 0 || o.gatewayAlanlari > 0) stat('Gateway', sayiYaz(o.gateway), ipucu: 'Müşteri sunucusuna iletilen'),
            ],
          ),
          const SizedBox(height: 16),
          _trafik == null ? const SizedBox(height: 190, child: Center(child: CircularProgressIndicator.adaptive())) : TrafikGrafigi(dilimler: _trafik!),
        ],
      ),
    );
  }

  Widget _dikkatKarti(Ozet o) {
    final maddeler = <(Color, String, String?, Bolum)>[];
    for (final a in _alarmlar ?? const <EtkinAlarm>[]) {
      maddeler.add((
        a.kritik ? Marka.gul : Marka.kehribar,
        a.etiket.isEmpty ? a.ad : '${a.ad} · ${a.etiket}',
        [a.ayrinti, suredir(a.baslangic)].where((s) => s.isNotEmpty).join(' · '),
        Bolum.alarmlar,
      ));
    }
    final e = harita(_motor?['engine']);
    if (mantik(e['bulk_paused'])) maddeler.add((Marka.gul, 'Toplu gönderim durduruldu', metinYa(e['pause_reason']), Bolum.teslimatKontrol));
    for (final b in haritalar(_motor?['brakes']).where((b) => mantik(b['active'], true))) {
      final kim = metinYa(b['mailbox']) ?? metinYa(b['organization_name']) ?? 'platform';
      maddeler.add((Marka.kehribar, 'Gönderim freni: $kim', metinYa(b['reason']), Bolum.teslimatKontrol));
    }
    final bekletilen = tamsayi(harita(e['queued'])['held']);
    if (bekletilen > 0) maddeler.add((Marka.kehribar, '$bekletilen ileti bekletiliyor', 'Kuyrukta onay ya da fren bekleyen iletiler', Bolum.kuyruk));
    final karantina = _karantina == null ? 0 : tamsayi(harita(_karantina!['summary'])['held']);
    if (karantina > 0) maddeler.add((Marka.kehribar, '$karantina ileti karantinada', 'Serbest bırakma ya da silme kararı bekliyor', Bolum.karantina));
    if (o.bekleyenAlanlar > 0) maddeler.add((Marka.mavi, '${o.bekleyenAlanlar} alan adı DNS doğrulaması bekliyor', null, Bolum.alanlar));
    maddeler.sort((a, b) => _sira(a.$1).compareTo(_sira(b.$1)));
    final r = context.r;
    return BolumKarti(
      baslik: 'Dikkat gerektirenler',
      ikon: maddeler.isEmpty ? Simgeler.checkCircle : Simgeler.warningAmber,
      sag: maddeler.isEmpty ? null : Rozet('${maddeler.length}', renk: Marka.kehribar),
      child: maddeler.isEmpty
          ? const Bant('Her şey yolunda; bekleyen bir iş yok.', renk: Marka.zumrut, ikon: Simgeler.checkCircleOutline)
          : Column(
              children: [
                for (final (renk, baslik, ayrinti, bolum) in maddeler.take(8))
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: bolum.gorunur ? () => bolumeGit(bolum) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(9)),
                            child: Icon(Simgeler.priorityHigh, size: 17, color: renk),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(baslik, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                if (ayrinti != null && ayrinti.isNotEmpty)
                                  Text(ayrinti, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(Simgeler.chevronRight, color: r.silik, size: 18),
                        ],
                      ),
                    ),
                  ),
                if (maddeler.length > 8) Text('+${maddeler.length - 8} madde daha', style: TextStyle(color: r.silik, fontSize: 12)),
              ],
            ),
    );
  }

  Widget _kuyrukKarantinaKarti(Ozet o) {
    final r = context.r;
    final e = harita(harita(_motor?['engine'])['queued']);
    final ks = harita(_karantina?['summary']);
    Widget kutu(String etiket, String deger, IconData ikon, Color renk, Bolum? b) => Expanded(
      child: Material(
        color: r.ic,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: b != null && b.gorunur ? () => bolumeGit(b) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(ikon, size: 18, color: renk),
                const SizedBox(height: 8),
                Text(deger, style: gosterim(20, agirlik: FontWeight.w600)),
                Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11.5)),
              ],
            ),
          ),
        ),
      ),
    );
    return BolumKarti(
      baslik: 'Kuyruk ve karantina',
      ikon: Simgeler.inventory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              kutu('Kuyrukta', o.kuyruk == null ? '—' : sayiYaz(o.kuyruk), Simgeler.formatListNumbered, Marka.mavi, Bolum.kuyruk),
              const SizedBox(width: 8),
              kutu('Başarısız (bugün)', sayiYaz(o.basarisiz), Simgeler.errorOutline, (o.basarisiz ?? 0) > 0 ? Marka.gul : Marka.zumrut, Bolum.teslimatSorunlari),
              if (_motor != null) ...[
                const SizedBox(width: 8),
                kutu('Bekletilen', sayiYaz(tamsayi(e['held'])), Simgeler.pauseCircleOutline, Marka.kehribar, Bolum.kuyruk),
              ],
            ],
          ),
          if (_karantina != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                kutu('Karantinada', sayiYaz(tamsayi(ks['held'])), Simgeler.shield, Marka.kehribar, Bolum.karantina),
                const SizedBox(width: 8),
                kutu('Virüs (7 gün)', sayiYaz(tamsayi(ks['virus_7d'])), Simgeler.coronavirus, Marka.gul, Bolum.karantina),
                const SizedBox(width: 8),
                kutu('Engellenen ek (7 gün)', sayiYaz(tamsayi(ks['blocked_7d'])), Simgeler.attachFile, Marka.gul, Bolum.karantina),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sonUyarilarKarti() {
    final r = context.r;
    final l = _alarmGecmisi!;
    return BolumKarti(
      baslik: 'Son uyarılar',
      ikon: Simgeler.notifications,
      sag: TextButton(onPressed: () => bolumeGit(Bolum.alarmlar), child: const Text('Tümü')),
      child: l.isEmpty
          ? Text('Henüz uyarı yok.', style: TextStyle(color: r.silik))
          : Column(
              children: [
                for (final a in l)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        DurumNoktasi(a.durum == 'resolved' ? Marka.zumrut : (a.onem == 'critical' ? Marka.gul : Marka.kehribar)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(a.etiket.isEmpty ? a.kuralAdi : '${a.kuralAdi} · ${a.etiket}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                              Text(
                                [alarmDurumlari[a.durum] ?? a.durum, if (a.orgAdi.isNotEmpty) a.orgAdi].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: r.silik, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(goreliZaman(a.zaman), style: TextStyle(color: r.silik, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  int _sira(Color c) => c == Marka.gul ? 0 : (c == Marka.kehribar ? 1 : 2);

  Widget _sunucuKarti(Map<String, dynamic> n) {
    final r = context.r;
    final yuk = (n['load_avg'] is List ? n['load_avg'] as List : const []).map((v) => ondalik(v).toStringAsFixed(2).replaceAll('.', ',')).join(' · ');
    final bellekTop = tamsayi(n['mem_total']), bellekBos = tamsayi(n['mem_available']);
    final diskler = harita(n['disks']);
    final gorulen = <String>{};
    final diskSatirlari = <Widget>[];
    for (final e in diskler.entries) {
      final d = harita(e.value);
      final top = tamsayi(d['total_bytes']);
      if (top == 0 || !gorulen.add('$top/${d['free_bytes']}')) continue;
      diskSatirlari.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                diskler.length > 1 && gorulen.length > 1 ? metin(d['path']) : 'Disk (posta deposu ve kuyruk)',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
              const SizedBox(height: 4),
              KullanimCubugu(kullanilan: tamsayi(d['used_bytes']), toplam: top),
            ],
          ),
        ),
      );
    }
    return BolumKarti(
      baslik: 'Sunucu',
      ikon: Simgeler.dns,
      altBaslik: '${metin(n['hostname'])} · sürüm ${metin(n['version'], '—')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BilgiSatiri('Çalışma süresi', sureYaz(ondalikYa(n['host_uptime']))),
          BilgiSatiri('Yük ortalaması', yuk.isEmpty ? '—' : '$yuk  (${tamsayi(n['cpus'])} çekirdek)'),
          if (bellekTop > 0) ...[
            Text('Bellek', style: TextStyle(color: r.soluk, fontSize: 12.5)),
            const SizedBox(height: 4),
            KullanimCubugu(kullanilan: bellekTop - bellekBos, toplam: bellekTop),
          ],
          ...diskSatirlari,
        ],
      ),
    );
  }

  Widget _motorKarti(Map<String, dynamic> m) {
    final r = context.r;
    final e = harita(m['engine']);
    if (!mantik(m['available']) || m['engine'] is! Map) {
      return BolumKarti(
        baslik: 'Teslimat motoru',
        ikon: Simgeler.send,
        child: Text('Giden posta motoru bu sunucuda çalışmıyor.', style: TextStyle(color: r.silik)),
      );
    }
    final q = harita(e['queued']);
    Widget mini(String a, String d, {Color? renk}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(a, style: TextStyle(color: r.silik, fontSize: 11)),
          Text(
            d,
            style: TextStyle(fontWeight: FontWeight.w600, color: renk),
          ),
        ],
      ),
    );
    final ertele = tamsayi(e['deferred_10m']), hata = tamsayi(e['failed_10m']), bekle = tamsayi(q['held']);
    final mod = metin(e['mode']);
    return BolumKarti(
      baslik: 'Teslimat motoru',
      ikon: Simgeler.send,
      altBaslik: 'Mod: ${mod == 'direct' ? 'doğrudan teslim' : mod}${mantik(e['bulk_paused']) ? ' · toplu gönderim durdu' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(sayiYaz(tamsayi(e['delivered_10m'])), style: gosterim(26, agirlik: FontWeight.w600)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('teslim · son 10 dk', style: TextStyle(color: r.silik, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              mini('Erteleme', sayiYaz(ertele), renk: ertele > 0 ? Marka.kehribar : null),
              mini('Hata', sayiYaz(hata), renk: hata > 0 ? Marka.gul : null),
              mini('Bağlantı', '${tamsayi(e['running_connections'])}/${tamsayi(e['max_connections'])}'),
              mini('Kuyruk', sayiYaz(tamsayi(q['normal']))),
              mini('Toplu', sayiYaz(tamsayi(q['bulk']))),
              mini('Bekletilen', sayiYaz(bekle), renk: bekle > 0 ? Marka.kehribar : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _saglikKarti() {
    final r = context.r;
    return BolumKarti(
      baslik: 'Sistem sağlığı',
      ikon: Simgeler.monitorHeart,
      altBaslik: _saglikZamani == null ? null : 'Son kontrol ${goreliZaman(_saglikZamani)}',
      child: Column(
        children: [
          for (final c in _saglik!)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: switch (metin(c['status'])) {
                        'ok' => Marka.zumrut,
                        'down' => Marka.gul,
                        _ => r.silik.withValues(alpha: .5),
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(saglikEtiketleri[metin(c['name'])] ?? metin(c['name']), style: const TextStyle(fontSize: 13.5))),
                  Flexible(
                    child: Text(
                      switch (metin(c['status'])) {
                        'ok' =>
                          c['latency_ms'] != null
                              ? '${ondalik(c['latency_ms']).toStringAsFixed(1).replaceAll('.', ',')} ms'
                              : (metinYa(c['detail']) ?? 'çalışıyor'),
                        'down' => 'erişilemiyor',
                        _ => metinYa(c['detail'])?.replaceAll('Phase', 'Faz') ?? 'kapalı',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: r.silik, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _islemlerKarti() {
    final r = context.r;
    return BolumKarti(
      baslik: 'Son işlemler',
      ikon: Simgeler.receiptLong,
      sag: TextButton(onPressed: () => bolumeGit(Bolum.denetim), child: const Text('Tümü')),
      child: _islemler!.isEmpty
          ? Text('Henüz kayıt yok.', style: TextStyle(color: r.silik))
          : Column(
              children: [
                for (final a in _islemler!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [denetimEylemi(a.eylem).etiket, denetimHedefi(a.hedefTuru, a.hedefId, a.orgAdi, a.ayrintilar)].whereType<String>().join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: tonRengi(denetimEylemi(a.eylem).ton)),
                              ),
                              Text(
                                [a.aktor.isEmpty ? 'sistem' : a.aktor, ?a.orgAdi].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: r.silik, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(goreliZaman(a.zaman), style: TextStyle(color: r.silik, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

Color? tonRengi(String ton) => switch (ton) {
  'danger' => Marka.gul,
  'warning' => Marka.kehribar,
  _ => null,
};

/// Son 24 saatin toplamının önceki 24 saate göre yüzde değişimi (48 saatlik saatlik diziden).
double? ozetDegisimi(List<TrafikDilimi>? l, int Function(TrafikDilimi) f) {
  if (l == null || l.length < 2) return null;
  final yari = l.length ~/ 2;
  final once = l.take(yari).fold(0, (a, d) => a + f(d));
  final simdi = l.skip(yari).fold(0, (a, d) => a + f(d));
  return degisimYuzdesi(simdi, once);
}
