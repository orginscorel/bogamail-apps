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
        v = await widget.api.post(widget.girisYolu, {
          'email': _adres.text.trim(),
          'password': _sifre.text,
          if (widget.kaydetSecenegi) 'save': _kaydet,
        });
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
    final v = await metinSor(context, 'Sunucu adresi',
        ilk: widget.api.sunucu, ipucu: BogaApi.varsayilanSunucu, tamam: 'Kaydet');
    if (v == null) return;
    await widget.api.sunucuAyarla(v);
    await widget.api.cerezleriTemizle();
    if (mounted) setState(() {});
    bildir('Sunucu ayarlandı', mesaj: widget.api.sunucu, tur: MesajTur.basari);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final mfa = _mfaJeton != null;
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: r.zemin,
        body: LayoutBuilder(builder: (context, k) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: k.maxHeight),
              child: Column(children: [
                // Üst marka alanı
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(gradient: Marka.gece, borderRadius: BorderRadius.vertical(bottom: Radius.circular(32))),
                  padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 36, 24, 44),
                  child: Column(children: [
                    if (widget.geri != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: 'Geri',
                          onPressed: widget.geri,
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        ),
                      ),
                    BogaIsaret(boyut: 84, isaret: widget.isaret),
                    const SizedBox(height: 14),
                    Text(widget.baslik, style: gosterim(28, renk: Colors.white)),
                    const SizedBox(height: 6),
                    Text(widget.aciklama, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 14)),
                  ]),
                ),
                if (widget.ust != null && !mfa)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: widget.ust),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: mfa ? _mfaFormu(r) : _sifreFormu(r),
                    ),
                  ),
                ),
                if (_hata != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
                        child: Row(children: [
                          const Icon(Icons.error_outline_rounded, color: Marka.gul, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13.5))),
                        ]),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: _bekliyor ? null : _sunucu,
                  icon: Icon(Icons.dns_rounded, size: 16, color: r.silik),
                  label: Text(Uri.tryParse(widget.api.sunucu)?.host ?? widget.api.sunucu, style: TextStyle(color: r.silik, fontSize: 12.5)),
                ),
                Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 12),
                  child: Text('Bogahost · Sürüm ${widget.api.surum}', style: TextStyle(color: r.silik.withValues(alpha: .7), fontSize: 11)),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  Widget _sifreFormu(Renkler r) => Form(
        key: _form,
        child: AutofillGroup(
          child: Column(key: const ValueKey('sifre'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _adres,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              decoration: InputDecoration(labelText: 'E-posta adresi', hintText: widget.adresIpucu, prefixIcon: const Icon(Icons.alternate_email_rounded)),
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
                prefixIcon: const Icon(Icons.lock_rounded),
                suffixIcon: IconButton(
                  tooltip: _gizli ? 'Göster' : 'Gizle',
                  icon: Icon(_gizli ? Icons.visibility_rounded : Icons.visibility_off_rounded),
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
            _dugme('Giriş yap', Icons.login_rounded),
          ]),
        ),
      );

  Widget _mfaFormu(Renkler r) => Column(key: const ValueKey('mfa'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.verified_user_rounded, color: r.birincil),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('İki adımlı doğrulama', style: gosterim(17, agirlik: FontWeight.w700, renk: r.metin)),
              Text('Doğrulama uygulamanızdaki 6 haneli kodu ya da bir kurtarma kodunu girin.', style: TextStyle(color: r.soluk, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _kod,
          autofocus: true,
          keyboardType: TextInputType.visiblePassword,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          style: gosterim(26, agirlik: FontWeight.w700, renk: r.metin).copyWith(letterSpacing: 6),
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
        _dugme('Doğrula', Icons.check_rounded),
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
      ]);

  Widget _dugme(String yazi, IconData ikon) => SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(14), boxShadow: context.r.golge),
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
            onPressed: _bekliyor ? null : _gonder,
            child: _bekliyor
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(yazi, style: const TextStyle(color: Colors.white)),
                    const SizedBox(width: 8),
                    Icon(ikon, color: Colors.white, size: 19),
                  ]),
          ),
        ),
      );
}
