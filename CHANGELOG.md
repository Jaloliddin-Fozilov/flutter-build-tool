# Changelog

Loyihaning barcha muhim o'zgarishlari shu faylga yoziladi.

Format [Keep a Changelog](https://keepachangelog.com/uz/1.1.0/) asosida,
versiyalash esa [Semantic Versioning](https://semver.org/lang/uz/) qoidasiga rioya qiladi.

## [1.5.0] — 2026-05-14

### Qo'shildi

- **Per-project konfiguratsiya** — har bir Flutter loyihasi o'z `package_name`
  (Android) yoki `bundle_id` (iOS) bo'yicha alohida konfiguratsiya saqlaydi.
  Birinchi marta sozlangach, **hech qachon qayta so'ralmaydi**.
  - Android: `~/.config/flutter-build-tool/play/<package_name>.json`
  - iOS: `~/.config/flutter-build-tool/appstore/<bundle_id>.json`
- **Silent davom etish** — sozlangan loyiha uchun "Shu sozlamalar bilan davom
  etamizmi?" prompti olib tashlandi. Endi bir qatorli xulosa: `✓ Play Store:
  com.example.app → internal (saqlangan)`.
- **Cross-project Service Account / API Key reuse** — yangi loyiha aniqlanganda,
  boshqa loyihalardan saqlangan kalit avtomatik taklif qilinadi. Foydalanuvchi
  faqat track yoki tasdiqlash so'raladi.
- **iOS bundle_id auto-detect** — `ios/Runner.xcodeproj/project.pbxproj`
  ichidan `PRODUCT_BUNDLE_IDENTIFIER` avtomatik o'qiladi (RunnerTests
  filtrlanadi).
- **Legacy config migration** — v1.4.x dagi yagona-fayl konfiguratsiyasi
  (`play_store.json`, `app_store_connect.json`) avtomatik per-project formatga
  ko'chiriladi, foydalanuvchi xabarsiz davom etadi.

### O'zgartirildi

- **`setup_*` va wizard funksiyalari endi `package_name`/`bundle_id` argument
  qabul qiladi** — bu loyiha aralashmasligini ta'minlaydi.
- **`upload_to_*` funksiyalari per-project config'dan o'qiydi** — current
  loyihaning sozlamalari ishlatiladi.

### Sizning foydangiz

| Avval (v1.4.x) | Endi (v1.5.0) |
|----------------|----------------|
| Har deploy'da "Shu sozlamalar bilan davom etamizmi? (y)" | Silent, bir qator info |
| Yangi loyihada eski package qayta yoziladi | Yangi loyiha alohida sozlanadi, eskisi saqlanadi |
| Service Account ko'p loyihada qayta sozlanadi | Mavjud SA avtomatik taklif qilinadi |

## [1.4.1] — 2026-05-14

### Tuzatildi

- **Auto-update `curl: (56)` xatosi `sudo` o'rnatilgan tizimlarda** — agar skript
  `/usr/local/bin/` kabi tizim direktoriyasida joylashgan bo'lsa, oddiy
  foydalanuvchi yozish ruxsatiga ega emas. Avval `curl` "write failed" xatosi
  bilan yiqilardi (passed 1413 returned 4294967295).
  - Yangi xulq: yangilashdan oldin skript yozish ruxsatini tekshiradi.
  - Ruxsat yo'q bo'lsa: faylni `/tmp/` ga yuklab, validate qilib, so'ng `sudo cp`
    bilan o'rnatadi.
  - Foydalanuvchi sudo parolini bir marta kiritadi, qolgani avtomatik.
  - Sudo bo'lmasa yoki bekor qilinsa, aniq qo'lda yangilash buyrug'i ko'rsatiladi.

## [1.4.0] — 2026-05-14

### Qo'shildi

- **Avtomatik sozlash wizard'lari (iOS va Android)** — Key ID, Issuer ID, JSON
  yo'lini qo'lda yozish o'rniga, skript brauzerni ochib, fayl yuklanishini
  kutib, kerakli ma'lumotlarni avtomatik aniqlaydi.
  - `appstore_setup_wizard` — App Store Connect API Key avtomatik sozlash:
    - Brauzerda API Keys sahifasi ochiladi
    - `.p8` fayl Downloads'da paydo bo'lganini polling + spinner bilan kutadi
    - Fayl nomidan Key ID avtomatik aniqlanadi (`AuthKey_AB12CD34.p8` → `AB12CD34`)
    - Apple konvensiyasiga muvofiq `~/.appstoreconnect/private_keys/` ga ko'chiriladi
    - Issuer ID clipboard'dan UUID format'da avtomatik taklif qilinadi
  - `playstore_setup_wizard` — Google Play Service Account avtomatik sozlash:
    - 3 ta brauzer sahifasi ketma-ket ochiladi (API library, Service Accounts,
      Play Console API access)
    - Yangi yuklangan Service Account JSON `"type": "service_account"`
      marker bilan filterlanadi
    - JSON dan `client_email`, `project_id` avtomatik chiqariladi
    - Package name `build.gradle*` dan avtomatik aniqlanadi
    - `~/.config/flutter-build-tool/play_store_key.json` ga ko'chiriladi
- **Yangi yordamchilar**:
  - `open_url` — brauzerda URL ochish (macOS open, Linux xdg-open, WSL explorer.exe)
  - `wait_for_download` — Downloads papkasini polling, spinner bilan kutish
  - `read_clipboard` — macOS pbpaste, Linux xclip/xsel
- **Sozlash usuli tanlovi**: yangi user'larga ham wizard, ham qo'lda kiritish
  variantlari ko'rsatiladi (wizard default).

### Talablar

- Mavjud talablar saqlanadi.
- Linux'da clipboard auto-detect uchun `xclip` yoki `xsel` (ixtiyoriy — bo'lmasa
  Issuer ID qo'lda kiritiladi).

## [1.3.0] — 2026-05-14

### Qo'shildi

- **Android Play Store upload** — Google Play Developer API ga to'g'ridan-to'g'ri
  upload. Hech qanday Ruby, Python yoki Node yo'q — pure bash + openssl + curl.
  - Yangi menu opsiyasi: `[ ] Play Store upload (Production + Android + AAB bilan)`
  - **JWT RS256 signing** openssl bilan to'g'ridan-to'g'ri (RFC 7515 muvofiq base64url)
  - 4 ta API call'ni avtomatik orkestratsiya qiladi:
    `edits` → `bundles upload` → `tracks` → `:commit`
  - Service Account JSON `~/.config/flutter-build-tool/play_store_key.json` ga
    saqlanadi (`chmod 600`), sozlama `play_store.json` da.
  - Track tanlash: `internal`/`alpha`/`beta`/`production` (default: `internal`).
  - Package name avtomatik aniqlanadi `android/app/build.gradle*` dan.
  - Xato hollari uchun foydali ko'rsatmalar.
- **Loyiha fayllariga teginmaslik** — Triple-T plugin yoki Fastfile kabi
  yondashuvlardan farqli ravishda, `build.gradle` ga hech narsa qo'shilmaydi.
  Faqat `~/.config/flutter-build-tool/` dagi sozlamalar.

### Talablar

- `openssl` (JWT RS256 signing uchun) — macOS, Linux'da bor.
- `curl` — OAuth2 + API calls uchun.
- Google Play Developer hisob + Service Account + JSON Key fayli.
- App allaqachon Play Console'da yaratilgan va birinchi qo'lda upload qilingan.

## [1.2.0] — 2026-05-14

### Qo'shildi

- **iOS App Store Connect upload** — `xcrun altool` orqali avtomatik upload.
  Transporter app'idagi qo'lda upload jarayonini almashtiradi.
  - Yangi menu opsiyasi: `[ ] App Store Connect upload (Production + iOS bilan)`
  - API Key sozlamasi `~/.config/flutter-build-tool/app_store_connect.json` ga
    saqlanadi (`chmod 600`), `.p8` fayl xavfsiz `~/.appstoreconnect/private_keys/`
    ostida turadi.
  - Birinchi marta ishlatishda interaktiv setup: Key ID, Issuer ID, `.p8` yo'li.
  - `ios/ExportOptions.plist` yo'q bo'lsa, Team ID kiritib avtomatik yaratiladi.
  - iOS Production build endi `--export-options-plist` flag bilan ishga tushadi
    (faqat upload yoqilgan paytda).
  - Xato holatlari uchun foydali ko'rsatmalar (Bundle ID, signing, versiya
    konflikti, Team ID).

### Talablar

- `xcrun` (Xcode Command Line Tools) — App Store upload uchun.
- App Store Connect API Key (.p8 fayl) — Apple Developer hisobida yaratiladi.
- `ios/ExportOptions.plist` — yo'q bo'lsa skript yaratib beradi.

## [1.1.0] — 2026-05-14

### Qo'shildi

- **`+` qisqartmasi** — versiya yoki build number kiritishda `+` belgisini bossa,
  oxirgi raqamli qism avtomatik +1 ga oshiriladi.
  - `1.0.23` + `+` → `1.0.24`
  - `34` + `+` → `35`
  - `v1.0.0` + `+` → `v1.0.1`
  - `1.0.0-beta.3` + `+` → `1.0.0-beta.4`
- **Linux va WSL qo'llab-quvvatlash** — build natijalarini ochish endi `xdg-open`
  (Linux) va `explorer.exe` (WSL) orqali ham ishlaydi, faqat macOS `open` emas.

### Tuzatildi

- **Keystore overwrite endi backup oladi** — eskisini `rm -f` bilan o'chirib
  yuborish o'rniga, `*.bak.<timestamp>` ga ko'chiriladi. Bu Play Store relizining
  imzo kalitini tasodifan yo'qotishdan saqlaydi.
- **`pubspec.yaml` parsing izohlar bilan to'g'ri ishlaydi** — `name:` va `version:`
  qatorlarida `# izoh` bo'lsa, ilgari noto'g'ri qiymat o'qilardi (masalan
  `my_app#productionapp`). Endi `awk` orqali izohlar olib tashlanadi.
- **`set -o pipefail` qo'shildi** — `grep | head` kabi pipeline'lardagi
  yashirin xatolarni darrov topish uchun.

### O'zgartirildi

- **Auto-update HTTP timeout 3s → 5s** — sekin tarmoqlarda yangilanish
  tekshiruvi noto'g'ri "yangilanish yo'q" demasligi uchun.

## [1.0.0] — 2026-05-13

### Qo'shildi

- Birinchi reliz.
- Strelka klavishlari bilan boshqariladigan interaktiv checkbox menyu.
- `pubspec.yaml`, iOS `project.pbxproj`, Android `build.gradle`/`.kts`
  o'rtasida versiya sinxronizatsiyasi.
- Android signing avtomatlashtirish: keystore yaratish, ulash,
  `key.properties` va `build.gradle` ga `signingConfigs.release` inject qilish.
- GitHub'dan auto-update tekshiruvi va o'z-o'zini yangilash.
- AAB va APK formatlari, Production va Debug rejimlari.
- Build natijalarini Finder'da avtomatik ochish.

[1.5.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.5.0
[1.4.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.4.1
[1.4.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.4.0
[1.3.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.3.0
[1.2.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.2.0
[1.1.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.1.0
[1.0.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.0.0
