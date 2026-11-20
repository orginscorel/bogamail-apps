import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/sohbet_servisi.dart';

/// Kişi avatarı + sağ altta çevrimiçi noktası (yeşil: çevrimiçi, sarı: uzakta).
class VarlikAvatari extends StatelessWidget {
  const VarlikAvatari({super.key, required this.kisi, this.boyut = 40});
  final SohbetKisi kisi;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final v = varlikMetni(kisi);
    final nokta = v.cevrimici ? Marka.zumrut : (v.uzakta ? Marka.kehribar : null);
    return SizedBox(
      width: boyut,
      height: boyut,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Avatar(kisi.gorunen, boyut: boyut, tohum: kisi.adres),
          if (nokta != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Semantics(
                label: v.metin,
                child: Container(
                  width: boyut * .3,
                  height: boyut * .3,
                  decoration: BoxDecoration(
                    color: nokta,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.r.kart, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Oda simgesi: birebirde karşı tarafın avatarı, grupta grup simgesi, kanalda #.
class OdaSimgesi extends StatelessWidget {
  const OdaSimgesi({super.key, required this.oda, this.boyut = 44});
  final SohbetOdasi oda;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (oda.birebir) {
      final k = oda.karsi(SohbetDurum.benId);
      if (k != null) return VarlikAvatari(kisi: k, boyut: boyut);
    }
    return Container(
      width: boyut,
      height: boyut,
      decoration: BoxDecoration(
        color: oda.kanal ? r.vurguYumusak : Avatar.renkFor(oda.id).withValues(alpha: .15),
        borderRadius: BorderRadius.circular(boyut * .3),
      ),
      alignment: Alignment.center,
      child: oda.kanal ? Text('#', style: gosterim(boyut * .48, renk: r.vurgu)) : Icon(Icons.groups_rounded, color: Avatar.renkFor(oda.id), size: boyut * .55),
    );
  }
}

/// Okunmamış sayısı hapı.
class SayiHapi extends StatelessWidget {
  const SayiHapi(this.sayi, {super.key});
  final int sayi;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 22),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: context.r.vurgu, borderRadius: BorderRadius.circular(20)),
    child: Text(
      sayi > 99 ? '99+' : '$sayi',
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800),
    ),
  );
}
