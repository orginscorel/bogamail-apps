import 'dart:async';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../veri/canli.dart';
import '../../veri/modeller.dart';
import '../../veri/sohbet_servisi.dart';
import 'ortak.dart';

/// Bir sohbet odası: iletiler (eskiler yukarı kaydırınca yüklenir), yazma alanı, kendi iletisini silme, canlı güncelleme.
/// Canlı akış bağlı değilken 10 saniyede bir yoklanır.
class SohbetOdasiEkrani extends StatefulWidget {
  const SohbetOdasiEkrani({super.key, required this.odaId, this.sayfa = true, this.kapat});
  final String odaId;

  /// true: kendi AppBar'ı olan tam sayfa; false: geniş ekranın sağ bölmesi.
  final bool sayfa;
  final VoidCallback? kapat;

  @override
  State<SohbetOdasiEkrani> createState() => _SohbetOdasiEkraniState();
}

class _SohbetOdasiEkraniState extends State<SohbetOdasiEkrani> {
  final _metin = TextEditingController();
  final _odak = FocusNode();
  final _kaydirma = ScrollController();
  List<SohbetMesaji> _mesajlar = [];
  bool _yukleniyor = true;
  bool _eskiYukleniyor = false;
  bool _eskiBitti = false;
  bool _gonderiyor = false;
  String? _hata;
  StreamSubscription<CanliOlay>? _abone;
  Timer? _yoklama;

  SohbetOdasi? get _oda {
    for (final o in SohbetDurum.ben.odalar) {
      if (o.id == widget.odaId) return o;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    SohbetDurum.ben.acikOda = widget.odaId;
    SohbetDurum.ben.addListener(_durum);
    _abone = SohbetDurum.ben.olaylar.listen(_canli);
    _kaydirma.addListener(_kaydi);
    _yoklama = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!Canli.ben.bagli.value) _yeniler();
    });
    _yukle();
  }

  @override
  void didUpdateWidget(SohbetOdasiEkrani eski) {
    super.didUpdateWidget(eski);
    if (eski.odaId != widget.odaId) {
      SohbetDurum.ben.acikOda = widget.odaId;
      _mesajlar = [];
      _eskiBitti = false;
      _yukle();
    }
  }

  @override
  void dispose() {
    if (SohbetDurum.ben.acikOda == widget.odaId) SohbetDurum.ben.acikOda = null;
    SohbetDurum.ben.removeListener(_durum);
    _abone?.cancel();
    _yoklama?.cancel();
    _metin.dispose();
    _odak.dispose();
    _kaydirma.dispose();
    super.dispose();
  }

  void _durum() {
    if (mounted) setState(() {});
  }

  void _kaydi() {
    // Liste ters çizildiğinden (en yeni altta) "sonraki" kısım eski iletilerdir.
    if (_kaydirma.position.extentAfter < 300 && !_eskiYukleniyor && !_eskiBitti && _mesajlar.isNotEmpty) _eskiler();
  }

  Future<void> _yukle() async {
    final oda = widget.odaId;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final l = await Sohbet.mesajlar(oda);
      if (!mounted || oda != widget.odaId) return;
      setState(() {
        _mesajlar = l;
        _eskiBitti = l.length < 100;
        _yukleniyor = false;
      });
      unawaited(SohbetDurum.ben.okunduIsaretle(oda));
    } catch (e) {
      if (mounted) {
        setState(() {
          _hata = hataMetni(e);
          _yukleniyor = false;
        });
      }
    }
  }

  Future<void> _eskiler() async {
    setState(() => _eskiYukleniyor = true);
    try {
      final l = await Sohbet.mesajlar(widget.odaId, once: _mesajlar.first.id);
      if (!mounted) return;
      setState(() {
        _mesajlar = [...l, ..._mesajlar];
        _eskiBitti = l.length < 100;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _eskiYukleniyor = false);
    }
  }

  /// Son iletiden yenileri alır.
  Future<void> _yeniler() async {
    if (_yukleniyor) return;
    try {
      final son = _mesajlar.isEmpty ? null : _mesajlar.last.id;
      final l = await Sohbet.mesajlar(widget.odaId, sonra: son);
      if (!mounted || l.isEmpty) return;
      final var_ = _mesajlar.map((m) => m.id).toSet();
      setState(() => _mesajlar = [..._mesajlar, ...l.where((m) => !var_.contains(m.id))]);
      unawaited(SohbetDurum.ben.okunduIsaretle(widget.odaId));
    } catch (_) {}
  }

  /// Silinen iletiler için yüklü aralığı yeniden alır.
  Future<void> _tazele() async {
    try {
      final l = await Sohbet.mesajlar(widget.odaId, sonra: _mesajlar.isEmpty ? null : _mesajlar.first.id - 1);
      if (!mounted) return;
      final yeni = {for (final m in l) m.id: m};
      setState(() => _mesajlar = [for (final m in _mesajlar) yeni[m.id] ?? m, ...l.where((m) => _mesajlar.isEmpty || m.id > _mesajlar.last.id)]);
    } catch (_) {}
  }

  void _canli(CanliOlay o) {
    if ('${o.veri['room_id'] ?? ''}' != widget.odaId) return;
    if (o.tur == 'chat_message') _yeniler();
    if (o.tur == 'chat_update') _tazele();
  }

  Future<void> _gonder() async {
    final t = _metin.text.trim();
    if (t.isEmpty || _gonderiyor) return;
    if (t.characters.length > 4000) {
      bildir('İleti çok uzun', mesaj: 'En fazla 4000 karakter yazabilirsiniz.', tur: MesajTur.uyari);
      return;
    }
    setState(() => _gonderiyor = true);
    try {
      final m = await Sohbet.gonder(widget.odaId, t);
      if (!mounted) return;
      _metin.clear();
      setState(() {
        if (!_mesajlar.any((x) => x.id == m.id)) _mesajlar = [..._mesajlar, m];
      });
      if (_kaydirma.hasClients) _kaydirma.jumpTo(0);
      SohbetDurum.ben.yenile();
    } catch (e) {
      bildir('İleti gönderilemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _gonderiyor = false);
      _odak.requestFocus();
    }
  }

  Future<void> _sil(SohbetMesaji m) async {
    if (!await onayla(context, 'İleti geri çekilsin mi?', mesaj: 'İleti herkes için "silindi" olarak görünür.', evet: 'Geri çek', tehlikeli: true)) return;
    try {
      await Sohbet.mesajSil(widget.odaId, m.id);
      await _tazele();
    } catch (e) {
      bildir('İleti silinemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    }
  }

  void _iletiMenusu(SohbetMesaji m) {
    if (m.silindi) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Kopyala'),
              onTap: () {
                Navigator.pop(c);
                kopyala(m.metin, mesaj: 'İleti kopyalandı');
              },
            ),
            if (m.benim)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Marka.gul),
                title: const Text('Geri çek (herkesten sil)', style: TextStyle(color: Marka.gul)),
                onTap: () {
                  Navigator.pop(c);
                  _sil(m);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _bilgi(SohbetOdasi oda) {
    final benId = SohbetDurum.benId;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(oda.baslik(benId), style: gosterim(18, agirlik: FontWeight.w700)),
              ),
              if (oda.aciklama.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Text(oda.aciklama, style: TextStyle(color: c.r.soluk)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  '${oda.uyeSayisi} üye',
                  style: TextStyle(color: c.r.silik, fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in oda.uyeler)
                      ListTile(
                        leading: VarlikAvatari(kisi: u),
                        title: Text(u.id == benId ? '${u.gorunen} (siz)' : u.gorunen),
                        subtitle: Text(
                          [
                            if (u.durum.isNotEmpty) sohbetDurumAdlari[u.durum] ?? u.durum,
                            if (u.durumMetni.isNotEmpty) u.durumMetni,
                            if (varlikMetni(u).metin.isNotEmpty) varlikMetni(u).metin,
                            if (u.altBilgi.isNotEmpty) u.altBilgi,
                          ].join(' · '),
                          maxLines: 2,
                        ),
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

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final oda = _oda;
    final benId = SohbetDurum.benId;
    final baslik = oda?.baslik(benId) ?? 'Sohbet';
    String alt = '';
    if (oda != null) {
      if (oda.birebir) {
        final k = oda.karsi(benId);
        if (k != null) {
          alt = [
            if (k.durum.isNotEmpty) sohbetDurumAdlari[k.durum] ?? '',
            if (k.durumMetni.isNotEmpty) k.durumMetni,
            varlikMetni(k).metin,
          ].where((s) => s.isNotEmpty).join(' · ');
        }
      } else {
        alt = '${oda.uyeSayisi} üye';
      }
    }
    final ust = Row(
      children: [
        if (oda != null) OdaSimgesi(oda: oda, boyut: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                baslik,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gosterim(17, agirlik: FontWeight.w700),
              ),
              if (alt.isNotEmpty)
                Text(
                  alt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: r.silik, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ),
      ],
    );
    final eylemler = [if (oda != null) IconButton(tooltip: 'Üyeler ve bilgi', icon: const Icon(Icons.info_outline_rounded), onPressed: () => _bilgi(oda))];
    final govde = Column(
      children: [
        Expanded(child: _liste()),
        _yazmaAlani(),
      ],
    );
    if (widget.sayfa) {
      return Scaffold(
        backgroundColor: r.zemin,
        appBar: AppBar(titleSpacing: 0, title: ust, actions: eylemler),
        body: SafeArea(top: false, child: govde),
      );
    }
    return Material(
      color: r.zemin,
      child: Column(
        children: [
          Container(
            height: 60,
            color: r.kart,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: ust),
                ...eylemler,
                if (widget.kapat != null) IconButton(tooltip: 'Kapat', icon: const Icon(Icons.close_rounded), onPressed: widget.kapat),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: govde),
        ],
      ),
    );
  }

  Widget _liste() {
    if (_yukleniyor && _mesajlar.isEmpty) return const Durum.yukleniyor();
    if (_hata != null && _mesajlar.isEmpty) return Durum.hata(_hata!, tekrar: _yukle);
    if (_mesajlar.isEmpty) {
      return const Durum.bos('Henüz ileti yok. İlk iletiyi siz yazın!', ikon: Icons.chat_bubble_outline_rounded);
    }
    final ters = _mesajlar.reversed.toList();
    final grup = _oda != null && !_oda!.birebir;
    return ListView.builder(
      controller: _kaydirma,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: ters.length + (_eskiBitti ? 0 : 1),
      itemBuilder: (c, i) {
        if (i >= ters.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final m = ters[i];
        final onceki = i + 1 < ters.length ? ters[i + 1] : null; // zamanca önceki
        final yeniGun = onceki == null || !_ayniGun(onceki.tarih, m.tarih);
        final ayniKisi =
            !yeniGun && onceki.gonderenId == m.gonderenId && m.tarih != null && onceki.tarih != null && m.tarih!.difference(onceki.tarih!).inMinutes < 5;
        return Column(
          children: [
            if (yeniGun) _gunAyraci(m.tarih),
            MesajBalonu(mesaj: m, adGoster: grup && !m.benim && !ayniKisi, sikisik: ayniKisi, uzunBas: () => _iletiMenusu(m)),
          ],
        );
      },
    );
  }

  static bool _ayniGun(DateTime? a, DateTime? b) => a != null && b != null && a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _gunAyraci(DateTime? d) {
    final r = context.r;
    final n = DateTime.now();
    final metin = d == null
        ? ''
        : _ayniGun(d, n)
        ? 'Bugün'
        : _ayniGun(d, n.subtract(const Duration(days: 1)))
        ? 'Dün'
        : DateFormat('d MMMM y, EEEE', 'tr_TR').format(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(20)),
          child: Text(
            metin,
            style: TextStyle(fontSize: 11.5, color: r.soluk, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _yazmaAlani() {
    final r = context.r;
    final oda = _oda;
    return Container(
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: SafeArea(
        top: false,
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.enter): _gonder},
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('sohbet-yaz'),
                  controller: _metin,
                  focusNode: _odak,
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: oda?.kanal == true ? 'Kanala yazın (@ad ile birinden bahsedin)' : 'İleti yazın',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const ValueKey('sohbet-gonder'),
                tooltip: 'Gönder (Enter)',
                style: IconButton.styleFrom(backgroundColor: r.vurgu, foregroundColor: Colors.white, minimumSize: const Size(46, 46)),
                onPressed: _metin.text.trim().isEmpty || _gonderiyor ? null : _gonder,
                icon: _gonderiyor
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sohbet balonu: kendi iletileri sağda vurgu renginde, diğerleri solda kart renginde. @bahsetmeler vurgulanır.
class MesajBalonu extends StatelessWidget {
  const MesajBalonu({super.key, required this.mesaj, this.adGoster = false, this.sikisik = false, this.uzunBas});
  final SohbetMesaji mesaj;
  final bool adGoster;
  final bool sikisik;
  final VoidCallback? uzunBas;

  static final _bahsetme = RegExp(r'(^|[\s(])(@[\p{L}\p{N}._%+-]+(?:@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+)?)', unicode: true);

  List<InlineSpan> _parcalar(String metin, TextStyle vurgu) {
    final out = <InlineSpan>[];
    var son = 0;
    for (final m in _bahsetme.allMatches(metin)) {
      final bas = m.start + m.group(1)!.length;
      if (bas > son) out.add(TextSpan(text: metin.substring(son, bas)));
      out.add(TextSpan(text: m.group(2), style: vurgu));
      son = m.end;
    }
    if (son < metin.length) out.add(TextSpan(text: metin.substring(son)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ben = mesaj.benim;
    final renk = ben ? r.vurgu : r.kart;
    final yazi = ben ? Colors.white : r.metin;
    final saat = mesaj.tarih == null ? '' : DateFormat('HH:mm').format(mesaj.tarih!);
    return Padding(
      padding: EdgeInsets.only(top: sikisik ? 2 : 8),
      child: Row(
        mainAxisAlignment: ben ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: GestureDetector(
                onLongPress: uzunBas,
                onSecondaryTap: uzunBas,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                  decoration: BoxDecoration(
                    color: mesaj.silindi ? r.ic : renk,
                    border: ben || mesaj.silindi ? null : Border.all(color: r.kenar),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(ben ? 18 : 6),
                      bottomRight: Radius.circular(ben ? 6 : 18),
                    ),
                    boxShadow: ben || mesaj.silindi ? null : r.hafifGolge,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (adGoster)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            mesaj.gonderenAd,
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Avatar.renkFor(mesaj.gonderenId ?? mesaj.gonderenAd)),
                          ),
                        ),
                      if (mesaj.silindi)
                        Text(
                          'Bu ileti geri çekildi',
                          style: TextStyle(fontStyle: FontStyle.italic, color: r.silik, fontSize: 14),
                        )
                      else
                        SelectableText.rich(
                          TextSpan(
                            style: TextStyle(color: yazi, fontSize: 15, height: 1.35),
                            children: _parcalar(
                              mesaj.metin,
                              TextStyle(
                                fontWeight: FontWeight.w800,
                                color: ben ? Colors.white : r.vurgu,
                                backgroundColor: ben ? Colors.white24 : r.vurguYumusak,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Align(
                        alignment: Alignment.bottomRight,
                        widthFactor: 1,
                        child: Text(
                          '$saat${mesaj.duzenlendi != null ? ' · düzenlendi' : ''}',
                          style: TextStyle(fontSize: 10.5, color: ben && !mesaj.silindi ? Colors.white70 : r.silik),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
