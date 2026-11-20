import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../ortak/bilesenler.dart';
import '../ortak/iskelet.dart';
import '../ortak/sayfali.dart';
import '../ortak/tablo.dart';
import '../oturum.dart';
import '../veri/json.dart';

/// Entegrasyonlar (web: /admin/integrations): faturalama sistemi (WHMCS) API anahtarları. Yalnızca gerçek süper yönetici
/// oturumu (sunucu: requirePlatform). Anahtar oluşturulunca bir kez gösterilir; iptal edilen anahtar hemen reddedilir.
class EntegrasyonlarEkrani extends StatefulWidget {
  const EntegrasyonlarEkrani({super.key});

  @override
  State<EntegrasyonlarEkrani> createState() => _EntegrasyonlarEkraniState();
}

/// GET /api-keys öğesi.
class ApiAnahtari {
  const ApiAnahtari({
    required this.id,
    required this.ad,
    required this.onek,
    required this.ipler,
    required this.olusturma,
    required this.sonKullanim,
    required this.sonIp,
    required this.iptal,
    required this.bagliHesap,
  });
  final String id, ad, onek;
  final List<String> ipler;
  final DateTime? olusturma, sonKullanim, iptal;
  final String? sonIp;
  final int bagliHesap;
  bool get iptalEdildi => iptal != null;

  factory ApiAnahtari.coz(Map<String, dynamic> m) => ApiAnahtari(
    id: metin(m['id']),
    ad: metin(m['name']),
    onek: metin(m['prefix']),
    ipler: metinler(m['allowed_ips']),
    olusturma: tarihOku(m['created_at']),
    sonKullanim: tarihOku(m['last_used_at']),
    sonIp: metinYa(m['last_used_ip']),
    iptal: tarihOku(m['revoked_at']),
    bagliHesap: tamsayi(m['linked_accounts']),
  );
}

class _EntegrasyonlarEkraniState extends State<EntegrasyonlarEkrani> {
  String _taban = '';
  int _bagli = 0;

  late final _y = SayfaYukleyici.yerel<ApiAnahtari>(() async {
    final m = harita(await Uyg.api.get('/api/v1/api-keys'));
    final l = haritalar(m['items']).map(ApiAnahtari.coz).toList();
    // Etkin anahtarlar önce (web ile aynı sıra; sıralama kararlı).
    final sirali = [...l.where((k) => !k.iptalEdildi), ...l.where((k) => k.iptalEdildi)];
    if (mounted) {
      setState(() {
        _taban = metin(m['base_url']);
        _bagli = l.isEmpty ? 0 : l.first.bagliHesap;
      });
    }
    return sirali;
  });

  bool get _izinli => Uyg.platformYoneticisi && Uyg.taklit == null;

  @override
  void initState() {
    super.initState();
    if (_izinli) _y.yenile();
  }

  @override
  void dispose() {
    _y.dispose();
    super.dispose();
  }

  Future<void> _yeni() async {
    final olustu = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => const _AnahtarOlusturDialog());
    if (olustu == true) _y.yenile();
  }

  Future<void> _iptal(ApiAnahtari k) async {
    final ok = await onayla(
      context,
      'Anahtar iptal edilsin mi?',
      mesaj: '"${k.ad}" anahtarıyla yapılan istekler hemen reddedilir. WHMCS otomatik kurulum ve askıya alma işlemleri yeni anahtar girilene kadar durur.',
      evet: 'İptal et',
      tehlikeli: true,
    );
    if (!ok) return;
    final v = await islem(() => Uyg.api.delete('/api/v1/api-keys/${k.id}').then((_) => true), tamam: 'Anahtar iptal edildi');
    if (v == true) _y.yenile();
  }

  String get _host {
    final u = Uri.tryParse(_taban);
    return u == null || u.host.isEmpty ? '…' : u.host;
  }

  Widget _kurulum(BuildContext context) {
    final r = context.r;
    Widget adim(int n, String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text('$n.', style: TextStyle(color: r.silik, fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 13.5))),
        ],
      ),
    );
    return BolumKarti(
      ikon: Icons.extension_rounded,
      baslik: 'WHMCS kurulumu',
      altBaslik: 'Modül: modules/servers/bogamail',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          adim(1, 'Bu sayfada WHMCS sunucusunun IP adresiyle bir anahtar oluşturun.'),
          adim(
            2,
            'WHMCS → Sistem Ayarları → Sunucular → Yeni sunucu: modül BogaMail, ana makine adı $_host, '
            'Erişim Karması / Şifre alanına anahtar. Bağlantıyı test edin.',
          ),
          adim(3, 'Ürün → Modül Ayarları: modül BogaMail, paket kodu (ör. kurumsal-mail-1), "Ödeme alınınca otomatik kur".'),
          adim(4, 'Askıya alma / yeniden açma WHMCS otomasyonundan (gecikmiş fatura) gelir; veri hiçbir zaman silinmez.'),
          const SizedBox(height: 4),
          Text(
            'Bağlı müşteri hesabı: $_bagli. Müşteriler alan adlarını panelden ekler; WHMCS alan adı eklemez.',
            style: TextStyle(color: r.silik, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  String _kullanim(ApiAnahtari k) =>
      k.sonKullanim == null ? 'Kullanılmadı' : '${goreliZaman(k.sonKullanim)}${k.sonIp == null ? '' : ' · ${k.sonIp}'}';

  Widget _durum(BuildContext c, ApiAnahtari k) => k.iptalEdildi ? Rozet('İptal edildi', renk: c.r.silik) : const Rozet('Etkin', renk: Marka.zumrut);

  List<SatirEylemi> _eylemler(ApiAnahtari k) => k.iptalEdildi ? const [] : [SatirEylemi(Icons.block_rounded, 'İptal et', () => _iptal(k), tehlikeli: true)];

  @override
  Widget build(BuildContext context) {
    if (!_izinli) {
      return Iskelet(
        baslik: 'Entegrasyonlar',
        govde: Kapali(
          Uyg.taklit != null ? 'Müşteri görünümündeyken entegrasyonlar yönetilemez.' : 'Bu bölüm yalnızca platform yöneticilerine açıktır.',
        ),
      );
    }
    final tablo = VeriTablosu<ApiAnahtari>(
      yukleyici: _y,
      bosMetin: 'Henüz anahtar yok. WHMCS modülünü bağlamak için bir anahtar oluşturun.',
      bosIkon: Icons.key_rounded,
      tabloEnAz: 640,
      ust: const Padding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Bant('Anahtar yalnızca oluşturulduğunda bir kez gösterilir ve yalnızca izin verilen IP adreslerinden çalışır.', ikon: Icons.key_rounded),
      ),
      sutunlar: [
        Sutun('Ad', esnek: 3, hucre: (c, k) => IkiSatir(k.ad, alt: '${k.onek}…')),
        Sutun('İzinli IP', esnek: 3, hucre: (c, k) => SolukMetin(k.ipler.join(', '), mono: true)),
        Sutun('Son kullanım', esnek: 3, hucre: (c, k) => SolukMetin(_kullanim(k))),
        Sutun('Oluşturuldu', esnek: 2, hucre: (c, k) => SolukMetin(tamZaman(k.olusturma))),
        Sutun('Durum', esnek: 2, hucre: (c, k) => Align(alignment: Alignment.centerLeft, child: _durum(c, k))),
      ],
      eylemler: _eylemler,
      kart: (c, k) => VeriKarti(
        sol: Icon(Icons.key_rounded, color: k.iptalEdildi ? c.r.silik : c.r.birincil),
        baslik: k.ad,
        alt: '${k.onek}…',
        rozetler: [_durum(c, k)],
        alanlar: [('İzinli IP', k.ipler.join(', ')), ('Son kullanım', _kullanim(k)), ('Oluşturuldu', tamZaman(k.olusturma))],
        eylemler: _eylemler(k),
      ),
    );
    return Iskelet(
      baslik: 'Entegrasyonlar',
      alt: 'Faturalama sistemi (WHMCS) bağlantısı',
      yenile: _y.yenile,
      birincil: BirincilEylem(Icons.add_rounded, 'Yeni API anahtarı', _yeni),
      govde: LayoutBuilder(
        builder: (c, k) {
          if (k.maxWidth >= 1200) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tablo),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(0, 4, 16, 16), child: _kurulum(c)),
                ),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: tablo),
              ExpansionTile(
                leading: const Icon(Icons.extension_rounded),
                title: const Text('WHMCS kurulumu'),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [_kurulum(c)],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Yeni anahtar: ad + izinli IP'ler (sunucu: 1–100 karakter ad, 1–20 IP/CIDR, en geniş /24 veya /48). Oluşunca anahtar
/// bir kez gösterilir; diyalog true döner.
class _AnahtarOlusturDialog extends StatefulWidget {
  const _AnahtarOlusturDialog();

  @override
  State<_AnahtarOlusturDialog> createState() => _AnahtarOlusturDialogState();
}

class _AnahtarOlusturDialogState extends State<_AnahtarOlusturDialog> {
  final _ad = TextEditingController(text: 'WHMCS');
  final _ipler = TextEditingController();
  String? _hata, _hataAlani, _anahtar;
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _ipler.dispose();
    super.dispose();
  }

  Future<void> _olustur() async {
    setState(() {
      _mesgul = true;
      _hata = _hataAlani = null;
    });
    try {
      final v = harita(
        await Uyg.api.post('/api/v1/api-keys', {
          'name': _ad.text.trim(),
          'allowed_ips': _ipler.text.split(RegExp(r'[\s,]+')).where((x) => x.isNotEmpty).toList(),
        }),
      );
      if (!mounted) return;
      setState(() => _anahtar = metin(v['key']));
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = e.mesaj;
        _hataAlani = e.alan;
      });
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = _anahtar;
    if (k != null) {
      return AlertDialog(
        title: const Text('Anahtar oluşturuldu'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bu anahtar bir daha gösterilmez. Şimdi WHMCS sunucu ayarına yapıştırın.'),
              const SizedBox(height: 8),
              KopyaKutusu(k, mesaj: 'Anahtar kopyalandı'),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tamam'))],
      );
    }
    final hazir = _ad.text.trim().isNotEmpty && _ipler.text.trim().isNotEmpty;
    return AlertDialog(
      title: const Text('Yeni API anahtarı'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Faturalama sunucusunun IP adresini girin; anahtar başka adresten çalışmaz.'),
              const SizedBox(height: 14),
              TextField(
                controller: _ad,
                maxLength: 100,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: 'Ad', errorText: _hataAlani == 'name' ? _hata : null),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ipler,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'İzinli IP adresleri',
                  hintText: '203.0.113.10',
                  helperText: 'Birden çok adresi virgülle ayırın. En geniş aralık /24.',
                  errorText: _hataAlani == 'allowed_ips' ? _hata : null,
                ),
              ),
              if (_hata != null && _hataAlani != 'name' && _hataAlani != 'allowed_ips') ...[
                const SizedBox(height: 10),
                Text(_hata!, style: const TextStyle(color: Marka.gul, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton.icon(
          onPressed: _mesgul || !hazir ? null : _olustur,
          icon: _mesgul ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.key_rounded),
          label: const Text('Oluştur'),
        ),
      ],
    );
  }
}
