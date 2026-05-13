# Changelog

Loyihaning barcha muhim o'zgarishlari shu faylga yoziladi.

Format [Keep a Changelog](https://keepachangelog.com/uz/1.1.0/) asosida,
versiyalash esa [Semantic Versioning](https://semver.org/lang/uz/) qoidasiga rioya qiladi.

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

[1.2.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.2.0
[1.1.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.1.0
[1.0.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.0.0
