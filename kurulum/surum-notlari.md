## 1.6.0

**BogaMail (posta)**
- Önce yerel çalışma: görülen her şey (klasörler, listeler, iletiler, sohbet, kişiler, takvim) anında açılır; arka planda eşitlenir; internet yokken de okunur.
- Outlook gibi Giden Kutusu: çevrimdışı gönderilen iletiler ekleriyle bekler (Bekliyor / Gönderiliyor / Hata + Tekrar dene), açılıp düzenlenebilir ya da silinebilir; bağlantı gelince sırayla gider. Sunucudaki planlı ve gönderilemeyen iletiler de burada. Aynı ileti hiçbir durumda iki kez gönderilmez.
- Çevrimdışı değişiklikler (okundu, yıldız, arşiv, sil, taşı) sıraya alınır, bağlantı gelince işlenir; eşitleme göstergesinde "Çevrimdışı — son eşitleme" ve bekleyenler listesi.
- 1.5'te kaybolanlar geri geldi: Ekli iletiler, Tüm postalar, okunmamış sayıları, telefonda yanıt çubuğu. Ekler (PDF dahil) her iletide gövdenin üstünde kart; PDF/görsel/metin önizleme.
- Konuşmada önceki iletiler kararlı; açılan ileti kapanmaz, kaydırma zıplamaz.
- Masaüstü: posta gövdesi tam boyunda, tek kaydırma; geniş postalar alana sığar; gövde başlıkla hizalı.
- Spam denetimi satırı, SPF/DKIM/DMARC doğrulama çipleri, ayrıntı kutusu.
- Hesap değiştirince sağ üstte bildirim kartı.
- Taslak otomatik kaydı, planlı iletiyi düzenleme, Yazdır, takvimde Gün görünümü ve doğru takvim renkleri, kişileri vCard/CSV içe/dışa aktarma, sohbet durumunda "şu süre sonra temizle".

## 1.5.2

- Tüm hesaplar: satırdaki kutucukla seçim çalışır; seçince üstte toplu işlem çubuğu (Tümünü seç, Okundu/Okunmadı, Yıldız, Arşivle, Sil).

## 1.5.1

- macOS/Windows: HTML postalar küçük bir kutuda kesik açılıyordu; artık okuma alanının tamamını kullanır ve içerik kaydırılarak okunur.

## 1.5.0

**BogaMail (posta) — webmail ile aynı görünüm**
- Webin yazı tipi ve renkleri; liste satırı webdeki gibi: okunmamışta nokta, solda şerit ve kalın yazı, sağda tarih; konu satırının sonunda ataç, "Okundu/Okunmadı yap" ve yıldız.
- Klasör sütunu simgelere daraltılabilir (1400 px altında kendiliğinden); liste alanın %36'sı, okuma alanı daha geniş; aradaki çizgi sürüklenir.
- Okuma alanı konumu: Sağda / Altta / Kapalı (webdeki ayarla ortak).
- Konuşma: eski iletiler tek "N önceki ileti" düğmesinde, okundu işaretleri, kaydırınca üstte "Ad · saat" şeridi; konuşma gruplamasına sunucu karar verir, otomatik postalar (kodlar, bültenler) gruplanmaz.
- Geniş HTML postalar yatay kaydırma yerine alana sığdırılır; HTML gövde sağa kaymaz.

**Derleme**
- Android: işlemci başına ayrı APK (arm64 ~25 MB; eski cihazlar için -armv7); iOS/macOS derlemeleri analizi beklemeden başlar.

## 1.4.3

- Yeni posta bildirimleri: gönderen, konu ve içeriğin ilk satırları (önizleme) birlikte gösterilir; Android'de bildirim açılınca tam metin.

## 1.4.2

**BogaMail (posta) — masaüstü**
- Sol dar menünün altında Ayarlar, eşitleme durumu (renkli nokta), sürüm ve profil avatarı; menü genişlemez/taşmaz.
- Posta listesi daha geniş ve ferah; liste ile okuma alanı arası sürüklenerek ayarlanır (genişlik hatırlanır).
- Okuma alanı sadeleşti: kompakt konu ve gönderen satırı, Biçimli/Düz metin ⋯ menüsünde, içerik çerçevesiz ve tam genişlikte.
- Aynı konudaki iletiler otomatik konuşma görünümünde açılır.

## 1.4.1

- Posta listesi: fare iletinin üzerine gelince satır artık kaymıyor; işlem düğmeleri sağ üstte yüzerek belirir.

## 1.4.0

**BogaMail (posta)**
- Konuşma görünümü: eski iletiler tek satır, "N ileti daha", alıntı ve imzalar katlanır, ekler kompakt; ilk okunmamışa gider.
- Yeni tasarım: ince simge seti, daha hafif ve küçük yazılar, sık liste (ekrana daha çok ileti sığar).
- Hesap bloğu sol menünün altında; yükleme ekranı olmadan akıcı hesap geçişi (Ctrl/Cmd+1…9).
- Ayarlar gruplandı: Profil ve hesap / Posta / Uygulama; profil kartı.
- "Tüm hesaplar" sadeleşti.
- Bildirimler: izin isteme, her açılışta kayıt (tüm hesaplar), uygulama açıkken de bildirim, Mac bildirim sorunu giderildi.
- Arka planda çalışma: Android sürekli bağlantı servisi, Windows sistem tepsisi ve açılışta başlatma, Mac oturum açılınca başlatma.
- Hız: HTTP/2, resimlerin önceden yüklenmesi, sunucu resim önbelleği.

**BogaMail Yönetim**
- İnce simge seti, hafif yazılar, kullanıcı bloğu menünün altında.
- Bildirim izni, Android arka plan servisi, Windows tepsi, Mac oturum açılınca başlatma.

## 1.3.0

**BogaMail (posta)**
- "Tüm hesaplar": kayıtlı tüm hesapların postaları tek kutuda; hesap değiştirmeden okuma ve işlem, yanıtlarken otomatik hesap geçişi.
- Hesap ekleme düzeltildi: mevcut hesap kayıtlı değilse kaydetme önerilir; "Kayıtlı postalarınız" listesi ekleme ekranında.
- Hızlı açılış: yerel önbellek, önceden yükleme, tek istekte okundu işaretleme, önbellekli resimler.
- Masaüstü (macOS/Windows): web benzeri sol menü, klasör arama, sürükle-bırak taşıma, Shift/Cmd ile çoklu seçim, geniş ayarlar düzeni.
- Zengin metin düzenleyici (biçimlendirme araç çubuğu, düz metin kipi, Yüksek önem).
- Ayarlar web ile eşit: klasörler, etiket renkleri, süzgeç sıralama, IMAP taşıma, kurulum bilgileri, kayıtlı cihazlar, imza tasarımcısı.
- Canlı eşitleme göstergesi: Canlı / Bağlanıyor / geri sayım, "Şimdi eşitle".
- Renkli klasör simgeleri (Çöp, Spam, Gönderilenler…).
- Sohbet: Kişiler sekmesinde tüm iş arkadaşları ve siz; kanal/grup iletilerinde bildirim; yazarken harf yutma hatası giderildi.
- Yeni giriş ekranı.

**BogaMail Yönetim**
- Özet panelindeki okunmayan düğmeler düzeltildi.
- Masaüstü ayarlar düzeni.
- Yeni giriş ekranı.

## BogaMail 1.2.0

**1.2.0 yenilikleri**
- Sohbette dosya, fotoğraf ve kamera eki (virüs taramalı), resim önizleme
- Sohbette emoji tepkileri
- Yenilenen okuma ve yazma ekranları (konuşma görünümü, güvenlik uyarıları, ek şeridi, "Daha sonra gönder")
- Yönetim: bayi ve yönetici silme

## 1.1.0

**Yeni tasarım**
- Bogahost logosuyla yeni simgeler: BogaMail (indigo, zarf rozeti) ve BogaMail Yönetim (grafit, yeşil kontrol rozeti)
- Yeni açılış animasyonu; açık renk tema varsayılan
- Posta listesinde okunmuş/okunmamış ayrımı belirgin; üstte etiketli filtre (Tümü · Okunmamış · Yıldızlı · Ekli); anlaşılır alt gezinme
- Yönetimde yenilenen özet paneli ve tablolar

**BogaMail (posta)**
- Sohbet: kurum içi kanallar, bireysel ve grup sohbetleri, çevrimiçi durumu, anlık bildirim
- Takvim (ay/hafta/ajanda, davetler) ve Görevler (atama, yorum, e-postadan görev)
- Birden fazla hesap: hesaplar arası geçiş, hesap ekleme, "Kayıtlı postalarınız"
- Ek eklerken kamerayla fotoğraf/video çekme
- İmza düzenleyici (zengin metin, logo, değişkenler), süzgeçler, otomatik yanıt, kişiler, yönlendirme, güvenlik ayarları

**BogaMail Yönetim**
- Web panelindeki tüm bölümler (48 bölüm)
- Müşteri posta kutusuna ve müşteri/bayi paneline güvenli giriş
- Dosya yükleme/indirme, HTML önizleme, 2FA karekodu

**Genel**
- Uygulama içinden güncelleme (Android ve Windows indirip kurar; iPhone/Mac TestFlight)
- Oturumlar kendiliğinden sonlanmaz

Android APK ve Windows kurulum dosyaları bu sürümdedir; iPhone ve Mac sürümleri TestFlight'tadır.
