// Ayarlar → Bağlantı ve kurulum (web AccountSection'ın alt kartları): paketteki özellikler, posta programına kurulum
// (Apple profili, ayarları kopyala), IMAP/SMTP/POP3 bağlantı bilgileri ve CalDAV/CardDAV eşitleme.

import 'dart:io';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../oturum.dart';
import '../../veri/ayar_servisi.dart';
import 'ayar_ortak.dart';

const paketOzellikleri = {
  'webmail': 'Webmail',
  'smtp': 'SMTP (Outlook/telefon ile gönderim)',
  'imap': 'IMAP',
  'pop3': 'POP3 (yalnızca Gelen kutusu)',
  'external_send': 'Dış alan adlarına gönderim',
  'bulk_sending': 'Toplu gönderim',
  'forwarding': 'Yönlendirme',
  'autoresponder': 'Otomatik yanıt',
  'chat': 'Kurum içi mesajlaşma',
  'calendar': 'Takvim',
  'caldav': 'Takvim/kişi eşitleme (CalDAV/CardDAV)',
};

const _davAdimlari = {
  'iPhone / iPad': 'Ayarlar → Takvim → Hesaplar → Hesap Ekle → Diğer → "CalDAV Hesabı Ekle". Sunucu olarak adresi, kullanıcı adı ve şifrenizi girin. Kişiler için aynı ekrandan "CardDAV Hesabı Ekle"yi seçin.',
  'Mac (Takvim / Kişiler)': 'Takvim → Ayarlar → Hesaplar → + → Diğer CalDAV Hesabı; hesap türü "Elle", sunucu adresi ve bilgilerinizi girin. Kişiler uygulamasında Ayarlar → Hesaplar → + → Diğer Kişiler Hesabı → CardDAV.',
  'Android (DAVx⁵)': 'DAVx⁵ uygulamasını kurun → + → "URL ve kullanıcı adı ile giriş". Temel URL olarak sunucu adresini girin, ardından eşitlenecek takvimi ve "Kişiler" rehberini işaretleyin.',
  'Thunderbird': 'Takvim → Yeni Takvim → Ağda → kullanıcı adı ve konum olarak sunucu adresi; bulunan takvimleri seçin. Rehber için Adres Defteri → Yeni Adres Defteri → CardDAV Adres Defteri.',
  'Outlook (Windows)': 'Outlook CalDAV/CardDAV\'ı kendisi desteklemez. "CalDav Synchronizer" gibi bir eklenti kurup yeni profilde sunucu adresini, kullanıcı adını ve şifrenizi girin.',
};

class KurulumAyari extends StatelessWidget {
  const KurulumAyari({super.key});

  @override
  Widget build(BuildContext context) => SunucuAyarGovdesi(
    olustur: (context, a, _) {
      final adres = '${Uyg.kutu.value?['address'] ?? Uyg.adres}';
      final b = a.baglanti;
      final sunucu = b.sunucu.isNotEmpty ? b.sunucu : (Uri.tryParse(Uyg.api.sunucu)?.host ?? '');
      final imap = b.imapAcik && a.ozellik('imap');
      final smtp = b.smtpAcik && a.ozellik('smtp');
      final pop3 = b.pop3Acik && a.ozellik('pop3');
      return [
        _OzelliklerKarti(a: a),
        _ProgramKarti(adres: adres, sunucu: sunucu, b: b, imap: imap, dav: a.ozellik('caldav')),
        _BaglantiKarti(adres: adres, sunucu: sunucu, b: b, imap: imap, smtp: smtp, pop3: pop3, pop3Paket: a.ozellik('pop3')),
        _DavKarti(adres: adres, b: b, acik: a.ozellik('caldav') && b.davYolu.isNotEmpty, gorevler: a.ozellik('tasks')),
      ];
    },
  );
}

class _OzelliklerKarti extends StatelessWidget {
  const _OzelliklerKarti({required this.a});
  final SunucuAyarlari a;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AyarKarti(
      ikon: Simge.paket,
      baslik: 'Paketinizdeki özellikler',
      aciklama: 'Kurumunuzun e-posta paketinde size açık olan özellikler.',
      child: LayoutBuilder(
        builder: (_, k) {
          final sutun = k.maxWidth >= 560 ? 2 : 1;
          final g = (k.maxWidth - (sutun - 1) * 8) / sutun;
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in paketOzellikleri.entries)
                SizedBox(
                  width: g,
                  child: Container(
                    key: ValueKey('ozellik-${e.key}'),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: r.kenar),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(a.ozellik(e.key) ? Simge.basari : Simge.iptal, size: 18, color: a.ozellik(e.key) ? Marka.zumrut : r.silik),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.value, style: TextStyle(fontSize: 13.5, color: a.ozellik(e.key) ? r.metin : r.silik)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProgramKarti extends StatelessWidget {
  const _ProgramKarti({required this.adres, required this.sunucu, required this.b, required this.imap, required this.dav});
  final String adres;
  final String sunucu;
  final BaglantiBilgisi b;
  final bool imap;
  final bool dav;

  String get _metin => [
    'E-posta adresi: $adres',
    'Kullanıcı adı: $adres',
    'Şifre: webmail şifreniz',
    'Gelen posta (IMAP): $sunucu, bağlantı noktası ${b.imapPort} (${b.imapGuvenlik})',
    'Giden posta (SMTP): $sunucu, bağlantı noktası ${b.smtpPort} (${b.smtpGuvenlik}), kimlik doğrulama: kullanıcı adı + şifre',
  ].join('\n');

  Future<void> _appleProfili() async {
    try {
      final v = await Ayar.appleProfili();
      final d = await getTemporaryDirectory();
      final f = File('${d.path}/BogaMail.mobileconfig');
      await f.writeAsBytes(v, flush: true);
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'application/x-apple-aspen-config')]));
      } else {
        await OpenFilex.open(f.path);
      }
    } catch (e) {
      bildir('Kurulum profili alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    Widget kart(IconData i, String baslik, String metin, {Widget? eylem}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: r.kenar),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(i, size: 18, color: r.vurgu),
              const SizedBox(width: 8),
              Expanded(
                child: Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(metin, style: TextStyle(color: r.soluk, fontSize: 13, height: 1.4)),
          if (eylem != null) ...[const SizedBox(height: 10), eylem],
        ],
      ),
    );
    return AyarKarti(
      ikon: Simge.cihazlar,
      baslik: 'Posta programına kur',
      aciklama: 'Hesabınızı Apple Mail, Outlook, Thunderbird veya telefonunuzun posta uygulamasına ekleyin.',
      child: !imap
          ? const AyarNotu('Posta programı erişimi (IMAP) bu posta kutusu için açık değil. Açtırmak için kurum yöneticinize başvurun.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (b.kisitli) ...[
                  const AyarNotu(
                    'Deneme aşaması: posta programı bağlantıları şimdilik yalnızca yöneticinin izin verdiği IP adreslerinden kabul edilir.',
                    ton: NotTonu.uyari,
                  ),
                  const SizedBox(height: 10),
                ],
                IkiSutun(
                  esik: 600,
                  dikeyAralik: 10,
                  children: [
                    kart(
                      Simge.telefon,
                      'iPhone, iPad ve Mac (Apple Mail)',
                      'Kurulum profilini indirip açın; posta hesabınız${dav ? ', takviminiz ve kişileriniz' : ''} otomatik eklenir. Şifreniz dosyada yer almaz, kurulum sırasında sorulur.',
                      eylem: FilledButton.tonalIcon(
                        key: const ValueKey('apple-profili'),
                        onPressed: _appleProfili,
                        icon: const Icon(Simge.indir, size: 18),
                        label: const Text('Kurulum profilini indir'),
                      ),
                    ),
                    kart(
                      Simge.bilgisayar,
                      'Outlook, Thunderbird, Android',
                      'Yeni hesap eklerken "elle yapılandır" seçeneğini seçin ve aşağıdaki bilgileri girin. Tümünü tek seferde kopyalayabilirsiniz.',
                      eylem: OutlinedButton.icon(
                        key: const ValueKey('ayarlari-kopyala'),
                        onPressed: () => kopyala(_metin, mesaj: 'Ayarlar kopyalandı'),
                        icon: const Icon(Simge.kopyala, size: 18),
                        label: const Text('Ayarları kopyala'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _BilgiKutusu extends StatelessWidget {
  const _BilgiKutusu(this.baslik, this.satirlar);
  final String baslik;
  final List<(String, String)> satirlar;
  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(baslik, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 6),
          for (final (k, v) in satirlar)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(k, style: TextStyle(color: r.soluk, fontSize: 12.5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      v,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BaglantiKarti extends StatelessWidget {
  const _BaglantiKarti({
    required this.adres,
    required this.sunucu,
    required this.b,
    required this.imap,
    required this.smtp,
    required this.pop3,
    required this.pop3Paket,
  });
  final String adres;
  final String sunucu;
  final BaglantiBilgisi b;
  final bool imap;
  final bool smtp;
  final bool pop3;
  final bool pop3Paket;

  @override
  Widget build(BuildContext context) {
    final pop3Durum = pop3 ? null : (!b.pop3Acik ? 'Kapalı' : 'Paketinizde yok');
    final notlar = [
      if (b.kisitli) 'Deneme aşaması: bağlantı şimdilik yalnızca yönetici tarafından izin verilen IP adreslerinden kabul edilir.',
      if (b.not.isNotEmpty) b.not,
      if (b.kendindenImzali)
        'Sunucu sertifikası henüz kendinden imzalı: posta programınız ilk bağlantıda güvenlik uyarısı gösterebilir; sertifikayı kabul etmeniz gerekir.',
    ];
    return AyarKarti(
      ikon: Simge.kurulum,
      baslik: 'Bağlantı ayarları',
      aciklama: 'Outlook, Thunderbird veya telefon posta uygulaması için gereken bilgiler.',
      sag: DurumRozeti(imap ? 'Kullanılabilir' : (b.imapAcik ? 'Paketinizde kapalı' : 'Henüz kullanılamıyor'), acik: imap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imap)
            AyarNotu(
              'Hesabı eklerken aşağıdaki bilgileri ve şifrenizi kullanın. Klasörleriniz, okundu işaretleri ve silmeler her iki yönde eşitlenir.'
              '${notlar.isEmpty ? '' : '\n${notlar.join('\n')}'}',
              baslik: 'Posta programınızla bağlanabilirsiniz.',
              ton: NotTonu.tamam,
            )
          else if (b.imapAcik)
            const AyarNotu(
              'Posta programıyla bağlanmak için kurum yöneticinize başvurun.',
              baslik: 'IMAP erişimi paketinizde veya posta kutusu ayarlarınızda kapalı.',
              ton: NotTonu.uyari,
            )
          else
            const AyarNotu(
              'Aşağıdaki bilgiler yalnızca bilgilendirme amaçlıdır; şu anda posta programlarıyla bağlanamazsınız.',
              baslik: 'IMAP erişimi sunucu yöneticisi tarafından henüz açılmadı.',
              ton: NotTonu.uyari,
            ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (_, k) {
              final kutular = [
                _BilgiKutusu('Gelen posta (IMAP)', [
                  ('Sunucu', sunucu),
                  ('Bağlantı noktası', '${b.imapPort}'),
                  ('Güvenlik', b.imapGuvenlik),
                  ('Kullanıcı adı', adres),
                ]),
                _BilgiKutusu('Giden posta (SMTP)', [
                  ('Sunucu', sunucu),
                  ('Bağlantı noktası', '${b.smtpPort}'),
                  ('Güvenlik', b.smtpGuvenlik),
                  ('Kimlik doğrulama', 'Kullanıcı adı + şifre'),
                  if (!smtp) ('Durum', 'Henüz açılmadı'),
                ]),
                _BilgiKutusu('Gelen posta (POP3)', [
                  ('Sunucu', sunucu),
                  ('Bağlantı noktası', '${b.pop3Port}'),
                  ('Güvenlik', b.pop3Guvenlik),
                  ('Kullanıcı adı', adres),
                  if (pop3Durum != null) ('Durum', pop3Durum),
                ]),
              ];
              if (k.maxWidth < 600) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kutular);
              final g = (k.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                children: [for (final w in kutular) SizedBox(width: g, child: w)],
              );
            },
          ),
          if (pop3)
            Text(
              'POP3 yalnızca Gelen kutusundaki postaları indirir; klasörler ve okundu işaretleri eşitlenmez. Programınızda "sunucudan sil" seçeneği açıksa '
              'indirilen postalar buradan da silinir. Klasörleri eşitlemek için IMAP önerilir.',
              style: TextStyle(color: context.r.silik, fontSize: 12.5, height: 1.35),
            ),
        ],
      ),
    );
  }
}

class _DavKarti extends StatelessWidget {
  const _DavKarti({required this.adres, required this.b, required this.acik, required this.gorevler});
  final String adres;
  final BaglantiBilgisi b;
  final bool acik;
  final bool gorevler;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final url = '${Uyg.api.sunucu.replaceAll(RegExp(r'/+$'), '')}${b.davYolu}';
    return AyarKarti(
      ikon: Simge.yinelenen,
      baslik: 'Takvim ve kişi eşitleme (CalDAV/CardDAV)',
      aciklama: 'Telefonunuzun ve bilgisayarınızın takvim/kişiler uygulamasını takviminiz ve rehberinizle eşitleyin.',
      sag: DurumRozeti(acik ? 'Kullanılabilir' : 'Paketinizde yok', acik: acik),
      child: !acik
          ? const AyarNotu(
              'CalDAV/CardDAV eşitleme paketinizde veya posta kutusu ayarlarınızda kapalı. Eşitlemeyi açtırmak için kurum yöneticinize başvurun.',
              baslik: 'Paketinizde yok.',
              ton: NotTonu.uyari,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AyarNotu(
                  [
                    'Yaptığınız değişiklikler cihazlarda, cihazlarda yaptıklarınız burada görünür. Rehberde yalnızca kaydettiğiniz kişiler eşitlenir.',
                    if (gorevler) 'Görevleriniz aynı hesapta "Görevler" listesi olarak görünür: iPhone/Mac\'te Anımsatıcılar, Thunderbird\'de Görevler, Android\'de DAVx⁵ ile Tasks.org veya jtx Board.',
                    if (b.kisitli) 'Deneme aşaması: bağlantı şimdilik yalnızca yönetici tarafından izin verilen IP adreslerinden kabul edilir.',
                    if (b.kendindenImzali) 'Sunucu sertifikası henüz kendinden imzalı: uygulamanız ilk bağlantıda güvenlik uyarısı gösterebilir.',
                  ].join('\n'),
                  baslik: 'Takvim ve kişileriniz cihazlarınızla iki yönlü eşitlenir.',
                  ton: NotTonu.tamam,
                ),
                const SizedBox(height: 12),
                _BilgiKutusu('Hesap bilgileri', [('Sunucu adresi', url), ('Kullanıcı adı', adres), ('Şifre', 'Webmail şifreniz')]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => kopyala(url, mesaj: 'Sunucu adresi kopyalandı'),
                    icon: const Icon(Simge.kopyala, size: 18),
                    label: const Text('Sunucu adresini kopyala'),
                  ),
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (_, k) {
                    final sutun = k.maxWidth >= 600 ? 2 : 1;
                    final g = (k.maxWidth - (sutun - 1) * 10) / sutun;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final e in _davAdimlari.entries)
                          SizedBox(
                            width: g,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: r.kenar),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                  const SizedBox(height: 4),
                                  Text(e.value, style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.4)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
    );
  }
}
