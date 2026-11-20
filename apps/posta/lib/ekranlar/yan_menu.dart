import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/simgeler.dart';
import '../veri/canli.dart';
import '../veri/durum.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/yardimci.dart';
import 'ayarlar.dart';
import 'hesaplar.dart';

/// Kenar menüsü: hesap başlığı + kota, klasörler (okunmamış sayılarıyla), görünümler, kullanıcı klasörleri, etiketler.
/// Geniş ekranda kenar çubuğu; telefonda "Klasörler" sekmesinin sayfası ([sayfa]).
class YanMenu extends StatelessWidget {
  const YanMenu({super.key, required this.sec, this.yeniIleti, this.cekmecede = false, this.sayfa = false});
  final ValueChanged<Konum> sec;
  final VoidCallback? yeniIleti;
  final bool cekmecede;

  /// Telefon sekmesi: başlık çubuğu var, seçili konum vurgulanmaz, Ayarlar alt sekmede olduğundan gösterilmez.
  final bool sayfa;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ListenableBuilder(
      listenable: PostaDurum.ben,
      builder: (context, _) {
        final d = PostaDurum.ben;
        final govde = Material(
          color: r.kart,
          child: SafeArea(
            right: false,
            top: !sayfa,
            child: Column(
              children: [
                const _HesapBasligi(),
                if (yeniIleti != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(onPressed: yeniIleti, icon: const Icon(Icons.edit_rounded, size: 19), label: const Text('Yeni ileti')),
                    ),
                  ),
                Expanded(
                  child: !d.yuklendi && d.hata == null
                      ? const Center(child: CircularProgressIndicator.adaptive())
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                          children: [
                            if (d.hata != null)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(d.hata!, style: const TextStyle(color: Marka.gul)),
                              ),
                            const _Bolum(baslik: 'Posta kutusu'),
                            for (final k in d.sistemKlasorleri) _klasorOgesi(context, k),
                            const _Bolum(baslik: 'Görünümler'),
                            _oge(context, Icons.mark_email_unread_outlined, 'Okunmamışlar', const Konum.gorunum('unread')),
                            _oge(context, Icons.star_border_rounded, 'Yıldızlı', const Konum.gorunum('starred')),
                            _oge(context, Icons.label_important_outline_rounded, 'Önemli', const Konum.gorunum('important')),
                            _oge(context, Icons.attach_file_rounded, 'Ekli iletiler', const Konum.gorunum('attachments')),
                            _oge(context, Icons.notifications_active_outlined, 'Takip edilenler', const Konum.gorunum('followup')),
                            _oge(context, Icons.all_inbox_rounded, 'Tüm postalar', const Konum.gorunum('all')),
                            _Bolum(
                              baslik: 'Klasörlerim',
                              eylem: IconButton(
                                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                                tooltip: 'Klasör oluştur',
                                onPressed: () => _klasorOlustur(context),
                              ),
                            ),
                            if (d.kullaniciKlasorleri.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                child: Text('Henüz klasör yok.', style: TextStyle(color: r.silik, fontSize: 13)),
                              ),
                            for (final k in d.kullaniciKlasorleri) _klasorOgesi(context, k, menu: true),
                            _Bolum(
                              baslik: 'Etiketler',
                              eylem: IconButton(
                                icon: const Icon(Icons.new_label_outlined, size: 20),
                                tooltip: 'Etiket oluştur',
                                onPressed: () => _etiketOlustur(context),
                              ),
                            ),
                            if (d.etiketler.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                                child: Text('Henüz etiket yok.', style: TextStyle(color: r.silik, fontSize: 13)),
                              ),
                            for (final e in d.etiketler)
                              _oge(context, Icons.label_rounded, e.ad, Konum.etiket(e.id), sayi: e.okunmamis, renk: etiketRengi(e.renk)),
                          ],
                        ),
                ),
                const Divider(),
                if (!sayfa && !cekmecede)
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Ayarlar'),
                    trailing: _canliIsareti(r),
                    onTap: () {
                      final nav = Navigator.of(context);
                      if (cekmecede) nav.pop();
                      nav.push(MaterialPageRoute<void>(builder: (_) => const AyarlarEkrani()));
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
                  child: Row(
                    children: [
                      const Expanded(child: SurumEtiketi()),
                      if (sayfa) _canliIsareti(r),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        if (!sayfa) return govde;
        return Scaffold(
          appBar: AppBar(title: const Text('Klasörler')),
          body: govde,
        );
      },
    );
  }

  Widget _canliIsareti(Renkler r) => ValueListenableBuilder<bool>(
    valueListenable: Canli.ben.bagli,
    builder: (_, b, _) => Tooltip(
      message: b ? 'Canlı güncelleme bağlı' : 'Canlı güncelleme bağlanıyor',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: b ? Marka.zumrut : r.kenar),
          const SizedBox(width: 6),
          Text(
            b ? 'Canlı' : 'Bağlanıyor',
            style: TextStyle(fontSize: 11.5, color: r.silik, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  Widget _klasorOgesi(BuildContext context, Klasor k, {bool menu = false}) {
    // Web ile aynı: taslak/şablon/ertelenen için toplam, gönderilen/çöp için sayı yok.
    final sayi = switch (k.rol) {
      'drafts' || 'templates' || 'snoozed' => k.toplam,
      'sent' || 'trash' => 0,
      _ => k.okunmamis,
    };
    final soluk = k.rol == 'drafts' || k.rol == 'templates' || k.rol == 'snoozed' || k.rol == 'junk';
    return _oge(
      context,
      klasorSimgesi(k.rol),
      k.gorunenAd,
      Konum.klasor(k.id),
      sayi: sayi,
      solukSayi: soluk,
      menu: menu ? _KlasorMenusu(klasor: k) : null,
    );
  }

  Widget _oge(BuildContext context, IconData ikon, String ad, Konum konum, {int sayi = 0, bool solukSayi = false, Color? renk, Widget? menu}) {
    final r = context.r;
    final aktif = !sayfa && PostaDurum.ben.konum == konum;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: aktif ? r.vurguYumusak : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (cekmecede) Navigator.of(context).pop();
            sec(konum);
          },
          child: Semantics(
            selected: aktif,
            label: sayi > 0 ? (solukSayi ? '$ad, $sayi ileti' : '$ad, $sayi okunmamış') : ad,
            excludeSemantics: true,
            button: true,
            child: SizedBox(
              height: sayfa ? 50 : 44,
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 3,
                    height: 22,
                    decoration: BoxDecoration(color: aktif ? r.vurgu : Colors.transparent, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 9),
                  Icon(ikon, size: 21, color: renk ?? (aktif ? r.vurgu : r.soluk)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: aktif || (sayi > 0 && !solukSayi) ? FontWeight.w700 : FontWeight.w500,
                        color: aktif ? r.vurgu : r.metin,
                      ),
                    ),
                  ),
                  if (sayi > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: solukSayi ? r.ic : r.vurgu, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        sayi > 999 ? '999+' : '$sayi',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: solukSayi ? r.soluk : Colors.white),
                      ),
                    ),
                  menu ?? const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _klasorOlustur(BuildContext context) async {
    final ad = await metinSor(context, 'Yeni klasör', ipucu: 'Klasör adı', tamam: 'Oluştur');
    if (ad == null || ad.trim().isEmpty) return;
    await islem(() => Posta.klasorOlustur(ad.trim()), tamam: 'Klasör oluşturuldu');
    PostaDurum.ben.sayilariYenile(listeler: false);
  }

  Future<void> _etiketOlustur(BuildContext context) async {
    final ad = TextEditingController();
    var renk = 'blue';
    final v = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => AlertDialog(
          title: Text('Yeni etiket', style: gosterim(19, agirlik: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ad,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(hintText: 'Etiket adı'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in etiketRenkleri.entries)
                    Tooltip(
                      message: etiketRenkAdlari[e.key] ?? e.key,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => yenile(() => renk = e.key),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: e.value,
                            shape: BoxShape.circle,
                            border: renk == e.key ? Border.all(color: c.r.metin, width: 2.5) : null,
                          ),
                          child: renk == e.key ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oluştur')),
          ],
        ),
      ),
    );
    final metin = ad.text.trim();
    ad.dispose();
    if (v != true || metin.isEmpty) return;
    await islem(() => Posta.etiketOlustur(metin, renk), tamam: 'Etiket oluşturuldu');
    PostaDurum.ben.sayilariYenile(listeler: false);
  }
}

class _Bolum extends StatelessWidget {
  const _Bolum({required this.baslik, this.eylem});
  final String baslik;
  final Widget? eylem;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 14, 0, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            baslik.toUpperCase(),
            style: TextStyle(color: context.r.silik, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ),
        ?eylem,
      ],
    ),
  );
}

class _KlasorMenusu extends StatelessWidget {
  const _KlasorMenusu({required this.klasor});
  final Klasor klasor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '${klasor.ad} seçenekleri',
      icon: Icon(Icons.more_horiz_rounded, size: 19, color: context.r.silik),
      onSelected: (v) async {
        final d = PostaDurum.ben;
        switch (v) {
          case 'ad':
            final ad = await metinSor(context, 'Klasörü yeniden adlandır', ilk: klasor.ad, ipucu: 'Klasör adı');
            if (ad == null || ad.trim().isEmpty || ad.trim() == klasor.ad) return;
            await islem(() => Posta.klasorAdlandir(klasor.id, ad.trim()), tamam: 'Klasör yeniden adlandırıldı');
            d.sayilariYenile(listeler: false);
          case 'okundu':
            await islem(() => Posta.klasorOkundu(klasor.id), tamam: 'Tümü okundu işaretlendi');
            d.sayilariYenile();
          case 'sil':
            if (!await onayla(
              context,
              '"${klasor.ad}" silinsin mi?',
              mesaj: klasor.toplam > 0 ? 'Klasördeki ${klasor.toplam} ileti Çöp Kutusu\'na taşınır.' : null,
              evet: 'Sil',
              tehlikeli: true,
            )) {
              return;
            }
            await islem(() => Posta.klasorSil(klasor.id), tamam: 'Klasör silindi');
            if (d.konum == Konum.klasor(klasor.id)) {
              final gelen = d.rolu('inbox');
              if (gelen != null) d.git(Konum.klasor(gelen.id));
            }
            d.sayilariYenile();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'ad',
          child: ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text('Yeniden adlandır')),
        ),
        PopupMenuItem(
          value: 'okundu',
          child: ListTile(leading: Icon(Icons.done_all_rounded), title: Text('Tümünü okundu işaretle')),
        ),
        PopupMenuItem(
          value: 'sil',
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: Marka.gul),
            title: Text('Klasörü sil'),
          ),
        ),
      ],
    );
  }
}

class _HesapBasligi extends StatelessWidget {
  const _HesapBasligi();

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: Uyg.kutu,
      builder: (_, k, _) {
        final ad = Uyg.ad.trim();
        final adres = Uyg.adres;
        final kota = (k?['quota_bytes'] as num?)?.toInt() ?? 0;
        final kullanilan = (k?['used_bytes'] as num?)?.toInt() ?? 0;
        final sinirsiz = sinirsizKota(kota);
        final oran = sinirsiz ? 0.0 : (kullanilan / kota).clamp(0.0, 1.0);
        final renk = oran >= .9 ? Marka.gul : (oran >= .75 ? Marka.kehribar : r.birincil);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(ad.isEmpty ? adres : ad, boyut: 46, tohum: adres),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ad.isEmpty ? adres : ad,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: gosterim(16, agirlik: FontWeight.w700),
                        ),
                        if (ad.isNotEmpty)
                          Text(
                            adres,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.silik, fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('hesap-degistir'),
                    tooltip: 'Hesap değiştir / ekle',
                    icon: const Icon(Icons.unfold_more_rounded),
                    onPressed: () => hesapSeciciAc(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Semantics(
                label: sinirsiz
                    ? 'Kota: ${boyutYaz(kullanilan)} kullanılıyor, sınırsız'
                    : 'Kota: ${boyutYaz(kota)} alanın ${boyutYaz(kullanilan)} kadarı kullanılıyor',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: sinirsiz ? 0 : oran, minHeight: 5, backgroundColor: r.ic, color: renk),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      sinirsiz ? '${boyutYaz(kullanilan)} kullanılıyor · Sınırsız' : '${boyutYaz(kullanilan)} / ${boyutYaz(kota)} (%${(oran * 100).round()})',
                      style: TextStyle(color: r.silik, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
