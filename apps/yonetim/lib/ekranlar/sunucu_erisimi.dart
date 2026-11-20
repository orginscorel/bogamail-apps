import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'liste_ortak.dart';

/// Sunucu Erişimi (yalnızca süper yönetici, GET /host-security): SSH izin listesi, IP yasakları, koruma ayarları ve
/// SSH bağlantı denemeleri (ayrı sekmede sıralanabilir tablo). Değişiklikler güvenlik duvarına hemen uygulanır ve
/// denetim kayıtlarına yazılır. Web paneli gibi 30 saniyede bir tazelenir.
class SunucuErisimiEkrani extends StatefulWidget {
  const SunucuErisimiEkrani({super.key});
  @override
  State<SunucuErisimiEkrani> createState() => _SunucuErisimiEkraniState();
}

class _SunucuErisimiEkraniState extends State<SunucuErisimiEkrani> {
  SunucuErisimi? _d;
  String? _hata;
  String? _mesgul;
  Timer? _zamanlayici;

  // SSH denemeleri tablosu (yerel süzme / sıralama).
  String _q = '', _suzgec = '', _sira = 'son';
  bool _artan = false;
  late final _y = SayfaYukleyici.yerel<SshKaynagi>(() async {
    if (_d == null) await _getir();
    return _suzulmus();
  }, sayfaBoyu: 50);

  @override
  void initState() {
    super.initState();
    _y.yenile();
    _zamanlayici = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_mesgul == null) _yukle(sessiz: true);
    });
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _y.dispose();
    super.dispose();
  }

  Future<void> _getir() async {
    try {
      final v = await Uyg.api.get('/api/v1/host-security');
      if (mounted) {
        setState(() {
          _d = SunucuErisimi(harita(v));
          _hata = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
      if (_d == null) rethrow;
    }
  }

  Future<void> _yukle({bool sessiz = false}) async {
    try {
      await _getir();
    } catch (_) {
      return;
    }
    if (_y.sayfa <= 1 || !sessiz) {
      await _y.yenile();
    }
  }

  List<SshKaynagi> _suzulmus() {
    final d = _d;
    if (d == null) return const [];
    final q = _q.trim();
    final l = [
      for (final s in d.kaynaklar)
        if ((q.isEmpty || s.ip.contains(q) || s.kullanicilar.any((k) => k.contains(q))) &&
            switch (_suzgec) {
              'banned' => s.yasakli,
              'allowed' => s.izinli,
              'hostile' => s.dusmanca > 0 && !s.yasakli && !s.izinli,
              'accepted' => s.basarili > 0,
              _ => true,
            })
          s,
    ];
    int karsilastir(SshKaynagi a, SshKaynagi b) => switch (_sira) {
      'engellenen' => a.engellenen.compareTo(b.engellenen),
      'hatali' => a.toplamHatali.compareTo(b.toplamHatali),
      'basarili' => a.basarili.compareTo(b.basarili),
      'ip' => a.ip.compareTo(b.ip),
      _ => (a.sonGorulme ?? DateTime(0)).compareTo(b.sonGorulme ?? DateTime(0)),
    };
    l.sort((a, b) => _artan ? karsilastir(a, b) : karsilastir(b, a));
    return l;
  }

  void _tabloSuz(void Function() f) {
    setState(f);
    _y.yenile();
  }

  Future<void> _calistir(String anahtar, Future<Object?> Function() f, String tamam) async {
    setState(() => _mesgul = anahtar);
    final v = await islem(() async => await f() ?? true, tamam: tamam);
    if (mounted) setState(() => _mesgul = null);
    if (v != null) await _yukle();
  }

  Future<void> _izinVer(String ip) => _calistir('izin:$ip', () => Uyg.api.post('/api/v1/host-security/ssh-allow', {'ip': ip}), '$ip için SSH izni verildi');

  Future<void> _izinKaldir(String ip) async {
    final ben = ip == _d?.benimIp;
    final ok = await onayla(
      context,
      'SSH izni kaldırılsın mı?',
      mesaj: '$ip adresinden SSH bağlantıları güvenlik duvarında düşürülecek.${ben ? ' Bu sizin şu anki adresiniz; SSH ile bağlanamaz hale gelirsiniz.' : ''}',
      evet: 'Kaldır',
      tehlikeli: true,
    );
    if (!ok) return;
    await _calistir('izin:$ip', () => Uyg.api.delete('/api/v1/host-security/ssh-allow', q: {'ip': ip}).then((_) => true), 'SSH izni kaldırıldı');
  }

  Future<void> _izinEkle() async {
    final ip = await metinSor(context, 'SSH izni ver', ipucu: 'IP adresi (ör. 203.0.113.10)', tamam: 'İzin ver');
    if (ip == null || ip.trim().isEmpty) return;
    await _izinVer(ip.trim());
  }

  Future<void> _yasakKaldir(String ip) async {
    if (!await onayla(context, '$ip yasağı kaldırılsın mı?', mesaj: 'Bu adresten gelen bağlantılar yeniden kabul edilir.', evet: 'Yasağı kaldır')) return;
    await _calistir('yasak:$ip', () => Uyg.api.delete('/api/v1/host-security/bans', q: {'ip': ip}).then((_) => true), '$ip yasağı kaldırıldı');
  }

  Future<void> _yasakla([String? ip]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => YasakDialog(ip: ip, benimIp: _d?.benimIp),
    );
    if (ok == true) _yukle();
  }

  void _kayitlar(String ip) {
    if (context.genis) {
      ayrintiAc(context, 'SSH kayıtları', SshKayitlari(ip: ip, panelde: true), genislik: 680);
    } else {
      showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => SshKayitlari(ip: ip));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return DefaultTabController(
      length: 2,
      child: Iskelet(
        baslik: 'Sunucu Erişimi',
        alt: 'SSH izin listesi, IP yasakları ve bağlantı denemeleri',
        yenile: _yukle,
        birincil: d == null ? null : BirincilEylem(Icons.block_rounded, 'IP yasakla', _yasakla),
        sekmeler: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Genel bakış'),
            Tab(text: d == null ? 'SSH denemeleri' : 'SSH denemeleri (${d.kaynaklar.length})'),
          ],
        ),
        govde: d == null
            ? (_hata != null ? Durum.hata(_hata!, tekrar: _yukle) : const Durum.yukleniyor())
            : TabBarView(children: [_genel(d), _denemeler(d)]),
      ),
    );
  }

  Widget _genel(SunucuErisimi d) => RefreshIndicator.adaptive(
    onRefresh: _yukle,
    child: LayoutBuilder(
      builder: (c, k) {
        final iki = k.maxWidth >= 1000;
        final izin = _izinKarti(d), yasak = _yasakKarti(d), ayar = KorumaAyarlari(d: d, kaydedildi: _yukle);
        final t = d.toplamlar;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: k.maxWidth >= 700 ? 24 : 12, vertical: 12),
          children: [
            Text(
              'Sunucuya SSH ile kimlerin bağlanabileceği, yasaklı IP adresleri ve son bağlantı denemeleri. Değişiklikler güvenlik duvarına hemen uygulanır ve denetim kayıtlarına yazılır.',
              style: TextStyle(color: context.r.silik, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (d.duvarHatasi != null || d.kayitHatasi != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Bant(d.duvarHatasi ?? d.kayitHatasi!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              ),
            Izgara(
              enAz: 170,
              bosluk: 10,
              children: [
                OzetKutusu('SSH izinli adres', sayiYaz(d.sshIzinleri.length), ikon: Icons.key_rounded, renk: Marka.zumrut),
                OzetKutusu('Yasaklı adres', sayiYaz(d.yasaklar.length), ikon: Icons.block_rounded, renk: d.yasaklar.isEmpty ? null : Marka.gul),
                OzetKutusu('Başarılı giriş', sayiYaz(t['accepted'] ?? 0), alt: 'son ${d.gun} gün', ikon: Icons.login_rounded),
                OzetKutusu(
                  'Hatalı deneme',
                  sayiYaz((t['failed'] ?? 0) + (t['invalid_user'] ?? 0)),
                  alt: '${sayiYaz(t['invalid_user'] ?? 0)} olmayan kullanıcı',
                  ikon: Icons.password_rounded,
                  renk: (t['failed'] ?? 0) + (t['invalid_user'] ?? 0) > 0 ? Marka.kehribar : null,
                ),
                OzetKutusu(
                  'Duvarda engellenen',
                  d.dusurmeKaydi ? sayiYaz(t['dropped'] ?? 0) : '—',
                  alt: d.dusurmeKaydi ? 'son ${d.gun} gün' : 'kayıt kapalı',
                  ikon: Icons.shield_rounded,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _benimIpKarti(d),
            const SizedBox(height: 14),
            if (iki)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: izin),
                  const SizedBox(width: 14),
                  Expanded(child: yasak),
                ],
              )
            else ...[
              izin,
              const SizedBox(height: 14),
              yasak,
            ],
            const SizedBox(height: 14),
            if (iki)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _enCokDeneyenler(d)),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: ayar),
                ],
              )
            else ...[
              _enCokDeneyenler(d),
              const SizedBox(height: 14),
              ayar,
            ],
          ],
        );
      },
    ),
  );

  Widget _benimIpKarti(SunucuErisimi d) {
    final ok = d.benimIpIzinli;
    final renk = ok ? Marka.zumrut : Marka.kehribar;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: renk.withValues(alpha: .4)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.verified_user_rounded : Icons.warning_amber_rounded, color: renk, size: 26),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Şu an bağlı olduğunuz IP', style: TextStyle(color: context.r.soluk, fontSize: 12.5)),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: SelectableText(
                            d.benimIp.isEmpty ? '—' : d.benimIp,
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 18),
                          ),
                        ),
                        if (d.benimIp.isNotEmpty)
                          IconButton(
                            tooltip: 'Kopyala',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => kopyala(d.benimIp, mesaj: 'IP adresi kopyalandı'),
                            icon: const Icon(Icons.copy_rounded, size: 17),
                          ),
                      ],
                    ),
                    Text(
                      ok ? 'Bu adresten SSH ile bağlanabilirsiniz.' : 'Bu adresten SSH bağlantısı güvenlik duvarında engelleniyor.',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!ok && d.benimIp.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _mesgul != null ? null : () => _izinVer(d.benimIp),
              icon: _mesgul == 'izin:${d.benimIp}'
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.key_rounded),
              label: const Text("Bu IP'ye SSH izni ver", style: TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _izinKarti(SunucuErisimi d) {
    final r = context.r;
    return BolumKarti(
      baslik: 'SSH izin listesi',
      ikon: Icons.key_rounded,
      altBaslik: 'SSH (22) yalnızca bu adreslerden açıktır; diğer her yerden gelen bağlantı düşürülür.',
      sag: TextButton.icon(onPressed: _mesgul != null ? null : _izinEkle, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Ekle')),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: d.sshIzinleri.isEmpty
          ? Text('İzinli adres yok.', style: TextStyle(color: r.silik))
          : Column(
              children: [
                for (final (i, ip) in d.sshIzinleri.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, size: 16, color: Marka.zumrut),
                        const SizedBox(width: 10),
                        Expanded(child: SelectableText(ip, style: const TextStyle(fontFamily: 'monospace', fontSize: 14))),
                        if (ip == d.benimIp) const Rozet('siz', renk: Marka.mavi),
                        IconButton(
                          tooltip: d.sshIzinleri.length == 1 ? 'Son izinli adres kaldırılamaz' : 'SSH iznini kaldır',
                          onPressed: _mesgul != null || d.sshIzinleri.length == 1 ? null : () => _izinKaldir(ip),
                          icon: _mesgul == 'izin:$ip'
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.delete_outline_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _yasakKarti(SunucuErisimi d) {
    final r = context.r;
    return BolumKarti(
      baslik: 'Yasaklı IP adresleri',
      ikon: Icons.block_rounded,
      altBaslik: 'Yasaklı bir adresten gelen tüm bağlantılar (SSH, posta, web) güvenlik duvarında düşürülür.',
      sag: TextButton.icon(onPressed: () => _yasakla(), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Yasakla')),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: d.yasaklar.isEmpty
          ? Text('Yasaklı adres yok.', style: TextStyle(color: r.silik))
          : Column(
              children: [
                for (final (i, y) in d.yasaklar.indexed) ...[
                  if (i > 0) Divider(height: 1, color: r.kenar),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SelectableText(y.ip, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                                  if (y.otomatik) const Rozet('otomatik', renk: Marka.mor),
                                  Rozet(y.bitis == null ? 'süresiz' : 'bitiş ${kisaZaman(y.bitis)}', renk: r.silik),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (!y.panelden) 'Panel dışında eklenmiş kural' else if (y.neden.isNotEmpty) y.neden,
                                  if (y.yasaklayan.isNotEmpty && !y.otomatik) y.yasaklayan,
                                  if (y.olusturma != null) goreliZaman(y.olusturma),
                                ].join(' · '),
                                style: TextStyle(color: r.silik, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _mesgul != null ? null : () => _yasakKaldir(y.ip),
                          child: _mesgul == 'yasak:${y.ip}'
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Kaldır'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  /// En çok hatalı / engellenen deneme yapan ilk 8 adres (tamamı "SSH denemeleri" sekmesinde).
  Widget _enCokDeneyenler(SunucuErisimi d) {
    final r = context.r;
    final l = [...d.kaynaklar.where((s) => s.dusmanca > 0)]..sort((a, b) => b.dusmanca.compareTo(a.dusmanca));
    final enCok = l.isEmpty ? 1 : l.first.dusmanca;
    return BolumKarti(
      baslik: 'En çok deneme yapan adresler',
      ikon: Icons.terminal_rounded,
      altBaslik: 'Son ${d.gun} gün · hatalı ve engellenen denemeler.${d.dusurmeKaydi ? '' : ' Güvenlik duvarının engellediği denemeler kaydedilmiyor; koruma ayarlarından açabilirsiniz.'}',
      sag: Builder(builder: (c) => TextButton(onPressed: () => DefaultTabController.of(c).animateTo(1), child: const Text('Tümü'))),
      child: l.isEmpty
          ? Text('Kayıtlı hatalı SSH denemesi yok.', style: TextStyle(color: r.silik))
          : Column(
              children: [
                for (final s in l.take(8))
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _kayitlar(s.ip),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(s.ip, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (s.yasakli) const Rozet('yasaklı', renk: Marka.gul),
                                  ],
                                ),
                              ),
                              Text(sayiYaz(s.dusmanca), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: s.dusmanca / enCok,
                              minHeight: 5,
                              backgroundColor: r.ic,
                              color: s.yasakli ? r.silik : Marka.kehribar,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  List<SatirEylemi> _kaynakEylemleri(SunucuErisimi d, SshKaynagi s) => [
    SatirEylemi(Icons.description_outlined, 'Kayıtlar', () => _kayitlar(s.ip)),
    SatirEylemi(Icons.copy_rounded, 'IP adresini kopyala', () => kopyala(s.ip, mesaj: 'IP adresi kopyalandı')),
    if (s.yasakli) SatirEylemi(Icons.lock_open_rounded, 'Yasağı kaldır', () => _yasakKaldir(s.ip)),
    if (!s.yasakli && !s.izinli && s.ip != d.benimIp) SatirEylemi(Icons.block_rounded, 'Yasakla', () => _yasakla(s.ip), tehlikeli: true),
  ];

  Widget _denemeler(SunucuErisimi d) {
    final r = context.r;
    const suzgecler = {'hostile': 'Hatalı / engellenen', 'banned': 'Yasaklı', 'allowed': 'SSH izinli', 'accepted': 'Başarılı giriş yapan'};
    Widget rozetler(SshKaynagi s) => Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (s.yasakli) const Rozet('yasaklı', renk: Marka.gul),
        if (s.izinli) const Rozet('SSH izinli', renk: Marka.zumrut),
        if (s.ip == d.benimIp) const Rozet('siz', renk: Marka.mavi),
      ],
    );
    Widget sayi(int n, Color renk) => Text(sayiYaz(n), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: n > 0 ? renk : r.silik));
    return VeriTablosu<SshKaynagi>(
      yukleyici: _y,
      onTap: (s) => _kayitlar(s.ip),
      eylemler: (s) => _kaynakEylemleri(d, s),
      siralama: _sira,
      artan: _artan,
      siralamaDegisti: (a, b) => _tabloSuz(() {
        _sira = a;
        _artan = b;
      }),
      vurgulu: (s) => !s.yasakli && !s.izinli && s.dusmanca >= 20,
      bosIkon: Icons.terminal_rounded,
      bosMetin: _q.isEmpty && _suzgec.isEmpty ? 'Kayıtlı SSH denemesi yok.' : 'Eşleşen adres yok.',
      ust: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FiltreCubugu(
            arama: AramaAlani(ipucu: 'IP adresi veya kullanıcı adı…', degisti: (v) => _tabloSuz(() => _q = v)),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Durum',
                ikon: Icons.flag_outlined,
                secenekler: [('', 'Tümü'), for (final e in suzgecler.entries) (e.key, e.value)],
                secili: _suzgec,
                secildi: (v) => _tabloSuz(() => _suzgec = v),
              ),
            ],
            etkinler: [if (_suzgec.isNotEmpty) EtkinFiltre('Durum: ${suzgecler[_suzgec]}', () => _tabloSuz(() => _suzgec = ''))],
          ),
          if (!d.dusurmeKaydi)
            Padding(
              padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 0, context.genis ? 16 : 12, 8),
              child: const Bant('Güvenlik duvarının engellediği denemeler kaydedilmiyor; "Genel bakış" sekmesindeki koruma ayarlarından açabilirsiniz.'),
            ),
        ],
      ),
      sutunlar: [
        Sutun(
          'IP adresi',
          esnek: 3,
          siralama: 'ip',
          hucre: (c, s) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.ip, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 13.5)),
              if (s.yasakli || s.izinli || s.ip == d.benimIp) Padding(padding: const EdgeInsets.only(top: 3), child: rozetler(s)),
            ],
          ),
        ),
        Sutun('Engellenen', genislik: 100, sagaYasla: true, siralama: 'engellenen', hucre: (c, s) => sayi(s.engellenen, Marka.kehribar)),
        Sutun('Hatalı', genislik: 90, sagaYasla: true, siralama: 'hatali', hucre: (c, s) => sayi(s.toplamHatali, Marka.gul)),
        Sutun('Başarılı', genislik: 90, sagaYasla: true, siralama: 'basarili', hucre: (c, s) => sayi(s.basarili, Marka.zumrut)),
        Sutun('Denenen kullanıcılar', esnek: 3, hucre: (c, s) => SolukMetin(s.kullanicilar.join(', '))),
        Sutun('Son görülme', genislik: 120, siralama: 'son', hucre: (c, s) => Tooltip(message: tamZaman(s.sonGorulme), child: SolukMetin(goreliZaman(s.sonGorulme)))),
      ],
      kart: (c, s) => VeriKarti(
        baslik: s.ip,
        alt: s.kullanicilar.isEmpty ? null : 'Denenen: ${s.kullanicilar.join(', ')}',
        rozetler: [
          if (s.yasakli) const Rozet('yasaklı', renk: Marka.gul),
          if (s.izinli) const Rozet('SSH izinli', renk: Marka.zumrut),
          if (s.ip == d.benimIp) const Rozet('siz', renk: Marka.mavi),
        ],
        alanlar: [
          ('Engellenen', sayiYaz(s.engellenen)),
          ('Hatalı', sayiYaz(s.toplamHatali)),
          ('Başarılı', sayiYaz(s.basarili)),
          ('Son görülme', goreliZaman(s.sonGorulme)),
        ],
        vurgulu: !s.yasakli && !s.izinli && s.dusmanca >= 20,
        eylemler: _kaynakEylemleri(d, s),
        onTap: () => _kayitlar(s.ip),
      ),
    );
  }
}

/// IP yasakla (POST /host-security/bans): tek IP ya da CIDR aralığı, neden ve süre.
class YasakDialog extends StatefulWidget {
  const YasakDialog({super.key, this.ip, this.benimIp});
  final String? ip, benimIp;
  @override
  State<YasakDialog> createState() => _YasakDialogState();
}

class _YasakDialogState extends State<YasakDialog> {
  late final _ip = TextEditingController(text: widget.ip ?? '');
  final _neden = TextEditingController();
  int _saat = 24;
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _ip.dispose();
    _neden.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final ip = _ip.text.trim();
    if (ip == widget.benimIp &&
        !await onayla(
          context,
          'Kendi adresinizi yasaklıyorsunuz',
          mesaj: '$ip şu an bağlı olduğunuz adres. Yasaklanırsa panele bu adresten erişemeyebilirsiniz.',
          evet: 'Yine de yasakla',
          tehlikeli: true,
        )) {
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/host-security/bans', {'ip': ip, 'reason': _neden.text.trim(), 'hours': _saat});
      bildir('$ip yasaklandı', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('IP yasakla', style: gosterim(19, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Adresten gelen tüm bağlantılar güvenlik duvarında düşürülür. Tek IP ya da aralık (ör. 203.0.113.0/24) girebilirsiniz.',
                style: TextStyle(color: context.r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ip,
                autofocus: widget.ip == null,
                autocorrect: false,
                style: const TextStyle(fontFamily: 'monospace'),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'IP adresi'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _neden,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Neden', hintText: 'ör. SSH kaba kuvvet denemesi'),
              ),
              const SizedBox(height: 4),
              Text(
                'Süre',
                style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              SecimCipleri<int>(secenekler: [for (final (s, e) in yasakSureleri) (s, e)], secili: _saat, secildi: (v) => setState(() => _saat = v)),
              if (_hata != null) ...[const SizedBox(height: 12), Bant(_hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded)],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Marka.gul),
          onPressed: _mesgul || _ip.text.trim().isEmpty ? null : _kaydet,
          icon: _mesgul
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.block_rounded),
          label: const Text('Yasakla'),
        ),
      ],
    );
  }
}

/// Bir adresin SSH kayıtları (GET /host-security/events?ip=): ham günlük satırları eş aralıklı yazıyla.
class SshKayitlari extends StatefulWidget {
  const SshKayitlari({super.key, required this.ip, this.panelde = false});
  final String ip;

  /// Yan panelde (tam yükseklik) gösteriliyor; alt sayfa yüksekliği uygulanmaz.
  final bool panelde;
  @override
  State<SshKayitlari> createState() => _SshKayitlariState();
}

class _SshKayitlariState extends State<SshKayitlari> {
  List<SshOlayi>? _l;
  String? _hata;

  @override
  void initState() {
    super.initState();
    Uyg.api
        .get('/api/v1/host-security/events', q: {'ip': widget.ip})
        .then(
          (v) {
            if (mounted) setState(() => _l = haritalar(harita(v)['items']).map(SshOlayi.coz).toList());
          },
          onError: (Object e) {
            if (mounted) setState(() => _hata = hataMetni(e));
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _l;
    return SafeArea(
      child: SizedBox(
        height: widget.panelde ? null : MediaQuery.sizeOf(context).height * .8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.ip,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                  ),
                  if (l != null && l.isNotEmpty)
                    IconButton(
                      tooltip: 'Tümünü kopyala',
                      onPressed: () => kopyala(l.map((o) => o.satir).join('\n'), mesaj: 'Kayıtlar kopyalandı'),
                      icon: const Icon(Icons.copy_all_rounded),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Bu adresin SSH kayıtları (en yeni üstte, en fazla 1000 satır). Şifreler hiçbir zaman kaydedilmez.',
                style: TextStyle(color: r.silik, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _hata != null
                  ? Durum.hata(_hata!)
                  : l == null
                  ? const Durum.yukleniyor()
                  : l.isEmpty
                  ? const Durum.bos('Kayıt yok.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: l.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: r.kenar),
                      itemBuilder: (c, i) {
                        final o = l[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Rozet(sshOlayEtiketleri[o.tur] ?? o.tur, renk: _olayRengi(o.tur, r)),
                                  const SizedBox(width: 8),
                                  if (o.kullanici.isNotEmpty)
                                    Expanded(
                                      child: Text('kullanıcı: ${o.kullanici}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                                    )
                                  else
                                    const Spacer(),
                                  Text(kisaZaman(o.zaman), style: TextStyle(color: r.silik, fontSize: 11.5)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                o.satir,
                                style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: r.soluk, height: 1.35),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _olayRengi(String tur, Renkler r) => switch (tur) {
  'accepted' => Marka.zumrut,
  'failed' || 'invalid_user' => Marka.gul,
  'dropped' => Marka.kehribar,
  _ => r.silik,
};

/// Koruma ayarları (PUT /host-security/settings): engellenen deneme kaydı ve otomatik yasaklama.
class KorumaAyarlari extends StatefulWidget {
  const KorumaAyarlari({super.key, required this.d, required this.kaydedildi});
  final SunucuErisimi d;
  final VoidCallback kaydedildi;
  @override
  State<KorumaAyarlari> createState() => _KorumaAyarlariState();
}

class _KorumaAyarlariState extends State<KorumaAyarlari> {
  late OtomatikYasak _a = widget.d.otomatik;
  late final _esik = TextEditingController(text: '${_a.esik}');
  late final _pencere = TextEditingController(text: '${_a.pencereDk}');
  bool _mesgul = false;

  @override
  void didUpdateWidget(KorumaAyarlari eski) {
    super.didUpdateWidget(eski);
    if (eski.d.otomatik.json().toString() != widget.d.otomatik.json().toString()) {
      _a = widget.d.otomatik;
      _esik.text = '${_a.esik}';
      _pencere.text = '${_a.pencereDk}';
    }
  }

  @override
  void dispose() {
    _esik.dispose();
    _pencere.dispose();
    super.dispose();
  }

  Future<void> _kaydet(Map<String, dynamic> govde, String tamam) async {
    setState(() => _mesgul = true);
    final v = await islem(() => Uyg.api.put('/api/v1/host-security/settings', govde).then((_) => true), tamam: tamam);
    if (mounted) setState(() => _mesgul = false);
    if (v != null) widget.kaydedildi();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final kayit = widget.d.dusurmeKaydi;
    final esik = int.tryParse(_esik.text.trim()), pencere = int.tryParse(_pencere.text.trim());
    final gecerli = esik != null && esik >= 3 && esik <= 10000 && pencere != null && pencere >= 1 && pencere <= 10080;
    final sureler = {for (final (s, e) in yasakSureleri) s: e, _a.yasakSaat: yasakSuresiEtiketi(_a.yasakSaat)};
    return BolumKarti(
      baslik: 'Koruma ayarları',
      ikon: Icons.shield_rounded,
      altBaslik: 'Engellenen denemelerin kaydı ve tekrar tekrar deneyen adreslerin otomatik yasaklanması.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: kayit,
            onChanged: _mesgul ? null : (v) => _kaydet({'drop_log': v}, v ? 'Kayıt açıldı' : 'Kayıt kapatıldı'),
            title: const Text('Engellenen SSH denemelerini kaydet', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text(
              'İzin listesi dışından gelen SSH bağlantıları zaten düşürülür; bu ayar onları (dakikada en fazla 30) günlüğe de yazar.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          const Divider(height: 20),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _a.etkin,
            onChanged: (v) => setState(() => _a = _a.kopya(etkin: v)),
            title: const Text('Otomatik yasaklama', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _esik,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Deneme sayısı',
                    isDense: true,
                    errorText: esik == null || esik < 3 || esik > 10000 ? '3–10000' : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _pencere,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Süre (dk)',
                    isDense: true,
                    errorText: pencere == null || pencere < 1 || pencere > 10080 ? '1–10080' : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _a.yasakSaat,
            decoration: const InputDecoration(labelText: 'Yasak süresi', isDense: true),
            items: [for (final e in sureler.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _a = _a.kopya(yasakSaat: v)),
          ),
          const SizedBox(height: 10),
          Text(
            '${pencere ?? '?'} dakikada ${esik ?? '?'} veya daha fazla hatalı / engellenen SSH denemesi yapan adres yasaklanır. SSH izin listesindeki adresler, sunucunun kendi adresleri ve yerel ağlar hiçbir zaman yasaklanmaz.',
            style: TextStyle(color: r.silik, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _mesgul || !gecerli
                  ? null
                  : () => _kaydet({'autoban': _a.kopya(esik: esik, pencereDk: pencere).json()}, 'Otomatik yasaklama kaydedildi'),
              child: _mesgul
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Kaydet'),
            ),
          ),
        ],
      ),
    );
  }
}
