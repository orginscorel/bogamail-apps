import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../veri/durum.dart';
import '../veri/modeller.dart';
import 'simgeler.dart';

/// Taşıma hedefi seçtirir (kullanıcı klasörleri + Gelen + Arşiv).
Future<Klasor?> klasorSec(BuildContext context, {String? haricId}) {
  final hedefler = PostaDurum.ben.tasimaHedefleri(haricId);
  return showModalBottomSheet<Klasor>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Taşınacak klasör', style: gosterim(17, agirlik: FontWeight.w600)),
            ),
            if (hedefler.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Text('Taşınabilecek başka klasör yok. Kenar menüsünden klasör oluşturabilirsiniz.')),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final k in hedefler)
                    ListTile(
                      leading: Icon(klasorSimgesi(k.rol), color: klasorRengi(k.rol)),
                      title: Text(k.gorunenAd),
                      onTap: () => Navigator.pop(c, k),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Etiket seçimi: seçili etiket kümesindeki değişiklikleri döndürür (eklenecek, çıkarılacak).
Future<({Set<String> ekle, Set<String> cikar})?> etiketSec(BuildContext context, Set<String> mevcut) {
  final etiketler = PostaDurum.ben.etiketler;
  final secili = {...mevcut};
  return showModalBottomSheet<({Set<String> ekle, Set<String> cikar})>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, yenile) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Etiketler', style: gosterim(17, agirlik: FontWeight.w600)),
              ),
              if (etiketler.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Henüz etiketiniz yok. Kenar menüsünden etiket oluşturabilirsiniz.')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in etiketler)
                      CheckboxListTile(
                        value: secili.contains(e.id),
                        secondary: Icon(Simge.etiket, color: etiketRengi(e.renk)),
                        title: Text(e.ad),
                        onChanged: (v) => yenile(() => v == true ? secili.add(e.id) : secili.remove(e.id)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, (ekle: secili.difference(mevcut), cikar: mevcut.difference(secili))),
                  child: const Text('Uygula'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Erteleme zamanı (web'deki hazır seçeneklerle aynı) veya özel tarih/saat.
Future<DateTime?> ertelemeSec(BuildContext context) async {
  final simdi = DateTime.now();
  DateTime gun(int ek, int saat) => DateTime(simdi.year, simdi.month, simdi.day + ek, saat);
  final pazartesi = gun(((8 - simdi.weekday) % 7) == 0 ? 7 : (8 - simdi.weekday) % 7, 8);
  final secenekler = [
    ('3 saat sonra', simdi.add(const Duration(hours: 3))),
    ('Bu akşam', gun(0, 18)),
    ('Yarın sabah', gun(1, 8)),
    ('Pazartesi sabah', pazartesi),
    ('Gelecek hafta', gun(7, 8)),
  ].where((s) => s.$2.isAfter(simdi.add(const Duration(minutes: 1)))).toList();
  final bicim = DateFormat('EEE d MMM HH:mm', 'tr_TR');
  final v = await showModalBottomSheet<Object>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Ertele', style: gosterim(17, agirlik: FontWeight.w600)),
          ),
          for (final s in secenekler)
            ListTile(
              leading: const Icon(Simge.saat),
              title: Text(s.$1),
              trailing: Text(bicim.format(s.$2), style: TextStyle(color: context.r.silik, fontSize: 12.5)),
              onTap: () => Navigator.pop(c, s.$2),
            ),
          ListTile(leading: const Icon(Simge.takvimDuzenle), title: const Text('Tarih ve saat seç…'), onTap: () => Navigator.pop(c, 'ozel')),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (v is DateTime) return v;
  if (v != 'ozel' || !context.mounted) return null;
  final t = await showDatePicker(
    context: context,
    firstDate: simdi,
    lastDate: simdi.add(const Duration(days: 365)),
    initialDate: simdi.add(const Duration(days: 1)),
  );
  if (t == null || !context.mounted) return null;
  final s = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
  if (s == null) return null;
  final z = DateTime(t.year, t.month, t.day, s.hour, s.minute);
  if (!z.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
    bildir('Erteleme zamanı gelecekte olmalı', tur: MesajTur.uyari);
    return null;
  }
  return z;
}
