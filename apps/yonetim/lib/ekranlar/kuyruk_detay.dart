import 'package:boga_ortak/boga_ortak.dart';
import 'package:flutter/material.dart';

import '../oturum.dart';
import '../ortak/bilesenler.dart';
import '../veri/bicim.dart';
import '../veri/json.dart';
import '../veri/operasyon.dart';
import 'bolumler.dart';
import 'kuyruk.dart';

/// Kuyruktaki iletinin ayrıntısı, başlıkları (GET /queue/{id}/headers) ve işlemleri (POST /queue/bulk).
class KuyrukDetay extends StatefulWidget {
  const KuyrukDetay({super.key, required this.oge, required this.hataEtiketleri, required this.yonetebilir, required this.degisti, this.tamSayfa = false});
  final KuyrukOgesi oge;
  final Map<String, String> hataEtiketleri;

  /// Sunucunun can_manage bayrağı: bekletme/serbest bırakma/silme (yalnızca platform ve bayi).
  final bool yonetebilir;
  final VoidCallback degisti;
  final bool tamSayfa;

  @override
  State<KuyrukDetay> createState() => _KuyrukDetayState();
}

class _KuyrukDetayState extends State<KuyrukDetay> {
  List<(String, String)>? _basliklar;
  String? _hata;
  bool _hamGoster = false;

  KuyrukOgesi get o => widget.oge;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final v = harita(await Uyg.api.get('/api/v1/queue/${Uri.encodeComponent(o.kimlik)}/headers'));
      if (mounted) setState(() => _basliklar = [for (final h in haritalar(v['headers'])) (metin(h['name']), metin(h['value']))]);
    } catch (e) {
      if (mounted) setState(() => _hata = hataMetni(e));
    }
  }

  Future<bool> _toplu(String eylem, {String? mod, String? neden, String? tamam}) async {
    final v = await islem(
      () => Uyg.api.post('/api/v1/queue/bulk', {
        'action': eylem,
        'ids': [o.kimlik],
        'mode': ?mod,
        if (eylem == 'delete') 'confirm': 'SİL',
        if (neden != null && neden.isNotEmpty) 'reason': neden,
      }),
    );
    if (v == null) return false;
    final m = harita(v);
    final hatalar = haritalar(m['failed']);
    if (hatalar.isNotEmpty) {
      bildir('İşlem uygulanamadı', mesaj: metin(hatalar.first['error']), tur: MesajTur.hata);
      return false;
    }
    if (tamsayi(m['done']) == 0) {
      bildir('İleti artık kuyrukta değil', mesaj: 'Teslim edilmiş olabilir.', tur: MesajTur.uyari);
    } else if (tamam != null) {
      bildir(tamam, tur: MesajTur.basari);
    }
    widget.degisti();
    if (widget.tamSayfa && mounted) Navigator.of(context).maybePop();
    return true;
  }

  Future<void> _sil() async {
    final s = await showDialog<(String, String)>(
      context: context,
      builder: (_) => KuyrukSilDialog(giden: o.giden),
    );
    if (s == null) return;
    await _toplu('delete', mod: s.$1, neden: s.$2, tamam: s.$1 == 'bounce' ? 'İleti silindi, göndericiye bildirildi' : 'İleti sessizce silindi');
  }

  @override
  Widget build(BuildContext context) {
    final r = context.r;
    final ortak = Uyg.ortak && widget.yonetebilir && Uyg.taklit == null;
    return RefreshIndicator.adaptive(
      onRefresh: _yukle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Kutu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(o.giden ? Icons.north_east_rounded : Icons.south_west_rounded, color: o.giden ? Marka.mavi : Marka.zumrut),
                    const SizedBox(width: 8),
                    Text(o.giden ? 'Giden ileti' : 'Gelen ileti', style: gosterim(16, agirlik: FontWeight.w700)),
                    const Spacer(),
                    KuyrukDurumu(o),
                  ],
                ),
                const SizedBox(height: 10),
                BilgiSatiri('Kuyruk kimliği', o.kimlik, mono: true, kopyalanabilir: true),
                BilgiSatiri('Gönderen', o.gonderen.isEmpty ? '<> (boş zarf)' : o.gonderen, kopyalanabilir: o.gonderen.isNotEmpty),
                BilgiSatiri('Alıcılar', o.alicilar.isEmpty ? '—' : o.alicilar.join('\n')),
                if (o.orgAdi.isNotEmpty && !Uyg.musteri) BilgiSatiri('Müşteri', o.orgAdi),
                BilgiSatiri('Alındı', '${tamZaman(o.alinma)} (${yasYaz(o.yasSn)} önce)'),
                BilgiSatiri('Boyut', boyutYaz(o.boyut)),
                BilgiSatiri('Deneme', '${o.deneme}'),
                if (o.sonrakiDeneme != null) BilgiSatiri('Sonraki deneme', tamZaman(o.sonrakiDeneme)),
                if (o.sinif == 'bulk') const BilgiSatiri('Sınıf', 'Toplu gönderim'),
              ],
            ),
          ),
          if (o.frenNedeni.isNotEmpty) ...[
            const SizedBox(height: 12),
            Bant('Güvenlik freni: ${o.frenNedeni}', renk: Marka.gul, ikon: Icons.front_hand_rounded),
          ],
          if (o.sonHata.isNotEmpty) ...[
            const Baslik('Son hata'),
            Kutu(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (o.hataSinifi.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Rozet(widget.hataEtiketleri[o.hataSinifi] ?? o.hataSinifi, renk: Marka.kehribar),
                    ),
                  SelectableText(o.sonHata, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                ],
              ),
            ),
          ],
          const Baslik('İşlemler'),
          if (Bolum.takip.gorunur) ...[
            EylemSatiri(
              ikon: Icons.manage_search_rounded,
              baslik: 'Mesaj takibinde aç',
              ipucu: 'Bu iletinin teslim yolculuğunu (aşamalar, alıcı sonuçları, ham kayıtlar) gösterir',
              onTap: () {
                if (widget.tamSayfa) Navigator.of(context).maybePop();
                bolumeGit(Bolum.takip, kuyrukId: o.kimlik);
              },
            ),
            const SizedBox(height: 8),
          ],
          if (Uyg.taklit == null)
            EylemSatiri(
              ikon: Icons.replay_rounded,
              baslik: 'Şimdi yeniden dene',
              ipucu: 'Bekleme süresini atla, teslimi hemen dene',
              onTap: () => _toplu('retry', tamam: 'Yeniden deneme sıraya alındı'),
            ),
          if (ortak && o.giden) ...[
            const SizedBox(height: 8),
            o.durum == 'held'
                ? EylemSatiri(
                    ikon: Icons.play_arrow_rounded,
                    baslik: 'Serbest bırak',
                    ipucu: 'Teslim denemelerine devam etsin',
                    onTap: () => _toplu('release', tamam: 'İleti serbest bırakıldı'),
                  )
                : EylemSatiri(
                    ikon: Icons.pause_rounded,
                    baslik: 'Beklet',
                    ipucu: 'Serbest bırakılana kadar teslim edilmesin',
                    onTap: () => _toplu('hold', tamam: 'İleti bekletmeye alındı'),
                  ),
          ],
          if (ortak) ...[
            const SizedBox(height: 8),
            EylemSatiri(ikon: Icons.delete_outline_rounded, baslik: 'Kuyruktan sil', ipucu: 'Geri alınamaz', tehlikeli: true, onTap: _sil),
          ],
          Baslik(
            'Başlıklar',
            sag: _basliklar == null || _basliklar!.isEmpty
                ? null
                : TextButton(onPressed: () => setState(() => _hamGoster = !_hamGoster), child: Text(_hamGoster ? 'Tablo' : 'Ham metin')),
          ),
          Kutu(
            child: _hata != null
                ? Text(_hata!, style: TextStyle(color: r.silik))
                : _basliklar == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : _basliklar!.isEmpty
                ? Text('Başlık okunamadı (ileti gövdesi kuyrukta bulunamadı).', style: TextStyle(color: r.silik))
                : _hamGoster
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: 'Kopyala',
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          onPressed: () => kopyala(_basliklar!.map((h) => '${h.$1}: ${h.$2}').join('\n'), mesaj: 'Başlıklar kopyalandı'),
                        ),
                      ),
                      SelectableText(
                        _basliklar!.map((h) => '${h.$1}: ${h.$2}').join('\n'),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (a, d) in _basliklar!)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a,
                                style: TextStyle(color: r.soluk, fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                              SelectableText(d, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Silme biçimi (bounce/sessiz), isteğe bağlı gerekçe ve "SİL" onayı (web panelindeki iletişim kutusunun aynısı).
/// Sonuç: (mod, gerekçe). [adet] verilirse toplu silme başlığı gösterilir.
class KuyrukSilDialog extends StatefulWidget {
  const KuyrukSilDialog({super.key, required this.giden, this.adet = 1});
  final bool giden;
  final int adet;
  @override
  State<KuyrukSilDialog> createState() => _KuyrukSilDialogState();
}

class _KuyrukSilDialogState extends State<KuyrukSilDialog> {
  late String _mod = widget.giden ? 'bounce' : 'silent';
  final _neden = TextEditingController();
  final _onay = TextEditingController();

  @override
  void dispose() {
    _neden.dispose();
    _onay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tamam = {'SİL', 'SIL'}.contains(_onay.text.trim().toUpperCase());
    return AlertDialog(
      title: Text(widget.adet == 1 ? 'İleti kuyruktan silinsin mi?' : '${widget.adet} ileti kuyruktan silinsin mi?', style: gosterim(18, agirlik: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'İletiler alıcılara teslim edilmeyecek. İşlem geri alınamaz ve denetim kaydına yazılır.',
                style: TextStyle(color: context.r.silik, fontSize: 13),
              ),
              const SizedBox(height: 6),
              RadioGroup<String>(
                groupValue: _mod,
                onChanged: (v) => setState(() => _mod = v ?? _mod),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'bounce',
                      enabled: widget.giden,
                      title: const Text('Göndericiye bildir (bounce)'),
                      subtitle: Text(
                        widget.giden
                            ? 'Gönderen kendi posta kutumuzsa teslim edilemedi bildirimi (DSN) alır. Gelen/aktarılan iletilerde uygulanmaz.'
                            : 'Gelen iletilerde kullanılamaz (sahte göndericilere geri saçılma).',
                      ),
                    ),
                    const RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'silent',
                      title: Text('Sessiz sil'),
                      subtitle: Text('Kimseye bildirim gitmez. Yalnızca spam/kötüye kullanım gibi durumlarda bilerek seçin.'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _neden,
                maxLength: 300,
                decoration: InputDecoration(labelText: 'Gerekçe (denetim kaydı${_mod == 'bounce' ? ' ve bildirim' : ''})'),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Onaylamak için '),
                    const TextSpan(
                      text: 'SİL',
                      style: TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace'),
                    ),
                    const TextSpan(text: ' yazın'),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _onay,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'SİL', isDense: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Marka.gul),
          onPressed: tamam ? () => Navigator.pop(context, (_mod, _neden.text.trim())) : null,
          child: const Text('Sil'),
        ),
      ],
    );
  }
}
