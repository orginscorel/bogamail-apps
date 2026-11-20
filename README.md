# BogaMail uygulamaları

Bogahost posta sisteminin (BogaMail) yerel uygulamaları. Tek kod tabanından **iPhone/iPad, Mac, Android ve Windows**.

| Uygulama | Paket | Ne işe yarar |
|---|---|---|
| **BogaMail** (`apps/posta`) | `com.bogahost.posta` | Kurumsal e-posta: klasörler, okuma, yazma, ekler, arama, anlık bildirim |
| **BogaMail Yönetim** (`apps/yonetim`) | `com.bogahost.yonetim` | Yönetim paneli: özet, alan adları, posta kutuları, kuyruk, karantina, alarmlar, sunucu erişimi |

Ortak çekirdek `packages/boga_ortak`: API istemcisi (web paneliyle aynı oturum: çerez + CSRF, 30 gün kayan oturum),
tema, marka açılışı, giriş + iki adımlı doğrulama, Apple anlık bildirim kanalı.

## Anlık bildirim
- **iPhone / Mac:** sunucu (bogamaild) yeni postayı ve alarmları doğrudan Apple'a (APNs) gönderir; uygulama kapalıyken de gelir.
  Sunucu ayarı: `BOGAMAIL_APNS_KEY_FILE`, `BOGAMAIL_APNS_KEY_ID`, `BOGAMAIL_APNS_TEAM_ID`, `BOGAMAIL_APP_TOPIC_POSTA`, `BOGAMAIL_APP_TOPIC_YONETIM`.
- **Android:** arka planda en sık 15 dakikada bir yeni posta denetimi (Firebase projesi bağlanınca anlık olur).
- **Windows:** uygulama açıkken canlı akıştan bildirim.

## Geliştirme
```bash
export PATH=/opt/flutter/bin:$PATH
flutter pub get                       # depo kökünde (pub workspace)
cd apps/posta && flutter analyze && flutter test
```
Simgeler: `cd tool/simge && flutter test` (açılış işaretinden üretir), ardından iOS PNG'leri `go run ./tool/opak apps/*/ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` ile alfasızlaştırılır.

## Derleme ve dağıtım (GitHub Actions — `.github/workflows/uygulamalar.yml`)
`main` dalına her gönderimde ya da elle (Actions → Uygulamalar → Run workflow):
- Android: imzalı APK → GitHub sürümü (`surum-N`)
- iPhone: App Store imzası → **TestFlight**
- Mac: Mac App Store imzası + pkg → **App Store Connect / TestFlight**
- Windows: kurulum (.exe) ve taşınabilir zip → GitHub sürümü

Gerekli Actions gizlileri bir kez `bash kurulum/gizlileri-yukle.sh sahip/depo` ile yüklenir
(ASC_KEY_P8, IOS_P12_B64, IOS_P12_PASS, MAC_APP_P12_B64, MAC_INST_P12_B64, MAC_P12_PASS, ANDROID_KEYSTORE_B64, ANDROID_KEYSTORE_PASS).
Gizliler yoksa iş akışı yalnız derleme denetimi yapar. Apple profilleri `imza/` altındadır.
