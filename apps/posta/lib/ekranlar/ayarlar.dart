import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../oturum.dart';
import '../veri/bildirim.dart';
import '../veri/canli.dart';
import '../veri/durum.dart';
import '../veri/html_temizle.dart';
import '../veri/modeller.dart';
import '../veri/posta_servisi.dart';
import '../veri/tercihler.dart';
import '../veri/yardimci.dart';

class AyarlarEkrani extends StatefulWidget {
  const AyarlarEkrani({super.key});
  @override
  State<AyarlarEkrani> createState() => _AyarlarEkraniState();
}

class _AyarlarEkraniState extends State<AyarlarEkrani> {
  PostaAyarlari? _a;
  String? _hata;
  final _ad = TextEditingController();
  final _imza = TextEditingController();
  final _tatilKonu = TextEditingController();
  final _tatilMetin = TextEditingController();
  bool _tatil = false;
  String? _tatilBas;
  String? _tatilBit;
  int _geriAl = 0;
  bool _kaydediliyor = false;
  bool _profilKirli = false;
  bool _tatilKirli = false;

  // bildirimler
  Map<String, dynamic>? _push;
  bool _izin = true;
  bool _arkaPlan = true;

  @override
  void initState() {
    super.initState();
    _yukle();
    _bildirimDurumu();
    for (final c in [_ad, _imza]) {
      c.addListener(() {
        if (!_profilKirli) setState(() => _profilKirli = true);
      });
    }
    for (final c in [_tatilKonu, _tatilMetin]) {
      c.addListener(() {
        if (!_tatilKirli) setState(() => _tatilKirli = true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_ad, _imza, _tatilKonu, _tatilMetin]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    setState(() => _hata = null);
    try {
      final a = await Posta.ayarlar();
      if (!mounted) return;
      PostaDurum.ben.ayarlar = a;
      setState(() {
        _a = a;
        _ad.text = a.gorunenAd;
        _imza.text = a.imza.isNotEmpty ? a.imza : (a.imzaHtml.isNotEmpty ? htmlMetne(a.imzaHtml) : '');
        _tatil = a.tatilAcik;
        _tatilKonu.text = a.tatilKonu;
        _tatilMetin.text = a.tatilMetin;
        _tatilBas = a.tatilBaslangic;
        _tatilBit = a.tatilBitis;
        _geriAl = a.geriAlmaSaniye;
        _profilKirli = false;
        _tatilKirli = false;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _bildirimDurumu() async {
    if (Push.destekli) {
      try {
        final p = await Posta.pushBilgi();
        if (mounted) setState(() => _push = p);
      } catch (_) {}
    }
    if (Bildirim.android) {
      final i = await Bildirim.izinVar();
      final a = await Bildirim.arkaPlanAcik();
      if (mounted) {
        setState(() {
          _izin = i;
          _arkaPlan = a;
        });
      }
    }
  }

  Future<void> _kaydet(Map<String, dynamic> degisen, String tamam) async {
    setState(() => _kaydediliyor = true);
    try {
      await Posta.ayarKaydet(degisen);
      bildir(tamam, tur: MesajTur.basari);
      await _yukle();
      unawaited(Posta.kutuYenile());
    } catch (e) {
      bildir('Kaydedilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  bool get _zenginImza {
    final a = _a;
    if (a == null || a.imzaHtml.trim().isEmpty) return false;
    return a.imzaHtml.trim() != metindenHtml(a.imza.trim());
  }

  Future<void> _profilKaydet() async {
    final a = _a!;
    final d = <String, dynamic>{};
    if (_ad.text.trim() != a.gorunenAd) d['display_name'] = _ad.text.trim();
    final imza = _imza.text.trimRight();
    final eskiImza = a.imza.isNotEmpty ? a.imza : htmlMetne(a.imzaHtml);
    if (!a.imzaKilitli && imza != eskiImza) {
      if (_zenginImza &&
          !await onayla(
            context,
            'Biçimli imza değiştirilsin mi?',
            mesaj: 'Web postasında tasarladığınız biçimli imza (görseller, renkler) bu düz metin imzayla değiştirilecek.',
            evet: 'Değiştir',
          )) {
        return;
      }
      d['signature'] = imza;
      d['signature_html'] = imza.isEmpty ? '' : metindenHtml(imza);
    }
    if (d.isEmpty) {
      setState(() => _profilKirli = false);
      return;
    }
    await _kaydet(d, 'Profil kaydedildi');
  }

  Future<void> _tatilKaydet() async {
    if (_tatil && _tatilMetin.text.trim().isEmpty) {
      bildir('Otomatik yanıt metnini yazın', tur: MesajTur.uyari);
      return;
    }
    await _kaydet({
      'vacation_enabled': _tatil,
      'vacation_subject': _tatilKonu.text.trim(),
      'vacation_body': _tatilMetin.text,
      'vacation_start': _tatilBas ?? '',
      'vacation_end': _tatilBit ?? '',
    }, _tatil ? 'Otomatik yanıt açıldı' : 'Otomatik yanıt kaydedildi');
  }

  Future<void> _tarihSec(bool baslangic) async {
    final simdi = DateTime.now();
    final mevcut = DateTime.tryParse((baslangic ? _tatilBas : _tatilBit) ?? '');
    final t = await showDatePicker(
      context: context,
      firstDate: DateTime(simdi.year - 1),
      lastDate: DateTime(simdi.year + 3),
      initialDate: mevcut ?? simdi,
      helpText: baslangic ? 'Başlangıç tarihi' : 'Bitiş tarihi',
    );
    if (t == null) return;
    final s = DateFormat('yyyy-MM-dd').format(t);
    setState(() {
      if (baslangic) {
        _tatilBas = s;
      } else {
        _tatilBit = s;
      }
      _tatilKirli = true;
    });
  }

  Future<void> _cikis() async {
    if (!await onayla(context, 'Çıkış yapılsın mı?', mesaj: 'Bu cihazdaki oturumunuz kapatılır ve bildirimler durur.', evet: 'Çıkış yap', tehlikeli: true)) {
      return;
    }
    Canli.ben.durdur();
    await Bildirim.temizle();
    PostaDurum.ben.sifirla();
    await Uyg.cikis();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        bottom: _kaydediliyor ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: _hata != null
          ? Durum.hata(_hata!, tekrar: _yukle)
          : _a == null
          ? const Durum.yukleniyor()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: _bolumler()),
              ),
            ),
    );
  }

  List<Widget> _bolumler() {
    final r = context.r;
    final a = _a!;
    return [
      const Baslik('Hesap'),
      _hesap(),
      const Baslik('Profil ve imza'),
      Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ad,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Görünen ad', counterText: ''),
            ),
            const SizedBox(height: 12),
            if (a.imzaKilitli) ...[
              Text(
                'İmza',
                style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
                child: Text(htmlMetne(a.etkinImzaHtml), style: TextStyle(color: r.soluk)),
              ),
              const SizedBox(height: 6),
              Text('İmzanız kurumunuzun şablonuyla belirleniyor ve değiştirilemez.', style: TextStyle(color: r.silik, fontSize: 12.5)),
            ] else ...[
              TextField(
                controller: _imza,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'İmza', alignLabelWithHint: true, hintText: 'Yeni iletilerin altına eklenir'),
              ),
              if (_zenginImza)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Web postasında biçimli bir imza tasarlamışsınız; burada düz metin hâli gösteriliyor.',
                    style: TextStyle(color: r.silik, fontSize: 12.5),
                  ),
                ),
              if (a.imzaKurumdan && !_zenginImza)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Kendi imzanız boşsa kurumunuzun imza şablonu kullanılır.', style: TextStyle(color: r.silik, fontSize: 12.5)),
                ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _profilKirli && !_kaydediliyor ? _profilKaydet : null, child: const Text('Kaydet')),
            ),
          ],
        ),
      ),
      const Baslik('Görünüm'),
      Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tema',
              style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: temaKipi,
              builder: (_, k, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto_outlined)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {k},
                onSelectionChanged: (s) => Tercihler.temaAyarla(s.first),
              ),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: Tercihler.uzakGorseller,
              builder: (_, v, _) => SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: v,
                onChanged: Tercihler.uzakGorselAyarla,
                title: const Text('Uzak görselleri otomatik göster'),
                subtitle: const Text('Görseller sunucu üzerinden alınır; gönderen IP adresinizi görmez. Gereksiz ve uyarılı iletilerde yine sorulur.'),
              ),
            ),
          ],
        ),
      ),
      const Baslik('Bildirimler'),
      _bildirimler(),
      const Baslik('Gönderim'),
      Kutu(
        child: Row(
          children: [
            const Expanded(child: Text('Gönderimi geri alma süresi')),
            DropdownButton<int>(
              value: const [0, 5, 10, 20, 30].contains(_geriAl) ? _geriAl : 0,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Kapalı')),
                DropdownMenuItem(value: 5, child: Text('5 saniye')),
                DropdownMenuItem(value: 10, child: Text('10 saniye')),
                DropdownMenuItem(value: 20, child: Text('20 saniye')),
                DropdownMenuItem(value: 30, child: Text('30 saniye')),
              ],
              onChanged: _kaydediliyor ? null : (v) => _kaydet({'undo_send_seconds': v ?? 0}, 'Geri alma süresi kaydedildi'),
            ),
          ],
        ),
      ),
      const Baslik('Otomatik yanıt'),
      _tatilBolumu(),
      const Baslik('Hakkında'),
      Kutu(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Sunucu'),
              subtitle: Text(Uyg.api.sunucu),
              onTap: () => kopyala(Uyg.api.sunucu, mesaj: 'Sunucu adresi kopyalandı'),
            ),
            if (a.sunucu.isNotEmpty)
              ListTile(leading: const Icon(Icons.settings_ethernet_rounded), title: const Text('IMAP/SMTP sunucusu'), subtitle: Text(a.sunucu)),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Uygulama sürümü'),
              subtitle: Text(Uyg.api.surum.isEmpty ? '—' : Uyg.api.surum),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Marka.gul,
          side: BorderSide(color: Marka.gul.withValues(alpha: .4)),
        ),
        onPressed: _cikis,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Çıkış yap'),
      ),
    ];
  }

  Widget _hesap() {
    final r = context.r;
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: Uyg.kutu,
      builder: (_, k, _) {
        final kota = (k?['quota_bytes'] as num?)?.toInt() ?? 0;
        final kul = (k?['used_bytes'] as num?)?.toInt() ?? 0;
        final sinirsiz = sinirsizKota(kota);
        final oran = sinirsiz ? 0.0 : (kul / kota).clamp(0.0, 1.0);
        return Kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad, boyut: 52, tohum: Uyg.adres),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad, style: gosterim(17, agirlik: FontWeight.w700)),
                        Text(Uyg.adres, style: TextStyle(color: r.silik, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Depolama',
                    style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(sinirsiz ? '${boyutYaz(kul)} · Sınırsız' : '${boyutYaz(kul)} / ${boyutYaz(kota)}', style: TextStyle(color: r.silik, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: sinirsiz ? 0 : oran, minHeight: 8, backgroundColor: r.ic, color: oran >= .9 ? Marka.gul : r.birincil),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bildirimler() {
    final r = context.r;
    if (Push.destekli) {
      final p = _push;
      final acik = p?['available'] == true;
      final cihaz = (p?['devices'] as num?)?.toInt() ?? 0;
      return Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              p == null
                  ? 'Bildirim durumu alınıyor…'
                  : !acik
                  ? 'Uygulama bildirimleri bu sunucuda kapalı.'
                  : cihaz > 0
                  ? 'Bildirimler açık · $cihaz cihaz kayıtlı'
                  : 'Bu cihaz henüz kayıtlı değil.',
              style: TextStyle(color: r.soluk),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: !acik
                      ? null
                      : () async {
                          final ok = await Push.kaydet(Uyg.api, yol: Uyg.pushYolu, konu: Uyg.pushKonu);
                          bildir(
                            ok ? 'Bildirimler etkinleştirildi' : 'Bildirim izni verilmedi',
                            mesaj: ok ? null : 'Sistem Ayarları > Bildirimler bölümünden BogaMail\'e izin verin.',
                            tur: ok ? MesajTur.basari : MesajTur.uyari,
                          );
                          await _bildirimDurumu();
                        },
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Bildirimleri etkinleştir'),
                ),
                OutlinedButton.icon(
                  onPressed: !acik || cihaz == 0 ? null : () => islem(Posta.pushTest, tamam: 'Test bildirimi gönderildi'),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Test bildirimi gönder'),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (Bildirim.android) {
      return Kutu(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_izin)
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined, color: Marka.kehribar),
                title: const Text('Bildirim izni kapalı'),
                subtitle: const Text('Yeni e-postalardan haberdar olmak için izin verin.'),
                trailing: TextButton(
                  onPressed: () async {
                    await Bildirim.izinIste();
                    await _bildirimDurumu();
                  },
                  child: const Text('İzin ver'),
                ),
              ),
            SwitchListTile.adaptive(
              value: _arkaPlan,
              onChanged: (v) async {
                await Bildirim.arkaPlanAyarla(v);
                setState(() => _arkaPlan = v);
              },
              title: const Text('Arka planda yeni posta denetimi'),
              subtitle: const Text(
                'Uygulama kapalıyken Gelen Kutusu yaklaşık 15 dakikada bir denetlenir (Android en kısa bu aralığa izin verir; pil tasarrufu modunda gecikebilir).',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Test bildirimi göster'),
              onTap: () => Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: 'Bildirimler bu cihazda çalışıyor.'),
            ),
          ],
        ),
      );
    }
    if (Bildirim.windows) {
      return Kutu(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('BogaMail açıkken pencere arka plandaysa yeni e-postalar için Windows bildirimi gösterilir.', style: TextStyle(color: r.soluk)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => Bildirim.goster(iletiId: '', baslik: 'BogaMail', metin: 'Bildirimler bu bilgisayarda çalışıyor.'),
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('Test bildirimi göster'),
              ),
            ),
          ],
        ),
      );
    }
    return Kutu(
      child: Text('Bu platformda bildirim desteklenmiyor.', style: TextStyle(color: r.soluk)),
    );
  }

  Widget _tatilBolumu() {
    final r = context.r;
    final izinli = _a!.ozellik('autoresponder');
    String tarih(String? s) {
      final t = DateTime.tryParse(s ?? '');
      return t == null ? 'Seçilmedi' : DateFormat('d MMMM y', 'tr_TR').format(t);
    }

    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _tatil,
            onChanged: !izinli
                ? null
                : (v) => setState(() {
                    _tatil = v;
                    _tatilKirli = true;
                  }),
            title: const Text('Otomatik yanıt (izin/tatil)'),
            subtitle: Text(izinli ? 'Size yazan herkese bu yanıt gönderilir.' : 'Paketiniz otomatik yanıta izin vermiyor.'),
          ),
          if (izinli) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _tatilKonu,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Konu', hintText: 'Örn. İzindeyim', counterText: ''),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _tatilMetin,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Yanıt metni', alignLabelWithHint: true),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _tarihSec(true),
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text('Başlangıç: ${tarih(_tatilBas)}', overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _tarihSec(false),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: Text('Bitiş: ${tarih(_tatilBit)}', overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            if (_tatilBas != null || _tatilBit != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() {
                    _tatilBas = null;
                    _tatilBit = null;
                    _tatilKirli = true;
                  }),
                  child: const Text('Tarihleri temizle'),
                ),
              ),
            Text('Tarih seçmezseniz otomatik yanıt siz kapatana kadar açık kalır.', style: TextStyle(color: r.silik, fontSize: 12.5)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _tatilKirli && !_kaydediliyor ? _tatilKaydet : null, child: const Text('Kaydet')),
            ),
          ],
        ],
      ),
    );
  }
}
