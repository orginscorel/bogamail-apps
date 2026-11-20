import 'dart:convert';
import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/dosya.dart';
import '../ortak/simgeler.dart';

// Yönetici profil resmi (web: components/admin/branding.tsx). PUT /auth/avatar {data: base64 PNG/JPEG/GIF},
// DELETE /auth/avatar, resim: GET /users/{id}/avatar (yoksa 404). Sunucu resmi 256×256'ya küçültür; boyut sınırı
// limits.max_avatar_bytes (varsayılan 512 KB). Müşteri görünümündeyken değiştirilemez (sunucu 403 döner).

/// Yüklenmeden önce istemcide uygulanan üst sınır (sunucu sınırı ayrıca denetlenir).
const avatarEnFazla = 2 * 1024 * 1024;

class ProfilResmi extends StatefulWidget {
  const ProfilResmi({super.key, this.boyut = 56, this.duzenlenebilir = true});
  final double boyut;

  /// false: yalnızca resmi gösterir (hesap bloğu gibi kendi dokunma davranışı olan yerler için).
  final bool duzenlenebilir;

  @override
  State<ProfilResmi> createState() => _ProfilResmiState();
}

class _ProfilResmiState extends State<ProfilResmi> {
  Uint8List? _resim;
  bool _mesgul = false;

  String get _id => '${Uyg.ben.value?['id'] ?? ''}';
  bool get _duzenler => widget.duzenlenebilir && Uyg.taklit == null && _id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (_id.isEmpty) return;
    try {
      final b = await Uyg.api.indir('/api/v1/users/$_id/avatar', q: {'v': DateTime.now().millisecondsSinceEpoch});
      if (mounted) setState(() => _resim = b.isEmpty ? null : b);
    } catch (_) {
      if (mounted) setState(() => _resim = null);
    }
  }

  Future<void> _sec() async {
    final l = await dosyaSec(baslik: 'Profil resmi seç', uzantilar: const ['png', 'jpg', 'jpeg', 'gif']);
    if (l.isEmpty) return;
    final b = l.first.bayt;
    if (b.length > avatarEnFazla) {
      bildir('Resim çok büyük', mesaj: 'Daha küçük bir resim seçin (genellikle en fazla 512 KB).', tur: MesajTur.uyari);
      return;
    }
    setState(() => _mesgul = true);
    try {
      await Uyg.api.put('/api/v1/auth/avatar', {'data': base64Encode(b)});
      bildir('Profil resmi güncellendi', tur: MesajTur.basari);
      await _yukle();
    } catch (e) {
      bildir('Profil resmi yüklenemedi', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _kaldir() async {
    if (!await onayla(context, 'Profil resmi kaldırılsın mı?', evet: 'Kaldır', tehlikeli: true)) return;
    setState(() => _mesgul = true);
    try {
      await Uyg.api.delete('/api/v1/auth/avatar');
      bildir('Profil resmi kaldırıldı', tur: MesajTur.basari);
      if (mounted) setState(() => _resim = null);
    } catch (e) {
      bildir('Profil resmi kaldırılamadı', mesaj: hataMetni(e), tur: MesajTur.hata);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final s = widget.boyut;
    final ad = Uyg.ad.isEmpty ? Uyg.adres : Uyg.ad;
    final resim = _resim == null
        ? Avatar(ad, tohum: Uyg.adres, boyut: s)
        : ClipOval(
            child: Image.memory(_resim!, width: s, height: s, fit: BoxFit.cover, gaplessPlayback: true,
                errorBuilder: (_, _, _) => Avatar(ad, tohum: Uyg.adres, boyut: s)),
          );
    if (!_duzenler) return resim;
    return PopupMenuButton<int>(
      tooltip: 'Profil resmini değiştir',
      enabled: !_mesgul,
      onSelected: (v) => v == 0 ? _sec() : _kaldir(),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 0, child: ListTile(leading: Icon(Simgeler.upload), title: Text('Resim yükle'), dense: true)),
        if (_resim != null)
          const PopupMenuItem(value: 1, child: ListTile(leading: Icon(Simgeler.deleteOutline), title: Text('Resmi kaldır'), dense: true)),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          resim,
          if (_mesgul)
            Positioned.fill(child: CircularProgressIndicator(strokeWidth: 2, color: r.vurgu)),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: r.vurgu, shape: BoxShape.circle, border: Border.all(color: r.kart, width: 2)),
              child: const Icon(SimgelerKalin.photoCamera, size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
