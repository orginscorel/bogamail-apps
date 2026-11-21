import 'simge.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'tema.dart';

/// Uygulama genelinde kök gezgin ve bildirim alanı (ekranlardan bağımsız mesaj göstermek için).
final kokGezgin = GlobalKey<NavigatorState>();
final kokMesaj = GlobalKey<ScaffoldMessengerState>();

enum MesajTur { bilgi, basari, uyari, hata }

OverlayEntry? _tost;

/// Kısa bildirim. Postada bilgi / başarı bildirimleri sağ üstte (telefonda üst ortada) kendiliğinden kapanan
/// tost kartıdır ([onde]: avatar / renk noktası); uyarı ve hatalar ile yönetim uygulaması alttan kayan bant.
void bildir(String baslik, {String? mesaj, MesajTur tur = MesajTur.bilgi, Widget? onde}) {
  final kat = kokGezgin.currentState?.overlay;
  if (kimlik == Kimlik.posta && (tur == MesajTur.bilgi || tur == MesajTur.basari) && kat != null && kat.mounted) {
    _tost?.remove();
    late final OverlayEntry e;
    e = OverlayEntry(
      builder: (_) => _Tost(
        baslik: baslik,
        mesaj: mesaj,
        tur: tur,
        onde: onde,
        bitti: () {
          if (_tost == e) _tost = null;
          if (e.mounted) e.remove();
        },
      ),
    );
    _tost = e;
    kat.insert(e);
    return;
  }
  final m = kokMesaj.currentState;
  if (m == null) return;
  final renk = switch (tur) {
    MesajTur.basari => Marka.zumrut,
    MesajTur.uyari => Marka.kehribar,
    MesajTur.hata => Marka.gul,
    MesajTur.bilgi => Marka.mor,
  };
  final ikon = switch (tur) {
    MesajTur.basari => Simge.basari,
    MesajTur.uyari => Simge.uyari,
    MesajTur.hata => Simge.hataDolu,
    MesajTur.bilgi => Simge.bilgiDolu,
  };
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF15142E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: Duration(milliseconds: tur == MesajTur.hata ? 4500 : 2800),
      content: Row(
        children: [
          Icon(ikon, color: renk, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  baslik,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                if (mesaj != null && mesaj.isNotEmpty) Text(mesaj, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Tost kartı: sağ üst (telefonda üst orta), ~2.5 sn sonra solarak kapanır; dokununca hemen kapanır.
class _Tost extends StatefulWidget {
  const _Tost({required this.baslik, required this.mesaj, required this.tur, required this.onde, required this.bitti});
  final String baslik;
  final String? mesaj;
  final MesajTur tur;
  final Widget? onde;
  final VoidCallback bitti;

  @override
  State<_Tost> createState() => _TostState();
}

class _TostState extends State<_Tost> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();
  bool _kapaniyor = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 2500), _kapat);
  }

  Future<void> _kapat() async {
    if (!mounted || _kapaniyor) return;
    _kapaniyor = true;
    await _a.reverse();
    widget.bitti();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final mq = MediaQuery.of(context);
    final genis = mq.size.width >= 600;
    final ikon = widget.tur == MesajTur.basari ? Simge.basari : Simge.bilgiDolu;
    final renk = widget.tur == MesajTur.basari ? Marka.zumrut : r.birincil;
    final kart = Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _kapat,
        child: Container(
          key: const ValueKey('tost'),
          constraints: BoxConstraints(maxWidth: genis ? 360 : mq.size.width - 32),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
          decoration: BoxDecoration(
            color: r.kart,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: r.kenar),
            boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, 4))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget.onde ?? Icon(ikon, color: renk, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.baslik,
                      style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    if (widget.mesaj != null && widget.mesaj!.isNotEmpty) Text(widget.mesaj!, style: TextStyle(color: r.silik, fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final hareket = FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -.25), end: Offset.zero).animate(CurvedAnimation(parent: _a, curve: Curves.easeOut)),
        child: kart,
      ),
    );
    return Positioned(
      top: mq.padding.top + 12,
      right: genis ? 16 : 16,
      left: genis ? null : 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Align(alignment: genis ? Alignment.topRight : Alignment.topCenter, widthFactor: genis ? 1 : null, child: hareket),
      ),
    );
  }
}

/// Hata nesnesini kullanıcıya gösterilecek metne çevirir.
String hataMetni(Object e) => e is ApiHata ? e.mesaj : 'Beklenmeyen bir hata oluştu.';

/// Bir işlemi çalıştırır; hata olursa bildirir. Başarıda [tamam] mesajını gösterir.
Future<T?> islem<T>(Future<T> Function() f, {String? tamam}) async {
  try {
    final v = await f();
    if (tamam != null) bildir(tamam, tur: MesajTur.basari);
    return v;
  } catch (e) {
    bildir('İşlem tamamlanamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    return null;
  }
}

/// Evet/hayır onayı.
Future<bool> onayla(BuildContext context, String baslik, {String? mesaj, String evet = 'Onayla', bool tehlikeli = false}) async {
  final v = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w600)),
      content: mesaj == null ? null : Text(mesaj),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(
          style: tehlikeli ? FilledButton.styleFrom(backgroundColor: Marka.gul) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(evet),
        ),
      ],
    ),
  );
  return v ?? false;
}

/// Tek satırlık metin sorar.
Future<String?> metinSor(BuildContext context, String baslik, {String? ilk, String? ipucu, String tamam = 'Kaydet', bool gizli = false}) {
  final k = TextEditingController(text: ilk);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(baslik, style: gosterim(19, agirlik: FontWeight.w600)),
      content: TextField(
        controller: k,
        autofocus: true,
        obscureText: gizli,
        decoration: InputDecoration(hintText: ipucu),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(c, k.text.trim()), child: Text(tamam)),
      ],
    ),
  );
}

/// Yükleniyor / hata / boş durumlarını tek yerde çizen gövde.
class Durum extends StatelessWidget {
  const Durum.yukleniyor({super.key}) : hata = null, bos = null, ikon = null, tekrar = null;
  const Durum.hata(String this.hata, {super.key, this.tekrar}) : bos = null, ikon = null;
  const Durum.bos(String this.bos, {super.key, this.ikon = Simge.gelen, this.tekrar}) : hata = null;

  final String? hata;
  final String? bos;
  final IconData? ikon;
  final VoidCallback? tekrar;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    if (hata == null && bos == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final h = hata != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: h ? Marka.gul.withValues(alpha: .1) : r.birincilYumusak, shape: BoxShape.circle),
              child: Icon(h ? Simge.cevrimdisi : ikon, size: 34, color: h ? Marka.gul : r.birincil),
            ),
            const SizedBox(height: 16),
            Text(
              h ? hata! : bos!,
              textAlign: TextAlign.center,
              style: TextStyle(color: r.soluk, fontSize: 14.5),
            ),
            if (tekrar != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: tekrar, icon: const Icon(Simge.yenile, size: 18), label: const Text('Tekrar dene')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Basit kart kutusu.
class Kutu extends StatelessWidget {
  const Kutu({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.renk});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Material(
      color: renk ?? r.kart,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: r.kenar),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Bölüm başlığı.
class Baslik extends StatelessWidget {
  const Baslik(this.metin, {super.key, this.sag});
  final String metin;
  final Widget? sag;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            trBuyukHarf(metin),
            style: TextStyle(color: context.r.silik, fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1),
          ),
        ),
        ?sag,
      ],
    ),
  );
}

/// Renkli küçük etiket.
class Rozet extends StatelessWidget {
  const Rozet(this.metin, {super.key, this.renk = Marka.mor, this.ikon});
  final String metin;
  final Color renk;
  final IconData? ikon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: renk.withValues(alpha: .13), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ikon != null) ...[Icon(ikon, size: 13, color: renk), const SizedBox(width: 4)],
        Text(
          metin,
          style: TextStyle(color: renk, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Ad/adres baş harfli renkli yuvarlak.
class Avatar extends StatelessWidget {
  const Avatar(this.ad, {super.key, this.boyut = 40, this.tohum});
  final String ad;
  final double boyut;
  final String? tohum;

  static const _palet = [
    Color(0xFF3B82F6),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
    Color(0xFFF43F5E),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFF0891B2),
    Color(0xFFD946EF),
  ];

  static Color renkFor(String s) {
    var h = 0;
    for (final c in s.toLowerCase().codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palet[h % _palet.length];
  }

  @override
  Widget build(BuildContext context) {
    final renk = renkFor(tohum ?? ad);
    return Container(
      width: boyut,
      height: boyut,
      alignment: Alignment.center,
      // Posta: web gibi düz renk ve küçük baş harfler (size-9 → text-xs); yönetim degradeli.
      decoration: kimlik == Kimlik.posta
          ? BoxDecoration(shape: BoxShape.circle, color: renk)
          : BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(renk, Colors.white, .12)!, renk]),
            ),
      child: Text(
        basHarf(ad),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: boyut * (kimlik == Kimlik.posta ? .34 : .38)),
      ),
    );
  }
}

String basHarf(String adVeyaAdres) {
  final s = adVeyaAdres.replaceAll(RegExp(r'@.*'), '').replaceAll(RegExp(r'[._\-"]+'), ' ').trim();
  final p = s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  final a = p.first.characters.first;
  final b = p.length > 1 ? p.last.characters.first : '';
  return trBuyukHarf(a + b);
}

// ---- biçimlendirme ----

final _saat = DateFormat('HH:mm', 'tr_TR');
final _gunAy = DateFormat('d MMM', 'tr_TR');
final _tam = DateFormat('d MMMM y HH:mm', 'tr_TR');
final _tarih = DateFormat('d.MM.y', 'tr_TR');

DateTime? tarihCoz(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

/// Liste satırı için kısa zaman: bugün → saat, bu yıl → gün ay, eski → tarih.
String kisaZaman(DateTime? d) {
  if (d == null) return '';
  final n = DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return _saat.format(d);
  if (d.year == n.year) return _gunAy.format(d);
  return _tarih.format(d);
}

String tamZaman(DateTime? d) => d == null ? '' : _tam.format(d);

/// "3 dk önce" tarzı göreli zaman.
String goreliZaman(DateTime? d) {
  if (d == null) return '';
  final f = DateTime.now().difference(d);
  if (f.isNegative) return tamZaman(d);
  if (f.inSeconds < 60) return 'az önce';
  if (f.inMinutes < 60) return '${f.inMinutes} dk önce';
  if (f.inHours < 24) return '${f.inHours} sa önce';
  if (f.inDays < 7) return '${f.inDays} gün önce';
  return kisaZaman(d);
}

/// Bayt → "1,2 MB".
String boyutYaz(num? b) {
  if (b == null) return '';
  if (b >= 1125899906842624) return 'Sınırsız';
  const b1 = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < b1.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v >= 100 ? 0 : 1);
  return '${s.replaceAll('.', ',')} ${b1[i]}';
}

final _sayi = NumberFormat.decimalPattern('tr_TR');
String sayiYaz(num? n) => n == null ? '–' : _sayi.format(n);

/// Panoya kopyalar ve bildirir.
Future<void> kopyala(String metin, {String mesaj = 'Kopyalandı'}) async {
  await Clipboard.setData(ClipboardData(text: metin));
  bildir(mesaj, tur: MesajTur.basari);
}

/// Anında geçişli rota (kök değişimleri için).
class HizliRota<T> extends PageRouteBuilder<T> {
  HizliRota({required WidgetBuilder builder})
    : super(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (c, _, _) => builder(c),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );
}

/// Türkçe büyük harf: i → İ, ı → I (Dart toUpperCase "i"yi "I" yapar).
String trBuyukHarf(String s) => s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
