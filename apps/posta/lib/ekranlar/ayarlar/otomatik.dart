// Ayarlar → Otomatik yanıt (web VacationSection + AutoRulesCard): izin/tatil yanıtı (tarih aralığı, konu, metin) ve
// kurallı otomatik yanıtlara geçiş.

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../veri/ayar_servisi.dart';
import '../hesap/otomatik_yanit.dart';
import 'ayar_ortak.dart';

class OtomatikYanitAyari extends StatelessWidget {
  const OtomatikYanitAyari({super.key});

  @override
  Widget build(BuildContext context) => SunucuAyarGovdesi(
    olustur: (context, a, kaydet) => [
      _TatilFormu(key: ValueKey('tatil-${a.tatilAcik}|${a.tatilKonu}|${a.tatilMetin.hashCode}|${a.tatilBaslangic}|${a.tatilBitis}'), a: a, kaydet: kaydet),
      AyarKarti(
        ikon: Icons.auto_mode_rounded,
        baslik: 'Otomatik yanıt kuralları',
        aciklama: 'Mesai dışı, belirli günler, iç/dış gönderen veya konuya göre ayrı yanıtlar.',
        sag: a.ozellik('autoresponder') ? null : const DurumRozeti('Paketinizde kapalı', acik: false),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('otomatik-kurallar'),
            onPressed: a.ozellik('autoresponder')
                ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OtomatikYanitKurallariEkrani()))
                : null,
            icon: const Icon(Icons.rule_rounded, size: 18),
            label: const Text('Kuralları yönet'),
          ),
        ),
      ),
    ],
  );
}

class _TatilFormu extends StatefulWidget {
  const _TatilFormu({super.key, required this.a, required this.kaydet});
  final SunucuAyarlari a;
  final AyarKaydedici kaydet;
  @override
  State<_TatilFormu> createState() => _TatilFormuState();
}

class _TatilFormuState extends State<_TatilFormu> {
  late bool _acik = widget.a.tatilAcik;
  late final _konu = TextEditingController(text: widget.a.tatilKonu);
  late final _metin = TextEditingController(text: widget.a.tatilMetin);
  late String _bas = widget.a.tatilBaslangic ?? '';
  late String _bit = widget.a.tatilBitis ?? '';
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    _konu.addListener(() => setState(() {}));
    _metin.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _konu.dispose();
    _metin.dispose();
    super.dispose();
  }

  SunucuAyarlari get a => widget.a;

  bool get _kirli =>
      _acik != a.tatilAcik || _konu.text != a.tatilKonu || _metin.text != a.tatilMetin || _bas != (a.tatilBaslangic ?? '') || _bit != (a.tatilBitis ?? '');

  String? get _aralikHatasi => _bas.isNotEmpty && _bit.isNotEmpty && _bit.compareTo(_bas) < 0 ? 'Bitiş tarihi başlangıçtan önce olamaz.' : null;
  String? get _metinHatasi => _acik && _metin.text.trim().isEmpty ? 'Otomatik yanıt metnini yazın.' : null;

  Future<void> _gonder([Map<String, dynamic>? d]) async {
    setState(() => _mesgul = true);
    await widget.kaydet(
      d ??
          {
            'vacation_enabled': _acik,
            'vacation_subject': _konu.text.trim(),
            'vacation_body': _metin.text,
            'vacation_start': _bas.isEmpty ? null : _bas,
            'vacation_end': _bit.isEmpty ? null : _bit,
          },
      tamam: (d?['vacation_enabled'] ?? _acik) == true ? 'Otomatik yanıt açıldı' : 'Otomatik yanıt kaydedildi',
    );
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _tarihSec(bool baslangic) async {
    final simdi = DateTime.now();
    final mevcut = DateTime.tryParse(baslangic ? _bas : _bit);
    final ilk = baslangic ? DateTime(simdi.year - 1) : (DateTime.tryParse(_bas) ?? DateTime(simdi.year - 1));
    final t = await showDatePicker(
      context: context,
      firstDate: ilk,
      lastDate: DateTime(simdi.year + 3),
      initialDate: mevcut != null && !mevcut.isBefore(ilk) ? mevcut : (simdi.isBefore(ilk) ? ilk : simdi),
      helpText: baslangic ? 'Başlangıç tarihi' : 'Bitiş tarihi',
    );
    if (t == null) return;
    final s = DateFormat('yyyy-MM-dd').format(t);
    setState(() => baslangic ? _bas = s : _bit = s);
  }

  Widget _tarih(bool baslangic) {
    final r = context.r;
    final v = baslangic ? _bas : _bit;
    final t = DateTime.tryParse(v);
    return AyarAlani(
      etiket: baslangic ? 'Başlangıç tarihi' : 'Bitiş tarihi',
      ipucu: baslangic ? 'Boş bırakılırsa hemen başlar.' : 'Bu günün sonunda kendiliğinden kapanır.',
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: ValueKey(baslangic ? 'tatil-bas' : 'tatil-bit'),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () => _tarihSec(baslangic),
              icon: Icon(baslangic ? Icons.event_outlined : Icons.event_available_outlined, size: 18),
              label: Text(t == null ? 'Seçilmedi' : DateFormat('d MMMM y', 'tr_TR').format(t), overflow: TextOverflow.ellipsis),
            ),
          ),
          if (v.isNotEmpty)
            IconButton(
              tooltip: baslangic ? 'Başlangıç tarihini temizle' : 'Bitiş tarihini temizle',
              icon: Icon(Icons.close_rounded, color: r.silik),
              onPressed: () => setState(() => baslangic ? _bas = '' : _bit = ''),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!a.ozellik('autoresponder')) {
      return AyarKarti(
        ikon: Icons.beach_access_outlined,
        baslik: 'Otomatik yanıt',
        aciklama: 'İzindeyken size yazanlara otomatik bir cevap gönderilir.',
        sag: const DurumRozeti('Paketinizde kapalı', acik: false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AyarNotu('Otomatik yanıt özelliği paketinizde kapalı. Kullanmak istiyorsanız kurumunuzun e-posta yöneticisine başvurun.'),
            if (a.tatilAcik) ...[
              const SizedBox(height: 10),
              AyarNotu(
                'Önceden açılmış bir otomatik yanıtınız hâlâ etkin görünüyor.',
                ton: NotTonu.uyari,
                alt: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton(onPressed: _mesgul ? null : () => _gonder({'vacation_enabled': false}), child: const Text('Otomatik yanıtı kapat')),
                ),
              ),
            ],
          ],
        ),
      );
    }
    final hata = _aralikHatasi ?? _metinHatasi;
    return AyarKarti(
      ikon: Icons.beach_access_outlined,
      baslik: 'Otomatik yanıt',
      aciklama: 'İzindeyken veya ofis dışındayken size yazanlara otomatik bir cevap gönderilir.',
      sag: DurumRozeti(a.tatilAcik ? 'Açık' : 'Kapalı', acik: a.tatilAcik),
      alt: KaydetDugmesi(key: const ValueKey('tatil-kaydet'), etkin: _kirli && hata == null, mesgul: _mesgul, basildi: _gonder),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('tatil-ac'),
            contentPadding: EdgeInsets.zero,
            value: _acik,
            onChanged: (v) => setState(() => _acik = v),
            title: const Text('Otomatik yanıtı aç'),
            subtitle: const Text('Tarih seçmezseniz siz kapatana kadar açık kalır.'),
          ),
          const SizedBox(height: 8),
          Opacity(
            opacity: _acik ? 1 : .65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IkiSutun(esik: 520, children: [_tarih(true), _tarih(false)]),
                if (_aralikHatasi != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_aralikHatasi!, style: const TextStyle(color: Marka.gul, fontSize: 12.5)),
                  ),
                AyarAlani(
                  etiket: 'Konu',
                  ipucu: 'Boş bırakılırsa "Otomatik yanıt: (gelen iletinin konusu)" kullanılır.',
                  child: TextField(
                    key: const ValueKey('tatil-konu'),
                    controller: _konu,
                    maxLength: 300,
                    decoration: const InputDecoration(hintText: 'Ofis dışındayım', counterText: ''),
                  ),
                ),
                AyarAlani(
                  etiket: 'Mesaj',
                  child: TextField(
                    key: const ValueKey('tatil-metin'),
                    controller: _metin,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: 20000,
                    decoration: InputDecoration(
                      counterText: '',
                      errorText: _metinHatasi,
                      hintText: 'Merhaba,\n\n20 Ağustos\'a kadar izindeyim. Acil konular için muhasebe@firma.com adresine yazabilirsiniz.\n\nİyi çalışmalar.',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const AyarNotu(
            '• Aynı kişiye 7 günde en fazla bir kez yanıt gönderilir.\n'
            '• E-posta listelerine, toplu gönderimlere ve otomatik postalara (bildirimler, "noreply" adresleri, başka otomatik yanıtlar) yanıt verilmez.\n'
            '• Mesajı değiştirirseniz herkes yeni mesajı bir kez daha alabilir.',
            baslik: 'Nasıl çalışır?',
          ),
        ],
      ),
    );
  }
}
