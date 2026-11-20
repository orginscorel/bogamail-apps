import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../veri/bicim.dart';
import '../veri/json.dart';
import '../ortak/simgeler.dart';

// Kurum geneli otomatik yanıt kuralı (internal/api/autoreply_rules.go autoRule, autorules.Conditions).

const ekipHaftaGunleri = [(1, 'Pzt'), (2, 'Sal'), (3, 'Çar'), (4, 'Per'), (5, 'Cum'), (6, 'Cmt'), (7, 'Paz')];

/// Yeni kural için varsayılan gövde (web: newAutoRule(true)).
Map<String, dynamic> ekipYeniKural() => {
  'id': '',
  'name': '',
  'enabled': true,
  'position': 100,
  'department': '',
  'conditions': {
    'schedule': 'outside',
    'weekdays': [1, 2, 3, 4, 5],
    'start_time': '09:00',
    'end_time': '18:00',
    'sender': 'any',
    'senders': <String>[],
    'subject_keywords': <String>[],
  },
  'subject': '',
  'body_html': '',
  'once_per_days': 4,
  'org_wide': true,
};

/// Kuralın kısa özeti (web: ruleSummary).
String ekipKuralOzeti(Map<String, dynamic> k) {
  final c = harita(k['conditions']);
  final p = <String>[];
  final zaman = metin(c['schedule'], 'always');
  if (zaman != 'always') {
    final gunler = [
      for (final g in (c['weekdays'] is List ? c['weekdays'] as List : const []))
        ?ekipHaftaGunleri.where((w) => w.$1 == tamsayi(g)).map((w) => w.$2).firstOrNull,
    ].join(', ');
    p.add('${zaman == 'outside' ? 'Mesai dışında' : 'Mesai saatlerinde'} ($gunler ${metin(c['start_time'])}–${metin(c['end_time'])})');
  }
  final bas = metin(c['date_from']), son = metin(c['date_to']);
  if (bas.isNotEmpty || son.isNotEmpty) p.add('${bas.isEmpty ? '…' : bas} – ${son.isEmpty ? '…' : son}');
  if (c['sender'] == 'internal') p.add('kurum içi gönderenler');
  if (c['sender'] == 'external') p.add('kurum dışı gönderenler');
  final g = metinler(c['senders']), a = metinler(c['subject_keywords']);
  if (g.isNotEmpty) p.add('gönderen: ${g.join(', ')}');
  if (a.isNotEmpty) p.add('konuda: ${a.join(', ')}');
  if (metin(k['department']).isNotEmpty) p.add('departman: ${k['department']}');
  p.add('aynı kişiye ${tamsayi(k['once_per_days'], 1)} günde bir');
  return p.join(' · ');
}

String _duzdenHtml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll(RegExp(r'\r?\n'), '<br>');

List<String> _listeAyir(String s) => s.split(RegExp(r'[,;\n]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

/// Kural oluşturma / düzenleme. [kaydet] sunucuya yazar (hata fırlatırsa form açık kalır). Kaydedilirse true döner.
class EkipKuralDialog extends StatefulWidget {
  const EkipKuralDialog({super.key, required this.kural, required this.departmanlar, required this.kaydet});
  final Map<String, dynamic> kural;
  final List<String> departmanlar;
  final Future<void> Function(Map<String, dynamic>) kaydet;
  @override
  State<EkipKuralDialog> createState() => _EkipKuralDialogState();
}

class _EkipKuralDialogState extends State<EkipKuralDialog> {
  late final Map<String, dynamic> _k = Map<String, dynamic>.from(widget.kural);
  late final Map<String, dynamic> _c = Map<String, dynamic>.from(harita(widget.kural['conditions']));
  late final _ad = TextEditingController(text: metin(_k['name']));
  late final _departman = TextEditingController(text: metin(_k['department']));
  late final _gonderenler = TextEditingController(text: metinler(_c['senders']).join(', '));
  late final _kelimeler = TextEditingController(text: metinler(_c['subject_keywords']).join(', '));
  late final _konu = TextEditingController(text: metin(_k['subject']));
  late final _govde = TextEditingController(text: htmldenMetin(metin(_k['body_html'])));
  late final _gun = TextEditingController(text: '${tamsayi(_k['once_per_days'], 4)}');
  late bool _etkin = mantik(_k['enabled'], true);
  late String _zaman = metin(_c['schedule'], 'always');
  late String _gonderen = metin(_c['sender'], 'any');
  late Set<int> _gunler = {for (final g in (_c['weekdays'] is List ? _c['weekdays'] as List : const [])) tamsayi(g)};
  late String _baslangic = metin(_c['start_time'], '09:00');
  late String _bitis = metin(_c['end_time'], '18:00');
  late String _tarihBas = metin(_c['date_from']);
  late String _tarihSon = metin(_c['date_to']);
  bool _mesgul = false;
  String? _hata;

  @override
  void dispose() {
    for (final k in [_ad, _departman, _gonderenler, _kelimeler, _konu, _govde, _gun]) {
      k.dispose();
    }
    super.dispose();
  }

  Future<void> _saatSec(bool bas) async {
    final s = (bas ? _baslangic : _bitis).split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(s.first) ?? 9, minute: s.length > 1 ? int.tryParse(s[1]) ?? 0 : 0),
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
    );
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => bas ? _baslangic = v : _bitis = v);
  }

  Future<void> _tarihSec(bool bas) async {
    final simdi = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(bas ? _tarihBas : _tarihSon) ?? simdi,
      firstDate: DateTime(simdi.year - 1),
      lastDate: DateTime(simdi.year + 5),
    );
    if (d == null) return;
    final v = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    setState(() => bas ? _tarihBas = v : _tarihSon = v);
  }

  Future<void> _gonder() async {
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final k = {
      ..._k,
      'name': _ad.text.trim(),
      'enabled': _etkin,
      'department': _departman.text.trim(),
      'subject': _konu.text.trim(),
      'body_html': _duzdenHtml(_govde.text),
      'once_per_days': (int.tryParse(_gun.text.trim()) ?? 1).clamp(1, 365),
      'org_wide': true,
      'conditions': {
        ..._c,
        'schedule': _zaman,
        'weekdays': (_gunler.toList()..sort()),
        'start_time': _baslangic,
        'end_time': _bitis,
        'date_from': _tarihBas,
        'date_to': _tarihSon,
        'sender': _gonderen,
        'senders': _listeAyir(_gonderenler.text),
        'subject_keywords': _listeAyir(_kelimeler.text),
      },
    };
    try {
      await widget.kaydet(k);
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

  Widget _grup(String baslik, List<Widget> c) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: context.r.kenar),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          baslik,
          style: TextStyle(color: context.r.soluk, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...c,
      ],
    ),
  );

  Widget _secimDugmesi(String etiket, String deger, VoidCallback onTap, {VoidCallback? temizle}) => InputDecorator(
    decoration: InputDecoration(
      labelText: etiket,
      suffixIcon: temizle != null && deger.isNotEmpty
          ? IconButton(tooltip: 'Temizle', icon: const Icon(Simgeler.close, size: 18), onPressed: temizle)
          : null,
    ),
    child: InkWell(onTap: onTap, child: Text(deger.isEmpty ? '—' : deger)),
  );

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final yeni = metin(_k['id']).isEmpty;
    return AlertDialog(
      title: Text(yeni ? 'Yeni otomatik yanıt kuralı' : 'Kuralı düzenle'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gelen ileti koşullara uyarsa yanıt gönderilir. Toplu postalar, listeler, otomatik iletiler ve doğrudan alıcı olmayan iletiler (RFC 3834) yanıtlanmaz.',
                style: TextStyle(color: r.soluk, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ad,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Kural adı', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Checkbox(value: _etkin, onChanged: (v) => setState(() => _etkin = v ?? true)),
                  const Text('Etkin'),
                ],
              ),
              const SizedBox(height: 8),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _departman.text),
                optionsBuilder: (v) => widget.departmanlar.where((d) => d.toLowerCase().contains(v.text.toLowerCase())),
                onSelected: (v) => _departman.text = v,
                fieldViewBuilder: (c, k, odak, gonder) => TextField(
                  controller: k,
                  focusNode: odak,
                  maxLength: 100,
                  onChanged: (v) => _departman.text = v,
                  decoration: const InputDecoration(labelText: 'Departman', hintText: 'Boş: tüm kurum', counterText: ''),
                ),
              ),
              _grup('Zaman (Türkiye saati)', [
                DropdownButtonFormField<String>(
                  initialValue: _zaman,
                  decoration: const InputDecoration(labelText: 'Zaman koşulu'),
                  items: const [
                    DropdownMenuItem(value: 'always', child: Text('Her zaman')),
                    DropdownMenuItem(value: 'outside', child: Text('Mesai saatleri dışında')),
                    DropdownMenuItem(value: 'inside', child: Text('Mesai saatleri içinde')),
                  ],
                  onChanged: (v) => setState(() => _zaman = v ?? 'always'),
                ),
                if (_zaman != 'always') ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final (n, e) in ekipHaftaGunleri)
                        FilterChip(
                          label: Text(e),
                          selected: _gunler.contains(n),
                          showCheckmark: false,
                          onSelected: (s) => setState(() => _gunler = s ? ({..._gunler, n}) : (_gunler.where((x) => x != n).toSet())),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _secimDugmesi('Başlangıç', _baslangic, () => _saatSec(true))),
                      const SizedBox(width: 8),
                      Expanded(child: _secimDugmesi('Bitiş', _bitis, () => _saatSec(false))),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _secimDugmesi('Tarih başı (isteğe bağlı)', _tarihBas, () => _tarihSec(true), temizle: () => setState(() => _tarihBas = '')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _secimDugmesi('Tarih sonu', _tarihSon, () => _tarihSec(false), temizle: () => setState(() => _tarihSon = ''))),
                  ],
                ),
              ]),
              _grup('Gönderen ve konu', [
                DropdownButtonFormField<String>(
                  initialValue: _gonderen,
                  decoration: const InputDecoration(labelText: 'Gönderen türü'),
                  items: const [
                    DropdownMenuItem(value: 'any', child: Text('Tüm gönderenler')),
                    DropdownMenuItem(value: 'internal', child: Text('Yalnızca kurum içi')),
                    DropdownMenuItem(value: 'external', child: Text('Yalnızca kurum dışı')),
                  ],
                  onChanged: (v) => setState(() => _gonderen = v ?? 'any'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _gonderenler,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Belirli gönderenler (adres veya @alanadi, virgülle)',
                    hintText: 'ör. @musteri.com.tr, ali@firma.com',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _kelimeler,
                  decoration: const InputDecoration(labelText: 'Konuda geçen kelimeler (virgülle; biri yeterli)', hintText: 'ör. teklif, fatura'),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _konu,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Yanıt konusu (boş: "Otomatik yanıt: …")', counterText: ''),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _govde,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Yanıt metni', alignLabelWithHint: true),
              ),
              const SizedBox(height: 4),
              Text('Değişkenler: {{ad}}, {{unvan}}, {{departman}}, {{telefon}}, {{sirket}}, {{eposta}}', style: TextStyle(color: r.silik, fontSize: 12)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _gun,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Aynı gönderene en fazla (gün)', helperText: '1–365'),
                  ),
                ),
              ),
              if (_hata != null) ...[const SizedBox(height: 8), Text(_hata!, style: const TextStyle(color: Marka.gul))],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _mesgul ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _mesgul ? null : _gonder, child: const Text('Kaydet')),
      ],
    );
  }
}
