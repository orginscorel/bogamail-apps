import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'tema.dart';

/// Açılıştaki işaretin rozeti: posta → yeni ileti noktası, yönetim → kalkan.
enum AcilisIsaret { posta, yonetim }

bool hareketAzalt(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

/// Marka açılışı: gece laciverti zemin üzerinde parçacıklar toplanır, mor kutu açılır, zarf çizilir, kapağı kapanır,
/// rozet yerine oturur, parıltı geçer. Bu sırada [hazirla] çalışır (oturum kontrolü); bitince sonraki ekran ortadan
/// büyüyen daireyle açılır. Ağ beklerken işaretin çevresinde yörünge yayı döner.
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key, required this.alt, required this.isaret, required this.hazirla});

  /// İşaretin altındaki aralıklı yazı ("POSTA", "YÖNETİM").
  final String alt;
  final AcilisIsaret isaret;

  /// Sonraki ekranı hazırlar. Hata fırlatırsa mesaj ve "Tekrar dene" gösterilir.
  final Future<Widget> Function() hazirla;

  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> with TickerProviderStateMixin {
  static const _sure = 1800;
  late final _giris = AnimationController(vsync: this, duration: const Duration(milliseconds: _sure))..forward();
  late final _yorunge = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final _aurora = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();
  late final _cikis = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  String? _hata;

  @override
  void initState() {
    super.initState();
    _basla();
  }

  /// Hazırlık bitince koreografinin kalanını hızlandırarak bitirir; açılış veriden uzun sürmez.
  Future<void> _girisiBitir() async {
    if (hareketAzalt(context)) {
      _giris.value = 1;
      return;
    }
    if (!_giris.isAnimating) return;
    final ms = ((1 - _giris.value) * _sure * .45).round();
    await _giris.animateTo(1, duration: Duration(milliseconds: ms)).orCancel.catchError((_) {});
  }

  Future<void> _basla() async {
    setState(() => _hata = null);
    Widget? sonraki;
    try {
      sonraki = await widget.hazirla();
    } catch (e) {
      if (!mounted) return;
      setState(() => _hata = e is ApiHata ? e.mesaj : 'Uygulama başlatılamadı. Tekrar deneyin.');
      return;
    }
    if (!mounted) return;
    await _girisiBitir();
    if (!mounted) return;
    await _cikis.forward();
    if (!mounted) return;
    final hedef = sonraki;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: Duration(milliseconds: hareketAzalt(context) ? 0 : 420),
      pageBuilder: (_, _, _) => hedef,
      transitionsBuilder: (_, a, _, child) => ClipPath(clipper: _DaireAcilim(Curves.easeInOutCubic.transform(a.value)), child: child),
    ));
  }

  @override
  void dispose() {
    _giris.dispose();
    _yorunge.dispose();
    _aurora.dispose();
    _cikis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Marka.lacivert0,
        body: AnimatedBuilder(
          animation: Listenable.merge([_giris, _yorunge, _aurora, _cikis]),
          builder: (_, _) {
            final c = Curves.easeInCubic.transform(_cikis.value);
            return CustomPaint(
              painter: _AuroraCizer(t: _aurora.value, gir: _ara(_giris.value, 0, .4)),
              child: Center(
                child: Opacity(
                  opacity: 1 - c,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Transform.scale(
                      scale: 1 + .4 * c,
                      child: SizedBox(
                        width: 260,
                        height: 260,
                        child: CustomPaint(
                          painter: _IsaretCizer(t: _giris.value, yorunge: _yorunge.value, bekliyor: _hata == null, isaret: widget.isaret),
                        ),
                      ),
                    ),
                    _Yazi(t: _giris.value, alt: widget.alt),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 100,
                      child: _hata == null
                          ? Opacity(
                              opacity: _ara(_giris.value, .88, 1),
                              child: Text('Hazırlanıyor…', style: TextStyle(color: Colors.white.withValues(alpha: .5), fontSize: 12.5, letterSpacing: .4)),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(children: [
                                Text(_hata!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 14),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .12), foregroundColor: Colors.white),
                                  onPressed: _basla,
                                  icon: const Icon(Icons.refresh_rounded, size: 18),
                                  label: const Text('Tekrar dene'),
                                ),
                              ]),
                            ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [a,b] aralığını 0..1'e çevirir (dışı kırpılır).
double _ara(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _Yazi extends StatelessWidget {
  const _Yazi({required this.t, required this.alt});
  final double t;
  final String alt;
  @override
  Widget build(BuildContext context) {
    const kelime = 'BogaMail';
    final p = Curves.easeOutCubic.transform(_ara(t, .8, 1));
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < kelime.length; i++)
          Builder(builder: (_) {
            final h = Curves.easeOutBack.transform(_ara(t, .62 + i * .024, .8 + i * .024));
            return Opacity(
              opacity: h.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 16 * (1 - h)),
                child: Text(kelime[i], style: gosterim(30, renk: i < 4 ? Colors.white : const Color(0xFFC7D2FE))),
              ),
            );
          }),
      ]),
      const SizedBox(height: 3),
      Opacity(
        opacity: p,
        child: Text(alt, style: TextStyle(color: Marka.gok.withValues(alpha: .85), letterSpacing: 1 + 5 * p, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

/// Yavaşça dolaşan iki renk bulutu: zemin canlı ama sakin.
class _AuroraCizer extends CustomPainter {
  _AuroraCizer({required this.t, required this.gir});
  final double t, gir;
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..shader = Marka.gece.createShader(Offset.zero & s));
    if (gir <= 0) return;
    final a = t * math.pi * 2;
    void bulut(Offset m, double r, Color renk) {
      c.drawCircle(m, r, Paint()..shader = RadialGradient(colors: [renk.withValues(alpha: .42 * gir), renk.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: m, radius: r)));
    }

    final k = math.max(s.width, s.height);
    bulut(Offset(s.width * (.25 + .08 * math.sin(a)), s.height * (.22 + .05 * math.cos(a))), k * .55, Marka.mor);
    bulut(Offset(s.width * (.8 + .06 * math.cos(a * 1.3)), s.height * (.78 + .05 * math.sin(a))), k * .5, Marka.mavi);
    bulut(Offset(s.width * (.7 + .05 * math.sin(a * .7)), s.height * (.18 + .04 * math.sin(a * 1.6))), k * .28, Marka.gok);
  }

  @override
  bool shouldRepaint(_AuroraCizer o) => o.t != t || o.gir != gir;
}

/// İşaret sahnesi (64×64 birimlik kutu, 120 px):
///  0.00–0.40  dört yandan parçacıklar uçup zarfın köşelerine dizilir
///  0.25–0.50  mor-mavi kutu merkezden yaylanarak açılır
///  0.40–0.66  zarfın gövdesi çizilir
///  0.58–0.78  kapak yukarıdan kapanır
///  0.70–0.90  rozet yerine oturur (posta: yeni ileti noktası, yönetim: kalkan)
///  0.82–1.00  çapraz parıltı; sonra beklerken yörünge yayı döner
class _IsaretCizer extends CustomPainter {
  _IsaretCizer({required this.t, required this.yorunge, required this.bekliyor, required this.isaret});
  final double t, yorunge;
  final bool bekliyor;
  final AcilisIsaret isaret;

  static const _govde = Rect.fromLTWH(13, 19, 38, 27);

  static final List<({Offset hedef, Offset kaynak, double gecikme, double donus})> _parca = () {
    final r = math.Random(7);
    final hedefler = <Offset>[];
    for (var i = 0; i <= 6; i++) {
      hedefler.add(Offset(_govde.left + _govde.width * i / 6, _govde.top));
      hedefler.add(Offset(_govde.left + _govde.width * i / 6, _govde.bottom));
    }
    for (var i = 1; i < 4; i++) {
      hedefler.add(Offset(_govde.left, _govde.top + _govde.height * i / 4));
      hedefler.add(Offset(_govde.right, _govde.top + _govde.height * i / 4));
    }
    return [
      for (final h in hedefler)
        () {
          final aci = r.nextDouble() * math.pi * 2;
          final uzak = 70 + r.nextDouble() * 60;
          return (
            hedef: h,
            kaynak: const Offset(32, 32) + Offset(math.cos(aci), math.sin(aci)) * uzak,
            gecikme: r.nextDouble() * .16,
            donus: (r.nextDouble() - .5) * 6,
          );
        }(),
    ];
  }();

  @override
  void paint(Canvas c, Size s) {
    final merkez = s.center(Offset.zero);
    c.save();
    c.translate(merkez.dx - 60, merkez.dy - 60);
    c.scale(120 / 64);
    ciz64(c);
    c.restore();

    // Yörünge: beklerken işaretin çevresinde dönen kuyruklu yay + noktalar
    final yb = _ara(t, .84, 1);
    if (yb > 0 && bekliyor) {
      const r = 106.0;
      for (var i = 0; i < 24; i++) {
        final a = i / 24 * math.pi * 2;
        final gec = _ara(yb, i / 48, i / 48 + .5);
        c.drawCircle(merkez + Offset(math.cos(a), math.sin(a)) * r, i % 6 == 0 ? 1.6 : 1, Paint()..color = Colors.white.withValues(alpha: (i % 6 == 0 ? .45 : .2) * gec));
      }
      final bas = yorunge * math.pi * 2 - math.pi / 2;
      final yay = Rect.fromCircle(center: merkez, radius: r);
      c.drawArc(
        yay,
        bas - 1.8,
        1.8,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            transform: GradientRotation(bas - 1.8),
            colors: [Marka.lavanta.withValues(alpha: 0), Marka.gok.withValues(alpha: yb), Marka.gok.withValues(alpha: yb)],
            stops: const [0, .27, 1],
          ).createShader(yay),
      );
      final uc = merkez + Offset(math.cos(bas), math.sin(bas)) * r;
      c.drawCircle(uc, 7, Paint()..color = Marka.gok.withValues(alpha: .25 * yb));
      c.drawCircle(uc, 3.4, Paint()..color = Colors.white.withValues(alpha: yb));
    }
  }


  /// İşaretin 64×64 birimlik içeriği (simge üretimi de bunu kullanır). [zemin] false: mor kutu ve hale çizilmez.
  void ciz64(Canvas c, {bool zemin = true}) {
    final kutu = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(17));
    // Hale
    final hale = zemin ? _ara(t, .25, .7) : 0.0;
    if (hale > 0) {
      c.drawCircle(const Offset(32, 32), 46 + 6 * hale,
          Paint()..shader = RadialGradient(colors: [Marka.morAcik.withValues(alpha: .5 * hale), Marka.mor.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: const Offset(32, 32), radius: 54)));
    }

    // Kutu
    final z = Curves.easeOutBack.transform(_ara(t, .25, .5));
    if (z > 0 && zemin) {
      c.save();
      c.translate(32, 32);
      c.scale(z);
      c.translate(-32, -32);
      c.drawRRect(kutu, Paint()..shader = Marka.grad.createShader(const Rect.fromLTWH(0, 0, 64, 64)));
      // üst ışık
      c.drawRRect(kutu, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.center, colors: [Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: 0)]).createShader(const Rect.fromLTWH(0, 0, 64, 64)));
      c.restore();
    }

    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    // Zarf gövdesi: yuvarlatılmış dikdörtgen yolu ilerleyerek çizilir
    final g = Curves.easeInOutCubic.transform(_ara(t, .4, .66));
    if (g > 0) {
      final yol = Path()..addRRect(RRect.fromRectAndRadius(_govde, const Radius.circular(4.5)));
      for (final m in yol.computeMetrics()) {
        c.drawPath(m.extractPath(0, m.length * g), kalem);
      }
    }

    // Kapak: açık (tepe yukarıda) → kapalı (V aşağıda)
    final k = Curves.easeOutBack.transform(_ara(t, .58, .78));
    if (k > 0) {
      final tepeY = ui.lerpDouble(_govde.top - 12, _govde.top + 14, k)!;
      final kapak = Path()
        ..moveTo(_govde.left + 1.5, _govde.top + 1.5)
        ..lineTo(32, tepeY)
        ..lineTo(_govde.right - 1.5, _govde.top + 1.5);
      c.drawPath(kapak, kalem..color = Colors.white.withValues(alpha: _ara(t, .58, .64)));
      kalem.color = Colors.white;
    }

    // Uçan parçacıklar
    final sondur = _ara(t, .42, .6);
    if (sondur < 1) {
      for (final m in _parca) {
        final u = Curves.easeOutCubic.transform(_ara(t, m.gecikme, m.gecikme + .3));
        if (u <= 0) continue;
        final p = Offset.lerp(m.kaynak, m.hedef, u)!;
        c.save();
        c.translate(p.dx, p.dy);
        c.rotate(m.donus * (1 - u));
        final boy = 3.2 + 2.2 * (1 - u);
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: boy, height: boy), const Radius.circular(1)),
          Paint()..color = Color.lerp(Marka.gok, Colors.white, u)!.withValues(alpha: u.clamp(0, 1) * (1 - sondur)),
        );
        c.restore();
      }
    }

    // Rozet
    final rz = Curves.elasticOut.transform(_ara(t, .7, .92));
    if (rz > 0) {
      c.save();
      c.translate(50, 16);
      c.scale(rz);
      if (isaret == AcilisIsaret.posta) {
        c.drawCircle(Offset.zero, 8.5, Paint()..color = Marka.lacivert1);
        c.drawCircle(Offset.zero, 6.5, Paint()..color = Marka.gok);
        c.drawCircle(const Offset(-1.6, -1.8), 2, Paint()..color = Colors.white.withValues(alpha: .8));
      } else {
        final kalkan = Path()
          ..moveTo(0, -8)
          ..quadraticBezierTo(5, -6.5, 7, -6.5)
          ..quadraticBezierTo(7.5, 4, 0, 8.5)
          ..quadraticBezierTo(-7.5, 4, -7, -6.5)
          ..quadraticBezierTo(-5, -6.5, 0, -8)
          ..close();
        c.drawPath(kalkan, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..color = Marka.lacivert1);
        c.drawPath(kalkan, Paint()..color = Marka.zumrut);
        c.drawPath(
            Path()
              ..moveTo(-3, 0)
              ..lineTo(-.6, 2.6)
              ..lineTo(3.4, -2.4),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.8
              ..strokeCap = StrokeCap.round
              ..color = Colors.white);
      }
      c.restore();
    }

    // Parıltı
    final pr = _ara(t, .82, 1);
    if (pr > 0 && pr < 1) {
      c.save();
      c.clipRRect(kutu);
      final x = -40 + 150 * Curves.easeInOutCubic.transform(pr);
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 14, 0)
          ..lineTo(x - 10, 64)
          ..lineTo(x - 24, 64)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: .26),
      );
      c.restore();
    }
  }

  @override
  bool shouldRepaint(_IsaretCizer o) => o.t != t || o.yorunge != yorunge || o.bekliyor != bekliyor;
}

class _DaireAcilim extends CustomClipper<Path> {
  _DaireAcilim(this.v);
  final double v;
  @override
  Path getClip(Size s) {
    final r = math.sqrt(s.width * s.width + s.height * s.height) / 2 * v;
    return Path()..addOval(Rect.fromCircle(center: s.center(Offset.zero), radius: math.max(r, .1)));
  }

  @override
  bool shouldReclip(_DaireAcilim o) => o.v != v;
}

/// Uygulama simgesi ve küçük logolar için durağan işaret (açılışın son karesi).
class BogaIsaret extends StatelessWidget {
  const BogaIsaret({super.key, this.boyut = 56, this.isaret = AcilisIsaret.posta});
  final double boyut;
  final AcilisIsaret isaret;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: boyut,
        height: boyut,
        child: FittedBox(
          child: SizedBox(
            width: 130,
            height: 130,
            child: CustomPaint(painter: _IsaretCizer(t: 1, yorunge: 0, bekliyor: false, isaret: isaret)),
          ),
        ),
      );
}

/// Simge üretimi için: işaretin son karesini 64 birimlik alana çizer.
void isaretCiz(Canvas c, AcilisIsaret isaret, {bool zemin = true}) =>
    _IsaretCizer(t: 1, yorunge: 0, bekliyor: false, isaret: isaret).ciz64(c, zemin: zemin);
