
import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart';

export '../ortak/dosya.dart' show dosyaIndir;
import '../veri/json.dart';
import '../veri/modeller.dart';

// Posta kutusu yönetici işlemleri (web: mailboxes/page.tsx "Yönet"): dışa aktarma, boyut limitleri, IMAP ile
// taşıma, yedekten geri yükleme, 2FA sıfırlama, uygulama şifresi silme. Sunucu: impersonate.go, limits_api.go,
// migration.go, backup.go, mfa.go, accounts.go.

/// Tüm postaları .zip (EML) olarak indirir: GET /mailboxes/{id}/export (denetim kaydına yazılır).
Future<void> kutuyuDisariAktar(BuildContext context, PostaKutusu k) async {
  if (!await onayla(
    context,
    'Posta kutusu dışa aktarılsın mı?',
    mesaj: '${k.adres} kutusundaki tüm iletiler (${boyutYaz(k.kullanilan)}) .zip içinde EML dosyaları olarak bu cihaza indirilir. İşlem denetim kaydına yazılır ve kutu sahibi güvenlik kaydında görür.',
    evet: 'İndir',
  )) {
    return;
  }
  final ad = '${k.adresAscii.replaceAll('@', '_at_')}-${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9T]'), '').substring(0, 15)}.zip';
  await dosyaIndir('/api/v1/mailboxes/${k.id}/export', ad, baslik: 'Dışa aktarılıyor', tur: 'application/zip');
}

const _limitAdlari = {'max_message_bytes': 'İleti boyutu', 'max_attachment_bytes': 'Ek boyutu', 'max_signature_bytes': 'İmza boyutu'};
const _kaynakAdlari = {'mailbox': 'bu kutu', 'customer': 'müşteri', 'package': 'paket', 'platform': 'platform'};

/// Boyut limitleri: GET/PATCH /mailboxes/{id}/limits ({anahtar: bayt | "inherit"}). Düzenleme yalnızca süper ve bayi
/// yöneticisine açıktır (can_edit).
Future<void> boyutLimitleri(BuildContext context, PostaKutusu k) async {
  final Map<String, dynamic> v;
  try {
    v = harita(await Uyg.api.get('/api/v1/mailboxes/${k.id}/limits'));
  } catch (e) {
    bildir('Limitler alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    return;
  }
  if (!context.mounted) return;
  final etkin = harita(v['effective']);
  final kutu = harita(harita(v['levels'])['mailbox']);
  final duzenler = mantik(v['can_edit']) && Uyg.taklit == null;
  final alanlar = {for (final a in _limitAdlari.keys) a: TextEditingController(text: kutu[a] == null ? '' : (tamsayi(kutu[a]) / 1048576).toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''))};
  String? hata;
  await showDialog<void>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => AlertDialog(
        title: Text('Boyut limitleri', style: gosterim(19, agirlik: FontWeight.w700)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(k.adres, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              for (final e in _limitAdlari.entries) ...[
                BilgiSatiri(
                  e.value,
                  '${boyutYaz(tamsayi(harita(etkin[e.key])['bytes']))} · ${_kaynakAdlari[metin(harita(etkin[e.key])['source'])] ?? metin(harita(etkin[e.key])['source'])} düzeyinden',
                ),
                if (duzenler)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: alanlar[e.key],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(isDense: true, labelText: '${e.value} (MB)', hintText: 'Boş: üst düzeyden devral'),
                    ),
                  ),
              ],
              if (hata != null) Bant(hata!, renk: Marka.gul, ikon: Icons.error_outline_rounded),
              if (!duzenler) Text('Limitleri yalnızca platform ve bayi yöneticileri değiştirebilir.', style: TextStyle(color: c.r.silik, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(duzenler ? 'Vazgeç' : 'Kapat')),
          if (duzenler)
            FilledButton(
              onPressed: () async {
                final govde = <String, Object>{};
                for (final a in _limitAdlari.keys) {
                  final t = alanlar[a]!.text.trim().replaceAll(',', '.');
                  if (t.isEmpty) {
                    govde[a] = 'inherit';
                  } else {
                    final mb = double.tryParse(t);
                    if (mb == null || mb <= 0) {
                      yenile(() => hata = '${_limitAdlari[a]} için geçerli bir sayı girin.');
                      return;
                    }
                    govde[a] = (mb * 1048576).round();
                  }
                }
                try {
                  await Uyg.api.patch('/api/v1/mailboxes/${k.id}/limits', govde);
                  if (c.mounted) Navigator.pop(c);
                  bildir('Limitler kaydedildi', tur: MesajTur.basari);
                } catch (e) {
                  yenile(() => hata = hataMetni(e));
                }
              },
              child: const Text('Kaydet'),
            ),
        ],
      ),
    ),
  );
}

/// IMAP ile taşıma: GET /migration-presets, POST /mailboxes/{id}/migrations {host, port, security, username, password}.
Future<bool> imapTasima(BuildContext context, PostaKutusu k) async {
  var hazir = <Map<String, dynamic>>[];
  try {
    hazir = haritalar(harita(await Uyg.api.get('/api/v1/migration-presets'))['items']);
  } catch (_) {}
  if (!context.mounted) return false;
  final sunucu = TextEditingController(), port = TextEditingController(text: '993'), kullanici = TextEditingController(text: k.adresAscii), sifre = TextEditingController();
  var guvenlik = 'tls';
  String? secili, hata;
  var mesgul = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => AlertDialog(
        title: Text('IMAP ile taşı', style: gosterim(19, agirlik: FontWeight.w700)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Eski sunucudaki postalar ${k.adres} kutusuna aktarılır. Var olan iletiler atlanır.', style: TextStyle(color: c.r.soluk, fontSize: 13)),
                const SizedBox(height: 12),
                if (hazir.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    initialValue: secili,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Sağlayıcı', isDense: true),
                    items: [for (final p in hazir) DropdownMenuItem(value: metin(p['key']), child: Text(metin(p['name']), overflow: TextOverflow.ellipsis))],
                    onChanged: (d) => yenile(() {
                      secili = d;
                      final p = hazir.firstWhere((x) => metin(x['key']) == d);
                      final alan = k.adresAscii.contains('@') ? k.adresAscii.split('@').last : '';
                      sunucu.text = metin(p['host']).replaceAll('{domain}', alan);
                      port.text = '${tamsayi(p['port'], 993)}';
                      guvenlik = metin(p['security'], 'tls');
                      final oauth = metinYa(p['oauth_status']);
                      hata = oauth == null ? null : 'Not: $oauth';
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(controller: sunucu, decoration: const InputDecoration(labelText: 'IMAP sunucusu', hintText: 'imap.ornek.com', isDense: true)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', isDense: true)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: guvenlik,
                        decoration: const InputDecoration(labelText: 'Güvenlik', isDense: true),
                        items: const [DropdownMenuItem(value: 'tls', child: Text('SSL/TLS')), DropdownMenuItem(value: 'starttls', child: Text('STARTTLS'))],
                        onChanged: (d) => yenile(() => guvenlik = d ?? 'tls'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: kullanici, autocorrect: false, decoration: const InputDecoration(labelText: 'Kullanıcı adı', isDense: true)),
                const SizedBox(height: 10),
                TextField(controller: sifre, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre', isDense: true)),
                if (hata != null) ...[const SizedBox(height: 10), Bant(hata!, renk: Marka.kehribar, ikon: Icons.info_outline_rounded)],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: mesgul ? null : () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: mesgul
                ? null
                : () async {
                    yenile(() {
                      mesgul = true;
                      hata = null;
                    });
                    try {
                      await Uyg.api.post('/api/v1/mailboxes/${k.id}/migrations', {
                        'host': sunucu.text.trim(),
                        'port': int.tryParse(port.text.trim()) ?? 993,
                        'security': guvenlik,
                        'username': kullanici.text.trim(),
                        'password': sifre.text,
                      });
                      if (c.mounted) Navigator.pop(c, true);
                    } catch (e) {
                      yenile(() {
                        mesgul = false;
                        hata = hataMetni(e);
                      });
                    }
                  },
            child: const Text('Taşımayı başlat'),
          ),
        ],
      ),
    ),
  );
  if (ok == true) bildir('Taşıma başlatıldı', mesaj: 'İlerlemeyi kutu ayrıntısında izleyebilirsiniz.', tur: MesajTur.basari);
  return ok == true;
}

/// Yedekten geri yükleme: GET /mailboxes/{id}/backups → POST /mailboxes/{id}/backups/{run}/restore {mode}.
Future<void> yedektenGeriYukle(BuildContext context, PostaKutusu k) async {
  final Map<String, dynamic> v;
  try {
    v = harita(await Uyg.api.get('/api/v1/mailboxes/${k.id}/backups'));
  } catch (e) {
    bildir('Yedekler alınamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    return;
  }
  if (!context.mounted) return;
  final gunler = haritalar(v['items']);
  final kok = metin(v['restore_root'], 'Geri Yüklenenler');
  String? secili = gunler.isEmpty ? null : metin(gunler.first['run']);
  var mod = 'restore_folder';
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => AlertDialog(
        title: Text('Yedekten geri yükle', style: gosterim(19, agirlik: FontWeight.w700)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: gunler.isEmpty
              ? const Text('Bu posta kutusunun henüz yedeği yok.')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Silinen iletiler seçilen günün yedeğinden geri getirilir; kutuda zaten olanlar atlanır.', style: TextStyle(color: c.r.soluk, fontSize: 13)),
                      if (v['retention_days'] != null)
                        Text('Yedekler ${tamsayi(v['retention_days'])} gün saklanır.', style: TextStyle(color: c.r.silik, fontSize: 12)),
                      const SizedBox(height: 8),
                      RadioGroup<String>(
                        groupValue: secili,
                        onChanged: (d) => yenile(() => secili = d),
                        child: Column(
                          children: [
                            for (final g in gunler.take(30))
                              RadioListTile<String>(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: metin(g['run']),
                                title: Text(tamZaman(tarihOku(g['started_at']))),
                                subtitle: Text('${sayiYaz(tamsayi(g['messages']))} ileti · ${boyutYaz(tamsayi(g['bytes']))}'),
                              ),
                          ],
                        ),
                      ),
                      const Divider(),
                      RadioGroup<String>(
                        groupValue: mod,
                        onChanged: (d) => yenile(() => mod = d ?? mod),
                        child: Column(
                          children: [
                            RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'restore_folder', title: Text('"$kok" klasörüne')),
                            const RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero, value: 'original', title: Text('Özgün klasörlerine')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          if (gunler.isNotEmpty) FilledButton(onPressed: secili == null ? null : () => Navigator.pop(c, true), child: const Text('Geri yükle')),
        ],
      ),
    ),
  );
  if (ok != true || secili == null) return;
  final s = await islem(() => Uyg.api.post('/api/v1/mailboxes/${k.id}/backups/${Uri.encodeComponent(secili!)}/restore', {'mode': mod}));
  if (s != null) {
    final m = harita(s);
    bildir(
      'Geri yükleme tamamlandı',
      mesaj: '${sayiYaz(tamsayi(m['restored']))} ileti geri yüklendi · ${sayiYaz(tamsayi(m['duplicates']))} zaten vardı${metinYa(m['folder']) != null ? ' · ${m['folder']}' : ''}',
      tur: MesajTur.basari,
    );
  }
}

/// İki adımlı doğrulamayı sıfırlar: POST /mailboxes/{id}/mfa/reset.
Future<bool> kutuMfaSifirla(BuildContext context, PostaKutusu k) async {
  if (!await onayla(
    context,
    'İki adımlı doğrulama sıfırlansın mı?',
    mesaj: '${k.adres} için doğrulama uygulaması ve kurtarma kodları kaldırılır; kullanıcı bir sonraki girişte yeniden kurar.',
    evet: 'Sıfırla',
    tehlikeli: true,
  )) {
    return false;
  }
  return await islem(() => Uyg.api.post('/api/v1/mailboxes/${k.id}/mfa/reset').then((_) => true), tamam: 'İki adımlı doğrulama sıfırlandı') == true;
}

/// Uygulama şifresini siler: DELETE /mailboxes/{id}/app-passwords/{pid}.
Future<bool> uygulamaSifresiSil(BuildContext context, PostaKutusu k, Map<String, dynamic> s) async {
  if (!await onayla(
    context,
    '"${metin(s['name'])}" silinsin mi?',
    mesaj: 'Bu şifreyi kullanan posta programı (IMAP/SMTP) bağlanamaz.',
    evet: 'Sil',
    tehlikeli: true,
  )) {
    return false;
  }
  return await islem(() => Uyg.api.delete('/api/v1/mailboxes/${k.id}/app-passwords/${metin(s['id'])}').then((_) => true), tamam: 'Uygulama şifresi silindi') == true;
}

const tasimaDurumlari = {
  'queued': 'Sırada',
  'running': 'Sürüyor',
  'done': 'Tamamlandı',
  'failed': 'Başarısız',
  'cancelled': 'İptal edildi',
  'paused': 'Duraklatıldı',
};
