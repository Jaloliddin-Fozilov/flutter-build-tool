# Flutter Build Tool

Flutter loyihalari uchun universal interaktiv build skripti. Versiya boshqaruvi, AAB/APK formatlari, Android signing avtomatik sozlash, iOS App Store Connect upload, Android Play Store upload va auto-update bilan.

## Tezkor boshlash (bitta buyruq)

Flutter loyihasi ildizidan ishga tushiring — yuklab oladi, ruxsat beradi va darrov interaktiv menyu ochadi:

```bash
curl -fsSL https://raw.githubusercontent.com/Jaloliddin-Fozilov/flutter-build-tool/main/flutter_build.sh -o flutter_build.sh && chmod +x flutter_build.sh && ./flutter_build.sh
```

Faqat yuklab olib, keyin ishga tushirmoqchi bo'lsangiz:

```bash
curl -fsSL https://raw.githubusercontent.com/Jaloliddin-Fozilov/flutter-build-tool/main/flutter_build.sh -o flutter_build.sh && chmod +x flutter_build.sh
```

Global o'rnatish (har qaysi loyihadan `flutter-build` deb chaqirish uchun):

```bash
sudo curl -fsSL https://raw.githubusercontent.com/Jaloliddin-Fozilov/flutter-build-tool/main/flutter_build.sh -o /usr/local/bin/flutter-build && sudo chmod +x /usr/local/bin/flutter-build
```

Keyin xohlagan Flutter loyihasidan:

```bash
flutter-build
```

## Imkoniyatlar

- **Interaktiv UI** — strelkalar bilan boshqariladigan checkbox menyu
- **Versiya boshqaruvi** — `pubspec.yaml`, iOS `project.pbxproj`, Android `build.gradle` ni avtomatik sinxronlaydi
- **`+` qisqartmasi** — versiya yoki build kiritishda `+` bossangiz, oxirgi raqam +1 ga oshadi (`1.0.23` → `1.0.24`, `34` → `35`)
- **Platforma tanlash** — Android va iOS ni alohida yoki birga build qilish
- **Format tanlash** — AAB (Play Store), APK (sideload), yoki ikkalasi
- **Debug yoki Production** rejimlar
- **Android signing** — keystore yaratish, mavjud keystoreni ulash, `key.properties` va `build.gradle` avtomatik sozlash (eski keystore xavfsiz backup qilinadi)
- **iOS App Store upload** — `xcrun altool` orqali avtomatik TestFlight/App Store deploy (Transporter app'iga muqobil)
- **Android Play Store upload** — Google Play Developer API ga to'g'ridan-to'g'ri (Ruby, Python, Node — hech narsa kerak emas; pure bash + openssl)
- **Avtomatik sozlash wizard'lari** — brauzer ochiladi, key fayllari Downloads'dan avtomatik aniqlanadi, sozlash bir necha clickda tugaydi (Key ID, Issuer ID, JSON yo'l — barchasi auto-detect)
- **Per-project konfiguratsiya** — har loyiha o'z `package_name`/`bundle_id` bo'yicha alohida sozlanadi. Bir marta sozlasangiz, **qayta so'ralmaydi**. Bir Service Account ko'p loyihaga ishlatilishi mumkin (cross-project reuse).
- **Auto-update** — har ishga tushganda yangilanish tekshiriladi
- **Cross-platform ochish** — build natijalari macOS (`open`), Linux (`xdg-open`), WSL (`explorer.exe`) da avtomatik ochiladi

## Manbadan o'rnatish (kontribyutorlar uchun)

```bash
git clone https://github.com/Jaloliddin-Fozilov/flutter-build-tool.git
cd flutter-build-tool
chmod +x flutter_build.sh
```

## Foydalanish

Skriptni Flutter loyihasi ildizidan ishga tushiring:

```bash
./flutter_build.sh
```

Yoki global o'rnatilgan bo'lsa:

```bash
flutter-build
```

### Bayroqlar

| Bayroq | Tavsifi |
|--------|---------|
| `--version`, `-v` | Versiyani ko'rsatish |
| `--help`, `-h` | Yordam |
| `--no-update-check` | Yangilanish tekshiruvisiz ishga tushirish (CI uchun) |

## Talablar

- **macOS**, **Linux**, yoki **WSL** (iOS build va App Store upload faqat macOS)
- **Flutter SDK** (PATH da)
- **Java JDK** (Android signing uchun, `keytool` kerak)
- **Xcode Command Line Tools** (iOS App Store upload uchun, `xcrun altool` kerak)
- **openssl** (Android Play Store upload uchun, JWT RS256 signing kerak) — macOS/Linux'da bor
- **Bash 3.2+** (macOS standart bash 3.2 ham qo'llab-quvvatlanadi)
- **curl** (auto-update va deploy uchun)
- **xdg-open** Linux uchun, **explorer.exe** WSL uchun (build natijalarini ochish uchun)

## Ishlash jarayoni

1. **Hozirgi versiyalarni o'qish** — `pubspec.yaml`, iOS, Android
2. **Tanlovlar menyusi**:
   - Production / Debug
   - Android / iOS / ikkalasi
   - `flutter clean` / `flutter pub get`
3. **Android format** (Android tanlangan bo'lsa):
   - AAB (Play Store)
   - APK (sideload, test)
4. **Yangi versiyalarni kiritish**:
   - `Enter` — hozirgi qiymatni saqlash
   - `+` — oxirgi raqamni avtomatik +1 ga oshirish
   - Boshqa qiymat — qo'lda kiritilgan qiymat
5. **Tasdiqlash**
6. **Versiya fayllari yangilash**
7. **Android signing tekshiruvi** (Production + Android bo'lsa):
   - Yangi keystore yaratish
   - Mavjud keystoreni ulash
   - Joriy keystoreni ko'rsatish
   - Debug signing bilan davom etish
8. **Build** — APK / AAB / IPA
9. **Natijalarni ochish** — macOS Finder, Linux file manager yoki WSL Explorer

## Android Play Store upload

Skript Play Console'dagi qo'lda AAB upload jarayonini avtomatlashtiradi. Triple-T plugin yoki fastlane kabi alohida dependency'lar **kerak emas** — to'g'ridan-to'g'ri Google Play Developer API'siga ulanadi (`openssl` bilan RS256 JWT signing).

Menu'da `Play Store upload` checkbox'ini yoqing — Production + Android + AAB bilan birga ishlatiladi.

### Avtomatik sozlash wizard'i (tavsiya etiladi)

Birinchi marta ishga tushirganingizda, skript sizdan **wizard** yoki **qo'lda** kiritishni tanlashni so'raydi. Wizard tanlasangiz:

```
▶ Google Play API avtomatik sozlash

[1/4] Google Play Android Developer API ni yoqing
  🌐 Brauzerda Cloud Console API library ochiladi
  ℹ "Enable" tugmasini bosing
  → Yoqilgandan keyin Enter bosing

[2/4] Service Account yarating
  🌐 Brauzerda Service Accounts sahifasi ochiladi
  ℹ + Create Service Account → Name: flutter-build-deploy → Done
  → Yaratganingizdan keyin Enter bosing

[3/4] JSON Key yuklab oling
  ℹ Keys → Add Key → Create new key → JSON → Create
  ⠋ Yuklab olishni kutmoqda... (3s / 90s)
  ✓ JSON aniqlandi: my-project-abc123.json
  ✓ Service Account: flutter-build-deploy@my-project.iam.gserviceaccount.com
  ✓ Project: my-project-123456
  ✓ Ko'chirildi: ~/.config/flutter-build-tool/play_store_key.json

[4/4] Play Console ruxsatlari
  🌐 Brauzerda Play Console API access sahifasi ochiladi
  ℹ Grant access → Releases ruxsatlari → Apply
  → Apply qilganingizdan keyin Enter bosing

✓ Sozlandi!
```

Hech qanday yo'lni qo'lda yozish kerak emas — skript brauzerni ochadi, Downloads'dan faylni topadi, JSON ichidagi `client_email`, `project_id` ni avtomatik o'qiydi.

### Qo'lda sozlash (advanced)

Agar wizard ishlamasa yoki o'zingiz bosqichlarni nazorat qilmoqchi bo'lsangiz:

#### 1) Google Cloud Service Account yaratish

1. [Google Cloud Console](https://console.cloud.google.com) ga kiring (Play Console hisobingiz bilan)
2. **Project** tanlang (yoki yarating)
3. **APIs & Services** → **Library** → **"Google Play Android Developer API"** ni yoqing
4. **IAM & Admin** → **Service Accounts** → **Create Service Account**
   - Name: `flutter-build-deploy`
   - "Grant access" qadamini **skip**
5. Yaratilgan Service Account → **Keys** → **Add Key** → **Create new key** → **JSON**
6. JSON fayl yuklab olinadi — uni xavfsiz joyga saqlang

#### 2) Play Console'da ruxsat berish

1. [Play Console](https://play.google.com/console) → **Setup** → **API access**
2. Google Cloud project'ni tanlang (1-qadamdagi project)
3. Yaratilgan Service Account paydo bo'ladi → **Grant access**
4. **App permissions**: faqat sizning app'ingizni tanlang (xavfsizlik uchun)
5. **Account permissions**: kerakli ruxsatlar:
   - ✅ Releases — "Release apps to testing tracks"
   - ✅ Releases — "Release to production..."
   - ✅ Store presence — "View app information..."
6. **Apply** ni bosing

#### 3) Tool sozlash

Skriptni Production + Android + AAB + Play Store upload bilan ishga tushiring — interaktiv setup boshlanadi:
- Service Account JSON yo'li so'raladi
- Tool standart joyga ko'chirib qo'yishni taklif qiladi (`~/.config/flutter-build-tool/play_store_key.json`)
- Package name (applicationId) avtomatik aniqlanadi
- Default track tanlanadi (tavsiya: `internal`)
- Sozlamalar `~/.config/flutter-build-tool/play_store.json` ga saqlanadi

### Keyingi safarlardan

Hech narsa kiritish kerak emas — sozlamalar yodda. Faqat checkbox yoqing va build tugagach upload avtomatik boshlanadi.

### Upload jarayoni

```
▶ Play Store ga yuklash
  ℹ AAB:          build/app/outputs/bundle/release/app-release.aab (15 MB)
  ℹ Package:      com.example.myapp
  ℹ Track:        internal
  ℹ Service Acc:  flutter-build-deploy@my-project.iam.gserviceaccount.com

  ℹ [1/5] Access token olinmoqda...     ✓
  ℹ [2/5] Edit yaratilmoqda...           ✓ Edit yaratildi: abc123
  ℹ [3/5] AAB yuklanmoqda (15 MB)...    ✓ AAB yuklandi, versionCode=42
  ℹ [4/5] Track'ga qo'shilmoqda: internal... ✓ Track'ga qo'shildi
  ℹ [5/5] Edit commit qilinmoqda...     ✓

  ✓ Muvaffaqiyatli yuklandi!
```

### Track'lar haqida

| Track | Tavsifi | Qachon ishlatish |
|-------|---------|------------------|
| `internal` | Darrov publish, faqat 100 gacha internal tester | Tezkor sinov, hech qanday review yo'q |
| `alpha` | Closed testing, ko'p testerlar | Beta'dan oldin keng sinov |
| `beta` | Open testing, hamma kira oladi (link bilan) | Public beta |
| `production` | Play Store'da publish | Real reliz (Google review bo'lishi mumkin) |

**Tavsiya**: avval `internal` track'ga yuboring, sinab ko'ring, keyin Play Console'da `production` ga "promote" qiling.

### Xato hollar

| Xato | Sabab | Yechim |
|------|-------|--------|
| `403 The caller does not have permission` | Service Account permissions yetishmaydi | Play Console → API access → Service Account → Releases ruxsatlari |
| `Package not found` | `package_name` noto'g'ri yoki birinchi upload qilinmagan | App allaqachon Play Console'da yaratilgan va birinchi AAB qo'lda yuklangan bo'lishi kerak |
| `Version code already used` | Versiya raqami avval yuklangan | `pubspec.yaml` da build numberni `+` bilan oshiring (interactive menu'da `+` qisqartmasi) |
| `Bundle is not signed` | AAB signed emas | Production build qiling (`Production` checkbox'ini yoqing) |
| `OAuth2 error` | JWT yoki Service Account JSON xato | `.p8` faylni qayta tekshiring, Cloud Console'da Service Account holatini ko'ring |

### Xavfsizlik haqida

- **Service Account JSON git'ga commit qilinmasligi shart** — `.gitignore` ga qo'shing
- Tool faylni `chmod 600` qiladi (faqat egasi o'qiy oladi)
- Service Account JSON yo'qolsa, Cloud Console'da kalitni o'chirib yangisini yarating — Google account parolingiz xavfsiz qoladi

## iOS App Store Connect upload (TestFlight + App Store)

Skript Transporter app'idagi qo'lda upload jarayonini avtomatlashtiradi. Menu'da `App Store Connect upload` checkbox'ini yoqing — Production va iOS bilan birga ishlatiladi.

### Birinchi marta sozlash

1. **App Store Connect API Key yarating**:
   - [App Store Connect](https://appstoreconnect.apple.com/) → Users and Access → Integrations → API Keys → **`+ Generate Key`**
   - Yaratilgan `.p8` faylni yuklab oling (**faqat bir marta** yuklash mumkin!)
   - Key ID va Issuer ID ni eslab qoling

2. **`.p8` faylni Apple konvensiyasiga muvofiq joylashtiring**:
   ```bash
   mkdir -p ~/.appstoreconnect/private_keys
   mv ~/Downloads/AuthKey_AB12CD34.p8 ~/.appstoreconnect/private_keys/
   ```

3. **Skriptni ishga tushiring** — birinchi safar interaktiv setup boshlanadi:
   - Key ID kiritasiz
   - Issuer ID kiritasiz
   - `.p8` yo'lini tasdiqlaysiz
   - Sozlamalar `~/.config/flutter-build-tool/app_store_connect.json` ga saqlanadi (`chmod 600`)

4. **`ios/ExportOptions.plist` yo'q bo'lsa**, skript Team ID so'rab avtomatik yaratadi.

### Keyingi safarlardan

Hech narsa kiritish kerak emas — sozlamalar saqlangan. Faqat checkbox yoqing va build tugagach upload avtomatik boshlanadi.

### Upload jarayoni

```
▶ App Store Connect ga yuklash
  ℹ IPA:    build/ios/ipa/MyApp.ipa (24 MB)
  ℹ Key ID: AB12CD34
  ℹ Jarayon 5-30 daqiqa davom etishi mumkin. Ulanish uzilmasligi muhim.

  [xcrun altool real-time progress]

  ✓ Muvaffaqiyatli yuklandi!
  ℹ TestFlight processing 10-30 daqiqa davom etadi
  ℹ Status uchun email kuting yoki: https://appstoreconnect.apple.com/apps
```

### Xato hollar

| Xato | Sabab | Yechim |
|------|-------|--------|
| `No app with bundle identifier...` | App Store Connect'da app yaratilmagan | App Store Connect'da yangi app yarating |
| `Redundant Binary Upload` | Bu versiya allaqachon yuklangan | `pubspec.yaml` da build numberni `+` bilan oshiring |
| `Invalid Code Signing` | Distribution certificate yaroqsiz | Xcode → Settings → Accounts → Manage Certificates |
| `Team ID mismatch` | `ExportOptions.plist` da noto'g'ri Team ID | Apple Developer hisobidan to'g'ri Team ID ni kiriting |

## `+` qisqartmasi misollar

Versiya yoki build number kiritish so'ralganda `+` belgisini bossangiz, eski qiymatning oxirgi raqamli qismi avtomatik +1 ga oshiriladi:

| Eski qiymat | `+` natija |
|-------------|------------|
| `1.0.23` | `1.0.24` |
| `34` | `35` |
| `1.0` | `1.1` |
| `v1.0.0` | `v1.0.1` |
| `1.0.0-beta.3` | `1.0.0-beta.4` |

Bu tezkor patch relizlar uchun foydali — versiya raqamini eslab qolish va qayta yozish o'rniga bitta `+` yetadi.

## Android signing avtomatlashtirish

Skript Production + Android tanlangan paytda quyidagilarni avtomatik bajaradi:

- `keytool -genkeypair` orqali yangi keystore yaratish
- `android/key.properties` yozish (parollar bilan)
- `android/.gitignore` ga `key.properties`, `*.jks`, `*.keystore` qo'shish
- `android/app/build.gradle` (yoki `.kts`) ga `signingConfigs.release` blokini inject qilish
- Avval `*.bak.<timestamp>` backup yaratish

Mavjud keystore bo'lsa — `key.properties` ni ko'rsatadi (parollar yashirilgan), `keytool` orqali alias va expiry sanasini tasdiqlaydi.

## Auto-update

Har ishga tushganda 3 sekund timeout bilan GitHub-dan yangi versiya tekshiriladi. Yangi versiya bo'lsa:

```
⚠ Yangi versiya mavjud: 1.0.2 (joriy: 1.0.0)
ℹ Repo: https://github.com/Jaloliddin-Fozilov/flutter-build-tool
  Hozir yangilamoqchimisiz? (y/n):
```

Tasdiqlasangiz:
1. Yangi skript yuklab olinadi
2. `bash -n` orqali sintaksis tekshiriladi
3. Eski skript `*.bak.<timestamp>` ga backup qilinadi
4. Yangi skript o'rnatiladi va qayta ishga tushirish so'raladi

## Hissa qo'shish

PR-larga ochiq. Issue ochsangiz, ish jarayoni va xato xabarlarini ham ulashing.

## License

MIT — qarang [LICENSE](LICENSE).
