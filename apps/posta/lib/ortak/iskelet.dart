import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

/// Yüklenirken parıldayan yer tutucu.
class Parilti extends StatefulWidget {
  const Parilti({super.key, required this.child});
  final Widget child;
  @override
  State<Parilti> createState() => _ParildaState();
}

class _ParildaState extends State<Parilti> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final taban = r.ic;
    final parlak = r.koyu ? const Color(0xFF2C2A5A) : Colors.white;
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (_, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (b) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [taban, parlak, taban],
          stops: const [.25, .5, .75],
          transform: _Kaydir(_a.value),
        ).createShader(b),
        child: child,
      ),
    );
  }
}

class _Kaydir extends GradientTransform {
  const _Kaydir(this.t);
  final double t;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

class _Cubuk extends StatelessWidget {
  const _Cubuk({required this.en, this.boy = 12});
  final double en;
  final double boy;
  @override
  Widget build(BuildContext context) => Container(
    width: en,
    height: boy,
    decoration: BoxDecoration(color: context.r.ic, borderRadius: BorderRadius.circular(6)),
  );
}

/// İleti listesi iskeleti.
class ListeIskeleti extends StatelessWidget {
  const ListeIskeleti({super.key, this.satir = 9});
  final int satir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'İletiler yükleniyor',
      child: Parilti(
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: satir,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: context.r.ic, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Cubuk(en: 110.0 + (i % 3) * 30),
                          const Spacer(),
                          const _Cubuk(en: 36, boy: 10),
                        ],
                      ),
                      const SizedBox(height: 9),
                      _Cubuk(en: 200.0 + (i % 4) * 22),
                      const SizedBox(height: 7),
                      const _Cubuk(en: double.infinity, boy: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Okuyucu iskeleti.
class OkuyucuIskeleti extends StatelessWidget {
  const OkuyucuIskeleti({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'İleti yükleniyor',
      child: Parilti(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Cubuk(en: 280, boy: 22),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: context.r.ic, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_Cubuk(en: 150), SizedBox(height: 8), _Cubuk(en: 100, boy: 10)]),
                ],
              ),
              const SizedBox(height: 28),
              for (var i = 0; i < 7; i++) ...[_Cubuk(en: i == 6 ? 180 : double.infinity), const SizedBox(height: 12)],
            ],
          ),
        ),
      ),
    );
  }
}
