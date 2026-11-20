import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show QrKodu;
import '../veri/json.dart';
import 'taklit_islemleri.dart';

// Kendi hesabının iki adımlı doğrulaması (web: account/page.tsx; sunucu: mfa.go):
// POST /auth/mfa/setup → {secret, otpauth_uri, qr_svg}; POST /auth/mfa/enable {code} → {recovery_codes};
// POST /auth/mfa/disable {code}; POST /auth/mfa/recovery-codes {code} → {recovery_codes}.
// Müşteri görünümünde sunucu bu işlemleri reddeder.

Future<String?> _kodSor(BuildContext context, String baslik, {String? aciklama, String tamam = 'Onayla'}) {
  final k = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (aciklama != null) ...[Text(aciklama), const SizedBox(height: 12)],
          TextField(
            controller: k,
            autofocus: true,
            keyboardType: TextInputType.visiblePassword,
            decoration: const InputDecoration(labelText: 'Doğrulama ya da kurtarma kodu'),
            onSubmitted: (v) => Navigator.pop(c, v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, k.text.trim()), child: Text(tamam)),
      ],
    ),
  );
}

Future<void> _kodlariGoster(BuildContext context, List<String> kodlar) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (c) => AlertDialog(
    title: Text('Kurtarma kodları', style: gosterim(19, agirlik: FontWeight.w700)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Telefonunuza erişemezseniz bu kodlarla giriş yapabilirsiniz. Her kod bir kez kullanılır; güvenli bir yerde saklayın.'),
        KopyaKutusu(kodlar.join('\n'), mesaj: 'Kodlar kopyalandı'),
        const SizedBox(height: 10),
        const Bant('Bu kodlar yalnızca şimdi gösterilir.', renk: Marka.kehribar, ikon: Icons.key_rounded),
      ],
    ),
    actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Kaydettim'))],
  ),
);

/// İki adımlı doğrulamayı açar: kurulum anahtarı gösterilir, uygulamadaki kod doğrulanır, kurtarma kodları verilir.
Future<bool> mfaAc(BuildContext context) async {
  final Map<String, dynamic> k;
  try {
    k = harita(await Uyg.api.post('/api/v1/auth/mfa/setup'));
  } catch (e) {
    bildir('Kurulum başlatılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    return false;
  }
  if (!context.mounted) return false;
  final gizli = metin(k['secret']);
  final uri = metin(k['otpauth_uri']);
  final kod = TextEditingController();
  String? hata;
  var mesgul = false;
  final kodlar = await showDialog<List<String>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => AlertDialog(
        title: Text('İki adımlı doğrulamayı aç', style: gosterim(19, agirlik: FontWeight.w700)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('1. Doğrulayıcı uygulamanızla (Google Authenticator, Microsoft Authenticator, 1Password…) bu QR kodunu okutun '
                    'ya da anahtarı elle ekleyin:'),
                if (uri.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Center(child: QrKodu(uri, boyut: 200)),
                  const SizedBox(height: 8),
                ],
                KopyaKutusu(gizli, mesaj: 'Anahtar kopyalandı'),
                if (uri.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        try {
                          if (!await adresAc(Uri.parse(uri))) await kopyala(uri, mesaj: 'Kurulum bağlantısı kopyalandı');
                        } catch (_) {
                          await kopyala(uri, mesaj: 'Kurulum bağlantısı kopyalandı');
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Doğrulayıcı uygulamada aç'),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text('2. Uygulamanın gösterdiği 6 haneli kodu yazın:'),
                const SizedBox(height: 8),
                TextField(
                  controller: kod,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(labelText: 'Doğrulama kodu', errorText: hata, counterText: ''),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: mesgul ? null : () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: mesgul
                ? null
                : () async {
                    yenile(() {
                      mesgul = true;
                      hata = null;
                    });
                    try {
                      final v = harita(await Uyg.api.post('/api/v1/auth/mfa/enable', {'code': kod.text.trim()}));
                      if (c.mounted) Navigator.pop(c, metinler(v['recovery_codes']));
                    } catch (e) {
                      yenile(() {
                        mesgul = false;
                        hata = hataMetni(e);
                      });
                    }
                  },
            child: const Text('Doğrula ve aç'),
          ),
        ],
      ),
    ),
  );
  if (kodlar == null) return false;
  bildir('İki adımlı doğrulama açıldı', tur: MesajTur.basari);
  if (kodlar.isNotEmpty && context.mounted) await _kodlariGoster(context, kodlar);
  return true;
}

/// İki adımlı doğrulamayı kapatır (geçerli kod ister).
Future<bool> mfaKapat(BuildContext context) async {
  final kod = await _kodSor(context, 'İki adımlı doğrulama kapatılsın mı?', aciklama: 'Hesabınız yalnızca şifreyle korunur. Onaylamak için güncel kodu yazın.', tamam: 'Kapat');
  if (kod == null || kod.isEmpty) return false;
  return await islem(() => Uyg.api.post('/api/v1/auth/mfa/disable', {'code': kod}).then((_) => true), tamam: 'İki adımlı doğrulama kapatıldı') == true;
}

/// Yeni kurtarma kodları üretir (eskiler geçersiz olur).
Future<void> mfaKodlariYenile(BuildContext context) async {
  final kod = await _kodSor(context, 'Yeni kurtarma kodları', aciklama: 'Eski kodlar geçersiz olur. Onaylamak için güncel kodu yazın.', tamam: 'Üret');
  if (kod == null || kod.isEmpty) return;
  final v = await islem(() => Uyg.api.post('/api/v1/auth/mfa/recovery-codes', {'code': kod}));
  if (v != null && context.mounted) await _kodlariGoster(context, metinler(harita(v)['recovery_codes']));
}
