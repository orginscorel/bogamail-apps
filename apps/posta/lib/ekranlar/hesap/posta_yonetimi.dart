import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../ortak/simgeler.dart';
import '../../veri/durum.dart';
import '../../veri/hesap_servisi.dart';
import '../../veri/modeller.dart';
import '../../veri/posta_servisi.dart';
import '../../veri/yardimci.dart';
import 'ortak.dart';

final _tamTarih = DateFormat('d MMM y HH:mm', 'tr_TR');
String _zaman(DateTime? d) => d == null ? '—' : _tamTarih.format(d);

// ---------------------------------------------------------------- planlanan gönderimler

class PlanlananlarEkrani extends StatelessWidget {
  const PlanlananlarEkrani({super.key});

  static const _durumlar = {
    'pending': ('Bekliyor', Marka.mavi),
    'sending': ('Gönderiliyor', Marka.kehribar),
    'sent': ('Gönderildi', Marka.zumrut),
    'failed': ('Başarısız', Marka.gul),
    'cancelled': ('İptal edildi', Color(0xFF94A3B8)),
  };

  Future<void> _ertele(BuildContext context, Planli p, Future<void> Function() yenile) async {
    final simdi = DateTime.now();
    final ilk = p.zaman ?? simdi.add(const Duration(hours: 1));
    final g = await showDatePicker(
      context: context,
      firstDate: simdi,
      lastDate: simdi.add(const Duration(days: 365)),
      initialDate: ilk.isBefore(simdi) ? simdi : ilk,
    );
    if (g == null || !context.mounted) return;
    final s = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(ilk));
    if (s == null) return;
    final z = DateTime(g.year, g.month, g.day, s.hour, s.minute);
    if (!z.isAfter(DateTime.now())) {
      bildir('Gönderim zamanı gelecekte olmalı', tur: MesajTur.uyari);
      return;
    }
    await islem(() => Hesap.planErtele(p.id, z), tamam: 'Gönderim zamanı değiştirildi');
    await yenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<Planli>>(
    baslik: 'Planlanan gönderimler',
    altBaslik: '"Daha sonra gönder" ile zamanladığınız iletiler. Bekleyenlerin zamanını değiştirebilir veya iptal edebilirsiniz.',
    yukle: Hesap.planlananlar,
    govde: (context, l, yenile) {
      if (l.isEmpty) return [const BosKart('Planlanmış gönderim yok.', ikon: Icons.schedule_send_outlined)];
      final r = context.r;
      return [
        KartListe(
          children: [
            for (final p in l)
              ListTile(
                leading: Icon(Icons.schedule_send_rounded, color: r.vurgu),
                title: Text(p.konu.trim().isEmpty ? '(konu yok)' : p.konu, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kime: ${p.kime.isEmpty ? '—' : p.kime.join(', ')}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Rozet(_zaman(p.zaman), ikon: Icons.event_rounded, renk: r.vurgu),
                        Rozet(_durumlar[p.durum]?.$1 ?? p.durum, renk: _durumlar[p.durum]?.$2 ?? Marka.mavi),
                      ],
                    ),
                    if (p.hata.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(p.hata, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
                      ),
                  ],
                ),
                isThreeLine: true,
                trailing: !p.bekliyor
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Seçenekler',
                        onSelected: (v) async {
                          if (v == 'zaman') {
                            await _ertele(context, p, yenile);
                          } else if (await onayla(context, 'Gönderim iptal edilsin mi?', mesaj: 'İleti gönderilmeyecek.', evet: 'İptal et', tehlikeli: true)) {
                            await islem(() => Hesap.planIptal(p.id), tamam: 'Gönderim iptal edildi');
                            await yenile();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'zaman',
                            child: ListTile(leading: Icon(Icons.edit_calendar_rounded), title: Text('Zamanı değiştir')),
                          ),
                          PopupMenuItem(
                            value: 'iptal',
                            child: ListTile(
                              leading: Icon(Icons.cancel_schedule_send_outlined, color: Marka.gul),
                              title: Text('Gönderimi iptal et'),
                            ),
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

// ---------------------------------------------------------------- kişiler

class KisilerEkrani extends StatefulWidget {
  const KisilerEkrani({super.key});
  @override
  State<KisilerEkrani> createState() => _KisilerEkraniState();
}

class _KisilerEkraniState extends State<KisilerEkrani> {
  final _ara = TextEditingController();
  String? _tur; // null | saved | favorite | auto
  List<Kisi>? _l;
  int _toplam = 0;
  String? _hata;
  int _istek = 0;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _ara.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    try {
      final v = await Hesap.kisiler(q: _ara.text, tur: _tur);
      if (!mounted || no != _istek) return;
      setState(() {
        _l = v.ogeler;
        _toplam = v.toplam;
        _hata = null;
      });
    } catch (e) {
      if (mounted && no == _istek) setState(() => _hata = hataMetni(e));
    }
  }

  Future<void> _duzenle([Kisi? k]) async {
    final ad = TextEditingController(text: k?.ad);
    final eposta = TextEditingController(text: k?.eposta);
    final tel = TextEditingController(text: k?.telefon);
    final sirket = TextEditingController(text: k?.sirket);
    final not = TextEditingController(text: k?.not);
    var favori = k?.favori ?? false;
    final tamam = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, yenile) => AlertDialog(
          title: Text(k == null || k.id.isEmpty ? 'Yeni kişi' : 'Kişiyi düzenle', style: gosterim(19, agirlik: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ad,
                    decoration: const InputDecoration(labelText: 'Ad soyad'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: eposta,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-posta adresi'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tel,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Telefon'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sirket,
                    decoration: const InputDecoration(labelText: 'Şirket'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: not,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Not'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: favori,
                    onChanged: (v) => yenile(() => favori = v),
                    title: const Text('Favori'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    final yeni = Kisi(
      id: k?.id ?? '',
      ad: ad.text.trim(),
      eposta: eposta.text.trim(),
      telefon: tel.text.trim(),
      sirket: sirket.text.trim(),
      not: not.text.trim(),
      favori: favori,
    );
    for (final c in [ad, eposta, tel, sirket, not]) {
      c.dispose();
    }
    if (tamam != true) return;
    if (!gecerliEposta(yeni.eposta)) {
      bildir('Geçerli bir e-posta adresi yazın', tur: MesajTur.uyari);
      return;
    }
    await islem(() => Hesap.kisiKaydet(yeni), tamam: 'Kişi kaydedildi');
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final l = _l;
    return Scaffold(
      appBar: AppBar(title: const Text('Kişiler')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _duzenle(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Kişi ekle'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: TextField(
                  controller: _ara,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _yukle(),
                  onChanged: (_) => _yukle(),
                  decoration: const InputDecoration(hintText: 'Ad, adres veya şirket ara', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final t in const [(null, 'Tümü'), ('favorite', 'Favoriler'), ('saved', 'Kaydedilenler'), ('auto', 'Otomatik eklenenler')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(t.$2),
                          selected: _tur == t.$1,
                          showCheckmark: false,
                          selectedColor: r.vurgu,
                          labelStyle: TextStyle(color: _tur == t.$1 ? Colors.white : r.metin, fontWeight: FontWeight.w600),
                          onSelected: (_) {
                            setState(() => _tur = t.$1);
                            _yukle();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _hata != null && l == null
                    ? Durum.hata(_hata!, tekrar: _yukle)
                    : l == null
                    ? const Durum.yukleniyor()
                    : RefreshIndicator(
                        onRefresh: _yukle,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          children: [
                            if (l.isEmpty)
                              const BosKart('Kişi bulunamadı. Yazıştığınız adresler otomatik olarak eklenir.', ikon: Icons.contacts_outlined)
                            else ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                child: Text(
                                  '${sayiYaz(_toplam)} kişi',
                                  style: TextStyle(color: r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                              KartListe(children: [for (final k in l) _satir(k)]),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _satir(Kisi k) {
    final r = context.r;
    final ad = k.ad.isEmpty ? k.eposta : k.ad;
    return ListTile(
      leading: Avatar(ad, boyut: 40, tohum: k.eposta),
      title: Row(
        children: [
          Flexible(
            child: Text(
              ad,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (k.otomatik) ...[const SizedBox(width: 6), const Rozet('Otomatik', renk: Color(0xFF94A3B8))],
        ],
      ),
      subtitle: Text([k.eposta, if (k.sirket.isNotEmpty) k.sirket].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => _duzenle(k),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: k.favori ? 'Favorilerden çıkar' : 'Favorilere ekle',
            icon: Icon(k.favori ? Icons.star_rounded : Icons.star_border_rounded, color: k.favori ? Marka.kehribar : r.silik),
            onPressed: () async {
              await islem(() => Hesap.kisiKaydet(k.kopya(favori: !k.favori)));
              await _yukle();
            },
          ),
          IconButton(
            tooltip: 'Sil',
            icon: Icon(Icons.delete_outline_rounded, color: r.silik),
            onPressed: () async {
              if (!await onayla(context, '"$ad" silinsin mi?', evet: 'Sil', tehlikeli: true)) return;
              await islem(() => Hesap.kisiSil(k.id), tamam: 'Kişi silindi');
              await _yukle();
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- güvenilir / engelli gönderenler

class GondericiListeleriEkrani extends StatefulWidget {
  const GondericiListeleriEkrani({super.key});
  @override
  State<GondericiListeleriEkrani> createState() => _GondericiListeleriEkraniState();
}

class _GondericiListeleriEkraniState extends State<GondericiListeleriEkrani> {
  String _tur = 'block';

  Future<void> _ekle(Future<void> Function() yenile) async {
    final v = await metinSor(context, _tur == 'block' ? 'Engellenecek gönderen' : 'Güvenilir gönderen', ipucu: 'ad@ornek.com veya @ornek.com', tamam: 'Ekle');
    if (v == null || v.trim().isEmpty) return;
    final d = v.trim();
    if (!(d.startsWith('@') && d.length > 3 && d.contains('.')) && !gecerliEposta(d)) {
      bildir('Bir e-posta adresi veya @alanadi yazın', tur: MesajTur.uyari);
      return;
    }
    await islem(() => Hesap.gondericiEkle(_tur, d), tamam: _tur == 'block' ? 'Gönderen engellendi' : 'Güvenilir listesine eklendi');
    await yenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<GondericiKaydi>>(
    baslik: 'Güvenilir ve engelli gönderenler',
    altBaslik: 'Engellenen gönderenlerin iletileri doğrudan Gereksiz klasörüne gider. Güvenilir gönderenler hiçbir zaman gereksiz sayılmaz.',
    yukle: Hesap.gondericiListeleri,
    fab: (context, yenile) => FloatingActionButton.extended(onPressed: () => _ekle(yenile), icon: const Icon(Icons.add_rounded), label: const Text('Ekle')),
    govde: (context, l, yenile) {
      final r = context.r;
      final secili = l.where((k) => k.tur == _tur).toList();
      return [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'block', icon: const Icon(Icons.block_rounded), label: Text('Engelli (${l.where((k) => k.tur == 'block').length})')),
            ButtonSegment(
              value: 'allow',
              icon: const Icon(Icons.verified_user_outlined),
              label: Text('Güvenilir (${l.where((k) => k.tur == 'allow').length})'),
            ),
          ],
          selected: {_tur},
          onSelectionChanged: (s) => setState(() => _tur = s.first),
        ),
        const SizedBox(height: 12),
        if (secili.isEmpty)
          BosKart(
            _tur == 'block' ? 'Engellenmiş gönderen yok.' : 'Güvenilir gönderen yok.',
            ikon: _tur == 'block' ? Icons.block_rounded : Icons.verified_user_outlined,
          )
        else
          KartListe(
            children: [
              for (final k in secili)
                ListTile(
                  leading: Icon(_tur == 'block' ? Icons.block_rounded : Icons.verified_user_rounded, color: _tur == 'block' ? Marka.gul : Marka.zumrut),
                  title: Text(k.deger),
                  subtitle: k.tarih == null ? null : Text('Eklenme: ${_zaman(k.tarih)}'),
                  trailing: IconButton(
                    tooltip: 'Listeden çıkar',
                    icon: Icon(Icons.close_rounded, color: r.silik),
                    onPressed: () async {
                      await islem(() => Hesap.gondericiSil(k.id), tamam: 'Listeden çıkarıldı');
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

// ---------------------------------------------------------------- yönlendirme

class YonlendirmeEkrani extends StatefulWidget {
  const YonlendirmeEkrani({super.key});
  @override
  State<YonlendirmeEkrani> createState() => _YonlendirmeEkraniState();
}

class _YonlendirmeEkraniState extends State<YonlendirmeEkrani> {
  final _adres = TextEditingController();
  bool _kopya = true;
  bool _hazir = false;

  @override
  void dispose() {
    _adres.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<Yonlendirme>(
    baslik: 'Yönlendirme',
    yukle: () async {
      final y = await Hesap.yonlendirme();
      if (!_hazir) {
        _adres.text = y.adres;
        _kopya = y.kopyaKalsin;
        _hazir = true;
      }
      return y;
    },
    govde: (context, y, yenile) {
      final r = context.r;
      final yonetici = y.belirleyen.startsWith('admin');
      return [
        Kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(y.adres.isEmpty ? Icons.forward_to_inbox_outlined : Icons.forward_to_inbox_rounded, color: y.adres.isEmpty ? r.silik : r.vurgu),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      y.adres.isEmpty ? 'Yönlendirme kapalı' : 'Gelen postalar ${y.adres} adresine yönlendiriliyor',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (!y.izinli)
                Text('Paketiniz yönlendirmeye izin vermiyor.', style: TextStyle(color: r.soluk))
              else ...[
                TextField(
                  controller: _adres,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Yönlendirilecek adres', hintText: 'Boş bırakırsanız yönlendirme kapanır'),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _kopya,
                  onChanged: (v) => setState(() => _kopya = v),
                  title: const Text('Bu posta kutusunda da bir kopya tut'),
                ),
                if (!y.disIzinli) Text('Yalnızca kurumunuzdaki adreslere yönlendirebilirsiniz.', style: TextStyle(color: r.silik, fontSize: 12.5)),
                if (yonetici)
                  Text(
                    'Bu yönlendirme yöneticiniz tarafından ayarlandı. Değiştirirseniz sizin ayarınız geçerli olur.',
                    style: TextStyle(color: r.silik, fontSize: 12.5),
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (y.adres.isNotEmpty)
                      TextButton(
                        onPressed: () async {
                          await islem(() => Hesap.yonlendirmeKaydet('', true), tamam: 'Yönlendirme kapatıldı');
                          _adres.clear();
                          await yenile();
                        },
                        child: const Text('Kapat'),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final a = _adres.text.trim();
                        if (a.isNotEmpty && !gecerliEposta(a)) {
                          bildir('Geçerli bir e-posta adresi yazın', tur: MesajTur.uyari);
                          return;
                        }
                        await islem(() => Hesap.yonlendirmeKaydet(a, _kopya), tamam: a.isEmpty ? 'Yönlendirme kapatıldı' : 'Yönlendirme kaydedildi');
                        await yenile();
                      },
                      child: const Text('Kaydet'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ];
    },
  );
}

// ---------------------------------------------------------------- karantina

class KarantinaEkrani extends StatelessWidget {
  const KarantinaEkrani({super.key});
  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<KarantinaKaydi>>(
    baslik: 'Karantina',
    altBaslik: 'Güvenlik taramasında tutulan ve size teslim edilmeyen iletiler. Serbest bırakılması için yöneticinize başvurun.',
    yukle: Hesap.karantina,
    govde: (context, l, _) {
      if (l.isEmpty) return [const BosKart('Karantinada ileti yok.', ikon: Icons.shield_outlined)];
      return [
        KartListe(
          children: [
            for (final k in l)
              ListTile(
                leading: const Icon(Icons.gpp_maybe_outlined, color: Marka.kehribar),
                title: Text(k.konu.trim().isEmpty ? '(konu yok)' : k.konu, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${k.gonderen}\n${k.neden} · ${_zaman(k.tarih)}${k.bitis == null ? '' : ' · Silinme: ${_zaman(k.bitis)}'}'),
                isThreeLine: true,
              ),
          ],
        ),
      ];
    },
  );
}

// ---------------------------------------------------------------- gönderim durumu

class GonderimDurumuEkrani extends StatefulWidget {
  const GonderimDurumuEkrani({super.key});
  @override
  State<GonderimDurumuEkrani> createState() => _GonderimDurumuEkraniState();
}

class _GonderimDurumuEkraniState extends State<GonderimDurumuEkrani> {
  String _yon = 'out';
  String _q = '';

  static Color _ton(String t) => switch (t) {
    'ok' => Marka.zumrut,
    'bad' => Marka.gul,
    'warn' => Marka.kehribar,
    _ => Marka.mavi,
  };

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<GonderimOlayi>>(
    key: ValueKey('$_yon|$_q'),
    baslik: 'Gönderim durumu',
    yukle: () => Hesap.gonderimDurumu(_yon, q: _q),
    govde: (context, l, _) => [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'out', icon: Icon(Icons.north_east_rounded), label: Text('Gönderilen')),
          ButtonSegment(value: 'in', icon: Icon(Icons.south_west_rounded), label: Text('Gelen')),
        ],
        selected: {_yon},
        onSelectionChanged: (s) => setState(() => _yon = s.first),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: TextEditingController(text: _q),
        textInputAction: TextInputAction.search,
        onSubmitted: (v) => setState(() => _q = v.trim()),
        decoration: const InputDecoration(hintText: 'Adres veya konu ara', prefixIcon: Icon(Icons.search_rounded), isDense: true),
      ),
      const SizedBox(height: 12),
      if (l.isEmpty)
        const BosKart('Kayıt bulunamadı.', ikon: Icons.local_shipping_outlined)
      else
        KartListe(
          children: [
            for (final o in l)
              ListTile(
                title: Text(_yon == 'out' ? o.alici : o.gonderen, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      children: [
                        Rozet(o.durumEtiketi, renk: _ton(o.ton)),
                        Rozet(_zaman(o.zaman), renk: const Color(0xFF94A3B8)),
                      ],
                    ),
                    if (o.ozet.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(o.ozet)),
                    if (o.cozum.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Öneri: ${o.cozum}', style: const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                  ],
                ),
              ),
          ],
        ),
    ],
  );
}

// ---------------------------------------------------------------- yedekler

class YedeklerEkrani extends StatelessWidget {
  const YedeklerEkrani({super.key});

  Future<void> _geriYukle(BuildContext context, Yedek y) async {
    final kip = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('${_zaman(y.tarih)} yedeğini geri yükle', style: gosterim(17, agirlik: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Ayrı bir klasöre'),
              subtitle: const Text('Önerilen: iletiler "Geri yüklenenler" altında yeni bir klasöre konur.'),
              onTap: () => Navigator.pop(c, 'restore_folder'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore_rounded),
              title: const Text('Özgün klasörlerine'),
              subtitle: const Text('Eksik iletiler eski yerlerine döner; var olanlar tekrarlanmaz.'),
              onTap: () => Navigator.pop(c, 'original'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kip == null) return;
    final s = await islem(() => Hesap.yedekGeriYukle(y.calisma, kip));
    if (s != null) {
      bildir(
        '${sayiYaz(s.geriYuklenen)} / ${sayiYaz(s.toplam)} ileti geri yüklendi',
        mesaj: s.klasor.isEmpty ? null : 'Klasör: ${s.klasor}',
        tur: MesajTur.basari,
      );
    }
    PostaDurum.ben.sayilariYenile();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<({List<Yedek> ogeler, int saklama})>(
    baslik: 'Yedekler',
    yukle: Hesap.yedekler,
    govde: (context, v, _) => [
      if (v.saklama > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Yedekler ${v.saklama} gün saklanır.', style: TextStyle(color: context.r.soluk)),
        ),
      if (v.ogeler.isEmpty)
        const BosKart('Henüz yedek yok.', ikon: Icons.backup_outlined)
      else
        KartListe(
          children: [
            for (final y in v.ogeler)
              ListTile(
                leading: Icon(Icons.backup_rounded, color: context.r.vurgu),
                title: Text(_zaman(y.tarih)),
                subtitle: Text('${sayiYaz(y.ileti)} ileti · ${boyutYaz(y.boyut)}'),
                trailing: TextButton(onPressed: () => _geriYukle(context, y), child: const Text('Geri yükle')),
              ),
          ],
        ),
    ],
  );
}

// ---------------------------------------------------------------- etiketler

class EtiketlerEkrani extends StatelessWidget {
  const EtiketlerEkrani({super.key});

  Future<String?> _renkSec(BuildContext context, String mevcut) => showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final e in etiketRenkleri.entries)
              Tooltip(
                message: etiketRenkAdlari[e.key] ?? e.key,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(c, e.key),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: e.value,
                    child: e.key == mevcut ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  /// Yeni etiket: ad ve renk (web LabelsSection ile aynı).
  Future<({String ad, String renk})?> _yeniEtiket(BuildContext context) {
    final ad = TextEditingController();
    var renk = 'blue';
    return showDialog<({String ad, String renk})>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: const Text('Yeni etiket'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('yeni-etiket-ad'),
                controller: ad,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Etiket adı', counterText: ''),
                onChanged: (_) => ss(() {}),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final e in etiketRenkleri.entries)
                    Tooltip(
                      message: etiketRenkAdlari[e.key] ?? e.key,
                      child: InkWell(
                        key: ValueKey('yeni-etiket-renk-${e.key}'),
                        customBorder: const CircleBorder(),
                        onTap: () => ss(() => renk = e.key),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: e.value,
                          child: e.key == renk ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
            FilledButton(onPressed: ad.text.trim().isEmpty ? null : () => Navigator.pop(c, (ad: ad.text.trim(), renk: renk)), child: const Text('Oluştur')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<Etiket>>(
    baslik: 'Etiketler',
    altBaslik: 'Etiketler iletileri klasör değiştirmeden gruplar. Bir iletiye birden fazla etiket verebilirsiniz.',
    yukle: Posta.etiketler,
    fab: (context, yenile) => FloatingActionButton.extended(
      onPressed: () async {
        final y = await _yeniEtiket(context);
        if (y == null) return;
        await islem(() => Posta.etiketOlustur(y.ad, y.renk), tamam: 'Etiket oluşturuldu');
        PostaDurum.ben.sayilariYenile(listeler: false);
        await yenile();
      },
      icon: const Icon(Icons.new_label_outlined),
      label: const Text('Etiket ekle'),
    ),
    govde: (context, l, yenile) {
      if (l.isEmpty) return [const BosKart('Henüz etiket yok.', ikon: Icons.label_outline_rounded)];
      Future<void> sonra() async {
        PostaDurum.ben.sayilariYenile(listeler: false);
        await yenile();
      }

      return [
        KartListe(
          children: [
            for (final e in l)
              ListTile(
                leading: Icon(Icons.label_rounded, color: etiketRengi(e.renk)),
                title: Text(e.ad),
                subtitle: Text('${sayiYaz(e.toplam)} ileti${e.okunmamis > 0 ? ' · ${sayiYaz(e.okunmamis)} okunmamış' : ''}'),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Seçenekler',
                  onSelected: (v) async {
                    switch (v) {
                      case 'ad':
                        final ad = await metinSor(context, 'Etiketi yeniden adlandır', ilk: e.ad);
                        if (ad == null || ad.trim().isEmpty || ad.trim() == e.ad) return;
                        await islem(() => Hesap.etiketGuncelle(e.id, ad: ad.trim()), tamam: 'Etiket güncellendi');
                      case 'renk':
                        final r = await _renkSec(context, e.renk);
                        if (r == null || r == e.renk) return;
                        await islem(() => Hesap.etiketGuncelle(e.id, renk: r), tamam: 'Renk değiştirildi');
                      case 'sil':
                        if (!context.mounted ||
                            !await onayla(
                              context,
                              '"${e.ad}" silinsin mi?',
                              mesaj: 'İletiler silinmez, yalnızca bu etiket kaldırılır.',
                              evet: 'Sil',
                              tehlikeli: true,
                            )) {
                          return;
                        }
                        await islem(() => Hesap.etiketSil(e.id), tamam: 'Etiket silindi');
                    }
                    await sonra();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'ad',
                      child: ListTile(leading: Icon(Icons.drive_file_rename_outline), title: Text('Yeniden adlandır')),
                    ),
                    PopupMenuItem(
                      value: 'renk',
                      child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('Rengi değiştir')),
                    ),
                    PopupMenuItem(
                      value: 'sil',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: Marka.gul),
                        title: Text('Sil'),
                      ),
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
