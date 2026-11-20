import 'simge.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_drawing/path_drawing.dart';

import 'api.dart';
import 'guncelleme.dart';
import 'tema.dart';

/// Hangi uygulamanın işareti: posta → indigo zemin + zarf rozeti, yönetim → grafit zemin + yeşil kontrol rozeti.
enum AcilisIsaret { posta, yonetim }

bool hareketAzalt(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

// ---------------------------------------------------------------------------------------------------------------
// Bogahost logosu (bogahost.com/templates/bogahost/img/logo-new.svg, işaret kısmı): boynuzlu taç + üç sunucu sütunu.
// Özgün koordinatlar 47 × 55.75 birimlik alandadır.

const _sutunYollari = [
  'M5.11,22.74V46.22c0,2.07,2,3.76,4.46,3.76h2.62c2.46,0,4.46-1.69,4.46-3.76V22.74c0-2.07-2-3.76-4.46-3.76H9.57C7.11,19,5.11,20.67,5.11,22.74ZM12.19,21a2,2,0,0,1,2.09,1.76V46.22A2,2,0,0,1,12.19,48H9.57a1.94,1.94,0,0,1-2.09-1.76V22.74A1.94,1.94,0,0,1,9.57,21Z',
  'M17.72,23.44V51.29a4.46,4.46,0,0,0,4.46,4.46H24.8a4.46,4.46,0,0,0,4.46-4.46V23.44A4.46,4.46,0,0,0,24.8,19H22.18A4.46,4.46,0,0,0,17.72,23.44Zm7.08-2.09a2.1,2.1,0,0,1,2.09,2.09V51.29a2.1,2.1,0,0,1-2.09,2.09H22.18a2.1,2.1,0,0,1-2.09-2.09V23.44a2.1,2.1,0,0,1,2.09-2.09Z',
  'M30.33,22.74V46.22c0,2.07,2,3.76,4.46,3.76h2.62c2.46,0,4.47-1.69,4.47-3.76V22.74c0-2.07-2-3.76-4.47-3.76H34.79C32.33,19,30.33,20.67,30.33,22.74ZM37.41,21a1.94,1.94,0,0,1,2.09,1.76V46.22A1.94,1.94,0,0,1,37.41,48H34.79a2,2,0,0,1-2.09-1.76V22.74A2,2,0,0,1,34.79,21Z',
];
const _cubukYollari = [
  'M9.69,33.38V43.7a1.19,1.19,0,0,0,2.37,0V33.38a1.19,1.19,0,1,0-2.37,0Z',
  'M22.31,39.66V50a1.19,1.19,0,0,0,2.37,0V39.66a1.19,1.19,0,1,0-2.37,0Z',
  'M34.92,33.38V43.7a1.19,1.19,0,0,0,2.37,0V33.38a1.19,1.19,0,1,0-2.37,0Z',
];
const _tacYolu =
    'M29.51,16.66H42.9A4.08,4.08,0,0,0,47,12.58V.9a.9.9,0,0,0-.9-.9.91.91,0,0,0-.74.38l-4,5.68a.87.87,0,0,0-.16.52v4.3H26.49l-2.61,3.75-.38.53,3-4.28H5.79V6.58a.87.87,0,0,0-.17-.52L1.65.38A.88.88,0,0,0,.92,0h0A.9.9,0,0,0,0,.9V12.59a4.07,4.07,0,0,0,4.08,4.07H17.49Z';

const _logoG = 47.0;
const _logoY = 55.75;

class _Logo {
  _Logo._();
  static final sutunlar = [for (final d in _sutunYollari) parseSvgPathData(d)];
  static final cubuklar = [for (final d in _cubukYollari) parseSvgPathData(d)];
  static final tac = parseSvgPathData(_tacYolu);
}

/// Uygulamanın imza degradesi (açılış/simge). [Marka.grad]'dan bağımsızdır: simge üretiminde kimlik ayarlı olmayabilir.
LinearGradient isaretDegradesi(AcilisIsaret i) => i == AcilisIsaret.posta
    ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7B6DF0), Marka.mor, Color(0xFF3624A6)], stops: [0, .5, 1])
    : const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF353D5C), Marka.grafit, Color(0xFF10131E)],
        stops: [0, .55, 1],
      );

/// [a, b] aralığını 0..1'e eşler ve eğriyi uygular.
double _aralik(double t, double a, double b, [Curve e = Curves.linear]) {
  if (t <= a) return 0;
  if (t >= b) return 1;
  return e.transform((t - a) / (b - a));
}

/// Logoyu (ilerlemeye göre) [alan]a çizer. [t]: 0..1 koreografi; 1 = tam logo.
/// Sunucu sütunları alttan sırayla yükselir, iç göstergeleri dolar; taç önce çizgiyle çizilir sonra dolar.
void _logoCiz(Canvas c, Rect alan, Color renk, double t) {
  final olcek = alan.height / _logoY;
  c.save();
  c.translate(alan.center.dx - _logoG * olcek / 2, alan.top);
  c.scale(olcek);
  for (var i = 0; i < 3; i++) {
    final a = _aralik(t, .08 + i * .09, .42 + i * .09, Curves.easeOutBack);
    if (a <= 0) continue;
    c.save();
    c.translate(0, (1 - a) * 18);
    final p = Paint()..color = renk.withValues(alpha: renk.a * a.clamp(0.0, 1.0));
    c.drawPath(_Logo.sutunlar[i], p);
    final b = _aralik(t, .40 + i * .07, .62 + i * .07, Curves.easeOutCubic);
    if (b > 0) {
      final cb = _Logo.cubuklar[i].getBounds();
      c.save();
      c.clipRect(Rect.fromLTRB(cb.left - 1, cb.bottom - cb.height * b, cb.right + 1, cb.bottom + 1));
      c.drawPath(_Logo.cubuklar[i], p);
      c.restore();
    }
    c.restore();
  }
  final ciz = _aralik(t, .30, .70, Curves.easeInOutCubic);
  if (ciz > 0) {
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = renk;
    final dol = _aralik(t, .58, .80, Curves.easeOut);
    if (dol < 1) {
      for (final m in _Logo.tac.computeMetrics()) {
        c.drawPath(m.extractPath(0, m.length * ciz), kalem);
      }
    }
    if (dol > 0) c.drawPath(_Logo.tac, Paint()..color = renk.withValues(alpha: renk.a * dol));
  }
  c.restore();
}

/// Rozet: posta → zarf, yönetim → kontrol sürgüleri (yeşil). Merkez [m], yarıçap [y]; [halka] zeminden ayıran kenar.
void _rozetCiz(Canvas c, Offset m, double y, AcilisIsaret i, {required Color halka, double olcek = 1}) {
  if (olcek <= 0) return;
  c.save();
  c.translate(m.dx, m.dy);
  c.scale(olcek);
  c.drawCircle(Offset.zero, y * 1.22, Paint()..color = halka);
  if (i == AcilisIsaret.posta) {
    c.drawCircle(Offset.zero, y, Paint()..color = Colors.white);
    final r = Rect.fromCenter(center: Offset(0, y * .02), width: y * 1.08, height: y * .78);
    final kalem = Paint()
      ..color = Marka.mor
      ..style = PaintingStyle.stroke
      ..strokeWidth = y * .14
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(y * .12)), kalem);
    c.drawPath(
      Path()
        ..moveTo(r.left + y * .06, r.top + y * .08)
        ..lineTo(0, r.center.dy + y * .1)
        ..lineTo(r.right - y * .06, r.top + y * .08),
      kalem,
    );
  } else {
    c.drawCircle(Offset.zero, y, Paint()..color = Marka.yesil);
    final kalem = Paint()
      ..color = Colors.white
      ..strokeWidth = y * .13
      ..strokeCap = StrokeCap.round;
    final dugme = Paint()..color = Colors.white;
    final ic = Paint()..color = Marka.yesil;
    for (final (sira, konum) in const [(-1, -.28), (0, .3), (1, -.05)]) {
      final yy = sira * y * .42;
      c.drawLine(Offset(-y * .52, yy), Offset(y * .52, yy), kalem);
      final k = Offset(konum * y, yy);
      c.drawCircle(k, y * .2, dugme);
      c.drawCircle(k, y * .09, ic);
    }
  }
  c.restore();
}

/// Simge üretimi ve küçük işaretler için: işaretin son karesini 64 birimlik alana çizer.
/// [zemin]: yuvarlatılmış kare degrade zemin de çizilsin mi.
void isaretCiz(Canvas c, AcilisIsaret isaret, {bool zemin = true}) {
  if (zemin) {
    const r = Rect.fromLTWH(0, 0, 64, 64);
    c.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(14.5)), Paint()..shader = isaretDegradesi(isaret).createShader(r));
  }
  _logoCiz(c, const Rect.fromLTWH(10.5, 10, 34, 36.4), Colors.white, 1);
  _rozetCiz(c, const Offset(46.5, 46.5), 9.6, isaret, halka: isaret == AcilisIsaret.posta ? const Color(0xFF4532BD) : const Color(0xFF181C2B));
}

/// Uygulama işareti (yuvarlatılmış kare). Giriş ekranı, yan menü başlığı.
class BogaIsaret extends StatelessWidget {
  const BogaIsaret({super.key, this.boyut = 56, this.isaret = AcilisIsaret.posta});
  final double boyut;
  final AcilisIsaret isaret;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: boyut,
    height: boyut,
    child: CustomPaint(painter: _IsaretBoyayici(isaret)),
  );
}

class _IsaretBoyayici extends CustomPainter {
  _IsaretBoyayici(this.isaret);
  final AcilisIsaret isaret;
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 64, s.height / 64);
    isaretCiz(c, isaret);
  }

  @override
  bool shouldRepaint(_IsaretBoyayici o) => o.isaret != isaret;
}

// ---------------------------------------------------------------------------------------------------------------

/// Marka açılışı. Posta: beyaz zemin, indigo logo. Yönetim: grafit zemin, beyaz logo + yeşil vurgu.
/// Bogahost logosunun sunucu sütunları alttan sırayla yükselir, iç göstergeleri dolar, taç çizilip dolar; rozet
/// yerine oturur, uygulama adı belirir. Bu sırada [hazirla] çalışır; bekleme uzarsa altta ince ilerleme çizgisi
/// akar. Bitince sonraki ekran yumuşak bir yakınlaşmayla açılır.
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key, required this.alt, required this.isaret, required this.hazirla, this.api});

  /// Uygulama adının altındaki aralıklı yazı ("POSTA", "YÖNETİM").
  final String alt;
  final AcilisIsaret isaret;

  /// Sonraki ekranı hazırlar. Hata fırlatırsa mesaj ve "Tekrar dene" gösterilir.
  final Future<Widget> Function() hazirla;

  /// Verilirse açılışta güncelleme denetlenir; zorunlu güncellemede uygulama yerine güncelleme ekranı açılır.
  final BogaApi? api;

  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> with TickerProviderStateMixin {
  static const _sure = 1900;
  late final _giris = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _sure),
  )..forward();
  late final _akis = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  late final _cikis = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  String? _hata;

  bool get _koyuZemin => widget.isaret == AcilisIsaret.yonetim;

  @override
  void initState() {
    super.initState();
    _basla();
  }

  Future<void> _girisiBitir() async {
    if (hareketAzalt(context)) {
      _giris.value = 1;
      return;
    }
    if (!_giris.isAnimating) return;
    final ms = ((1 - _giris.value) * _sure * .5).round();
    await _giris.animateTo(1, duration: Duration(milliseconds: ms)).orCancel.catchError((_) {});
  }

  Future<void> _basla() async {
    setState(() => _hata = null);
    final api = widget.api;
    final denetim = api == null
        ? Future<void>.value()
        : Guncelleme.denetle(api, zorla: true).timeout(const Duration(seconds: 4), onTimeout: () => null).then((_) {});
    Widget? sonraki;
    try {
      sonraki = await widget.hazirla();
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata = e is ApiHata ? e.mesaj : 'Uygulama başlatılamadı. Tekrar deneyin.');
      return;
    }
    await denetim;
    if (!mounted) return;
    if (api != null && Guncelleme.zorunlu.value) sonraki = ZorunluGuncellemeEkrani(api: api);
    await _girisiBitir();
    if (!mounted) return;
    await _cikis.forward();
    if (!mounted) return;
    final hedef = sonraki;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: Duration(milliseconds: hareketAzalt(context) ? 0 : 380),
        pageBuilder: (_, _, _) => hedef,
        transitionsBuilder: (_, a, _, child) {
          final e = Curves.easeOutCubic.transform(a.value);
          return Opacity(
            opacity: e,
            child: Transform.scale(scale: .965 + .035 * e, child: child),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _giris.dispose();
    _akis.dispose();
    _cikis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final koyu = _koyuZemin;
    final zemin = koyu ? Marka.grafit : Colors.white;
    final yazi = koyu ? Colors.white : const Color(0xFF111427);
    final soluk = koyu ? Colors.white.withValues(alpha: .55) : const Color(0xFF6B7189);
    final aksan = koyu ? Marka.yesil : Marka.mor;
    if (hareketAzalt(context) && _giris.value < 1) _giris.value = 1;
    return AnnotatedRegion(
      value: koyu ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: zemin,
        body: AnimatedBuilder(
          animation: Listenable.merge([_giris, _akis, _cikis]),
          builder: (context, _) {
            final t = _giris.value;
            final cik = Curves.easeInCubic.transform(_cikis.value);
            final yaziA = _aralik(t, .62, .92, Curves.easeOutCubic);
            final rozet = _aralik(t, .70, .98, Curves.elasticOut);
            final bekliyor = _hata == null && t >= 1;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _Zemin(aksan: aksan, koyu: koyu, t: t),
                  ),
                ),
                Center(
                  child: Opacity(
                    opacity: 1 - cik,
                    child: Transform.scale(
                      scale: 1 - .06 * cik,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 150,
                            height: 150,
                            child: CustomPaint(
                              painter: _AcilisLogo(t: t, rozet: rozet, isaret: widget.isaret, renk: koyu ? Colors.white : Marka.mor, halka: zemin),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Opacity(
                            opacity: yaziA,
                            child: Transform.translate(
                              offset: Offset(0, 10 * (1 - yaziA)),
                              child: Column(
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'Boga',
                                          style: gosterim(34, renk: yazi),
                                        ),
                                        TextSpan(
                                          text: 'Mail',
                                          style: gosterim(34, renk: aksan),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: aksan.withValues(alpha: koyu ? .16 : .10),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      widget.alt,
                                      style: TextStyle(
                                        fontFamily: 'packages/boga_ortak/Poppins',
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 3.2,
                                        color: aksan,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 30),
                          SizedBox(
                            width: 120,
                            height: 3,
                            child: AnimatedOpacity(
                              opacity: bekliyor ? 1 : 0,
                              duration: const Duration(milliseconds: 250),
                              child: CustomPaint(
                                painter: _Akis(faz: _akis.value, renk: aksan, iz: soluk.withValues(alpha: .18)),
                              ),
                            ),
                          ),
                          if (_hata != null) ...[
                            const SizedBox(height: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Text(
                                _hata!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: yazi.withValues(alpha: .85), fontSize: 14, height: 1.4),
                              ),
                            ),
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: aksan, foregroundColor: koyu ? Marka.grafit : Colors.white),
                              onPressed: _basla,
                              icon: const Icon(Simge.yenile),
                              label: const Text('Tekrar dene'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 22,
                  child: Opacity(
                    opacity: yaziA * (1 - cik),
                    child: Column(
                      children: [
                        Text(
                          'BOGAHOST',
                          style: TextStyle(fontSize: 11, letterSpacing: 4, fontWeight: FontWeight.w600, color: soluk),
                        ),
                        const SizedBox(height: 4),
                        SurumEtiketi(renk: soluk, ortala: true),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AcilisLogo extends CustomPainter {
  _AcilisLogo({required this.t, required this.rozet, required this.isaret, required this.renk, required this.halka});
  final double t, rozet;
  final AcilisIsaret isaret;
  final Color renk, halka;

  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 150);
    _logoCiz(c, const Rect.fromLTWH(30, 14, 84, 99.6), renk, t);
    _rozetCiz(c, const Offset(116, 112), 19, isaret, halka: halka, olcek: rozet);
  }

  @override
  bool shouldRepaint(_AcilisLogo o) => o.t != t || o.rozet != rozet || o.renk != renk;
}

/// Zemin: merkezde yumuşak vurgu ışığı + merkezden açılan, kenarlara doğru sönen nokta ızgarası.
class _Zemin extends CustomPainter {
  _Zemin({required this.aksan, required this.koyu, required this.t});
  final Color aksan;
  final bool koyu;
  final double t;

  @override
  void paint(Canvas c, Size s) {
    final m = Offset(s.width / 2, s.height / 2 - 40);
    final r = math.max(s.width, s.height) * .55;
    final isik = _aralik(t, 0, .6, Curves.easeOut);
    c.drawCircle(m, r, Paint()..shader = ui.Gradient.radial(m, r, [aksan.withValues(alpha: (koyu ? .22 : .10) * isik), aksan.withValues(alpha: 0)]));
    final taban = koyu ? Colors.white : const Color(0xFF111427);
    final nokta = Paint();
    const ara = 26.0;
    final gorunur = _aralik(t, .05, .5);
    for (double x = (s.width % ara) / 2; x < s.width; x += ara) {
      for (double y = (s.height % ara) / 2; y < s.height; y += ara) {
        final u = (Offset(x, y) - m).distance / r;
        if (u > gorunur * 1.4) continue;
        final a = (1 - u).clamp(0.0, 1.0);
        if (a <= 0) continue;
        nokta.color = taban.withValues(alpha: (koyu ? .09 : .06) * a);
        c.drawCircle(Offset(x, y), 1.1, nokta);
      }
    }
  }

  @override
  bool shouldRepaint(_Zemin o) => o.t != t || o.koyu != koyu;
}

/// Bekleme çizgisi: ince izde akan kısa vurgu parçası.
class _Akis extends CustomPainter {
  _Akis({required this.faz, required this.renk, required this.iz});
  final double faz;
  final Color renk, iz;
  @override
  void paint(Canvas c, Size s) {
    final h = s.height;
    final kap = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(h));
    c.drawRRect(kap, Paint()..color = iz);
    final w = s.width * .38;
    final x = -w + (s.width + w) * Curves.easeInOutSine.transform(faz);
    c.save();
    c.clipRRect(kap);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, h), Radius.circular(h)), Paint()..color = renk);
    c.restore();
  }

  @override
  bool shouldRepaint(_Akis o) => o.faz != faz;
}
