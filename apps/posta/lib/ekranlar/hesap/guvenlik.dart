import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../veri/hesap_servisi.dart';
import 'ortak.dart';

final _tarih = DateFormat('d MMM y HH:mm', 'tr_TR');
String _z(DateTime? d) => d == null ? '—' : _tarih.format(d);

// ---------------------------------------------------------------- şifre

class SifreEkrani extends StatefulWidget {
  const SifreEkrani({super.key});
  @override
  State<SifreEkrani> createState() => _SifreEkraniState();
}

class _SifreEkraniState extends State<SifreEkrani> {
  final _eski = TextEditingController();
  final _yeni = TextEditingController();
  final _tekrar = TextEditingController();
  bool _gizli = true;
  bool _mesgul = false;

  @override
  void dispose() {
    for (final c in [_eski, _yeni, _tekrar]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    if (_eski.text.isEmpty || _yeni.text.isEmpty) return bildir('Mevcut ve yeni şifreyi yazın', tur: MesajTur.uyari);
    if (_yeni.text != _tekrar.text) return bildir('Yeni şifreler eşleşmiyor', tur: MesajTur.uyari);
    setState(() => _mesgul = true);
    final ok = await islem(() async {
      await Hesap.sifreDegistir(_eski.text, _yeni.text);
      return true;
    }, tamam: 'Şifreniz değiştirildi');
    if (!mounted) return;
    setState(() => _mesgul = false);
    if (ok == true) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    InputDecoration d(String e) => InputDecoration(
      labelText: e,
      suffixIcon: IconButton(
        tooltip: _gizli ? 'Göster' : 'Gizle',
        icon: Icon(_gizli ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _gizli = !_gizli),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Şifre değiştir')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Kutu(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: _eski, obscureText: _gizli, autofillHints: const [AutofillHints.password], decoration: d('Mevcut şifre')),
                    const SizedBox(height: 12),
                    TextField(controller: _yeni, obscureText: _gizli, autofillHints: const [AutofillHints.newPassword], decoration: d('Yeni şifre')),
                    const SizedBox(height: 12),
                    TextField(controller: _tekrar, obscureText: _gizli, decoration: d('Yeni şifre (tekrar)')),
                    const SizedBox(height: 12),
                    Text(
                      'Şifre değişince diğer cihazlardaki oturumlar kapanır ve tüm uygulama şifreleri iptal edilir. '
                      'Telefonunuzdaki/bilgisayarınızdaki posta programlarında yeni şifreyi girmeniz gerekir.',
                      style: TextStyle(color: r.silik, fontSize: 12.5),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _mesgul ? null : _kaydet, child: const Text('Şifreyi değiştir')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- iki adımlı doğrulama

Future<String?> _kodSor(BuildContext context, String baslik) =>
    metinSor(context, baslik, ipucu: 'Doğrulama uygulamasındaki 6 haneli kod veya kurtarma kodu', tamam: 'Onayla');

class IkiAdimliEkrani extends StatelessWidget {
  const IkiAdimliEkrani({super.key});

  Future<void> _kur(BuildContext context, Future<void> Function() yenile) async {
    final k = await islem(Hesap.ikiAdimKur);
    if (k == null || !context.mounted) return;
    final kod = TextEditingController();
    final onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('İki adımlı doğrulamayı kur', style: gosterim(19, agirlik: FontWeight.w700)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1. Google Authenticator, Microsoft Authenticator gibi bir doğrulama uygulamasında "anahtar gir" seçeneğini açın ve aşağıdaki anahtarı ekleyin.',
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.r.ic, borderRadius: BorderRadius.circular(12)),
                  child: SelectableText(
                    k.gizli,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => kopyala(k.gizli, mesaj: 'Anahtar kopyalandı'),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Anahtarı kopyala'),
                    ),
                    TextButton.icon(
                      onPressed: () => kopyala(k.uri, mesaj: 'Bağlantı kopyalandı'),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('otpauth bağlantısı'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('2. Uygulamanın gösterdiği 6 haneli kodu yazın.'),
                const SizedBox(height: 8),
                TextField(
                  controller: kod,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '123456'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Etkinleştir')),
        ],
      ),
    );
    final metin = kod.text.trim();
    kod.dispose();
    if (onay != true || metin.isEmpty || !context.mounted) return;
    final kodlar = await islem(() => Hesap.ikiAdimAc(metin), tamam: 'İki adımlı doğrulama açıldı');
    if (kodlar != null && context.mounted) {
      await gizliGoster(
        context,
        'Kurtarma kodları',
        'Telefonunuza erişemezseniz bu kodlarla giriş yapabilirsiniz. Her kod bir kez kullanılır; güvenli bir yerde saklayın. Bu kodlar bir daha gösterilmez.',
        kodlar.join('\n'),
      );
    }
    await yenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<IkiAdimDurumu>(
    baslik: 'İki adımlı doğrulama',
    altBaslik: 'Girişte şifrenize ek olarak telefonunuzdaki doğrulama uygulamasından bir kod istenir.',
    yukle: Hesap.ikiAdim,
    govde: (context, d, yenile) {
      final r = context.r;
      return [
        Kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(d.acik ? Icons.verified_user_rounded : Icons.gpp_maybe_outlined, color: d.acik ? Marka.zumrut : Marka.kehribar, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.acik ? 'Açık' : 'Kapalı', style: gosterim(18, agirlik: FontWeight.w700)),
                        if (d.acik)
                          Text('${_z(d.acilis)} tarihinden beri · ${d.kurtarmaKalan} kurtarma kodu kaldı', style: TextStyle(color: r.soluk, fontSize: 13)),
                        if (d.zorunlu) Text('Kurumunuz iki adımlı doğrulamayı zorunlu tutuyor.', style: TextStyle(color: r.soluk, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!d.kullanilabilir)
                Text('Bu sunucuda iki adımlı doğrulama kullanılamıyor.', style: TextStyle(color: r.soluk))
              else if (!d.acik)
                FilledButton.icon(onPressed: () => _kur(context, yenile), icon: const Icon(Icons.lock_outline_rounded), label: const Text('Kur ve etkinleştir'))
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final kod = await _kodSor(context, 'Yeni kurtarma kodları');
                        if (kod == null || kod.isEmpty) return;
                        final l = await islem(() => Hesap.kurtarmaKodlari(kod));
                        if (l != null && context.mounted) await gizliGoster(context, 'Yeni kurtarma kodları', 'Eski kodlar artık geçersiz.', l.join('\n'));
                        await yenile();
                      },
                      icon: const Icon(Icons.key_rounded),
                      label: const Text('Kurtarma kodlarını yenile'),
                    ),
                    if (!d.zorunlu)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Marka.gul),
                        onPressed: () async {
                          final kod = await _kodSor(context, 'İki adımlı doğrulamayı kapat');
                          if (kod == null || kod.isEmpty) return;
                          await islem(() => Hesap.ikiAdimKapat(kod), tamam: 'İki adımlı doğrulama kapatıldı');
                          await yenile();
                        },
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Kapat'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ];
    },
  );
}

// ---------------------------------------------------------------- uygulama şifreleri

class UygulamaSifreleriEkrani extends StatelessWidget {
  const UygulamaSifreleriEkrani({super.key});

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<({List<UygulamaSifresi> ogeler, bool ikiAdim})>(
    baslik: 'Uygulama şifreleri',
    altBaslik: 'Outlook, Apple Mail, Thunderbird gibi posta programları için ayrı şifreler. Her birini ayrı ayrı iptal edebilirsiniz.',
    yukle: Hesap.uygulamaSifreleri,
    fab: (context, yenile) => FloatingActionButton.extended(
      onPressed: () async {
        final ad = await metinSor(context, 'Yeni uygulama şifresi', ipucu: 'Örn. iPhone Mail, Outlook (iş)', tamam: 'Oluştur');
        if (ad == null || ad.trim().isEmpty) return;
        final s = await islem(() => Hesap.uygulamaSifresiOlustur(ad));
        if (s != null && context.mounted) {
          await gizliGoster(
            context,
            'Uygulama şifresi oluşturuldu',
            '"${ad.trim()}" için bu şifreyi posta programınızdaki şifre alanına girin. Bir daha gösterilmez.',
            s,
          );
        }
        await yenile();
      },
      icon: const Icon(Icons.add_rounded),
      label: const Text('Şifre oluştur'),
    ),
    govde: (context, v, yenile) {
      final r = context.r;
      return [
        if (v.ogeler.isEmpty)
          const BosKart('Uygulama şifresi yok.', ikon: Icons.key_outlined)
        else
          KartListe(
            children: [
              for (final s in v.ogeler)
                ListTile(
                  leading: Icon(Icons.key_rounded, color: r.vurgu),
                  title: Text(s.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Oluşturma: ${_z(s.olusturma)}\n'
                    '${s.sonKullanim == null ? 'Hiç kullanılmadı' : 'Son kullanım: ${_z(s.sonKullanim)}${s.sonProtokol.isEmpty ? '' : ' · ${s.sonProtokol.toUpperCase()}'}${s.sonIp.isEmpty ? '' : ' · ${s.sonIp}'}'}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'İptal et',
                    icon: const Icon(Icons.delete_outline_rounded, color: Marka.gul),
                    onPressed: () async {
                      if (!await onayla(
                        context,
                        '"${s.ad}" iptal edilsin mi?',
                        mesaj: 'Bu şifreyi kullanan program artık bağlanamaz.',
                        evet: 'İptal et',
                        tehlikeli: true,
                      )) {
                        return;
                      }
                      await islem(() => Hesap.uygulamaSifresiSil(s.id), tamam: 'Uygulama şifresi iptal edildi');
                      await yenile();
                    },
                  ),
                ),
            ],
          ),
      ];
    },
  );
}

// ---------------------------------------------------------------- bağlı cihazlar (ActiveSync)

class CihazlarEkrani extends StatelessWidget {
  const CihazlarEkrani({super.key});

  Future<void> _temizle(BuildContext context, Cihaz c, Future<void> Function() yenile) async {
    final onay = TextEditingController();
    var tur = 'account';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, yenileD) => AlertDialog(
          title: Text('${c.gorunen} temizlensin mi?', style: gosterim(19, agirlik: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<String>(
                groupValue: tur,
                onChanged: (v) => yenileD(() => tur = v ?? 'account'),
                child: const Column(
                  children: [
                    RadioListTile(
                      value: 'account',
                      title: Text('Yalnızca bu hesabı kaldır'),
                      subtitle: Text('Cihazdaki posta, kişi ve takvim verisi silinir.'),
                    ),
                    RadioListTile(value: 'full', title: Text('Cihazı tamamen sıfırla'), subtitle: Text('Telefon fabrika ayarlarına döner. Geri alınamaz!')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text('Onaylamak için SİL yazın:'),
              const SizedBox(height: 6),
              TextField(controller: onay, autofocus: true),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Marka.gul),
              onPressed: () => Navigator.pop(d, onay.text.trim().toUpperCase() == 'SİL' || onay.text.trim() == 'SIL'),
              child: const Text('Temizle'),
            ),
          ],
        ),
      ),
    );
    onay.dispose();
    if (ok != true) return;
    await islem(() => Hesap.cihazTemizle(c.id, tur), tamam: 'Temizleme komutu gönderildi; cihaz bir sonraki eşitlemede uygular');
    await yenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<({List<Cihaz> ogeler, bool acik})>(
    baslik: 'Bağlı cihazlar',
    altBaslik: 'Exchange ActiveSync ile posta kutunuza bağlanan telefon ve tabletler. Kaybolan bir cihazı engelleyebilir veya uzaktan temizleyebilirsiniz.',
    yukle: Hesap.cihazlar,
    govde: (context, v, yenile) {
      final r = context.r;
      if (v.ogeler.isEmpty) return [const BosKart('Bağlı cihaz yok.', ikon: Icons.smartphone_outlined)];
      return [
        KartListe(
          children: [
            for (final c in v.ogeler)
              ListTile(
                leading: Icon(Icons.smartphone_rounded, color: c.durum == 'blocked' ? Marka.gul : r.vurgu),
                title: Text(c.gorunen, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text([c.isletim, 'Son eşitleme: ${_z(c.sonEsitleme)}'].where((s) => s.isNotEmpty).join(' · ')),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        if (c.durum == 'blocked') const Rozet('Engelli', renk: Marka.gul) else const Rozet('İzinli', renk: Marka.zumrut),
                        if (c.silmeIstendi != null) const Rozet('Temizleme bekliyor', renk: Marka.kehribar, ikon: Icons.cleaning_services_outlined),
                      ],
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  tooltip: 'Seçenekler',
                  onSelected: (s) async {
                    switch (s) {
                      case 'izin':
                        await islem(
                          () => Hesap.cihazDurumu(c.id, c.durum == 'blocked'),
                          tamam: c.durum == 'blocked' ? 'Cihaza izin verildi' : 'Cihaz engellendi',
                        );
                      case 'temizle':
                        await _temizle(context, c, yenile);
                        return;
                      case 'iptal':
                        await islem(() => Hesap.cihazTemizlemeIptal(c.id), tamam: 'Temizleme iptal edildi');
                      case 'sil':
                        if (!await onayla(
                          context,
                          'Cihaz listeden kaldırılsın mı?',
                          mesaj: 'Cihaz yeniden bağlanırsa listede tekrar görünür.',
                          evet: 'Kaldır',
                          tehlikeli: true,
                        )) {
                          return;
                        }
                        await islem(() => Hesap.cihazSil(c.id), tamam: 'Cihaz kaldırıldı');
                    }
                    await yenile();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'izin',
                      child: ListTile(
                        leading: Icon(c.durum == 'blocked' ? Icons.check_circle_outline_rounded : Icons.block_rounded),
                        title: Text(c.durum == 'blocked' ? 'İzin ver' : 'Engelle'),
                      ),
                    ),
                    if (c.silmeIstendi == null)
                      const PopupMenuItem(
                        value: 'temizle',
                        child: ListTile(
                          leading: Icon(Icons.cleaning_services_outlined, color: Marka.gul),
                          title: Text('Uzaktan temizle…'),
                        ),
                      )
                    else
                      const PopupMenuItem(
                        value: 'iptal',
                        child: ListTile(leading: Icon(Icons.undo_rounded), title: Text('Temizlemeyi iptal et')),
                      ),
                    const PopupMenuItem(
                      value: 'sil',
                      child: ListTile(leading: Icon(Icons.delete_outline_rounded), title: Text('Listeden kaldır')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ];
    },
  );
}

// ---------------------------------------------------------------- yönetici erişim kaydı

class YoneticiErisimiEkrani extends StatelessWidget {
  const YoneticiErisimiEkrani({super.key});

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<YoneticiErisimi>(
    baslik: 'Yönetici erişim kaydı',
    altBaslik: 'Kurum yöneticilerinin destek amacıyla posta kutunuza eriştiği her oturum burada kayıt altındadır.',
    yukle: Hesap.yoneticiErisimi,
    govde: (context, v, _) {
      final r = context.r;
      return [
        if (v.etkin.isNotEmpty) ...[
          const Baslik('Şu an etkin erişim'),
          KartListe(
            children: [
              for (final e in v.etkin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_rounded, color: Marka.kehribar),
                  title: Text(e.yonetici),
                  subtitle: Text('${_z(e.baslangic)} – ${_z(e.bitis)}'),
                ),
            ],
          ),
        ],
        const Baslik('Geçmiş'),
        if (v.olaylar.isEmpty)
          const BosKart('Yöneticiler posta kutunuza erişmedi.', ikon: Icons.verified_user_outlined)
        else
          KartListe(
            children: [
              for (final o in v.olaylar)
                ListTile(
                  leading: Icon(Icons.history_rounded, color: r.silik),
                  title: Text(o.yonetici),
                  subtitle: Text([_z(o.zaman), o.eylem, if (o.neden.isNotEmpty) 'Neden: ${o.neden}', if (o.ip.isNotEmpty) o.ip].join(' · ')),
                ),
            ],
          ),
      ];
    },
  );
}
