import 'simge.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'acilis.dart';
import 'api.dart';
import 'ortak.dart';
import 'tema.dart';

/// Giriş: e-posta + şifre → (iki adımlı doğrulama açıksa) 6 haneli kod ya da kurtarma kodu.
/// "Bu cihazı hatırla" seçilirse sunucu 30 gün boyunca kodu tekrar sormaz.
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({
    super.key,
    required this.api,
    required this.baslik,
    required this.aciklama,
    required this.girisYolu,
    required this.isaret,
    required this.girisYapildi,
    this.adresIpucu = 'ad@firmaniz.com',
    this.ust,
    this.geri,
    this.kaydetSecenegi = false,
    this.ilkAdres,
  });

  final BogaApi api;
  final String baslik;
  final String aciklama;

  /// posta → /api/v1/mail/auth/login, yönetim → /api/v1/auth/login (2FA: aynı yol + /mfa)
  final String girisYolu;
  final AcilisIsaret isaret;
  final String adresIpucu;

  /// Oturum açıldı: uygulama ana ekranına geçer.
  final Future<void> Function(BuildContext context) girisYapildi;

  /// İsteğe bağlı: formun üstünde gösterilir (ör. kayıtlı hesaplar listesi).
  final Widget? ust;

  /// Verilirse sol üstte geri düğmesi gösterilir (ör. "Hesap ekle" kipi).
  final VoidCallback? geri;

  /// true: "Bu cihazda kayıtlı kalsın" kutusu gösterilir ve giriş isteğine `save` alanı eklenir.
  final bool kaydetSecenegi;

  /// Adres alanının ilk değeri (ör. oturumu kapanmış kayıtlı hesap).
  final String? ilkAdres;

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  late final _adres = TextEditingController(text: widget.ilkAdres);
  final _sifre = TextEditingController();
  final _kod = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _gizli = true;
  bool _bekliyor = false;
  bool _hatirla = true;
  bool _kaydet = true;
  String? _mfaJeton;
  String? _hata;

  @override
  void dispose() {
    _adres.dispose();
    _sifre.dispose();
    _kod.dispose();
    super.dispose();
  }

  Future<void> _gonder() async {
    if (_bekliyor) return;
    if (_mfaJeton == null && !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _bekliyor = true;
      _hata = null;
    });
    try {
      final dynamic v;
      if (_mfaJeton == null) {
        v = await widget.api.post(widget.girisYolu, {'email': _adres.text.trim(), 'password': _sifre.text, if (widget.kaydetSecenegi) 'save': _kaydet});
      } else {
        final kod = _kod.text.replaceAll(' ', '').trim();
        if (kod.isEmpty) {
          setState(() {
            _bekliyor = false;
            _hata = 'Doğrulama kodunu girin.';
          });
          return;
        }
        v = await widget.api.post('${widget.girisYolu}/mfa', {'mfa_token': _mfaJeton, 'code': kod, 'remember': _hatirla});
      }
      if (v is Map && v['mfa_required'] == true) {
        setState(() {
          _mfaJeton = '${v['mfa_token']}';
          _bekliyor = false;
        });
        return;
      }
      if (v is Map && v['mfa_setup_required'] == true) {
        setState(() {
          _bekliyor = false;
          _hata = 'Bu hesap için iki adımlı doğrulama zorunlu. Önce web panelinden kurun, sonra buradan giriş yapın.';
        });
        return;
      }
      if (!mounted) return;
      TextInput.finishAutofillContext();
      await widget.girisYapildi(context);
    } catch (e) {
      if (!mounted) return;
      final h = e is ApiHata ? e : null;
      setState(() {
        _bekliyor = false;
        _hata = hataMetni(e);
        // 2FA jetonu süresi doldu ya da çok fazla hatalı kod: şifre adımına dön
        if (h != null && (h.kod == 'mfa_expired' || (_mfaJeton != null && h.kod == 'rate_limited'))) {
          _mfaJeton = null;
          _kod.clear();
        }
      });
      return;
    }
    if (mounted) setState(() => _bekliyor = false);
  }

  Future<void> _sunucu() async {
    final v = await metinSor(context, 'Sunucu adresi', ilk: widget.api.sunucu, ipucu: BogaApi.varsayilanSunucu, tamam: 'Kaydet');
    if (v == null) return;
    final once = widget.api.sunucu;
    await widget.api.sunucuAyarla(v);
    // Çerezler (oturum ve kayıtlı hesaplar için cihaz çerezi) yalnız sunucu gerçekten değiştiyse silinir.
    if (widget.api.sunucu != once) await widget.api.cerezleriTemizle();
    if (mounted) setState(() {});
    bildir('Sunucu ayarlandı', mesaj: widget.api.sunucu, tur: MesajTur.basari);
  }

  List<(IconData, String, String)> get _ozellikler => widget.isaret == AcilisIsaret.posta
      ? const [
          (Simge.postaDolu, 'Kurumsal e-posta', 'Klasörler, etiketler, süzgeçler ve güçlü arama'),
          (Simge.sohbet, 'Sohbet', 'Kurum içi kanallar, bireysel ve grup mesajları'),
          (Simge.etkinlikOnay, 'Takvim ve görevler', 'Toplantılar, davetler ve iş takibi'),
        ]
      : const [
          (Simge.sunucu, 'Alan adları ve posta kutuları', 'Tüm müşterileri tek panelden yönetin'),
          (Simge.kalkan, 'Güvenlik', 'Karantina, tehdit koruması ve DLP'),
          (Simge.gonderimDurumu, 'İzleme', 'Kuyruk, teslimat ve anlık uyarılar'),
        ];

  String get _uygulamaAdi => widget.isaret == AcilisIsaret.posta ? 'BogaMail' : 'BogaMail Yönetim';

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final genis = MediaQuery.sizeOf(context).width >= 900;
    return AnnotatedRegion(
      value: r.koyu ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: r.zemin,
        body: genis
            ? Row(
                children: [
                  Expanded(flex: 5, child: _markaPaneli()),
                  Expanded(flex: 6, child: _formAlani(r, genis: true)),
                ],
              )
            : _formAlani(r, genis: false),
      ),
    );
  }

  /// Geniş ekranda sol marka paneli: uygulama degradesi, nokta dokusu, işaret, özellikler.
  Widget _markaPaneli() => DecoratedBox(
    decoration: BoxDecoration(gradient: isaretDegradesi(widget.isaret)),
    child: CustomPaint(
      painter: _NoktaDokusu(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BogaIsaret(boyut: 48, isaret: widget.isaret),
                  const SizedBox(width: 14),
                  Text(_uygulamaAdi, style: gosterim(22, renk: Colors.white)),
                ],
              ),
              const Spacer(),
              Text(
                widget.isaret == AcilisIsaret.posta ? 'İletişiminiz\ntek yerde.' : 'Posta altyapınız\nkontrolünüzde.',
                style: gosterim(44, renk: Colors.white, satir: 1.08),
              ),
              const SizedBox(height: 14),
              Text(widget.aciklama, style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 15.5, height: 1.45)),
              const SizedBox(height: 36),
              for (final (ikon, baslik, alt) in _ozellikler)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: .18)),
                        ),
                        child: Icon(ikon, color: widget.isaret == AcilisIsaret.posta ? Colors.white : Marka.yesil, size: 21),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              baslik,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14.5),
                            ),
                            Text(alt, style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                'BOGAHOST',
                style: TextStyle(color: Colors.white.withValues(alpha: .5), fontSize: 11, letterSpacing: 4, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _formAlani(Renkler r, {required bool genis}) {
    final mfa = _mfaJeton != null;
    final ust = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, k) {
        return Stack(
          children: [
            // Telefonda üstte uygulama renginde yumuşak bir ışık.
            if (!genis)
              Positioned(
                top: -120,
                left: -80,
                right: -80,
                height: 360,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        r.vurgu.withValues(alpha: r.koyu ? .22 : .13),
                        r.vurgu.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: k.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, ust + (genis ? 40 : 20), 24, MediaQuery.paddingOf(context).bottom + 16),
                      child: Column(
                        mainAxisAlignment: genis ? MainAxisAlignment.center : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (widget.geri != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: IconButton(
                                    tooltip: 'Geri',
                                    onPressed: widget.geri,
                                    icon: Icon(Simge.geri, color: r.metin),
                                  ),
                                ),
                              if (!genis)
                                Expanded(
                                  child: Row(
                                    children: [
                                      BogaIsaret(boyut: 40, isaret: widget.isaret),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          _uygulamaAdi,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: gosterim(17, agirlik: FontWeight.w600, renk: r.metin),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                  ),
                                )
                              else
                                const Spacer(),
                              _sunucuDugmesi(r),
                            ],
                          ),
                          SizedBox(height: genis ? 28 : 44),
                          Text(mfa ? 'Doğrulama' : (widget.geri != null ? 'Hesap ekle' : 'Hoş geldiniz'), style: gosterim(32, renk: r.metin)),
                          const SizedBox(height: 6),
                          Text(
                            mfa ? 'Hesabınız iki adımlı doğrulama ile korunuyor.' : '$_uygulamaAdi hesabınızla giriş yapın.',
                            style: TextStyle(color: r.soluk, fontSize: 15),
                          ),
                          const SizedBox(height: 26),
                          if (widget.ust != null && !mfa) ...[widget.ust!, const SizedBox(height: 18)],
                          DecoratedBox(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: r.golge),
                            child: Material(
                              color: r.kart,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: r.kenar),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: AnimatedSwitcher(duration: const Duration(milliseconds: 260), child: mfa ? _mfaFormu(r) : _sifreFormu(r)),
                              ),
                            ),
                          ),
                          if (_hata != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Marka.gul.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Marka.gul.withValues(alpha: .25)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Simge.hata, color: Marka.gul, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13.5)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Simge.kilit, size: 14, color: r.silik),
                              const SizedBox(width: 6),
                              Text('Güvenli bağlantı (TLS)', style: TextStyle(color: r.silik, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Bogahost · Sürüm ${widget.api.surum}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: r.silik.withValues(alpha: .8), fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sunucuDugmesi(Renkler r) => Tooltip(
    message: 'Sunucuyu değiştir',
    child: InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: _bekliyor ? null : _sunucu,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: r.ic,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: r.kenar),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: Marka.zumrut, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                Uri.tryParse(widget.api.sunucu)?.host ?? widget.api.sunucu,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: r.soluk, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _sifreFormu(Renkler r) => Form(
    key: _form,
    child: AutofillGroup(
      child: Column(
        key: const ValueKey('sifre'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _adres,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            decoration: InputDecoration(labelText: 'E-posta adresi', hintText: widget.adresIpucu, prefixIcon: const Icon(Simge.eposta)),
            validator: (v) => (v ?? '').contains('@') ? null : 'Geçerli bir e-posta adresi girin',
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _sifre,
            obscureText: _gizli,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _gonder(),
            decoration: InputDecoration(
              labelText: 'Şifre',
              prefixIcon: const Icon(Simge.kilitDolu),
              suffixIcon: IconButton(
                tooltip: _gizli ? 'Göster' : 'Gizle',
                icon: Icon(_gizli ? Simge.goster : Simge.gizle),
                onPressed: () => setState(() => _gizli = !_gizli),
              ),
            ),
            validator: (v) => (v ?? '').isEmpty ? 'Şifrenizi girin' : null,
          ),
          if (widget.kaydetSecenegi)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _kaydet,
              onChanged: (v) => setState(() => _kaydet = v ?? true),
              title: const Text('Bu cihazda kayıtlı kalsın', style: TextStyle(fontSize: 14)),
              subtitle: Text('Çıkış yapsanız da hesap listede kalır; şifresiz geri dönebilirsiniz.', style: TextStyle(color: r.silik, fontSize: 12)),
            ),
          SizedBox(height: widget.kaydetSecenegi ? 8 : 20),
          _dugme('Giriş yap', Simge.giris),
        ],
      ),
    ),
  );

  Widget _mfaFormu(Renkler r) => Column(
    key: const ValueKey('mfa'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(14)),
            child: Icon(Simge.guvenli, color: r.birincil),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'İki adımlı doğrulama',
                  style: gosterim(17, agirlik: FontWeight.w600, renk: r.metin),
                ),
                Text('Doğrulama uygulamanızdaki 6 haneli kodu ya da bir kurtarma kodunu girin.', style: TextStyle(color: r.soluk, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _kod,
        autofocus: true,
        keyboardType: TextInputType.visiblePassword,
        textAlign: TextAlign.center,
        autofillHints: const [AutofillHints.oneTimeCode],
        style: gosterim(26, agirlik: FontWeight.w600, renk: r.metin).copyWith(letterSpacing: 6),
        onSubmitted: (_) => _gonder(),
        decoration: const InputDecoration(hintText: '••••••'),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _hatirla,
        onChanged: (v) => setState(() => _hatirla = v),
        title: const Text('Bu cihazı hatırla', style: TextStyle(fontSize: 14)),
        subtitle: Text('30 gün boyunca kod sorulmaz', style: TextStyle(color: r.silik, fontSize: 12)),
      ),
      const SizedBox(height: 8),
      _dugme('Doğrula', Simge.onay),
      TextButton(
        onPressed: _bekliyor
            ? null
            : () => setState(() {
                _mfaJeton = null;
                _kod.clear();
                _hata = null;
              }),
        child: const Text('Geri dön'),
      ),
    ],
  );

  Widget _dugme(String yazi, IconData ikon) => SizedBox(
    height: 52,
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(14), boxShadow: context.r.golge),
      child: FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
        onPressed: _bekliyor ? null : _gonder,
        child: _bekliyor
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(yazi, style: const TextStyle(color: Colors.white)),
                  const SizedBox(width: 8),
                  Icon(ikon, color: Colors.white, size: 19),
                ],
              ),
      ),
    ),
  );
}

/// Marka panelinin nokta dokusu.
class _NoktaDokusu extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = Colors.white.withValues(alpha: .07);
    const ara = 22.0;
    for (double x = 11; x < s.width; x += ara) {
      for (double y = 11; y < s.height; y += ara) {
        c.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_NoktaDokusu o) => false;
}
