import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/secimler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/modeller.dart';
import '../ortak/simgeler.dart';

/// Kota seçici: hazır değerler (1–50 GB, Sınırsız) ve özel GB alanı.
class KotaSecici extends StatefulWidget {
  const KotaSecici({super.key, required this.deger, required this.degisti, this.hata});
  final int deger;
  final ValueChanged<int?> degisti;
  final String? hata;
  @override
  State<KotaSecici> createState() => _KotaSeciciState();
}

class _KotaSeciciState extends State<KotaSecici> {
  late final _k = TextEditingController(text: sinirsizMi(widget.deger) ? '' : baytGbMetni(widget.deger));
  late int? _deger = widget.deger;

  @override
  void dispose() {
    _k.dispose();
    super.dispose();
  }

  void _sec(int b) {
    setState(() {
      _deger = b;
      _k.text = sinirsizMi(b) ? '' : baytGbMetni(b);
    });
    widget.degisti(b);
  }

  @override
  Widget build(BuildContext context) {
    final gecersiz = _deger == null || _deger! < enKucukKota;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final (e, b) in kotaOnAyarlari) ChoiceChip(label: Text(e), selected: _deger == b, showCheckmark: false, onSelected: (_) => _sec(b))],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _k,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Özel kota',
            hintText: _deger != null && sinirsizMi(_deger!) ? 'Sınırsız' : 'ör. 2,5',
            suffixText: 'GB',
            isDense: true,
            errorText: widget.hata ?? (_k.text.isNotEmpty && gecersiz ? 'En az 10 MB olmalı' : null),
          ),
          onChanged: (v) {
            final b = gbdenBayt(v);
            setState(() => _deger = v.trim().isEmpty ? null : b);
            widget.degisti(b != null && b >= enKucukKota ? b : null);
          },
        ),
      ],
    );
  }
}

/// Şifre alanı: göster/gizle, yeniden üret, kopyala.
class SifreAlani extends StatefulWidget {
  const SifreAlani({super.key, required this.denetleyici, this.hata, this.etiket = 'Şifre'});
  final TextEditingController denetleyici;
  final String? hata;
  final String etiket;
  @override
  State<SifreAlani> createState() => _SifreAlaniState();
}

class _SifreAlaniState extends State<SifreAlani> {
  bool _goster = true;
  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.denetleyici,
    obscureText: !_goster,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(fontFamily: 'monospace'),
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      labelText: widget.etiket,
      errorText: widget.hata,
      helperText: widget.hata == null ? 'En az 10 karakter. Kayıttan sonra yalnızca bir kez gösterilir.' : null,
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _goster ? 'Gizle' : 'Göster',
            icon: Icon(_goster ? Simgeler.visibilityOff : Simgeler.visibility, size: 20),
            onPressed: () => setState(() => _goster = !_goster),
          ),
          IconButton(
            tooltip: 'Yeni şifre üret',
            icon: const Icon(Simgeler.casino, size: 20),
            onPressed: () => setState(() {
              widget.denetleyici.text = sifreUret();
              _goster = true;
            }),
          ),
          IconButton(
            tooltip: 'Kopyala',
            icon: const Icon(Simgeler.copy, size: 19),
            onPressed: () => kopyala(widget.denetleyici.text, mesaj: 'Şifre kopyalandı'),
          ),
        ],
      ),
    ),
  );
}

Widget _yukleniyorDugmesi(bool mesgul, String metin) =>
    mesgul ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(metin);

/// Yeni posta kutusu (POST /mailboxes). Başarıda şifre bir kez gösterilir.
class KutuOlusturDialog extends StatefulWidget {
  const KutuOlusturDialog({super.key, this.orgId, this.alanId, this.alanAdi});
  final String? orgId, alanId, alanAdi;
  @override
  State<KutuOlusturDialog> createState() => _KutuOlusturDialogState();
}

class _KutuOlusturDialogState extends State<KutuOlusturDialog> {
  late String? _alanId = widget.alanId;
  late String? _alanAdi = widget.alanAdi;
  String? _orgAdi;
  final _yerel = TextEditingController();
  final _ad = TextEditingController();
  final _sifre = TextEditingController(text: sifreUret());
  int? _kota = 5 * gib;
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void dispose() {
    _yerel.dispose();
    _ad.dispose();
    _sifre.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    final sifre = _sifre.text;
    try {
      final v = await Uyg.api.post('/api/v1/mailboxes', {
        'domain_id': _alanId,
        'local_part': _yerel.text.trim().toLowerCase(),
        'display_name': _ad.text.trim(),
        'password': sifre,
        'quota_bytes': _kota,
      });
      final m = PostaKutusu.coz(harita(v));
      if (!mounted) return;
      bildir('${m.adres} oluşturuldu', tur: MesajTur.basari);
      await sifreGoster(
        context,
        adres: m.adres,
        sifre: sifre,
        not: 'Bu şifreyi kullanıcıya güvenli bir kanaldan iletin; daha sonra görüntülenemez (yalnızca sıfırlanabilir).',
      );
      if (mounted) Navigator.pop(context, m);
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _alan = e.alan;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hazir = _alanId != null && _yerel.text.trim().isNotEmpty && _sifre.text.length >= 10 && _kota != null && !_mesgul;
    return AlertDialog(
      title: Text('Yeni posta kutusu', style: gosterim(19, agirlik: FontWeight.w600)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SecimAlani(
                etiket: 'Alan adı',
                deger: _alanAdi,
                hata: _alan == 'domain_id' ? _hata : null,
                onTap: () async {
                  final d = await alanSec(context, orgId: widget.orgId);
                  if (d != null) {
                    setState(() {
                      _alanId = d.id;
                      _alanAdi = d.gorunenAd;
                      _orgAdi = d.orgAdi;
                    });
                  }
                },
              ),
              if (_orgAdi != null && !Uyg.musteri)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text('Müşteri: $_orgAdi', style: TextStyle(color: context.r.silik, fontSize: 12)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _yerel,
                autofocus: true,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Kullanıcı adı',
                  hintText: 'ahmet',
                  suffixText: _alanAdi == null ? null : '@$_alanAdi',
                  errorText: _alan == 'local_part' ? _hata : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ad,
                decoration: const InputDecoration(labelText: 'Görünen ad', hintText: 'Ahmet Yılmaz'),
              ),
              const SizedBox(height: 12),
              SifreAlani(denetleyici: _sifre, hata: _alan == 'password' ? _hata : null),
              const SizedBox(height: 16),
              Text(
                'Kota',
                style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              KotaSecici(deger: _kota ?? 5 * gib, degisti: (v) => setState(() => _kota = v), hata: _alan == 'quota_bytes' ? _hata : null),
              if (_hata != null && !{'domain_id', 'local_part', 'password', 'quota_bytes'}.contains(_alan)) ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Simgeler.errorOutline),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: hazir ? _kaydet : null, child: _yukleniyorDugmesi(_mesgul, 'Oluştur')),
      ],
    );
  }
}

/// Görünen ad, kota ve saatlik gönderim sınırı (PATCH /mailboxes/{id}, yalnızca değişen alanlar).
class KutuDuzenleDialog extends StatefulWidget {
  const KutuDuzenleDialog({super.key, required this.kutu});
  final PostaKutusu kutu;
  @override
  State<KutuDuzenleDialog> createState() => _KutuDuzenleDialogState();
}

class _KutuDuzenleDialogState extends State<KutuDuzenleDialog> {
  late final _ad = TextEditingController(text: widget.kutu.gorunenAd);
  late final _sinir = TextEditingController(text: '${widget.kutu.saatlikSinir}');
  late int? _kota = widget.kutu.kota;
  bool _mesgul = false;
  String? _hata, _alan;

  @override
  void dispose() {
    _ad.dispose();
    _sinir.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    final k = widget.kutu;
    final govde = <String, dynamic>{
      if (_ad.text.trim() != k.gorunenAd) 'display_name': _ad.text.trim(),
      if (_kota != null && _kota != k.kota) 'quota_bytes': _kota,
      if (int.tryParse(_sinir.text.trim()) case final s? when s != k.saatlikSinir) 'send_limit_per_hour': s,
    };
    if (govde.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = _alan = null;
    });
    try {
      final v = await Uyg.api.patch('/api/v1/mailboxes/${k.id}', govde);
      bildir('Posta kutusu güncellendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, PostaKutusu.coz(harita(v)));
    } on ApiHata catch (e) {
      setState(() {
        _hata = e.mesaj;
        _alan = e.alan;
      });
    } catch (e) {
      setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sinir = int.tryParse(_sinir.text.trim());
    final hazir = !_mesgul && _kota != null && sinir != null && sinir >= 0 && sinir <= 100000;
    return AlertDialog(
      title: Text(
        widget.kutu.adres,
        style: gosterim(18, agirlik: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ad,
                decoration: InputDecoration(labelText: 'Görünen ad', errorText: _alan == 'display_name' ? _hata : null),
              ),
              const SizedBox(height: 16),
              Text(
                'Kota · kullanılan ${boyutYaz(widget.kutu.kullanilan)}',
                style: TextStyle(color: context.r.soluk, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              KotaSecici(deger: widget.kutu.kota, degisti: (v) => setState(() => _kota = v), hata: _alan == 'quota_bytes' ? _hata : null),
              const SizedBox(height: 4),
              Text('Kota artışları müşterinin paket kotasına göre denetlenir.', style: TextStyle(color: context.r.silik, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: _sinir,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Saatlik gönderim sınırı',
                  suffixText: 'ileti / saat',
                  errorText: _alan == 'send_limit_per_hour' ? _hata : null,
                ),
              ),
              if (_hata != null && !{'display_name', 'quota_bytes', 'send_limit_per_hour'}.contains(_alan)) ...[
                const SizedBox(height: 12),
                Bant(_hata!, renk: Marka.gul, ikon: Simgeler.errorOutline),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: hazir ? _kaydet : null, child: _yukleniyorDugmesi(_mesgul, 'Kaydet')),
      ],
    );
  }
}

/// Şifre sıfırlama (POST /mailboxes/{id}/password): güçlü şifre üretilir, bir kez gösterilir.
Future<void> sifreSifirla(BuildContext context, PostaKutusu k) async {
  var kapat = true;
  final evet = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => AlertDialog(
        title: Text('Şifreyi sıfırla', style: gosterim(19, agirlik: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${k.adres} için güçlü bir şifre üretilecek ve yalnızca bir kez gösterilecek.'),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: kapat,
              onChanged: (v) => yenile(() => kapat = v ?? true),
              title: const Text('Oturumları kapat'),
              subtitle: const Text('Açık webmail oturumları ve uygulama şifreleri (IMAP/SMTP) silinir.'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Şifreyi sıfırla')),
        ],
      ),
    ),
  );
  if (evet != true || !context.mounted) return;
  final sifre = sifreUret();
  final v = await islem(() => Uyg.api.post('/api/v1/mailboxes/${k.id}/password', {'password': sifre, 'revoke_sessions': kapat}));
  if (v == null || !context.mounted) return;
  final n = tamsayi(harita(v)['sessions_revoked']);
  await sifreGoster(
    context,
    adres: k.adres,
    sifre: sifre,
    not: '${kapat ? '$n oturum kapatıldı. ' : ''}Bu şifre yalnızca şimdi gösterilir; kullanıcıya güvenli bir kanaldan iletin.',
  );
}

/// Yönlendirme düzenleme (PUT /mailboxes/{id}/forwarding). Boş hedef yönlendirmeyi kapatır.
Future<Yonlendirme?> yonlendirmeDuzenle(BuildContext context, PostaKutusu k, Yonlendirme y) async {
  final hedef = TextEditingController(text: y.hedef);
  var kopya = y.kopyaKalsin;
  String? hata;
  var mesgul = false;
  final sonuc = await showDialog<Yonlendirme>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => AlertDialog(
        title: Text('Yönlendirme', style: gosterim(19, agirlik: FontWeight.w600)),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${k.adres} adresine gelen postalar aşağıdaki adrese iletilir.${y.disIzinli ? '' : ' Bu kutu için yalnızca kurum içi adresler kullanılabilir.'}',
                style: TextStyle(color: c.r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hedef,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(labelText: 'Hedef adres', hintText: 'boş = yönlendirme kapalı', errorText: hata),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: kopya,
                onChanged: (v) => yenile(() => kopya = v),
                title: const Text('Bu kutuda da bir kopya kalsın'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: mesgul
                ? null
                : () async {
                    yenile(() => (mesgul, hata) = (true, null));
                    try {
                      await Uyg.api.put('/api/v1/mailboxes/${k.id}/forwarding', {'forward_to': hedef.text.trim(), 'keep_copy': kopya});
                      final yeni = Yonlendirme.coz(await Uyg.api.get('/api/v1/mailboxes/${k.id}/forwarding'));
                      bildir(hedef.text.trim().isEmpty ? 'Yönlendirme kapatıldı' : 'Yönlendirme kaydedildi', tur: MesajTur.basari);
                      if (c.mounted) Navigator.pop(c, yeni);
                    } catch (e) {
                      yenile(() => (mesgul, hata) = (false, hataMetni(e)));
                    }
                  },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
  return sonuc;
}
