import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';

/// Oturum yokken açılış: bu cihazda kayıtlı hesap varsa "Kayıtlı postalarınız" listesi, yoksa giriş formu.
class GirisKapisi extends StatefulWidget {
  const GirisKapisi({super.key, this.bilgi});
  final String? bilgi;
  @override
  State<GirisKapisi> createState() => _GirisKapisiState();
}

class _GirisKapisiState extends State<GirisKapisi> {
  List<KayitliHesap>? _l;
  bool _form = false;
  String? _adres;
  String? _mesgul;

  @override
  void initState() {
    super.initState();
    _yukle();
    if (widget.bilgi != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => bildir(widget.bilgi!, tur: MesajTur.uyari));
    }
  }

  Future<void> _yukle() async {
    try {
      final l = await Uyg.hesaplar();
      if (mounted) setState(() => _l = l);
    } catch (_) {
      if (mounted) setState(() => _l = const []);
    }
  }

  Future<void> _gir(KayitliHesap h) async {
    setState(() => _mesgul = h.id);
    final ok = await Uyg.hesabaGec(id: h.id);
    if (!ok && mounted) {
      // Kayıt geçersiz (ör. şifre değişti): adres dolu giriş formu.
      setState(() {
        _mesgul = null;
        _adres = h.adres;
        _form = true;
      });
    }
  }

  Future<void> _kaldir(KayitliHesap h) async {
    if (!await onayla(context, '${h.adres} bu cihazdan kaldırılsın mı?', mesaj: 'Tekrar girmek için şifreniz gerekir.', evet: 'Kaldır', tehlikeli: true)) {
      return;
    }
    await islem(() => Uyg.hesabiKaldir(h.id), tamam: 'Hesap kaldırıldı');
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    if (l == null) return const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
    if (l.isEmpty || _form) {
      return Uyg.girisFormu(
        adres: _adres,
        geri: l.isEmpty
            ? null
            : () => setState(() {
                _form = false;
                _adres = null;
              }),
      );
    }
    final r = context.r;
    return Scaffold(
      backgroundColor: r.zemin,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              children: [
                const Center(child: BogaIsaret(boyut: 72, isaret: AcilisIsaret.posta)),
                const SizedBox(height: 16),
                Text(
                  'Kayıtlı postalarınız',
                  textAlign: TextAlign.center,
                  style: gosterim(24, agirlik: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Devam etmek için bir hesaba dokunun.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: r.soluk),
                ),
                const SizedBox(height: 24),
                Kutu(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final h in l)
                        HesapSatiri(
                          key: ValueKey('kayitli-${h.id}'),
                          hesap: h,
                          mesgul: _mesgul == h.id,
                          dokun: _mesgul == null ? () => _gir(h) : null,
                          kaldir: () => _kaldir(h),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const ValueKey('baska-hesap'),
                  onPressed: () => setState(() => _form = true),
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: const Text('Başka hesapla giriş'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hesap satırı: avatar, ad/adres, okunmamış rozeti, etkin işareti, "oturum kapalı" notu.
class HesapSatiri extends StatelessWidget {
  const HesapSatiri({super.key, required this.hesap, this.dokun, this.kaldir, this.mesgul = false});
  final KayitliHesap hesap;
  final VoidCallback? dokun;
  final VoidCallback? kaldir;
  final bool mesgul;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final h = hesap;
    return ListTile(
      onTap: dokun,
      leading: Avatar(h.gorunen, boyut: 42, tohum: h.adres),
      title: Text(
        h.gorunen,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(h.cikisYapti ? '${h.adres} · çıkış yapıldı' : h.adres, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mesgul) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          if (!mesgul && h.okunmamis > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: r.vurgu, borderRadius: BorderRadius.circular(20)),
              child: Text(
                h.okunmamis > 999 ? '999+' : '${h.okunmamis}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          if (h.etkin)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle_rounded, color: r.vurgu),
            ),
          if (kaldir != null && !h.etkin)
            PopupMenuButton<String>(
              tooltip: 'Seçenekler',
              onSelected: (_) => kaldir!(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'kaldir',
                  child: ListTile(leading: Icon(Icons.person_remove_outlined), title: Text('Bu cihazdan kaldır')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Hesap değiştirici (kenar menüsü başlığı ve Ayarlar): kayıtlı hesaplar, hesap ekle, çıkış, cihazdan kaldır.
Future<void> hesapSeciciAc(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const HesapSecici());

class HesapSecici extends StatefulWidget {
  const HesapSecici({super.key, this.gomulu = false});

  /// true: Ayarlar içinde kart olarak; false: alt sayfa.
  final bool gomulu;
  @override
  State<HesapSecici> createState() => _HesapSeciciState();
}

class _HesapSeciciState extends State<HesapSecici> {
  List<KayitliHesap>? _l;
  String? _mesgul;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final l = await Uyg.hesaplar();
      if (mounted) setState(() => _l = l);
    } catch (_) {
      if (mounted) setState(() => _l = const []);
    }
  }

  List<KayitliHesap> get _liste {
    final l = [...?_l];
    if (!l.any((h) => h.etkin) && Uyg.adres.isNotEmpty) {
      l.insert(0, KayitliHesap(id: '${Uyg.kutu.value?['mailbox_id'] ?? ''}', adres: Uyg.adres, ad: Uyg.ad, etkin: true));
    }
    return l;
  }

  Future<void> _gec(KayitliHesap h) async {
    if (h.etkin) {
      if (!widget.gomulu) Navigator.pop(context);
      return;
    }
    setState(() => _mesgul = h.id);
    final ok = await Uyg.hesabaGec(id: h.id);
    if (!ok && mounted) {
      setState(() => _mesgul = null);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (c) => Uyg.girisFormu(ekle: true, adres: h.adres, geri: () => Navigator.pop(c)),
        ),
      );
    }
  }

  Future<void> _kaldir(KayitliHesap h) async {
    if (!await onayla(
      context,
      '${h.adres} bu cihazdan kaldırılsın mı?',
      mesaj: 'Bu hesabın bildirimleri de bu cihaza gelmez.',
      evet: 'Kaldır',
      tehlikeli: true,
    )) {
      return;
    }
    await islem(() => Uyg.hesabiKaldir(h.id), tamam: 'Hesap kaldırıldı');
    _yukle();
  }

  Future<void> _cikis({required bool unut}) async {
    final ok = await onayla(
      context,
      unut ? 'Hesap bu cihazdan kaldırılsın mı?' : 'Çıkış yapılsın mı?',
      mesaj: unut
          ? 'Oturum kapatılır ve hesap kayıtlı listeden silinir. Tekrar girmek için şifre gerekir.'
          : 'Hesap bu cihazda kayıtlı kalır; listeden şifresiz geri dönebilirsiniz.',
      evet: unut ? 'Kaldır' : 'Çıkış yap',
      tehlikeli: true,
    );
    if (ok) await Uyg.cikis(unut: unut);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _liste;
    final govde = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.gomulu)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Hesaplar', style: gosterim(18, agirlik: FontWeight.w700)),
          ),
        if (_l == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        for (final h in l)
          HesapSatiri(
            key: ValueKey('hesap-${h.id}'),
            hesap: h,
            mesgul: _mesgul == h.id,
            dokun: _mesgul == null ? () => _gec(h) : null,
            kaldir: () => _kaldir(h),
          ),
        const Divider(),
        ListTile(
          key: const ValueKey('hesap-ekle'),
          leading: Icon(Icons.person_add_alt_rounded, color: r.vurgu),
          title: const Text('Hesap ekle'),
          onTap: () {
            final nav = Navigator.of(context);
            if (!widget.gomulu) nav.pop();
            nav.push(MaterialPageRoute<void>(builder: (c) => Uyg.girisFormu(ekle: true, geri: () => Navigator.pop(c))));
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout_rounded),
          title: const Text('Çıkış yap'),
          subtitle: const Text('Hesap bu cihazda kayıtlı kalır'),
          onTap: () => _cikis(unut: false),
        ),
        ListTile(
          leading: const Icon(Icons.person_remove_outlined, color: Marka.gul),
          title: const Text('Bu cihazdan kaldır', style: TextStyle(color: Marka.gul)),
          subtitle: const Text('Çıkış yapar ve hesabı kayıtlı listeden siler'),
          onTap: () => _cikis(unut: true),
        ),
      ],
    );
    if (widget.gomulu) return govde;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
        child: SingleChildScrollView(child: govde),
      ),
    );
  }
}
