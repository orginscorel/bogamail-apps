import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'liste_alarm_kurallari.dart';

/// Uyarılar: şu anda eşiği aşan kurallar (GET /alerts/active), uyarı kuralları, bildirim kanalları ve bildirim geçmişi
/// (GET /alerts/history). Push bildiriminden gelinince [Uyg.vurguluAlarm] olayı geçmişte vurgulanır.
class AlarmlarEkrani extends StatefulWidget {
  const AlarmlarEkrani({super.key});
  @override
  State<AlarmlarEkrani> createState() => _AlarmlarEkraniState();
}

class _AlarmlarEkraniState extends State<AlarmlarEkrani> with SingleTickerProviderStateMixin {
  static const _gecmisSekmesi = 3;
  late final _sekme = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));
  final _kurallar = GlobalKey<AlarmKurallariState>();
  final _kanallarAnahtar = GlobalKey<AlarmKanallariState>();
  final _yenileme = ValueNotifier<int>(0);
  List<EtkinAlarm>? _etkin;
  List<AlarmOlayi>? _gecmis;
  AlarmTurleri? _turler;
  List<AlarmKanali> _kanallar = const [];
  String? _hata;
  String _durum = '';
  int? _vurgu;
  final _anahtarlar = <int, GlobalKey>{};
  bool _degerlendiriliyor = false;

  bool get _degerlendirebilir => alarmYonetebilir;

  @override
  void initState() {
    super.initState();
    Uyg.vurguluAlarm.addListener(_vurguGeldi);
    _turleriYukle();
    final ilk = Uyg.vurguluAlarm.value;
    if (ilk != null) {
      Uyg.vurguluAlarm.value = null;
      _vurgu = ilk;
      _sekme.index = _gecmisSekmesi;
      _yukle().then((_) => _vurguyaKaydir());
    } else {
      _yukle();
    }
  }

  @override
  void dispose() {
    Uyg.vurguluAlarm.removeListener(_vurguGeldi);
    _sekme.dispose();
    _yenileme.dispose();
    super.dispose();
  }

  Future<void> _turleriYukle() async {
    try {
      final t = AlarmTurleri.coz(await Uyg.api.get('/api/v1/alerts/kinds'));
      if (mounted) setState(() => _turler = t);
    } catch (_) {}
  }

  void _vurguGeldi() {
    final id = Uyg.vurguluAlarm.value;
    if (id == null) return;
    Uyg.vurguluAlarm.value = null;
    setState(() {
      _vurgu = id;
      _durum = '';
    });
    _sekme.animateTo(_gecmisSekmesi);
    _yukle().then((_) => _vurguyaKaydir());
  }

  void _vurguyaKaydir() {
    final id = _vurgu;
    if (id == null || !mounted) return;
    final bulundu = _gecmis?.any((o) => o.id == id) ?? false;
    if (!bulundu) {
      bildir('Bildirimdeki alarm kaydı bulunamadı', mesaj: 'Kayıt geçmişten silinmiş ya da erişiminiz dışında olabilir.', tur: MesajTur.uyari);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _anahtarlar[id]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 400), alignment: .2);
    });
  }

  Future<void> _yukle() async {
    try {
      final s = await Future.wait([
        Uyg.api.get('/api/v1/alerts/active'),
        Uyg.api.get('/api/v1/alerts/history', q: {'limit': '500', if (_durum.isNotEmpty) 'status': _durum}),
      ]);
      if (!mounted) return;
      setState(() {
        _etkin = haritalar(harita(s[0])['items']).map(EtkinAlarm.coz).toList();
        _gecmis = haritalar(harita(s[1])['items']).map(AlarmOlayi.coz).toList();
        _hata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  void _hepsiniYenile() {
    _yukle();
    _yenileme.value++;
  }

  Future<void> _degerlendir() async {
    setState(() => _degerlendiriliyor = true);
    final v = await islem(() => Uyg.api.post('/api/v1/alerts/evaluate'));
    if (mounted) setState(() => _degerlendiriliyor = false);
    if (v == null) return;
    final n = tamsayi(harita(v)['notifications']);
    bildir('Kurallar değerlendirildi', mesaj: n == 0 ? 'Yeni bildirim yok.' : '$n bildirim gönderildi.', tur: MesajTur.basari);
    _hepsiniYenile();
  }

  BirincilEylem? get _birincil {
    if (!alarmYonetebilir) return null;
    return switch (_sekme.index) {
      1 => _turler == null ? null : BirincilEylem(Icons.add_rounded, 'Yeni kural', () => _kurallar.currentState?.yeni()),
      2 => BirincilEylem(Icons.add_rounded, 'Yeni kanal', () => _kanallarAnahtar.currentState?.yeni()),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final etkinSay = _etkin?.length ?? 0;
    return Iskelet(
      baslik: 'Uyarılar',
      alt: 'Eşik tabanlı kurallar ve bildirim kanalları · her dakika değerlendirilir',
      yenile: _hepsiniYenile,
      birincil: _birincil,
      eylemler: [
        if (_degerlendirebilir)
          IconButton(
            tooltip: 'Kuralları şimdi değerlendir',
            onPressed: _degerlendiriliyor ? null : _degerlendir,
            icon: _degerlendiriliyor
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                : const Icon(Icons.notifications_active_outlined),
          ),
      ],
      sekmeler: TabBar(
        controller: _sekme,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Etkin'),
                if (etkinSay > 0) ...[const SizedBox(width: 6), Badge(label: Text('$etkinSay'))],
              ],
            ),
          ),
          const Tab(text: 'Kurallar'),
          const Tab(text: 'Kanallar'),
          const Tab(text: 'Geçmiş'),
        ],
      ),
      govde: TabBarView(
        controller: _sekme,
        children: [
          _yukleniyorVeya(_etkinListe),
          AlarmKurallari(key: _kurallar, turler: _turler, kanallar: _kanallar, yenileme: _yenileme),
          AlarmKanallari(
            key: _kanallarAnahtar,
            turler: _turler,
            yenileme: _yenileme,
            degisti: (l) {
              if (mounted) setState(() => _kanallar = l);
            },
          ),
          _yukleniyorVeya(_gecmisListe),
        ],
      ),
    );
  }

  Widget _yukleniyorVeya(Widget Function() f) {
    if (_hata != null && _etkin == null) return Durum.hata(_hata!, tekrar: _yukle);
    if (_etkin == null) return const Durum.yukleniyor();
    return f();
  }

  Widget _etkinListe() {
    final r = context.r;
    final l = _etkin!;
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: l.isEmpty
          ? ListView(
              children: const [SizedBox(height: 360, child: Durum.bos('Şu anda eşiği aşan kural yok.', ikon: Icons.notifications_off_outlined))],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: l.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (c, i) {
                final a = l[i];
                final renk = a.kritik ? Marka.gul : Marka.kehribar;
                return Kutu(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(a.kritik ? Icons.error_rounded : Icons.warning_amber_rounded, color: renk),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(a.ad, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          Rozet(onemEtiketleri[a.onem] ?? a.onem, renk: renk),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (a.etiket.isNotEmpty || a.konu.isNotEmpty) Text(a.etiket.isNotEmpty ? a.etiket : a.konu, style: TextStyle(color: r.soluk)),
                      if (a.ayrinti.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(a.ayrinti, style: TextStyle(color: r.silik, fontSize: 12.5)),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Değer: ${_sayi(a.deger)}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: renk),
                          ),
                          Text('Eşik: ${_sayi(a.esik)}', style: TextStyle(color: r.silik)),
                          if (a.baslangic != null)
                            Tooltip(
                              message: tamZaman(a.baslangic),
                              child: Text(suredir(a.baslangic), style: TextStyle(color: r.silik)),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _gecmisListe() {
    final r = context.r;
    final l = _gecmis ?? const <AlarmOlayi>[];
    return Column(
      children: [
        FiltreCubugu(
          filtreler: [
            FiltreDugmesi<String>(
              etiket: 'Durum',
              ikon: Icons.flag_outlined,
              secenekler: [('', 'Tümü'), for (final e in alarmDurumlari.entries) (e.key, e.value)],
              secili: _durum,
              secildi: (v) {
                setState(() => _durum = v);
                _yukle();
              },
            ),
          ],
          sag: Text('${l.length} kayıt', style: TextStyle(color: r.silik, fontSize: 12.5)),
          etkinler: [
            if (_durum.isNotEmpty)
              EtkinFiltre('Durum: ${alarmDurumlari[_durum] ?? _durum}', () {
                setState(() => _durum = '');
                _yukle();
              }),
          ],
        ),
        Expanded(
          child: RefreshIndicator.adaptive(
            onRefresh: _yukle,
            child: l.isEmpty
                ? ListView(
                    children: const [SizedBox(height: 320, child: Durum.bos('Henüz alarm bildirimi yok.', ikon: Icons.history_rounded))],
                  )
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                    child: Column(
                      children: [
                        for (final o in l)
                          Padding(
                            key: _anahtarlar.putIfAbsent(o.id, GlobalKey.new),
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _OlaySatiri(o, vurgulu: o.id == _vurgu, r: r),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

String _sayi(double v) => v == v.roundToDouble() ? sayiYaz(v.round()) : v.toStringAsFixed(2).replaceAll('.', ',');

class _OlaySatiri extends StatelessWidget {
  const _OlaySatiri(this.o, {required this.vurgulu, required this.r});
  final AlarmOlayi o;
  final bool vurgulu;
  final Renkler r;

  @override
  Widget build(BuildContext context) {
    final renk = switch (o.durum) {
      'resolved' => Marka.zumrut,
      'test' => Marka.mavi,
      _ => o.onem == 'critical' ? Marka.gul : Marka.kehribar,
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: vurgulu ? r.birincilYumusak : r.kart,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vurgulu ? r.birincil : r.kenar, width: vurgulu ? 1.6 : 1),
      ),
      child: ExpansionTile(
        initiallyExpanded: vurgulu,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          o.durum == 'resolved' ? Icons.check_circle_rounded : (o.durum == 'test' ? Icons.science_rounded : Icons.notifications_active_rounded),
          color: renk,
        ),
        title: Text(o.kuralAdi, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          [
            alarmDurumlari[o.durum] ?? o.durum,
            if (o.etiket.isNotEmpty) o.etiket,
            if (!Uyg.musteri && o.orgAdi.isNotEmpty) o.orgAdi,
            goreliZaman(o.zaman),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: r.silik, fontSize: 12.5),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BilgiSatiri('Zaman', tamZaman(o.zaman)),
          BilgiSatiri('Önem', onemEtiketleri[o.onem] ?? o.onem),
          BilgiSatiri('Değer / eşik', '${_sayi(o.deger)} / ${_sayi(o.esik)}'),
          if (o.ayrinti.isNotEmpty) BilgiSatiri('Ayrıntı', o.ayrinti),
          if (o.teslimler.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Bildirim kanalları',
              style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            for (final (kanal, ok, hata) in o.teslimler)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(ok ? Icons.check_rounded : Icons.close_rounded, size: 16, color: ok ? Marka.zumrut : Marka.gul),
                    const SizedBox(width: 6),
                    Expanded(child: Text(ok ? kanal : '$kanal — $hata', style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
