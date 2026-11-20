// Bildirim izni tanıtımı (girişten sonra), izin kapalı / pil kısıtlı bandı ve Ayarlar'daki arka plan kartı.
// Metinler posta uygulamasıyla aynıdır (bkz. /root/bogamail-isler/posta-koordinasyon.md).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../oturum.dart';
import '../ortak/simgeler.dart';
import '../veri/arkaplan.dart';
import '../veri/bildirim.dart';

const _pilSoruldu = 'yonetim.pil.soruldu';
bool _buOturumdaSoruldu = false;

/// Testler: tanıtım bu süreçte yeniden gösterilebilsin.
@visibleForTesting
void bildirimTanitimiSifirla() => _buOturumdaSoruldu = false;

/// Kabuk açıldıktan sonra çağrılır: izin henüz sorulmadıysa tanıtıp sistem penceresini açar; Android'de izin
/// verildiyse ve uygulama pil kısıtlamasındaysa (bir kez) muafiyet ister. Müşteri görünümünde sorulmaz.
Future<void> bildirimTanitimi(BuildContext context) async {
  if (Uyg.taklit != null || _buOturumdaSoruldu) return;
  _buOturumdaSoruldu = true;
  var d = await Bildirim.yenile();
  if (!context.mounted) return;
  if (d == IzinDurumu.sorulmadi) {
    final evet = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        icon: Icon(Simgeler.notificationsActive, size: 32, color: c.r.birincil),
        title: const Text('Bildirimleri açın'),
        content: const Text(
          'Kritik alarmları, kuyruk birikmesini ve güvenlik olaylarını anında haber verebilmemiz için bildirim izni '
          'gerekiyor. Uygulama kapalıyken de bildirim alırsınız.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Şimdi değil')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bildirimlere izin ver')),
        ],
      ),
    );
    if (evet != true) return;
    await Bildirim.platform.izinIste();
    d = await Bildirim.yenile();
    if (!context.mounted) return;
  }
  if (d != IzinDurumu.verildi || !Arkaplan.platform.android || Bildirim.pilMuaf.value) return;
  try {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_pilSoruldu) ?? false) return;
    await p.setBool(_pilSoruldu, true);
  } catch (_) {}
  if (!context.mounted) return;
  if (await pilMuafiyetiSor(context)) await Bildirim.yenile();
}

/// Android: pil kısıtlaması açıklaması + sistem penceresi. Dönüş: sistem penceresi açıldı mı.
Future<bool> pilMuafiyetiSor(BuildContext context) async {
  final evet = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      scrollable: true,
      icon: Icon(Simgeler.bolt, size: 32, color: c.r.birincil),
      title: const Text('Arka planda bağlı kalın'),
      content: const Text(
        'Android\'in pil tasarrufu uygulamayı uyutabilir ve alarmlar gecikebilir. '
        'BogaMail Yönetim\'i pil kısıtlamasından muaf tutun.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Şimdi değil')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Muaf tut')),
      ],
    ),
  );
  if (evet != true) return false;
  await Bildirim.platform.pilMuafiyetiIste();
  return true;
}

/// Kabuğun üstündeki uyarı bandı: bildirim izni kapalıysa "Ayarları aç"; Android'de pil kısıtlıysa "Muaf tut".
class BildirimBandi extends StatelessWidget {
  const BildirimBandi({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IzinDurumu?>(
      valueListenable: Bildirim.durum,
      builder: (context, d, _) => ValueListenableBuilder<bool>(
        valueListenable: Bildirim.pilMuaf,
        builder: (context, muaf, _) => ValueListenableBuilder<bool>(
          valueListenable: Arkaplan.surekliBagli,
          builder: (context, bagli, _) {
            if (Uyg.taklit != null) return const SizedBox.shrink();
            if (d == IzinDurumu.reddedildi) {
              return _bant(
                context,
                Simgeler.notificationsOff,
                'Bildirimler kapalı: alarmları kaçırabilirsiniz.',
                'Ayarları aç',
                () => Bildirim.platform.ayarlariAc(),
              );
            }
            if (d == IzinDurumu.verildi && Arkaplan.platform.android && bagli && !muaf) {
              return _bant(context, Simgeler.bolt, 'Pil kısıtlaması açık: arka planda alarmlar gecikebilir.', 'Muaf tut', () async {
                await Bildirim.platform.pilMuafiyetiIste();
                await Bildirim.yenile();
              });
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _bant(BuildContext context, IconData ikon, String yazi, String eylem, VoidCallback f) {
    const renk = Marka.kehribar;
    return Material(
      color: renk.withValues(alpha: .12),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(ikon, size: 20, color: renk),
              const SizedBox(width: 12),
              Expanded(child: Text(yazi, style: TextStyle(fontSize: 13, color: context.r.metin))),
              TextButton(onPressed: f, child: Text(eylem)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ayarlar → Bildirimler: izin durumu ve arka planda çalışma (platforma göre).
class ArkaplanKarti extends StatefulWidget {
  const ArkaplanKarti({super.key});

  @override
  State<ArkaplanKarti> createState() => _ArkaplanKartiState();
}

class _ArkaplanKartiState extends State<ArkaplanKarti> {
  @override
  void initState() {
    super.initState();
    Bildirim.yenile();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ap = Arkaplan.platform;
    return ListenableBuilder(
      listenable: Listenable.merge([Bildirim.durum, Bildirim.pilMuaf, Arkaplan.surekliBagli, Arkaplan.giristeBaslat]),
      builder: (context, _) {
        final d = Bildirim.durum.value;
        final satirlar = <Widget>[
          if (d != null && d != IzinDurumu.gerekmiyor)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                d == IzinDurumu.verildi ? Simgeler.notificationsActive : Simgeler.notificationsOff,
                color: d == IzinDurumu.verildi ? Marka.zumrut : Marka.kehribar,
              ),
              title: Text(d == IzinDurumu.verildi ? 'Bildirim izni açık' : 'Bildirim izni kapalı'),
              subtitle: Text(
                d == IzinDurumu.reddedildi ? 'Sistem ayarlarından BogaMail Yönetim için bildirimlere izin verin.' : 'Alarmlar bu cihaza bildirim olarak gelir.',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
              trailing: switch (d) {
                IzinDurumu.reddedildi => TextButton(onPressed: Bildirim.platform.ayarlariAc, child: const Text('Ayarları aç')),
                IzinDurumu.sorulmadi => FilledButton(
                  onPressed: () async {
                    await Bildirim.platform.izinIste();
                    await Bildirim.yenile();
                  },
                  child: const Text('İzin ver'),
                ),
                _ => null,
              },
            ),
          if (ap.android) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: Arkaplan.surekliBagli.value,
              onChanged: Arkaplan.surekliBagliAyarla,
              title: const Text('Sürekli bağlı kal'),
              subtitle: Text(
                'Bildirim çubuğunda sessiz "BogaMail Yönetim bağlı" bildirimi görünür; alarmlar uygulama kapalıyken ve '
                'telefon yeniden başladıktan sonra da gelir.',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Simgeler.bolt, color: Bildirim.pilMuaf.value ? Marka.zumrut : Marka.kehribar),
              title: Text(Bildirim.pilMuaf.value ? 'Pil kısıtlamasından muaf' : 'Pil kısıtlaması açık'),
              subtitle: Text(
                Bildirim.pilMuaf.value ? 'Android uygulamayı arka planda uyutmaz.' : 'Android uygulamayı uyutabilir; alarmlar gecikebilir.',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
              trailing: Bildirim.pilMuaf.value
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await Bildirim.platform.pilMuafiyetiIste();
                        await Bildirim.yenile();
                      },
                      child: const Text('Muaf tut'),
                    ),
            ),
          ],
          if (ap.giristeBaslatVar)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: Arkaplan.giristeBaslat.value,
              onChanged: Arkaplan.giristeBaslatAyarla,
              title: const Text('Oturum açıldığında başlat'),
              subtitle: Text(
                ap.windows
                    ? 'Bilgisayar açılınca sistem tepsisinde başlar. Pencereyi kapatınca uygulama tepside çalışmayı sürdürür.'
                    : 'Mac\'e giriş yapınca başlar. Pencereyi kapatınca uygulama arka planda çalışmayı sürdürür.',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
            ),
        ];
        if (satirlar.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Kutu(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: satirlar),
          ),
        );
      },
    );
  }
}
