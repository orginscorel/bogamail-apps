import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/json.dart';
import 'alan_adlari.dart';
import 'musteri_form.dart';
import 'musteri_islemleri.dart';
import 'musteri_model.dart';
import 'paketim.dart';
import 'posta_kutulari.dart';
import 'taklit_islemleri.dart';

/// Müşteri üzerindeki ortak işlemler (tablo satır menüsü ve ayrıntı paneli aynı kodu kullanır).
class MusteriEylemleri {
  MusteriEylemleri._();

  static Future<Musteri?> duzenle(BuildContext context, Musteri m) => musteriFormuAc(context, musteri: m);

  /// PATCH /organizations/{id} {status}.
  static Future<Musteri?> durumDegistir(BuildContext context, Musteri m) async {
    final askiya = m.aktif;
    if (askiya &&
        !await onayla(
          context,
          '${m.ad} askıya alınsın mı?',
          mesaj: 'Müşterinin tüm posta kutuları giriş yapamaz ve posta gönderemez; müşteri yöneticileri panele giremez.',
          evet: 'Askıya al',
          tehlikeli: true,
        )) {
      return null;
    }
    final v = await islem(
      () => Uyg.api.patch('/api/v1/organizations/${m.id}', {'status': askiya ? 'suspended' : 'active'}),
      tamam: askiya ? 'Müşteri askıya alındı' : 'Müşteri etkinleştirildi',
    );
    return v == null ? null : Musteri.coz(harita(v));
  }

  /// DELETE /organizations/{id} (yalnızca hiç alan adı kalmadığında; Yönetici bölümündekiler silinemez).
  static Future<bool> sil(BuildContext context, Musteri m) async {
    if (m.alanSayisi > 0) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Müşteri silinemez'),
          content: Text('${m.ad} müşterisinin ${m.alanSayisi} alan adı var. Müşteri yalnızca hiç alan adı kalmadığında silinebilir.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Tamam'))],
        ),
      );
      return false;
    }
    final ok = await yazarakOnayla(
      context,
      baslik: '${m.ad} silinsin mi?',
      mesaj: 'Bu işlem geri alınamaz ve denetim kaydına yazılır. Onaylamak için müşteri adını yazın.',
      beklenen: m.ad,
    );
    if (!ok) return false;
    final v = await islem(() async {
      await Uyg.api.delete('/api/v1/organizations/${m.id}');
      return true;
    }, tamam: 'Müşteri silindi');
    return v == true;
  }

  /// POST /organizations/{id}/internal {internal}: Yönetici bölümüne taşı / müşterilere geri al.
  static Future<Musteri?> dahiliTasi(BuildContext context, Musteri m) async {
    final ok = await onayla(
      context,
      m.dahili ? '${m.ad} müşterilere taşınsın mı?' : '${m.ad} Yönetici bölümüne taşınsın mı?',
      mesaj: m.dahili
          ? 'Silme koruması kalkar: kuruluş, alan adları ve posta kutuları silinebilir hale gelir; bundan sonra silinen postalar arşivlenmez. Önceden arşivlenenler korunur.'
          : 'Kuruluş müşteri listesinden ayrılır. Kuruluş, alan adları ve posta kutuları silinemez; silinen her posta arşivde saklanır ve geri yüklenebilir. '
                'Faturalama sistemi (WHMCS) askıya alamaz.',
      evet: 'Taşı',
    );
    if (!ok) return null;
    final v = await islem(
      () => Uyg.api.post('/api/v1/organizations/${m.id}/internal', {'internal': !m.dahili}),
      tamam: m.dahili ? 'Müşterilere taşındı' : 'Yönetici bölümüne taşındı',
    );
    return v == null ? null : Musteri.coz(harita(v));
  }

  static void alanAdlari(BuildContext context, Musteri m) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlanAdlariEkrani(orgId: m.id, orgAdi: m.ad),
    ),
  );

  static void postaKutulari(BuildContext context, Musteri m) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PostaKutulariEkrani(orgId: m.id, orgAdi: m.ad),
    ),
  );

  static Future<void> paneleGir(BuildContext context, Musteri m) => musteriPanelineGir(context, id: m.id, ad: m.ad);
}

/// Müşteriyi kimliğiyle yükleyip ayrıntısını açar (GET /organizations/{id}); bağlantılar ve dahili kurumlar için.
Future<void> musteriDetayKimlikle(BuildContext context, String id, {void Function(Musteri?)? degisti}) async {
  final Musteri m;
  try {
    m = Musteri.coz(harita(await Uyg.api.get('/api/v1/organizations/$id')));
  } catch (e) {
    bildir('Müşteri açılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    return;
  }
  if (context.mounted) await musteriDetayAc(context, m, degisti ?? (_) {});
}

/// Ayrıntıyı açar: geniş ekranda sağdan kayan panel, telefonda tam sayfa.
/// [degisti]: müşteri güncellendiğinde yeni hali, silindiğinde null.
Future<void> musteriDetayAc(BuildContext context, Musteri m, void Function(Musteri?) degisti) {
  if (!context.genis) return sayfaAc<void>(context, m.ad, MusteriDetay(musteri: m, degisti: degisti));
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (c, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: c.r.zemin,
        elevation: 12,
        child: SizedBox(
          width: 560,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Müşteri ayrıntısı',
                          style: TextStyle(color: c.r.silik, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                Expanded(
                  child: MusteriDetay(musteri: m, degisti: degisti, panelde: true),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (c, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Müşteri ayrıntısı (GET /organizations/{id}): özet, kullanım, müşteri kartı, kısayollar, güvenlik ve tüm yönetim işlemleri.
class MusteriDetay extends StatefulWidget {
  const MusteriDetay({super.key, required this.musteri, required this.degisti, this.panelde = false});
  final Musteri musteri;
  final void Function(Musteri?) degisti;

  /// Yan panelde (silinince panel kapanır) ya da tam sayfada (sayfa kapanır).
  final bool panelde;
  @override
  State<MusteriDetay> createState() => _MusteriDetayState();
}

class _MusteriDetayState extends State<MusteriDetay> {
  late Musteri _m = widget.musteri;
  String? _hata;
  Map<String, dynamic>? _mfa;
  bool _mfaMesgul = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await Future.wait([
        Uyg.api.get('/api/v1/organizations/${_m.id}'),
        Uyg.api.get('/api/v1/organizations/${_m.id}/mfa-policy').then<Object?>((v) => v, onError: (_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _m = Musteri.coz(harita(r[0]));
        _mfa = r[1] == null ? null : harita(r[1]);
        _hata = null;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  void _guncel(Musteri? y) {
    if (y == null) return;
    setState(() => _m = y);
    widget.degisti(y);
  }

  Future<void> _mfaAyarla(String alan, bool deger) async {
    setState(() => _mfaMesgul = true);
    final v = await islem(
      () => Uyg.api.patch('/api/v1/organizations/${_m.id}/mfa-policy', {alan: deger}),
      tamam: 'İki adımlı doğrulama politikası güncellendi',
    );
    if (!mounted) return;
    setState(() {
      _mfaMesgul = false;
      if (v != null) _mfa = harita(v);
    });
  }

  Future<void> _sil() async {
    if (!await MusteriEylemleri.sil(context, _m) || !mounted) return;
    widget.degisti(null);
    Navigator.of(context).pop();
  }

  Future<void> _bayiYap() async {
    if (await bayiYapAc(context, _m)) await _yukle();
    if (mounted) widget.degisti(_m);
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    final yonetir = MusteriYetki.yonetir;
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, widget.panelde ? 4 : 12, 16, 32),
        children: [
          _ust(context, m),
          if (_hata != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Bant(_hata!, renk: Marka.gul, ikon: Icons.cloud_off_rounded),
            ),
          const SizedBox(height: 12),
          _kullanim(context, m),
          const Baslik('Müşteri kartı'),
          _kart(context, m),
          const Baslik('Kısayollar'),
          EylemSatiri(
            ikon: Icons.language_rounded,
            baslik: 'Alan adları',
            ipucu: '${m.alanSayisi} / ${sinirYaz(m.enFazlaAlan)} alan adı',
            onTap: () => MusteriEylemleri.alanAdlari(context, m),
          ),
          const SizedBox(height: 8),
          EylemSatiri(
            ikon: Icons.inbox_rounded,
            baslik: 'Posta kutuları',
            ipucu: '${m.kutuSayisi} / ${sinirYaz(m.enFazlaKutu)} posta kutusu',
            onTap: () => MusteriEylemleri.postaKutulari(context, m),
          ),
          const SizedBox(height: 8),
          EylemSatiri(
            ikon: Icons.verified_outlined,
            baslik: 'Paket ve kullanım',
            ipucu: 'Paket özellikleri, kalan haklar, gönderim sınırları ve veri dışa aktarma',
            onTap: () => sayfaAc(context, m.ad, PaketimEkrani(orgId: m.id, orgAdi: m.ad)),
          ),
          if (MusteriYetki.girer) ...[
            const SizedBox(height: 8),
            EylemSatiri(
              ikon: Icons.login_rounded,
              baslik: 'Müşteri paneline gir',
              ipucu: 'Müşterinin gördüğü panel (kayıt altında)',
              onTap: () => MusteriEylemleri.paneleGir(context, m),
            ),
          ],
          const Baslik('Güvenlik ve giriş'),
          _guvenlik(context),
          const SizedBox(height: 8),
          EylemSatiri(
            ikon: Icons.travel_explore_rounded,
            baslik: 'Kendi alan adıyla giriş',
            ipucu: 'Markalı giriş adresi (ör. posta.firmaniz.com) ve DNS denetimi',
            onTap: () => girisAdresiAc(context, m),
          ),
          if (Uyg.ortak) ...[
            const Baslik('Paket ve gönderim'),
            EylemSatiri(
              ikon: Icons.toggle_on_outlined,
              baslik: 'Özellikler',
              ipucu: MusteriYetki.haklariDuzenler ? 'Paketten bağımsız özellik aç / kapat' : 'Paketten gelen ve geçersiz kılınan özellikler',
              onTap: () => ozellikleriAc(context, m),
            ),
            const SizedBox(height: 8),
            EylemSatiri(
              ikon: Icons.straighten_rounded,
              baslik: 'Boyut limitleri',
              ipucu: 'İleti, ek ve imza boyutu',
              onTap: () => boyutLimitleriniAc(context, m),
            ),
            if (MusteriYetki.topluGonderim) ...[
              const SizedBox(height: 8),
              EylemSatiri(
                ikon: Icons.campaign_outlined,
                baslik: 'Toplu gönderim',
                ipucu: 'Kampanya onay kuralı ve hız sınırı',
                onTap: () => topluGonderimAc(context, m),
              ),
            ],
            if (MusteriYetki.platform) ...[
              const SizedBox(height: 8),
              EylemSatiri(ikon: Icons.dns_outlined, baslik: 'Çıkış IP\'si', ipucu: 'Dışarı giden postanın IP adresi', onTap: () => cikisIpAc(context, m)),
            ],
          ],
          if (MusteriYetki.disaAktarir || MusteriYetki.platform) const Baslik('Diğer işlemler'),
          if (MusteriYetki.disaAktarir) ...[
            EylemSatiri(
              ikon: Icons.inventory_2_outlined,
              baslik: 'Tümünü dışa aktar',
              ipucu: 'Tüm kutular: e-posta, kişiler, takvim (.zip)',
              onTap: () => disaAktarmaAc(context, m),
            ),
            const SizedBox(height: 8),
          ],
          if (MusteriYetki.platform && m.bayiId == null) ...[
            EylemSatiri(
              ikon: Icons.handshake_outlined,
              baslik: 'Bayi yap',
              ipucu: 'Bu müşteriyi bayiye dönüştür; kendi müşterilerini açabilsin',
              onTap: _bayiYap,
            ),
            const SizedBox(height: 8),
          ],
          if (MusteriYetki.platform)
            EylemSatiri(
              ikon: Icons.verified_user_outlined,
              baslik: m.dahili ? 'Müşterilere taşı' : 'Yönetici bölümüne taşı',
              ipucu: m.dahili ? 'Silme korumasını kaldır' : 'Müşterilerden ayır; silinmeye karşı koru',
              onTap: () async => _guncel(await MusteriEylemleri.dahiliTasi(context, m)),
            ),
          if (yonetir) ...[
            const Baslik('Tehlikeli bölge'),
            EylemSatiri(
              ikon: m.aktif ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
              baslik: m.aktif ? 'Müşteriyi askıya al' : 'Müşteriyi etkinleştir',
              ipucu: m.aktif ? 'Giriş ve gönderim durur' : 'Hesap yeniden kullanıma açılır',
              tehlikeli: m.aktif,
              onTap: () async => _guncel(await MusteriEylemleri.durumDegistir(context, m)),
            ),
            const SizedBox(height: 8),
            if (m.dahili)
              const Bant('Korumalı: Yönetici bölümündeki kuruluş silinemez.', ikon: Icons.verified_user_outlined)
            else
              EylemSatiri(
                ikon: Icons.delete_outline_rounded,
                baslik: 'Müşteriyi sil',
                ipucu: 'Yalnızca hiç alan adı kalmadığında',
                tehlikeli: true,
                onTap: _sil,
              ),
          ],
        ],
      ),
    );
  }

  Widget _ust(BuildContext context, Musteri m) {
    final r = context.r;
    final sektor = sektorler[m.p('sector')];
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Avatar(m.ad, tohum: m.id, boyut: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.ad, style: gosterim(18, agirlik: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [m.paketAdi ?? 'Paketsiz', if (m.bayiAdi != null) 'Bayi: ${m.bayiAdi}', if (m.eklenme != null) kisaZaman(m.eklenme)].join(' · '),
                      style: TextStyle(color: r.silik, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        DurumRozeti(m.durum),
                        if (m.dahili) const Rozet('Yönetici', renk: Marka.mavi, ikon: Icons.verified_user_outlined),
                        if (sektor != null) Rozet(sektor, renk: Marka.mor),
                        if (musteriTurleri[m.p('customer_type')] case final t?) Rozet(t, renk: Marka.zumrut),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (MusteriYetki.yonetir || MusteriYetki.girer) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (MusteriYetki.yonetir || Uyg.musteri)
                  FilledButton.icon(
                    onPressed: () async => _guncel(await MusteriEylemleri.duzenle(context, m)),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Düzenle'),
                  ),
                if (MusteriYetki.girer)
                  OutlinedButton.icon(
                    onPressed: () => MusteriEylemleri.paneleGir(context, m),
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: const Text('Müşteri paneline gir'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kullanim(BuildContext context, Musteri m) {
    final r = context.r;
    Widget hucre(String deger, String etiket) => Expanded(
      child: Column(
        children: [
          Text(
            deger,
            style: gosterim(17, agirlik: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(etiket, style: TextStyle(color: r.silik, fontSize: 12)),
        ],
      ),
    );
    final toplam = m.toplamKota ?? 0;
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              hucre('${m.alanSayisi} / ${sinirYaz(m.enFazlaAlan)}', 'Alan adı'),
              hucre('${m.kutuSayisi} / ${sinirYaz(m.enFazlaKutu)}', 'Posta kutusu'),
              hucre(boyutYaz(m.kullanilan), 'Kullanılan'),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Tahsis edilen kota',
            style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          if (toplam > 0)
            KullanimCubugu(kullanilan: m.ayrilan, toplam: toplam)
          else
            Text('${boyutYaz(m.ayrilan)} posta kutularına tahsis edildi · toplam kota sınırsız', style: TextStyle(color: r.silik, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _kart(BuildContext context, Musteri m) {
    String birlesik(List<String> l) => l.where((x) => x.isNotEmpty).join(' · ');
    final satirlar = <(String, String, bool)>[
      ('Ticari unvan', m.p('legal_name'), true),
      ('Sektör', birlesik([sektorler[m.p('sector')] ?? '', if (m.p('company_size').isNotEmpty) '${m.p('company_size')} kişi']), false),
      ('Yetkili', birlesik([m.p('contact_name'), m.p('contact_title')]), false),
      ('E-posta', m.p('contact_email'), true),
      ('Telefon', birlesik([m.p('contact_phone'), m.p('contact_mobile')]), true),
      ('Teknik irtibat', birlesik([m.p('tech_name'), m.p('tech_email'), m.p('tech_phone')]), false),
      ('Web sitesi', m.p('website'), true),
      ('Fatura e-postası', m.p('billing_email'), true),
      ('Vergi', birlesik([m.p('tax_office'), m.p('tax_number')]), true),
      ('MERSİS no', m.p('mersis_no'), true),
      (
        'Adres',
        birlesik([
          m.p('address'),
          [m.p('district'), m.p('city')].where((x) => x.isNotEmpty).join(' / '),
          m.p('postal_code'),
          m.p('country'),
        ]),
        false,
      ),
      ('Kaynak', m.p('source'), false),
    ].where((s) => s.$2.isNotEmpty).toList();
    if (satirlar.isEmpty && m.p('notes').isEmpty) {
      return const Bant('Müşteri kartı boş. "Düzenle" ile yetkili, sektör ve fatura bilgilerini ekleyin.', ikon: Icons.badge_outlined);
    }
    return Kutu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (a, d, k) in satirlar) BilgiSatiri(a, d, kopyalanabilir: k),
          if (m.p('notes').isNotEmpty) ...[const SizedBox(height: 8), Bant('Not: ${m.p('notes')}', renk: Marka.kehribar, ikon: Icons.sticky_note_2_outlined)],
        ],
      ),
    );
  }

  Widget _guvenlik(BuildContext context) {
    final mfa = _mfa;
    if (mfa == null) return const Bant('İki adımlı doğrulama politikası yüklenemedi.', ikon: Icons.shield_outlined);
    final duzenler = MusteriYetki.mfaDuzenler && !_mfaMesgul;
    return Kutu(
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: mantik(mfa['panel']),
              onChanged: duzenler ? (v) => _mfaAyarla('panel', v) : null,
              title: const Text('Panel kullanıcılarına iki adımlı doğrulama zorunlu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Müşteri yöneticileri girişte doğrulama kodu girer.'),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: mantik(mfa['webmail']),
              onChanged: duzenler ? (v) => _mfaAyarla('webmail', v) : null,
              title: const Text('Posta kutularına iki adımlı doğrulama zorunlu', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('Webmail girişlerinde doğrulama kodu istenir.'),
            ),
          ],
        ),
      ),
    );
  }
}
