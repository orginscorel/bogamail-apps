import 'dart:convert';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../ortak/dosya.dart' show dosyaIndir, dosyaSec;
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../veri/json.dart';
import 'ekip_kampanya_ortak.dart';

/// Toplu Gönderim → Kişi listeleri: listeler, kişiler, içe aktarma (yapıştırılan CSV), abonelik formu.
class ListelerSekmesi extends StatefulWidget {
  const ListelerSekmesi({super.key, required this.b});
  final KampanyaBaglami b;
  @override
  State<ListelerSekmesi> createState() => _ListelerSekmesiState();
}

class _ListelerSekmesiState extends State<ListelerSekmesi> {
  late final _y = SayfaYukleyici.yerel<Map<String, dynamic>>(
    () async => haritalar(harita(await Uyg.api.get('/api/v1/campaigns/lists', q: widget.b.q))['items']),
    sayfaBoyu: 25,
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _yenile() {
    _y.yenile();
    widget.b.yenile();
  }

  Future<void> _duzenle(Map<String, dynamic>? l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ListeDialog(b: widget.b, liste: l),
    );
    if (ok == true) _yenile();
  }

  Future<void> _sil(Map<String, dynamic> l) async {
    final ok = await onayla(
      context,
      'Liste silinsin mi?',
      mesaj:
          '"${metin(l['name'])}" ve içindeki ${sayiYaz(tamsayi(l['total']))} kişi kalıcı olarak silinir. Abonelikten çıkmış adresler bastırma listesinde kalır.',
      evet: 'Sil',
      tehlikeli: true,
    );
    if (!ok) return;
    await islem(() => Uyg.api.delete('/api/v1/campaigns/lists/${metin(l['id'])}'), tamam: 'Liste silindi');
    _yenile();
  }

  Future<void> _kisiler(Map<String, dynamic> l) async {
    await ekipPencere<void>(context, '${metin(l['name'])}: kişiler', KisilerGorunumu(liste: l, acik: widget.b.acik, degisti: widget.b.yenile), genislik: 960);
    _yenile();
  }

  Future<void> _iceAktar(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _IceAktarDialog(liste: l),
    );
    if (ok == true) _yenile();
  }

  Future<void> _form(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _FormDialog(b: widget.b, liste: l),
    );
    if (ok == true) _yenile();
  }

  List<SatirEylemi> _eylemler(Map<String, dynamic> l) => [
    SatirEylemi(Icons.people_outline_rounded, 'Kişiler', () => _kisiler(l)),
    SatirEylemi(
      Icons.download_rounded,
      'Kişileri CSV olarak indir',
      () => dosyaIndir('/api/v1/campaigns/lists/${metin(l['id'])}/export.csv', '${metinYa(l['name']) ?? 'liste'}-kisiler.csv',
          baslik: 'Kişiler indiriliyor', tur: 'text/csv'),
    ),
    if (widget.b.acik) SatirEylemi(Icons.upload_file_rounded, 'CSV içe aktar', () => _iceAktar(l)),
    SatirEylemi(Icons.dynamic_form_outlined, 'Abonelik formu', () => _form(l)),
    SatirEylemi(Icons.edit_outlined, 'Düzenle', () => _duzenle(l)),
    SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(l), tehlikeli: true),
  ];

  @override
  Widget build(BuildContext context) {
    final b = widget.b;
    final s = b.sinirlar;
    final enFazla = tamsayiYa(s['max_contacts']);
    final yatay = context.genis ? 16.0 : 12.0;
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin:
          'Henüz liste yok. Bir kişi listesi oluşturun; kişileri tek tek ekleyebilir, CSV ile içe aktarabilir ya da abonelik formu ile toplayabilirsiniz.',
      bosIkon: Icons.groups_outlined,
      onTap: _kisiler,
      eylemler: _eylemler,
      ust: Padding(
        padding: EdgeInsets.fromLTRB(yatay, 10, yatay, 8),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Text(
                'Yalnızca size izin vermiş kişileri ekleyin; her kayıtta onayın nasıl alındığı saklanır.'
                '${enFazla != null ? ' Kişi sınırı: ${sayiYaz(tamsayi(s['contacts']))} / ${sayiYaz(enFazla)}.' : ''}',
                style: TextStyle(color: context.r.soluk, fontSize: 12.5),
              ),
            ),
            FilledButton.icon(onPressed: b.acik ? () => _duzenle(null) : null, icon: const Icon(Icons.playlist_add_rounded), label: const Text('Yeni liste')),
          ],
        ),
      ),
      sutunlar: [
        Sutun('Liste', esnek: 4, hucre: (c, l) => IkiSatir(metin(l['name']), alt: metinYa(l['description']))),
        Sutun('Abone', esnek: 1, sagaYasla: true, hucre: (c, l) => Text(sayiYaz(tamsayi(l['subscribed'])))),
        Sutun('Onay bekliyor', esnek: 2, sagaYasla: true, hucre: (c, l) => Text(sayiYaz(tamsayi(l['pending'])))),
        Sutun(
          'Çıktı / geri döndü',
          esnek: 2,
          sagaYasla: true,
          hucre: (c, l) => Text('${sayiYaz(tamsayi(l['unsubscribed']))} / ${sayiYaz(tamsayi(l['bounced']) + tamsayi(l['complained']))}'),
        ),
        Sutun('Form', esnek: 1, hucre: (c, l) => mantik(l['form_enabled']) ? const Rozet('Açık', renk: Marka.zumrut) : const SolukMetin('Kapalı')),
      ],
      kart: (c, l) => VeriKarti(
        baslik: metin(l['name']),
        alt: metinYa(l['description']),
        rozetler: [if (mantik(l['form_enabled'])) const Rozet('Form açık', renk: Marka.zumrut)],
        alanlar: [('Abone', sayiYaz(tamsayi(l['subscribed']))), ('Toplam', sayiYaz(tamsayi(l['total']))), ('Onay bekliyor', sayiYaz(tamsayi(l['pending'])))],
        eylemler: _eylemler(l),
        onTap: () => _kisiler(l),
      ),
    );
  }
}

class _ListeDialog extends StatefulWidget {
  const _ListeDialog({required this.b, this.liste});
  final KampanyaBaglami b;
  final Map<String, dynamic>? liste;
  @override
  State<_ListeDialog> createState() => _ListeDialogState();
}

class _ListeDialogState extends State<_ListeDialog> {
  late final _ad = TextEditingController(text: metin(widget.liste?['name']));
  late final _aciklama = TextEditingController(text: metin(widget.liste?['description']));
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _ad.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final govde = {'organization_id': widget.b.orgId, 'name': _ad.text.trim(), 'description': _aciklama.text.trim()};
    try {
      if (widget.liste != null) {
        await Uyg.api.patch('/api/v1/campaigns/lists/${metin(widget.liste!['id'])}', govde);
      } else {
        await Uyg.api.post('/api/v1/campaigns/lists', govde);
      }
      bildir(widget.liste != null ? 'Liste güncellendi' : 'Liste oluşturuldu', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.liste != null ? 'Listeyi düzenle' : 'Yeni liste'),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kişileri amaçlarına göre ayrı listelerde tutun (ör. bülten, müşteriler).', style: TextStyle(color: context.r.soluk, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _ad,
            autofocus: true,
            maxLength: 120,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Ad', counterText: ''),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _aciklama,
            maxLength: 500,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Açıklama', counterText: ''),
          ),
          if (_hata != null) ...[const SizedBox(height: 8), Text(_hata!, style: const TextStyle(color: Marka.gul))],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
      FilledButton(onPressed: _mesgul || _ad.text.trim().isEmpty ? null : _kaydet, child: const Text('Kaydet')),
    ],
  );
}

/// Bir listenin kişileri: arama, durum süzgeci, kişi ekleme, abonelikten çıkarma / yeniden abone yapma, silme.
class KisilerGorunumu extends StatefulWidget {
  const KisilerGorunumu({super.key, required this.liste, required this.acik, required this.degisti});
  final Map<String, dynamic> liste;
  final bool acik;
  final VoidCallback degisti;
  @override
  State<KisilerGorunumu> createState() => _KisilerGorunumuState();
}

class _KisilerGorunumuState extends State<KisilerGorunumu> {
  String _ara = '';
  String _durum = 'all';

  late final _y = SayfaYukleyici<Map<String, dynamic>>(
    (s, b) async => Sayfa.coz(
      await Uyg.api.get(
        '/api/v1/campaigns/lists/${metin(widget.liste['id'])}/contacts',
        q: {'page': '$s', 'page_size': '$b', if (_ara.isNotEmpty) 'q': _ara, if (_durum != 'all') 'status': _durum},
      ),
      (m) => m,
    ),
  )..yenile();

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  void _yenile() {
    _y.yenile();
    widget.degisti();
  }

  Future<void> _durumDegistir(Map<String, dynamic> k, String d) async {
    await islem(
      () => Uyg.api.patch('/api/v1/campaigns/contacts/${metin(k['id'])}', {'status': d}),
      tamam: d == 'unsubscribed' ? 'Kişi abonelikten çıkarıldı' : 'Kişi yeniden abone yapıldı',
    );
    _yenile();
  }

  Future<void> _sil(Map<String, dynamic> k) async {
    final ok = await onayla(
      context,
      'Kişi silinsin mi?',
      mesaj: '${metin(k['email'])} listeden silinir. Abonelikten çıkmış bir adresi yeniden eklemek yerine çıkmış olarak bırakmanız önerilir.',
      evet: 'Sil',
      tehlikeli: true,
    );
    if (!ok) return;
    await islem(() => Uyg.api.delete('/api/v1/campaigns/contacts/${metin(k['id'])}'), tamam: 'Kişi silindi');
    _yenile();
  }

  Future<void> _ekle() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _KisiEkleDialog(liste: widget.liste),
    );
    if (ok == true) _yenile();
  }

  List<SatirEylemi> _eylemler(Map<String, dynamic> k) {
    final d = metin(k['status']);
    return [
      SatirEylemi(Icons.info_outline_rounded, 'Ayrıntılar', () => _ayrinti(k)),
      if (d == 'subscribed' || d == 'pending') SatirEylemi(Icons.person_remove_outlined, 'Abonelikten çıkar', () => _durumDegistir(k, 'unsubscribed')),
      if (d == 'bounced') SatirEylemi(Icons.person_add_alt_outlined, 'Yeniden abone yap', () => _durumDegistir(k, 'subscribed')),
      SatirEylemi(Icons.delete_outline_rounded, 'Sil', () => _sil(k), tehlikeli: true),
    ];
  }

  void _ayrinti(Map<String, dynamic> k) {
    final alanlar = harita(k['fields']);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(metin(k['email']), overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BilgiSatiri('Ad', metin(k['name'])),
              BilgiSatiri('Durum', kisiDurumlari[metin(k['status'])] ?? metin(k['status'])),
              BilgiSatiri('Onay kaynağı', kisiKaynaklari[metin(k['consent_source'])] ?? metin(k['consent_source'])),
              if (tarihOku(k['consent_at']) != null)
                BilgiSatiri('Onay', '${tamZaman(tarihOku(k['consent_at']))}${metin(k['consent_ip']).isNotEmpty ? ' · ${metin(k['consent_ip'])}' : ''}'),
              if (metin(k['consent_note']).isNotEmpty) BilgiSatiri('Not', metin(k['consent_note'])),
              for (final e in alanlar.entries) BilgiSatiri(e.key, metin(e.value)),
              BilgiSatiri('Eklendi', tamZaman(tarihOku(k['created_at']))),
              if (tarihOku(k['unsubscribed_at']) != null) BilgiSatiri('Çıktı', tamZaman(tarihOku(k['unsubscribed_at']))),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
      ),
    );
  }

  Widget _rozet(Map<String, dynamic> k) {
    final d = metin(k['status']);
    return Rozet(kisiDurumlari[d] ?? d, renk: kisiRengi(d, context.r.soluk));
  }

  @override
  Widget build(BuildContext context) {
    return VeriTablosu<Map<String, dynamic>>(
      yukleyici: _y,
      bosMetin: 'Kişi yok.',
      bosIkon: Icons.person_outline_rounded,
      tabloEnAz: 640,
      onTap: _ayrinti,
      eylemler: _eylemler,
      ust: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(context.genis ? 16 : 12, 10, context.genis ? 16 : 12, 0),
            child: Text('Onay bekleyenler e-postadaki doğrulama bağlantısına tıklayınca abone olur.', style: TextStyle(color: context.r.soluk, fontSize: 12.5)),
          ),
          FiltreCubugu(
            arama: AramaAlani(
              ipucu: 'E-posta veya ad ara',
              degisti: (v) {
                _ara = v.trim();
                _y.yenile();
              },
            ),
            filtreler: [
              FiltreDugmesi<String>(
                etiket: 'Durum',
                ikon: Icons.filter_list_rounded,
                secenekler: [('all', 'Tümü'), for (final e in kisiDurumlari.entries) (e.key, e.value)],
                secili: _durum,
                secildi: (v) {
                  setState(() => _durum = v);
                  _y.yenile();
                },
              ),
            ],
            sag: widget.acik ? FilledButton.tonalIcon(onPressed: _ekle, icon: const Icon(Icons.person_add_alt_rounded), label: const Text('Kişi ekle')) : null,
          ),
        ],
      ),
      sutunlar: [
        Sutun('Kişi', esnek: 4, hucre: (c, k) => IkiSatir(metin(k['email']), alt: metinYa(k['name']))),
        Sutun(
          'Durum',
          esnek: 2,
          hucre: (c, k) => Align(alignment: Alignment.centerLeft, child: _rozet(k)),
        ),
        Sutun(
          'Onay kaynağı',
          esnek: 3,
          hucre: (c, k) => IkiSatir(kisiKaynaklari[metin(k['consent_source'])] ?? metin(k['consent_source']), alt: metinYa(k['consent_note']), kalin: false),
        ),
        Sutun('Eklendi', esnek: 2, hucre: (c, k) => SolukMetin(tamZaman(tarihOku(k['created_at'])))),
      ],
      kart: (c, k) => VeriKarti(
        baslik: metin(k['email']),
        alt: metinYa(k['name']),
        rozetler: [_rozet(k)],
        alanlar: [
          ('Onay kaynağı', kisiKaynaklari[metin(k['consent_source'])] ?? metin(k['consent_source'])),
          ('Eklendi', kisaZaman(tarihOku(k['created_at']))),
        ],
        eylemler: _eylemler(k),
        onTap: () => _ayrinti(k),
      ),
    );
  }
}

class _KisiEkleDialog extends StatefulWidget {
  const _KisiEkleDialog({required this.liste});
  final Map<String, dynamic> liste;
  @override
  State<_KisiEkleDialog> createState() => _KisiEkleDialogState();
}

class _KisiEkleDialogState extends State<_KisiEkleDialog> {
  final _eposta = TextEditingController();
  final _ad = TextEditingController();
  final _not = TextEditingController();
  late final List<(TextEditingController, TextEditingController)> _alanlar = [
    for (final f in metinler(widget.liste['fields'])) (TextEditingController(text: f), TextEditingController()),
  ];
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in [
      _eposta,
      _ad,
      _not,
      for (final (a, b) in _alanlar) ...[a, b],
    ]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.post('/api/v1/campaigns/lists/${metin(widget.liste['id'])}/contacts', {
        'email': _eposta.text.trim(),
        'name': _ad.text.trim(),
        'fields': {
          for (final (a, b) in _alanlar)
            if (a.text.trim().isNotEmpty && b.text.trim().isNotEmpty) a.text.trim(): b.text.trim(),
        },
        'consent_note': _not.text.trim(),
      });
      bildir('Kişi eklendi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return AlertDialog(
      title: const Text('Kişi ekle'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Yalnızca size e-posta almak için izin vermiş kişileri ekleyin.', style: TextStyle(color: r.soluk, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: _eposta,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'E-posta'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ad,
                decoration: const InputDecoration(labelText: 'Ad'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _not,
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Onay notu',
                  hintText: 'ör. 12.11.2026 mağazada yazılı izin formu',
                  helperText: 'İznin ne zaman ve nasıl alındığı; denetimde kanıt olarak saklanır.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Özel alanlar',
                style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600),
              ),
              for (var i = 0; i < _alanlar.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: TextField(
                          controller: _alanlar[i].$1,
                          decoration: const InputDecoration(hintText: 'alan'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _alanlar[i].$2,
                          decoration: const InputDecoration(hintText: 'değer'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Alanı kaldır',
                        onPressed: () => setState(() {
                          final (a, b) = _alanlar.removeAt(i);
                          a.dispose();
                          b.dispose();
                        }),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _alanlar.add((TextEditingController(), TextEditingController()))),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Alan ekle'),
                ),
              ),
              if (_hata != null) Text(_hata!, style: const TextStyle(color: Marka.gul)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul || _eposta.text.trim().isEmpty || _not.text.trim().isEmpty ? null : _kaydet, child: const Text('Ekle')),
      ],
    );
  }
}

/// CSV içe aktarma: dosya seçmek yerine CSV metni yapıştırılır (POST .../import, data_base64). Önce önizleme.
class _IceAktarDialog extends StatefulWidget {
  const _IceAktarDialog({required this.liste});
  final Map<String, dynamic> liste;
  @override
  State<_IceAktarDialog> createState() => _IceAktarDialogState();
}

class _IceAktarDialogState extends State<_IceAktarDialog> {
  final _metin = TextEditingController();
  final _not = TextEditingController();
  Map<String, dynamic>? _on;
  bool _mesgul = false;
  String? _hata;
  String _dosyaAdi = 'yapistirilan.csv';
  // Dosyadan yüklenen ham içerik (metin değiştirilmediyse olduğu gibi gönderilir; sunucu kodlamayı kendisi çözer).
  List<int>? _hamBayt;
  String? _hamMetin;

  @override
  void dispose() {
    _metin.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _dosyadan() async {
    final l = await dosyaSec(baslik: 'CSV dosyası seç', uzantilar: const ['csv', 'txt']);
    if (l.isEmpty || !mounted) return;
    final f = l.first;
    if (f.bayt.length > 20 * 1024 * 1024) {
      bildir('Dosya çok büyük', mesaj: 'En fazla 20 MB CSV yüklenebilir.', tur: MesajTur.uyari);
      return;
    }
    setState(() {
      _dosyaAdi = f.ad;
      _metin.text = utf8.decode(f.bayt, allowMalformed: true);
      _hamBayt = f.bayt;
      _hamMetin = _metin.text;
    });
  }

  Future<void> _calistir(bool deneme) async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      final r = harita(
        await Uyg.api.post('/api/v1/campaigns/lists/${metin(widget.liste['id'])}/import', {
          'file_name': _dosyaAdi,
          'data_base64': base64Encode(_hamBayt != null && _metin.text == _hamMetin ? _hamBayt! : utf8.encode(_metin.text)),
          'consent_note': _not.text.trim(),
          'dry_run': deneme,
        }),
      );
      if (!mounted) return;
      if (deneme) {
        setState(() => _on = r);
      } else {
        bildir('${sayiYaz(tamsayi(r['added']))} kişi eklendi, ${sayiYaz(tamsayi(r['updated']))} güncellendi', tur: MesajTur.basari);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final on = _on;
    final hatali = haritalar(on?['invalid']);
    return AlertDialog(
      title: Text('${metin(widget.liste['name'])}: CSV içe aktar', overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CSV içeriğini yapıştırın; ilk sütun (ya da "email" başlıklı sütun) e-posta adresi, "ad"/"name" sütunu ad, diğer sütunlar özel alan olur. '
                'Önce önizleme gösterilir.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
              const SizedBox(height: 10),
              if (on == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _mesgul ? null : _dosyadan,
                    icon: const Icon(Icons.attach_file_rounded, size: 18),
                    label: Text(_dosyaAdi == 'yapistirilan.csv' ? 'Dosyadan yükle' : _dosyaAdi),
                  ),
                ),
              TextField(
                controller: _metin,
                minLines: 5,
                maxLines: 10,
                enabled: on == null,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'CSV metni', hintText: 'email,ad,sehir\nali@ornek.com,Ali,İstanbul', alignLabelWithHint: true),
              ),
              if (on != null) ...[
                const SizedBox(height: 12),
                Izgara(
                  enAz: 120,
                  bosluk: 8,
                  children: [
                    KucukSayi('Geçerli', tamsayi(on['valid'])),
                    KucukSayi('Tekrarlanan', tamsayi(on['duplicates'])),
                    KucukSayi('Bastırılmış', tamsayi(on['suppressed'])),
                    KucukSayi('Hatalı', hatali.length, kotu: hatali.isNotEmpty),
                  ],
                ),
                if (metinler(on['fields']).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Özel alanlar: ${metinler(on['fields']).join(', ')}', style: TextStyle(color: r.silik, fontSize: 12)),
                ],
                for (final s in haritalar(on['sample']).take(5))
                  Text(
                    '${tamsayi(s['line'])}. ${metin(s['email'])}${metin(s['name']).isNotEmpty ? ' · ${metin(s['name'])}' : ''}',
                    style: const TextStyle(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                for (final p in hatali.take(50))
                  Text('Satır ${tamsayi(p['line'])}: ${metin(p['value'])} (${metin(p['reason'])})', style: const TextStyle(fontSize: 12, color: Marka.gul)),
                const SizedBox(height: 6),
                Text('Bastırılmış (daha önce çıkmış / şikâyet etmiş / geri dönmüş) adresler abone yapılmaz.', style: TextStyle(color: r.silik, fontSize: 12)),
                const SizedBox(height: 10),
                TextField(
                  controller: _not,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Onay notu',
                    hintText: 'ör. 2025 fuarında imzalı izin formu ile toplanan liste',
                    helperText: 'Bu kişilerden iznin nasıl alındığını yazın; her kişiye kanıt olarak kaydedilir.',
                    helperMaxLines: 2,
                  ),
                ),
              ],
              if (_hata != null) ...[const SizedBox(height: 8), Text(_hata!, style: const TextStyle(color: Marka.gul))],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        if (on != null) TextButton(onPressed: _mesgul ? null : () => setState(() => _on = null), child: const Text('Düzenle')),
        if (on == null)
          FilledButton(onPressed: _mesgul || _metin.text.trim().isEmpty ? null : () => _calistir(true), child: const Text('Önizle'))
        else
          FilledButton(
            onPressed: _mesgul || _not.text.trim().isEmpty || tamsayi(on['valid']) == 0 ? null : () => _calistir(false),
            child: Text('${sayiYaz(tamsayi(on['valid']))} kişiyi içe aktar'),
          ),
      ],
    );
  }
}

/// Çift onaylı abonelik formu ayarları ve gömülebilir kod.
class _FormDialog extends StatefulWidget {
  const _FormDialog({required this.b, required this.liste});
  final KampanyaBaglami b;
  final Map<String, dynamic> liste;
  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  late bool _acik = mantik(widget.liste['form_enabled']);
  late String? _kutu = metinYa(widget.liste['form_mailbox_id']);
  late final _baslik = TextEditingController(text: metin(widget.liste['form_title']));
  late final _onay = TextEditingController(text: metin(widget.liste['form_consent']));
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    _baslik.dispose();
    _onay.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    try {
      await Uyg.api.patch('/api/v1/campaigns/lists/${metin(widget.liste['id'])}', {
        'organization_id': widget.b.orgId,
        'form_enabled': _acik,
        'form_mailbox_id': _kutu ?? '',
        'form_title': _baslik.text,
        'form_consent': _onay.text,
      });
      bildir('Form ayarları kaydedildi', tur: MesajTur.basari);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mesgul = false;
          _hata = hataMetni(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = widget.liste;
    final kutular = widget.b.gondericiler;
    final adres = '${Uyg.api.sunucu.replaceAll(RegExp(r'/+$'), '')}/api/v1/c/f/${metin(l['form_token'])}';
    final onayMetni = _onay.text.trim().isEmpty ? 'E-posta ile bilgilendirme almayı kabul ediyorum.' : _onay.text.trim();
    final kod =
        '<form action="$adres" method="post">\n'
        '  <input type="email" name="email" placeholder="E-posta adresiniz" required>\n'
        '  <input type="text" name="name" placeholder="Adınız">\n'
        '  <label><input type="checkbox" name="consent" value="1" required> $onayMetni</label>\n'
        '  <div style="position:absolute;left:-9999px" aria-hidden="true"><input type="text" name="website" tabindex="-1" autocomplete="off"></div>\n'
        '  <button type="submit">Abone ol</button>\n'
        '</form>';
    return AlertDialog(
      title: Text('${metin(l['name'])}: abonelik formu', overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Çift onay (double opt-in): forma yazılan adrese doğrulama e-postası gider; kişi bağlantıya tıklayana kadar "Onay bekliyor" durumunda kalır ve kampanya almaz.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Formu yayında tut'),
                value: _acik,
                onChanged: (v) => setState(() => _acik = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: kutular.any((s) => metin(s['mailbox_id']) == _kutu) ? _kutu : null,
                isExpanded: true,
                hint: const Text('Posta kutusu seçin'),
                decoration: const InputDecoration(labelText: 'Doğrulama e-postasını gönderen posta kutusu'),
                items: [
                  for (final s in kutular)
                    DropdownMenuItem(
                      value: metin(s['mailbox_id']),
                      child: Text(metin(s['address']), overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _kutu = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _baslik,
                decoration: InputDecoration(labelText: 'Form başlığı', hintText: metin(l['name'])),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _onay,
                minLines: 2,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Onay metni', hintText: 'E-posta ile kampanya ve duyuru almayı kabul ediyorum.'),
              ),
              const SizedBox(height: 12),
              if (mantik(l['form_enabled']) && metin(l['form_token']).isNotEmpty) ...[
                Text(
                  'Barındırılan form adresi',
                  style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                KopyaKutusu(adres),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Web sitenize eklenecek HTML',
                        style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                    TextButton.icon(onPressed: () => kopyala(kod), icon: const Icon(Icons.copy_rounded, size: 17), label: const Text('Kopyala')),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: r.ic,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: r.kenar),
                  ),
                  child: SelectableText(kod, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
                ),
                const SizedBox(height: 4),
                Text('"website" alanı botlara karşı gizli tuzaktır; kaldırmayın.', style: TextStyle(color: r.silik, fontSize: 12)),
              ] else
                Text('Formu yayına alıp kaydettiğinizde adres ve gömülebilir kod burada görünür.', style: TextStyle(color: r.soluk, fontSize: 13)),
              if (_hata != null) ...[const SizedBox(height: 8), Text(_hata!, style: const TextStyle(color: Marka.gul))],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        FilledButton(onPressed: _mesgul || (_acik && _kutu == null) ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}
