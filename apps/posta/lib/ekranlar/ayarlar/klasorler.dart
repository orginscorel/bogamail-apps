// Ayarlar → Klasörler (web FoldersSection): kendi klasörlerini oluştur / yeniden adlandır / sil; sistem klasörleri ve
// Çöp Kutusu / Gereksiz'i kalıcı boşaltma (onay kutulu).

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../../veri/durum.dart';
import '../../veri/modeller.dart';
import '../../veri/posta_servisi.dart';
import '../hesap/ortak.dart';
import 'ayar_ortak.dart';

const _rolSirasi = ['inbox', 'snoozed', 'drafts', 'sent', 'archive', 'templates', 'junk', 'trash'];

class KlasorlerEkrani extends StatelessWidget {
  const KlasorlerEkrani({super.key});

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<List<Klasor>>(
    baslik: 'Klasörler',
    yukle: Posta.klasorler,
    govde: (context, l, yenile) {
      Future<void> sonra() async {
        PostaDurum.ben.sayilariYenile();
        await yenile();
      }

      final sistem = l.where((k) => k.sistem).toList()
        ..sort((a, b) {
          int s(Klasor k) => _rolSirasi.contains(k.rol) ? _rolSirasi.indexOf(k.rol!) : 99;
          return s(a).compareTo(s(b));
        });
      final kendi = l.where((k) => !k.sistem).toList()..sort((a, b) => a.ad.toLowerCase().compareTo(b.ad.toLowerCase()));
      return [
        AyarKarti(
          ikon: Icons.create_new_folder_outlined,
          baslik: 'Klasörlerim',
          aciklama: 'İletilerinizi düzenlemek için kendi klasörlerinizi oluşturun; süzgeçlerle postaları otomatik taşıyabilirsiniz.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _YeniKlasor(olusturuldu: sonra),
              const SizedBox(height: 12),
              if (kendi.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Henüz klasörünüz yok.', style: TextStyle(color: context.r.soluk)),
                )
              else
                for (final k in kendi) _klasorSatiri(context, k, sonra),
            ],
          ),
        ),
        AyarKarti(
          ikon: Icons.folder_special_outlined,
          baslik: 'Sistem klasörleri',
          aciklama: 'Bu klasörler otomatik oluşturulur; adları değiştirilemez ve silinemez.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final k in sistem)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(k.gorunenAd),
                  trailing: Text(_sayi(k), style: TextStyle(color: context.r.silik, fontSize: 12.5)),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final rol in const ['trash', 'junk'])
                    if (sistem.where((k) => k.rol == rol).firstOrNull case final k?)
                      OutlinedButton.icon(
                        key: ValueKey('bosalt-$rol'),
                        style: OutlinedButton.styleFrom(foregroundColor: Marka.gul),
                        onPressed: k.toplam == 0 ? null : () => _bosalt(context, k, sonra),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: Text(rol == 'trash' ? 'Çöp Kutusu\'nu boşalt' : 'Gereksiz\'i boşalt'),
                      ),
                ],
              ),
            ],
          ),
        ),
      ];
    },
  );

  static String _sayi(Klasor k) => '${sayiYaz(k.toplam)} ileti${k.okunmamis > 0 ? ' · ${sayiYaz(k.okunmamis)} okunmamış' : ''}';

  Widget _klasorSatiri(BuildContext context, Klasor k, Future<void> Function() sonra) => ListTile(
    key: ValueKey('klasor-${k.id}'),
    contentPadding: EdgeInsets.zero,
    leading: Icon(Icons.folder_outlined, color: context.r.soluk),
    title: Text(k.ad, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(_sayi(k)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Yeniden adlandır',
          icon: const Icon(Icons.drive_file_rename_outline),
          onPressed: () async {
            final ad = await metinSor(context, 'Klasörü yeniden adlandır', ilk: k.ad);
            if (ad == null || ad.trim().isEmpty || ad.trim() == k.ad) return;
            await islem(() => Posta.klasorAdlandir(k.id, ad.trim()), tamam: 'Klasör yeniden adlandırıldı');
            await sonra();
          },
        ),
        IconButton(
          tooltip: 'Sil',
          icon: const Icon(Icons.delete_outline_rounded, color: Marka.gul),
          onPressed: () async {
            if (!await onayla(
              context,
              '"${k.ad}" klasörü silinsin mi?',
              mesaj: 'İçindeki iletiler Çöp Kutusu\'na taşınır${k.toplam > 0 ? ' (${sayiYaz(k.toplam)} ileti)' : ''}. Bu klasöre taşıyan süzgeçler de silinir.',
              evet: 'Klasörü sil',
              tehlikeli: true,
            )) {
              return;
            }
            await islem(() => Posta.klasorSil(k.id), tamam: 'Klasör silindi');
            await sonra();
          },
        ),
      ],
    ),
  );

  Future<void> _bosalt(BuildContext context, Klasor k, Future<void> Function() sonra) async {
    var anladim = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, ss) => AlertDialog(
          title: Text(k.rol == 'junk' ? 'Gereksiz klasörü boşaltılsın mı?' : 'Çöp Kutusu boşaltılsın mı?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${k.gorunenAd} klasöründeki ${sayiYaz(k.toplam)} ileti kalıcı olarak silinecek. Bu işlem geri alınamaz.'),
              const SizedBox(height: 8),
              CheckboxListTile(
                key: const ValueKey('bosalt-anladim'),
                contentPadding: EdgeInsets.zero,
                value: anladim,
                onChanged: (v) => ss(() => anladim = v ?? false),
                title: const Text('İletilerin kalıcı olarak silineceğini ve geri alınamayacağını anlıyorum.'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Marka.gul),
              onPressed: anladim ? () => Navigator.pop(c, true) : null,
              child: const Text('Kalıcı olarak sil'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final n = await islem(() => Posta.klasorBosalt(k.id));
    if (n != null) bildir('${sayiYaz(n)} ileti kalıcı olarak silindi', tur: MesajTur.basari);
    await sonra();
  }
}

class _YeniKlasor extends StatefulWidget {
  const _YeniKlasor({required this.olusturuldu});
  final Future<void> Function() olusturuldu;
  @override
  State<_YeniKlasor> createState() => _YeniKlasorState();
}

class _YeniKlasorState extends State<_YeniKlasor> {
  final _ad = TextEditingController();
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _ad.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ad.dispose();
    super.dispose();
  }

  Future<void> _olustur() async {
    final ad = _ad.text.trim();
    if (ad.isEmpty) return;
    setState(() => _mesgul = true);
    final ok = await islem(() => Posta.klasorOlustur(ad).then((_) => true), tamam: 'Klasör oluşturuldu');
    if (ok == true) {
      _ad.clear();
      await widget.olusturuldu();
    }
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          key: const ValueKey('yeni-klasor-ad'),
          controller: _ad,
          maxLength: 100,
          onSubmitted: (_) => _olustur(),
          decoration: const InputDecoration(hintText: 'Yeni klasör adı (örnek: Projeler)', counterText: '', isDense: true),
        ),
      ),
      const SizedBox(width: 10),
      FilledButton.icon(
        key: const ValueKey('yeni-klasor-olustur'),
        onPressed: _ad.text.trim().isEmpty || _mesgul ? null : _olustur,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Oluştur'),
      ),
    ],
  );
}
