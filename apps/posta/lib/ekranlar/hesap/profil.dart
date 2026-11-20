import 'dart:typed_data';

import 'package:boga_ortak/boga_ortak.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../veri/hesap_servisi.dart';
import 'ortak.dart';

/// İmza değişkenlerini dolduran profil bilgileri (unvan, departman, telefon, sosyal bağlantılar).
class ImzaProfiliEkrani extends StatefulWidget {
  const ImzaProfiliEkrani({super.key});
  @override
  State<ImzaProfiliEkrani> createState() => _ImzaProfiliEkraniState();
}

class _ImzaProfiliEkraniState extends State<ImzaProfiliEkrani> {
  static const _sosyalAdlar = {'linkedin': 'LinkedIn', 'x': 'X (Twitter)', 'instagram': 'Instagram', 'facebook': 'Facebook', 'youtube': 'YouTube'};
  final _alanlar = <String, TextEditingController>{};
  bool _hazir = false;

  TextEditingController _c(String k) => _alanlar.putIfAbsent(k, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _alanlar.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => YukleyiciSayfa<ImzaProfili>(
    baslik: 'Profil bilgileri',
    altBaslik: 'Kurum imza şablonundaki unvan, departman, telefon gibi alanlar buradan doldurulur.',
    yukle: () async {
      final p = await Hesap.profil();
      if (!_hazir) {
        _c('title').text = p.unvan;
        _c('department').text = p.departman;
        _c('phone').text = p.telefon;
        _c('mobile').text = p.cep;
        _c('web').text = p.web;
        for (final k in _sosyalAdlar.keys) {
          _c('s_$k').text = p.sosyal[k] ?? '';
        }
        _hazir = true;
      }
      return p;
    },
    govde: (context, p, yenile) {
      Widget alan(String k, String e, {TextInputType? tur}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _c(k),
          enabled: p.duzenlenebilir,
          keyboardType: tur,
          decoration: InputDecoration(labelText: e),
        ),
      );
      return [
        const AvatarKarti(),
        const SizedBox(height: 12),
        Kutu(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!p.duzenlenebilir)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Profil bilgileriniz kurumunuz tarafından yönetiliyor.', style: TextStyle(color: context.r.soluk)),
                ),
              alan('title', 'Unvan'),
              alan('department', 'Departman'),
              alan('phone', 'Telefon', tur: TextInputType.phone),
              alan('mobile', 'Cep telefonu', tur: TextInputType.phone),
              alan('web', 'Web sitesi', tur: TextInputType.url),
              const Baslik('Sosyal medya'),
              for (final e in _sosyalAdlar.entries) alan('s_${e.key}', e.value, tur: TextInputType.url),
              if (p.duzenlenebilir)
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () async {
                      await islem(
                        () => Hesap.profilKaydet({
                          'title': _c('title').text.trim(),
                          'department': _c('department').text.trim(),
                          'phone': _c('phone').text.trim(),
                          'mobile': _c('mobile').text.trim(),
                          'web': _c('web').text.trim(),
                          'social': {
                            for (final k in _sosyalAdlar.keys)
                              if (_c('s_$k').text.trim().isNotEmpty) k: _c('s_$k').text.trim(),
                          },
                        }),
                        tamam: 'Profil kaydedildi',
                      );
                      await yenile();
                    },
                    child: const Text('Kaydet'),
                  ),
                ),
            ],
          ),
        ),
      ];
    },
  );
}

/// Profil resmi: görüntüleme, yükleme (PNG/JPEG/GIF; boyut sınırını sunucu belirler, varsayılan 512 KB) ve kaldırma.
class AvatarKarti extends StatefulWidget {
  const AvatarKarti({super.key});
  @override
  State<AvatarKarti> createState() => _AvatarKartiState();
}

class _AvatarKartiState extends State<AvatarKarti> {
  Uint8List? _resim;
  bool _var = false;
  bool _mesgul = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final b = await Hesap.avatarBilgisi();
      Uint8List? r;
      if (b.var_ && b.kutuId.isNotEmpty) r = await Hesap.avatarGetir(b.kutuId);
      if (mounted) {
        setState(() {
          _var = b.var_;
          _resim = r;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _mesgul = false);
  }

  Future<void> _sec() async {
    final List<PlatformFile> l;
    try {
      l = await FilePicker.pickFiles(dialogTitle: 'Profil resmi seç', type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg', 'gif']);
    } catch (_) {
      bildir('Dosya seçilemedi', tur: MesajTur.hata);
      return;
    }
    if (l.isEmpty) return;
    final b = await l.first.readAsBytes();
    if (b.length > 1400 * 1024) {
      bildir('Resim çok büyük', mesaj: 'Daha küçük bir resim seçin (genellikle en fazla 512 KB).', tur: MesajTur.uyari);
      return;
    }
    setState(() => _mesgul = true);
    await islem(() => Hesap.avatarYukle(b), tamam: 'Profil resmi güncellendi');
    await _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    return Kutu(
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 64,
              height: 64,
              child: _resim != null
                  ? Image.memory(_resim!, fit: BoxFit.cover)
                  : Container(
                      color: r.ic,
                      child: Icon(Simge.kisiDolu, color: r.silik, size: 34),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Profil resmi', style: gosterim(16, agirlik: FontWeight.w600)),
                Text('İletilerinizde ve kurum içi sohbette görünür.', style: TextStyle(color: r.soluk, fontSize: 12.5)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(onPressed: _mesgul ? null : _sec, icon: const Icon(Simge.yukle, size: 18), label: Text(_var ? 'Değiştir' : 'Yükle')),
                    if (_var)
                      TextButton(
                        onPressed: _mesgul
                            ? null
                            : () async {
                                setState(() => _mesgul = true);
                                await islem(Hesap.avatarSil, tamam: 'Profil resmi kaldırıldı');
                                await _yukle();
                              },
                        child: const Text('Kaldır'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
