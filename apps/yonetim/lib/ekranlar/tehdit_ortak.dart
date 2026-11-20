import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/secimler.dart';
import '../veri/json.dart';

/// Müşteri filtresi çipi (ortak/platform yöneticisi için): seçiliyken dokununca ya da çarpıyla kaldırılır.
class MusteriFiltresi extends StatelessWidget {
  const MusteriFiltresi({super.key, required this.ad, required this.degisti});

  /// Seçili müşteri adı (null = tümü).
  final String? ad;
  final void Function(String? id, String? ad) degisti;

  Future<void> _sec(BuildContext context) async {
    if (ad != null) {
      degisti(null, null);
      return;
    }
    final o = await musteriSec(context);
    if (o != null) degisti(o.id, o.ad);
  }

  @override
  Widget build(BuildContext context) => InputChip(
    avatar: const Icon(Icons.business_rounded, size: 17),
    label: Text(ad ?? 'Tüm müşteriler'),
    selected: ad != null,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    onPressed: () => _sec(context),
    onDeleted: ad == null ? null : () => degisti(null, null),
    deleteButtonTooltipMessage: 'Filtreyi kaldır',
  );
}

/// Oturumdaki kullanıcının kendi müşteri kimliği (org_admin).
String? kendiMusterim() => metinYa(Uyg.ben.value?['organization_id']);

/// Liste ekleme formlarındaki kapsam seçimi: platform yöneticisi "Tüm platform" ya da müşteri, bayi müşteri seçer;
/// müşteri yöneticisi için gösterilmez (sunucu kendi müşterisini kullanır).
class KapsamSecici extends StatelessWidget {
  const KapsamSecici({super.key, required this.orgId, required this.orgAdi, required this.degisti, this.hata});
  final String? orgId, orgAdi, hata;
  final void Function(String? id, String? ad) degisti;

  @override
  Widget build(BuildContext context) {
    if (Uyg.musteri) return const SizedBox.shrink();
    final r = context.r;
    final platform = Uyg.platformYoneticisi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Kapsam', style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (platform)
              ChoiceChip(label: const Text('Tüm platform'), selected: orgId == null, showCheckmark: false, onSelected: (_) => degisti(null, null)),
            ChoiceChip(
              avatar: const Icon(Icons.business_rounded, size: 16),
              label: Text(orgAdi ?? 'Müşteri seçin'),
              selected: orgId != null,
              showCheckmark: false,
              onSelected: (_) async {
                final o = await musteriSec(context);
                if (o != null) degisti(o.id, o.ad);
              },
            ),
          ],
        ),
        if (hata != null) ...[const SizedBox(height: 4), Text(hata!, style: const TextStyle(color: Marka.gul, fontSize: 12))],
      ],
    );
  }
}

/// Açıklama paragrafı (sekme başlarında).
class Aciklama extends StatelessWidget {
  const Aciklama(this.metin, {super.key});
  final String metin;
  @override
  Widget build(BuildContext context) => Text(metin, style: TextStyle(color: context.r.soluk, fontSize: 13, height: 1.4));
}

/// Onay kutulu ayar satırı (başlık + açıklama).
class AyarAnahtari extends StatelessWidget {
  const AyarAnahtari({super.key, required this.baslik, this.ipucu, required this.deger, this.degisti});
  final String baslik;
  final String? ipucu;
  final bool deger;
  final ValueChanged<bool>? degisti;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    value: deger,
    onChanged: degisti,
    title: Text(baslik, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    subtitle: ipucu == null ? null : Text(ipucu!, style: TextStyle(fontSize: 12, color: context.r.silik)),
  );
}

/// Etiket–değer çifti (ayrıntı pencereleri).
class EtiketDeger extends StatelessWidget {
  const EtiketDeger(this.etiket, this.deger, {super.key, this.mono = false, this.sag});
  final String etiket, deger;
  final bool mono;
  final Widget? sag;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 92, child: Text(etiket, style: TextStyle(color: r.soluk, fontSize: 13))),
          Expanded(
            child: sag ??
                SelectableText(deger, style: TextStyle(fontSize: 13.5, fontFamily: mono ? 'monospace' : null, color: r.metin)),
          ),
        ],
      ),
    );
  }
}

/// Ayrıntı penceresi: geniş ekranda iletişim kutusu, telefonda tam sayfa.
Future<void> ayrintiGoster(BuildContext context, {required String baslik, String? alt, required List<Widget> icerik}) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (c) => Scaffold(
          appBar: AppBar(title: Text(baslik, overflow: TextOverflow.ellipsis)),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (alt != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(alt, style: TextStyle(color: c.r.silik, fontSize: 12.5))),
              ...icerik,
            ],
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(baslik, style: gosterim(18, agirlik: FontWeight.w700)),
          if (alt != null) Text(alt, style: TextStyle(color: c.r.silik, fontSize: 12.5, fontWeight: FontWeight.w500)),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: icerik)),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Kapat'))],
    ),
  );
}
