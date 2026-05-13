# Flutter Build Tool

Flutter loyihalari uchun universal interaktiv build skripti. Versiya boshqaruvi, AAB/APK formatlari, Android signing avtomatik sozlash, va auto-update bilan.

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

- **macOS**, **Linux**, yoki **WSL** (iOS build faqat macOS)
- **Flutter SDK** (PATH da)
- **Java JDK** (Android signing uchun, `keytool` kerak)
- **Bash 3.2+** (macOS standart bash 3.2 ham qo'llab-quvvatlanadi)
- **curl** (auto-update uchun, ixtiyoriy)
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
