// Ayarlar › Arka planda çalışma: Android "Sürekli bağlı kal" (ön plan hizmeti), pil kısıtlaması ve üretici yardımı;
// Windows / macOS "Oturum açıldığında başlat". Varsayılanlar açık.

import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/arkaplan.dart';
import '../../veri/bildirim_izni.dart';

class ArkaplanAyari extends StatefulWidget {
  const ArkaplanAyari({super.key});

  /// Bu platformda gösterilecek bir şey var mı.
  static bool get gerekli => Arkaplan.platform.android || Arkaplan.platform.giristeBaslatVar;

  @override
  State<ArkaplanAyari> createState() => _ArkaplanAyariState();
}

class _ArkaplanAyariState extends State<ArkaplanAyari> {
  bool? _pilMuaf;

  @override
  void initState() {
    super.initState();
    unawaited(_tazele());
  }

  Future<void> _tazele() async {
    final m = await Arkaplan.platform.pilMuaf();
    if (mounted) setState(() => _pilMuaf = m);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final p = Arkaplan.platform;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const BildirimIzniBandi(kenar: EdgeInsets.only(bottom: 12)),
        if (p.android) ...[
          ValueListenableBuilder<bool>(
            valueListenable: Arkaplan.surekliBagli,
            builder: (_, v, _) => SwitchListTile.adaptive(
              key: const ValueKey('surekli-bagli'),
              contentPadding: EdgeInsets.zero,
              value: v,
              onChanged: (x) => unawaited(Arkaplan.surekliBagliAyarla(x)),
              title: const Text('Sürekli bağlı kal'),
              subtitle: const Text(
                'Uygulama kapalıyken de tüm hesaplarınızın yeni e-postaları ve sohbet iletileri anında bildirilir. '
                'Bildirim çubuğunda sessiz bir "BogaMail bağlı" bildirimi görünür.',
              ),
            ),
          ),
          if (_pilMuaf == false)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Simge.pil, color: Marka.kehribar),
              title: const Text('Pil kısıtlaması açık'),
              subtitle: const Text('Android uygulamayı uyutabilir; bildirimler gecikebilir.'),
              trailing: FilledButton.tonal(
                onPressed: () async {
                  await p.pilMuafiyetiIste();
                  await _tazele();
                  BildirimIzni.pilKisitli.value = !(_pilMuaf ?? true);
                },
                child: const Text('Muaf tut'),
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Simge.bilgi, color: r.soluk),
            title: const Text('Telefonum uygulamayı kapatıyor'),
            subtitle: const Text('Xiaomi, Huawei, Oppo, Samsung gibi üreticilerde otomatik başlatma ayarı'),
            onTap: () => BildirimIzni.otomatikBaslatmaYardimiAc(context),
          ),
        ],
        if (p.giristeBaslatVar)
          ValueListenableBuilder<bool>(
            valueListenable: Arkaplan.giristeBaslat,
            builder: (_, v, _) => SwitchListTile.adaptive(
              key: const ValueKey('giriste-baslat'),
              contentPadding: EdgeInsets.zero,
              value: v,
              onChanged: (x) => unawaited(Arkaplan.giristeBaslatAyarla(x)),
              title: const Text('Oturum açıldığında başlat'),
              subtitle: Text(
                p.windows
                    ? 'BogaMail bilgisayar açılınca sistem tepsisinde başlar. Pencereyi kapatınca tepside çalışmayı sürdürür.'
                    : 'BogaMail Mac\'e giriş yapınca başlar. Pencereyi kapatınca çalışmayı sürdürür; tamamen çıkmak için ⌘Q.',
              ),
            ),
          ),
      ],
    );
  }
}
