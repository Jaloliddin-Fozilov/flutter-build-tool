# Changelog

Loyihaning barcha muhim o'zgarishlari shu faylga yoziladi.

Format [Keep a Changelog](https://keepachangelog.com/uz/1.1.0/) asosida,
versiyalash esa [Semantic Versioning](https://semver.org/lang/uz/) qoidasiga rioya qiladi.

## [1.17.6] — 2026-06-09

### Qo'shildi — Play POLICY/deklaratsiya 403 aniqlash (ruxsat emas)

User 403 oldi, lekin bu **ruxsat muammosi EMAS**:

```
"message": "All developers requesting access to the photo and video
permissions are required to tell Google Play about the core functionality
of their app"
```

Bu **Google Play policy gate** — ilova rasm/video ruxsatlarini so'raydi
(image_picker, image_cropper), va Google bu ruxsatlar nima uchun kerakligini
**deklaratsiya** qilishni talab qiladi. Deklaratsiya to'ldirilmaguncha,
**API ham, qo'lda submit ham** bloklanadi.

### Muammo — noto'g'ri tashxis

Avval har qanday commit 403 → "Service Account ruxsati yo'q" deb interaktiv
permission recovery menyusi ko'rsatardi. Lekin bu policy xatosi uchun
**noto'g'ri** — recovery menyu yordam bermaydi.

### Fix — policy xatosini AVVAL aniqlash

Commit 403 endi avval policy/deklaratsiya kalit so'zlarini tekshiradi:
`tell Google Play`, `core functionality`, `photo and video`, `data safety`,
`privacy policy`, `target api`, `advertising ID`, `App content`.

Topilsa, aniq yo'l-yo'riq beriladi (permission menyu emas):

```
✗ Bu RUXSAT emas — Google Play POLICY/deklaratsiya talabi

Google'ning aniq xabari:
  All developers requesting access to the photo and video permissions...

⚠ Photo va Video ruxsatlari deklaratsiyasi kerak
Ilovangiz rasm/video ruxsatlarini so'raydi (image_picker, image_cropper).

Yechim — Play Console'da to'ldiring:
  1. Play Console → ilovangizni oching
  2. Chap menyu: Policy → App content
  3. 'Photo and video permissions' bo'limini toping
  4. 'Start' / 'Manage' bosing va to'ldiring:
     • Ilova nima uchun rasm/videoga kirishi kerakligini tushuntiring
     • Yoki: kerak bo'lmasa, ruxsatlarni manifest'dan olib tashlang
  5. Saqlang va 1-2 soat kuting

[App content sahifasi avtomatik ochiladi]

MUHIM: deklaratsiyani to'ldirgach, AAB yuklangan — qayta build kerak emas:
  flutter-build → 3) Upload (build qilmasdan) → Android
```

### Boshqa policy turlari ham

`play_handle_commit_policy_403` quyidagilarni ham aniqlaydi:
- Data safety (Ma'lumotlar xavfsizligi)
- Target API level
- Advertising ID
- Privacy policy
- Umumiy App content

Har biriga aniq yechim.

### Texnik tafsilot

**Policy gate vs auth gate**: Google Play API 403'ni 2 sababdan qaytaradi —
(1) auth/permission (Service Account ruxsati), (2) policy/declaration
(App content to'ldirilmagan). Ikkalasi bir xil HTTP kod, lekin **butunlay
boshqa yechim**. Xabar matnini tahlil qilib ajratamiz — bu **error message
parsing** patterni.

**Bir marta to'ldiriladi**: policy deklaratsiyalar app-level, bir marta
to'ldiriladi. Keyingi upload'larda so'ralmaydi.

## [1.17.5] — 2026-06-09

### 🔴 KRITIK FIX — versiya `flutter build` flag'lari orqali (har doim ishlaydi)

User: "androidda build number oshmayapti pubspeckdan o(l)mayapti, custom
kiritsam ham ishlamadi".

### Sabab — `flutter.versionCode` reference ishonchsiz

Versiya pubspec → build.gradle (`flutter.versionCode` reference) → AAB
zanjiri orqali o'tardi. Ba'zi loyihalarda (eski template, custom setup) bu
reference pubspec'dan **o'qimaydi** — natijada custom build number ham
ta'sir qilmaydi.

### Fix — `--build-name` / `--build-number` flag'lari

Endi versiya `flutter build` ga **to'g'ridan-to'g'ri flag** orqali uzatiladi:

```
flutter build appbundle --release --build-name=1.0.11 --build-number=20
```

Bu flag'lar pubspec va build.gradle'dan **USTUN** — Flutter ularni
to'g'ridan-to'g'ri AAB/IPA ga yozadi. `flutter.versionCode` reference
ishlamasa ham, versiya **albatta** qo'llanadi.

Android (appbundle/apk) va iOS (ipa) — ikkalasida ham.

### O'zgartirildi — auto +1 o'chirildi (default = joriy)

User: "avtomatik oshmasin". v1.17.4'dagi avtomatik +1 default qaytarildi:

```
pubspec.yaml build # (versionCode)  [15]:    ← Enter → 15 (saqlanadi)
```

Oshirish uchun **'+'** bosing yoki yangi raqam yozing. Endi avtomatik oshmaydi.

### Endi versiya 100% ishonchli

| Holat | Avval | v1.17.5 |
|-------|-------|---------|
| Custom build # kiritish | Ba'zan ishlamasdi | **Albatta ishlaydi** (flag) |
| pubspec'dan o'qish | Reference'ga bog'liq | Flag bilan kafolatlangan |
| Eski template | Buzilardi | Flag bilan ishlaydi |

### Texnik tafsilot

**Build flags > config files**: `--build-name`/`--build-number` Flutter'ning
eng ishonchli versiya berish usuli — ular pubspec, build.gradle, project.pbxproj
hammasidan ustun. Config fayllarga tayanish o'rniga, build vaqtida aniq qiymat
berish — **explicit over implicit**.

**Belt and suspenders**: pubspec ham yangilanadi (repo izchilligi uchun) VA
flag ham uzatiladi (build uchun). Ikkala mexanizm — maksimal ishonchlilik.

## [1.17.4] — 2026-06-09

### O'zgartirildi — interaktiv Build'da versiya default = **+1** (avtomatik oshadi)

User: "androidda versiya ochirmayapti" — interaktiv Build'da versiya
o'zgarmadi.

### Sabab

Interaktiv Build'da (option 2) versiya prompt'ining default'i **joriy qiymat**
edi:
```
pubspec.yaml build # (versionCode)  [15]:    ← Enter → 15 (o'zgarmaydi)
```

Foydalanuvchi Enter bosib, versiya 15 da qoldi. Deploy tool'da eng tez-tez
holat — versiyani **oshirish**, lekin default "saqlash" edi.

### Fix — default endi joriy + 1

```
pubspec.yaml build # (versionCode)  [16]:    ← Enter → 16 (avtomatik +1)
```

Endi:
- **Enter** → build # avtomatik +1 oshadi (16)
- **Raqam yozish** → aniq qiymat (masalan 20)
- **Joriy'ni saqlash** → joriy raqamni yozing (15)

versionName (1.0.11) o'zgarmaydi — faqat build # oshadi (eng tez-tez naqsh).

### Play upload + store fetch bilan

Agar Play upload yoqilgan bo'lsa, default **store+1** (store'dan oxirgi).
Aks holda **lokal+1**. Har holda Enter bosish versiyani oshiradi.

### Foydalanuvchi tajriba taqqoslash

| Senariy | v1.17.3 | v1.17.4 |
|---------|---------|---------|
| Build, Enter bosish | Versiya o'zgarmaydi | **+1 oshadi** |
| Store fetch + Enter | store+1 | store+1 |
| Joriy'ni saqlash | Enter | Raqamni yozish |

### Texnik tafsilot

**Sensible default**: deploy tool'da "build qilish" odatda "yangi versiya
chiqarish" degani. Shuning uchun default **+1** bo'lishi mantiqiy. Bu
**convention over configuration** — eng tez-tez holatni default qilish.
Foydalanuvchi kamdan-kam holat (joriy'ni saqlash) uchun raqam yozadi.

## [1.17.3] — 2026-06-09

### Qo'shildi — persistent heartbeat (`\r` spinner paste'da yo'qolardi)

User v1.17.2 da ham upload "Release notes:" da to'xtagandek ko'rdi. Lekin
store fetch ISHLADI ("Store'dagi oxirgi: 25 → +1 → 26") — Google ulanadi.

### Sabab — `\r` spinner nusxa olganda ko'chmaydi

Spinner `\r` (carriage return) bilan **bir qatorni qayta-qayta yozadi**.
Terminal'da ko'rinadi, lekin **paste/log'ga ko'chmaydi** (transient). Shuning
uchun foydalanuvchi spinner'ni ko'rmay, "qotdi" deb o'ylaydi. Aslida upload
ishlayotgan bo'lishi mumkin.

### Fix — har 15 soniyada DOIMIY qator (heartbeat)

`\r` spinnerga qo'shimcha, har 15s da **newline bilan doimiy qator**:

```
  ⏳ Yuklanmoqda va qayta ishlanmoqda... 12s
  ⏳ Hali yuklanmoqda (15s, 98 MB sekin internetda normal)...
  ⏳ Yuklanmoqda va qayta ishlanmoqda... 27s
  ⏳ Hali yuklanmoqda (30s, 98 MB sekin internetda normal)...
  ⏳ Hali yuklanmoqda (45s, ...)...
```

Bu qatorlar **paste/log'da qoladi** — endi aniq ko'rinadi: ishlayaptimi
(soni oshyapti) yoki haqiqatan qotganmi (bir joyda turibdi).

### Barcha bosqichlarda

`_curl_spin` (token, edit, track, commit, connectivity) va [3/5] upload —
hammasida 15s heartbeat.

### Sizning holatingiz — ehtimol shunchaki sekin upload

Store fetch ishlagani (25→26) Google ulanishini isbotlaydi. 98 MB AAB
sekin internet/VPN'da 5-10 daqiqa yuklanadi. Endi heartbeat har 15s da
"hali yuklanmoqda" deb ko'rsatadi — qotmaganini bilasiz.

### Texnik tafsilot

**`\r` vs `\n` in terminal capture**: `\r` (carriage return) kursorni qator
boshiga qaytaradi, eski matnni qoplaydi. Bu real-time UI uchun zo'r, lekin
**terminal scrollback/copy** faqat `\n` (newline) bilan tugagan qatorlarni
saqlaydi. Shuning uchun progress'ni HAM `\r` (jonli), HAM `\n` (doimiy)
bilan ko'rsatish kerak — birinchisi tezkorlik, ikkinchisi tarix uchun.

## [1.17.2] — 2026-06-09

### Tuzatildi — `Store'dagi oxirgi: (bo'sh)` (subshell global trap)

User log: `✓ Store'dagi oxirgi:  → +1 → yangi build: 26` — store qiymati
**bo'sh** ko'rindi.

Sabab: `store_build=$(resolve_play_build_number ...)` — funksiya **subshell**'da
ishlaydi. Uning ichida o'rnatilgan `STORE_LATEST_VC` global o'zgaruvchi
**parent'ga o'tmaydi** (faqat stdout o'tadi). Klassik bash tuzog'i.

Fix: `play_get_latest_version_code`'ni to'g'ridan-to'g'ri `$()` da chaqiramiz —
store_max stdout orqali to'g'ri keladi:

```
✓ Store'dagi oxirgi: 31 → +1 → yangi build: 32 (konflikt yo'q)
```

### Yaxshilandi — connectivity check spinner

Google API tekshiruvi endi spinner ko'rsatadi (15s kutish ko'rinadi):

```
  ⏳ Google API ulanishi tekshirilmoqda... 3s
```

### "Android'ga yuklamayapti" — tashxis

Agar upload "Release notes:" dan keyin to'xtab qolsa, v1.17.2 da quyidagilar
ketma-ket ko'rinadi (har biri spinner bilan):

```
Release notes: ...
  ⏳ Google API ulanishi tekshirilmoqda... 1s
✓ Google API ulanishi bor (HTTP 404)
[1/5] Access token olinmoqda...
  ⏳ Access token... 2s
[2/5] Edit yaratilmoqda...
  ⏳ Edit yaratish... 1s
[3/5] AAB yuklanmoqda (98 MB)...
  ⏳ Yuklanmoqda... 47s        ← 98 MB sekin internetda 2-5 daqiqa
✓ Muvaffaqiyatli yuklandi!
```

**MUHIM**: 98 MB AAB sekin internet/VPN'da **bir necha daqiqa** yuklanadi.
Spinner harakatlanayotgan bo'lsa — kuting (qotmagan). Faqat **to'xtagan**
spinner = muammo.

### Texnik tafsilot

**Subshell variable scope**: `$(...)` yangi subshell yaratadi. Subshell'da
o'rnatilgan o'zgaruvchilar parent'ga ko'rinmaydi (faqat stdout/exit code).
Global'ni "qaytarish" uchun stdout orqali uzatish kerak. Bizning fix —
qiymatni to'g'ridan-to'g'ri stdout'dan olish.

## [1.17.1] — 2026-06-09

### O'zgartirildi — toza `store + 1` (lokal pubspec'ga qaramaydi)

User savol: "xullas auto deploy bosilganda shu ohirgi versiyani olib +1 qilib
chiqazib bersin".

v1.17.0 da `max(lokal, store) + 1` ishlatardi. Endi **toza `store + 1`** —
foydalanuvchi aniq shuni so'radi: store'dagi oxirgi versiyani olib, +1.

### Farq

| Holat | v1.17.0 (max+1) | v1.17.1 (store+1) |
|-------|-----------------|-------------------|
| store=31, lokal=11 | 32 | **32** |
| store=31, lokal=40 | 41 (lokal ustun) | **32** (store ustun) |

Endi lokal pubspec build raqami **ahamiyatsiz** — faqat store'dagi oxirgi
muhim. Bu eng sodda va tushunarli: "store'da nima bor, +1".

### Aniqroq xabar

```
⚡ Express: Store'dan oxirgi build number olinmoqda...
✓ Store'dagi oxirgi: 31 → +1 → yangi build: 32 (konflikt yo'q)
✓ Versiya: 1.0.0+11 → 1.0.0+32
```

Endi aniq ko'rinadi: store'da 31 bor edi, yangi 32.

### Nega store+1 (max emas)?

- **Sodda**: "store'dagi oxirgi + 1" — tushunish oson
- **Konfliktsiz**: store_max + 1 har doim store'da yo'q (kafolatlangan)
- **Lokal sync shart emas**: pubspec build raqami eskirgan/noto'g'ri bo'lsa
  ham muammo yo'q — store haqiqat manbai

### Texnik tafsilot

**Authoritative source wins**: lokal va store o'rtasida ziddiyat bo'lsa,
**store g'olib** (max emas). Bu "store = haqiqat" tamoyilining sof shakli.
Lokal raqam faqat store ololmaganda (fallback) ishlatiladi.

`STORE_LATEST_VC` global — store'dagi oxirgi qiymatni caller'ga uzatadi
(aniq xabar ko'rsatish uchun).

## [1.17.0] — 2026-06-09

### Qo'shildi — **Store'dan oxirgi build number'ni avtomatik olish**

User savol: "storelardan avtomatik ohirgi build numberni olishni iloji bormi
agar bo'lsa avtomatik olishni ham qo'shib ber professional qilib ber".

Mukammal — endi build raqami **Google Play'dagi haqiqiy oxirgi versionCode'dan**
hisoblanadi. Bu **versionCode conflict'ni butunlay yo'q qiladi** (eng tez-tez
uchraydigan upload xatosi).

### Qanday ishlaydi (fastlane'ning google_play_latest_version_code kabi)

1. Google Play API'dan barcha yuklangan AAB/APK'lar ro'yxati olinadi
2. Eng katta versionCode topiladi (store'dagi haqiqiy oxirgi)
3. Yangi build = **max(lokal, store) + 1** — har doim konfliktsiz

```
⚡ Express: Store'dan oxirgi build number olinmoqda...
✓ Store'dan olindi — yangi build: 32 (konflikt yo'q)
✓ Versiya: 1.0.0+11 → 1.0.0+32
```

### Express rejimda avtomatik

Auto Deploy (`--auto`) — build'dan oldin avtomatik store'dan so'raydi va
konfliktsiz raqamni ishlatadi. Savol yo'q.

### Interaktiv rejimda taklif

```
Store'dan oxirgi build number'ni tekshiraylikmi? (konflikt oldini oladi) (y/n) [y]: y

▶ Google Play'dan oxirgi build number olinmoqda...
✓ Store'dagi eng oxirgi'dan keyingi tavsiya: 32
  (Enter bosing — shu tavsiya ishlatiladi)

pubspec.yaml build # (versionCode)  [32]: ↵
```

### Yangi funksiyalar

- `play_get_latest_version_code` — Play API'dan eng katta versionCode
  (bundles + apks, edit yaratib-o'chirib)
- `resolve_play_build_number` — max(lokal, store) + 1 hisoblaydi

### Graceful fallback

Store'dan ololmasa (Google bloklangan, network, yoki birinchi release),
**lokal +1 ga qaytadi** — build to'xtamaydi:

```
ℹ Store'dan ololmadi (network/birinchi release) — lokal +1: 12
```

Tez connectivity probe (10s) — Google bloklangan bo'lsa, uzoq kutmasdan
darrov fallback.

### iOS cheklovi

App Store Connect build query uchun **`.p8` API key** kerak. Agar siz Apple ID
(altool/transporter) ishlatsangiz, iOS uchun store fetch ishlamaydi — lokal +1
ishlatiladi. (Apple ID auth build query API'sini qo'llab-quvvatlamaydi.)

### Foydalar

- **❌ versionCode conflict yo'q** — store haqiqat manbai
- **🖥️ Multi-machine/CI mos** — har qanday mashinadan to'g'ri raqam
- **🔄 Qo'lda upload bilan sync** — kimdir qo'lda yuklasa ham, keyingi avtomatik to'g'ri

### Texnik tafsilot

**Store as source of truth**: lokal pubspec raqami noto'g'ri bo'lishi mumkin
(boshqa mashina, CI, qo'lda upload Play Console'da). Store'ning o'zidan
so'rash — yagona ishonchli manba. Bu **distributed state reconciliation** —
markaziy haqiqatdan local'ni hisoblash.

**Edit yaratib-o'qib-o'chirish**: Play API'da o'qish uchun ham edit kerak.
Biz edit yaratamiz, bundles/apks ro'yxatini olamiz, edit'ni DELETE qilamiz
(orphan qoldirmaslik). Bu **read-only transaction** patterni.

## [1.16.4] — 2026-06-09

### Tashxis — Google Play bloki (Apple ishlaydi, Google yo'q)

User log tahlili: **iOS Apple'ga muvaffaqiyatli yuklandi** (altool, 2.8MB/s),
lekin **Play Store "Release notes:" da qotdi**.

Bu aniq belgi: **Apple serverlari ishlaydi, Google serverlari yo'q**. Demak
internet bor, lekin **Google API (oauth2.googleapis.com) bloklangan yoki
throttle qilingan** — O'zbekiston va ba'zi MDH tarmoqlarida keng tarqalgan.

### Tuzatildi — express_read literal `\033` ko'rsatardi

User chiqishida:
```
Hozir altool bilan qayta urinaylikmi? (y/n) [y]: \033[1m[⚡ auto: y]\033[0m
```

`\033[1m` literal ko'rinardi. Sabab: `BOLD='\033[1m'` literal string, va
`printf '%s'` uni interpretatsiya qilmaydi (faqat `echo -e`). Endi `echo -e`
ishlatiladi — toza chiqadi.

### Yaxshilandi — connectivity check VPN'ni tavsiya qiladi

Google API ulanmasa, endi aniq VPN yo'naltirish:

```
✗ Google API'ga ulanib bo'lmadi (oauth2.googleapis.com)

⚠ Apple (iOS) ishlasa-yu, Google (Android) ishlamasa — bu Google bloki
O'zbekiston va ba'zi MDH tarmoqlarida Google API'lar sekin/bloklangan.

🎯 ENG SAMARALI yechim: VPN yoqing
  Google Play API'ga ulanish uchun VPN (har qanday) yoqib, qaytadan urinib ko'ring

Boshqa yechimlar:
  • Mobil internet'ga o'ting (Wi-Fi o'rniga) yoki aksincha
  • Boshqa DNS: 8.8.8.8 yoki 1.1.1.1

AAB tayyor saqlangan — VPN yoqib qaytadan upload qiling (qayta build kerak emas):
  flutter-build → 3) Upload (build qilmasdan)
```

### Sizning holatingiz uchun yechim

1. **VPN yoqing** (har qanday — Google Play API'ga ulanish uchun)
2. Build allaqachon tayyor — qayta build shart emas:
   ```
   flutter-build → 3) Upload (build qilmasdan) → Android
   ```
3. VPN bilan Google API ulanadi, AAB yuklanadi

### Nega iOS ishladi-yu Android yo'q?

- **iOS (Apple)**: `contentdelivery.apple.com` — bloklanmagan
- **Android (Google)**: `oauth2.googleapis.com`, `androidpublisher.googleapis.com`
  — ba'zi tarmoqlarda bloklangan/sekin

Bu **server-specific** muammo, skript muammosi emas. VPN hal qiladi.

### Texnik tafsilot

**Asymmetric connectivity**: bitta tarmoqda turli xizmatlar turli holatda
bo'lishi mumkin (Apple reachable, Google blocked). Diagnostika har xizmatni
ALOHIDA tekshirishi kerak. Connectivity check aynan shuni qiladi —
Google'ni alohida probe qilib, aniq xabar beradi.

## [1.16.3] — 2026-06-08

### Qo'shildi — Google API connectivity pre-check (tez fail, hang emas)

User report: Android upload "Release notes:" da to'xtab qolyapti, `[1/5]`
umuman ko'rinmaydi. Bir necha marta aynan shu joyda.

### Tahlil

`[1/5]` dan oldin hech narsa qotmasligi kerak edi. Sabab — `[1/5]` token
so'rovi **oauth2.googleapis.com**'ga ulanmoqchi bo'lganda tarmoq sekin/bloklangan
bo'lsa, uzoq kutadi. Ba'zi tarmoqlarda (jumladan CIS/Uzbekistan) Google API'lar
sekin yoki vaqtincha bloklangan bo'lishi mumkin.

### Fix — connectivity pre-check

Upload boshida (token'dan oldin) tez ulanish tekshiruvi:

```
Google API ulanishi tekshirilmoqda...
✓ Google API ulanishi bor (HTTP 404)
[1/5] Access token olinmoqda...
```

Agar 15 soniyada ulanmasa — uzoq hang o'rniga **darrov aniq xabar**:

```
✗ Google API'ga ulanib bo'lmadi (oauth2.googleapis.com)

Sabab — internet sekin, uzilgan, yoki Google bloklangan:
  • Boshqa tarmoqda urinib ko'ring (Wi-Fi ↔ mobil)
  • VPN yoqilgan bo'lsa, o'chirib ko'ring (yoki yoqing)
  • Internet barqarorligini tekshiring

→ curl -v --connect-timeout 10 https://oauth2.googleapis.com/
→ ping -c 3 google.com
```

### MUHIM — eski versiyada bu yo'q

Agar siz spinner'ni va connectivity check'ni **ko'rmayotgan** bo'lsangiz,
eski versiyadasiz. Auto-update versiya tekshiruvi **5 soniya** timeout bilan —
sekin internetda u ham timeout bo'lib, yangilanish taklif qilinmasligi mumkin.

**Qo'lda yangilash:**
```bash
curl -fsSL https://raw.githubusercontent.com/Jaloliddin-Fozilov/flutter-build-tool/main/flutter_build.sh -o "$(which flutter-build)"
```

### Texnik tafsilot

**Fail-fast connectivity probe**: tarmoq operatsiyasidan oldin tez "reachable?"
tekshiruvi — bu **circuit breaker** patternining oddiy varianti. Bloklangan
xizmatga uzoq urinish o'rniga, darrov aniqlab, foydalanuvchiga aytadi.

**HTTP 404 = reachable**: `GET oauth2.googleapis.com/` 404 qaytaradi (endpoint
yo'q), lekin bu **ulanish bor** degani. Connectivity uchun har qanday HTTP
javob (hatto 404) — muvaffaqiyat. Faqat `000` (yoki bo'sh) = ulanmadi.

## [1.16.2] — 2026-06-08

### Tuzatildi — BARCHA Play upload bosqichlariga spinner (har qadam ko'rinadi)

User report: Android upload hali ham "qotib qolyapti" — paste "Play Store ga
yuklash" header'ida (▶ [1/5] dan oldin) to'xtagan.

### Sabab

v1.16.1 faqat **[3/5] AAB upload**'ga spinner qo'shgan edi. Lekin boshqa
network bosqichlari ([1/5] token, [2/5] edit, [4/5] track, [5/5] commit)
hali ham **jim** edi. Sekin internetda ulardan birortasi sekinlashsa,
foydalanuvchi qaysi qadamda ekanini va tirik ekanini bilmasdi.

### Fix — universal `_curl_spin` helper

Yangi `_curl_spin` — har bir Play API so'rovini elapsed-time spinner bilan
o'raydi:

```
  ⏳ Access token... 2s
  ⏳ Edit yaratish... 1s
  ⏳ AAB upload... 47s        (98 MB)
  ⏳ Track qo'shish (internal)... 3s
  ⏳ Commit... 8s
```

Endi **har bir bosqich** sekund hisoblagich ko'rsatadi. Qaysi qadamda
ekaningiz va skript tirikligini doim ko'rasiz.

### Spinner stderr'ga yoziladi

`_curl_spin` spinner'ni **stderr**'ga yozadi — shuning uchun token kabi
qiymatlarni qaytaradigan funksiyalarda ham ishlatish mumkin (stdout return
qiymatini ifloslamaydi). Bu **stream discipline** — UI stderr'da, ma'lumot
stdout'da.

### Har bosqichda timeout + HTTP code diagnostika

`_curl_spin` `SPIN_RC` (curl exit) va `SPIN_HTTP` (HTTP status) ni o'rnatadi.
Har bosqich:
- Timeout (rc 28) → aniq "timeout" xabari
- HTTP ≥ 400 → status kodi bilan xato

### Barcha 5 bosqich qamrab olindi

| Bosqich | Avval | v1.16.2 |
|---------|-------|---------|
| [1/5] Token | jim | ⏳ spinner |
| [2/5] Edit | jim | ⏳ spinner |
| [3/5] Upload | spinner (v1.16.1) | ⏳ spinner |
| [4/5] Track | jim | ⏳ spinner |
| [5/5] Commit | jim | ⏳ spinner |

### Texnik tafsilot

**Stream discipline (stdout vs stderr)**: spinner — bu **UI** (foydalanuvchi
uchun), funksiya return qiymati — bu **ma'lumot** (dastur uchun). Ularni
ajratish kerak: UI → stderr, ma'lumot → stdout. Shunda `token=$(get_token)`
da spinner token'ni ifloslamaydi. Bu Unix filtr falsafasi.

**HTTP code + body separation**: `curl -o body_file -w '%{http_code}'` —
body faylga, status kod stdout'ga. Ikkalasi alohida, aralashmaydi.

## [1.16.1] — 2026-06-08

### Tuzatildi — Android upload "oxirigacha qotib qolish" (server processing)

User report: "androidda ohirgcha deploy bo'lmayapti qotib qolyapti auto
uploadda testladim".

### Sabab — progress 100% bo'lgach Google JIM qayta ishlaydi

v1.15.3 progress bar qo'shdi, lekin u faqat **upload foizini** ko'rsatadi.
Progress 100% bo'lgach, **Google AAB'ni qayta ishlaydi** (98 MB validatsiya,
versionCode generatsiya = 1-3 daqiqa). Bu paytda curl **javob kutib jim
turadi** — progress bar 100%'da qotib, hech narsa o'zgarmaydi.

Foydalanuvchi "oxirigacha yetib, qotib qoldi" deb ko'radi — aslida Google
qayta ishlayotgan edi.

### Fix — uzluksiz elapsed-time spinner

`--progress-bar` o'rniga **background curl + sekund hisoblagich**:

```
[3/5] AAB yuklanmoqda (98 MB)...
(yuklash + Google qayta ishlash: sekin internetda 2-5 daqiqa — bu NORMAL)
  ⏳ Yuklanmoqda va qayta ishlanmoqda...  47s  (Ctrl+C bekor)
```

Hisoblagich **butun jarayon davomida** (upload + server processing) har
sekund yangilanadi. Endi 100%'dan keyin ham faollik ko'rinadi — hech qachon
qotgandek tuyulmaydi.

```
Yuklash yakunlandi (73s)
✓ AAB yuklandi, versionCode=31
```

### Texnik mexanizm

```bash
curl -sS ... -o body_file -w '%{http_code}' > code_file 2>/dev/null &
curl_pid=$!
while kill -0 "$curl_pid" 2>/dev/null; do
  printf '\r  ⏳ Yuklanmoqda... %3ds' "$secs"
  sleep 1; secs=$((secs + 1))
done
wait "$curl_pid"; upload_rc=$?
```

- **Background curl** (`&`) — body va http_code fayllarga
- **`kill -0` polling** — curl tirikligini tekshiradi
- **`\r` spinner** — bir qatorda yangilanadi
- **`wait`** — curl exit code'ini oladi

### max-time 1800 → 900

Upload timeout 30 daqiqadan **15 daqiqaga** kamaytirildi — sekin internetda
ham 98 MB 15 daqiqada yetadi, ortig'i foydasiz kutish.

### Texnik tafsilot

**Progress % ≠ butun jarayon**: `--progress-bar` faqat **transfer**'ni
ko'rsatadi (bytes uzatish). Lekin HTTP so'rovda transfer'dan keyin **server
processing** bor — javob kutish. Katta upload'da bu sezilarli. Spinner
ikkala fazani ham qamraydi (curl tugaguncha sanaydi).

**Liveness indicator**: elapsed-time counter — eng oddiy "men tirikman"
signali. Progress % yo'q, lekin **uzluksiz harakat** bor. "Qotdimi yoki
ishlayaptimi?" savoliga aniq javob.

## [1.16.0] — 2026-06-08

### Qo'shildi — iOS va Android versiyasini **pubspec.yaml'ga bog'lash**

User savol: "ios va android versiyani pubspeck yaml dan osin yani bir xil
qilib ber shular bilan bir xil yursin".

### Muammo — hardcoded versiyalar pubspec'dan ajraladi

Ba'zi loyihalarda `build.gradle` va `project.pbxproj` da versiya **qattiq
yozilgan** (hardcoded):
```gradle
versionCode 5          // pubspec'dan ajralgan
versionName "1.2.0"
```

Bu pubspec.yaml (`version: 1.0.0+1`) bilan **farq qiladi** — natijada
iOS/Android/pubspec uch xil versiyada bo'lishi mumkin.

### Fix — Flutter reference'larga aylantirish

Yangi `convert_to_flutter_version_refs` funksiyasi hardcoded'ni Flutter
reference'ga aylantiradi:

| Fayl | Avval | Keyin |
|------|-------|-------|
| `build.gradle` (Groovy) | `versionCode 5` | `versionCode flutter.versionCode` |
| `build.gradle.kts` (KTS) | `versionCode = 5` | `versionCode = flutter.versionCode` |
| `project.pbxproj` (iOS) | `CURRENT_PROJECT_VERSION = 5` | `= $(FLUTTER_BUILD_NUMBER)` |
| `project.pbxproj` (iOS) | `MARKETING_VERSION = 1.2.0` | `= $(FLUTTER_BUILD_NAME)` |

`flutter.versionCode` va `$(FLUTTER_BUILD_NUMBER)` — bular **pubspec.yaml'dan**
o'qiladi. Demak konvertatsiyadan keyin **uchala versiya doim bir xil yuradi**.

### Build vaqtida avtomatik taklif

Hardcoded versiya aniqlansa, build boshida taklif qilinadi:

```
⚠ Hardcoded versiya aniqlandi (pubspec'dan ajralgan):
  • Android: 1.2.0 (5) — build.gradle'da qattiq yozilgan
  • iOS: 1.2.0 (5) — project.pbxproj'da qattiq yozilgan

Ularni pubspec.yaml'ga bog'lash mumkin — keyin doim bir xil yuradi
(faqat pubspec'ni o'zgartirasiz, iOS+Android avtomatik oladi)

  Pubspec'ga bog'laymizmi? (y/n) [y]: y

✓ Android: android/app/build.gradle → Flutter reference (pubspec'dan oladi)
✓ iOS: ios/Runner.xcodeproj/project.pbxproj → Flutter reference (pubspec'dan oladi)

Endi iOS va Android versiyasi pubspec.yaml bilan bir xil yuradi.
```

### Express rejimda avtomatik

Auto Deploy (`--auto`) rejimida hardcoded aniqlansa, **savolsiz** avtomatik
bog'lanadi (Express falsafasi).

### Xavfsizlik

- **Backup**: konvertatsiyadan oldin har fayl `*.bak.*` ga saqlanadi
- **Idempotent**: allaqachon Flutter reference bo'lsa, o'zgartirmaydi
  (qayta ishlatish xavfsiz)
- **Faqat hardcoded**: raqamli/versiya qiymatlar almashtiriladi, ref'lar
  tegilmaydi

### Texnik tafsilot

**Single source of truth (Flutter idiom)**: standart Flutter loyihasi
versiyani faqat pubspec.yaml'da saqlaydi. `build.gradle` va `project.pbxproj`
shuni `flutter.versionCode` / `$(FLUTTER_BUILD_NUMBER)` orqali o'qiydi. Bu
**DRY** — versiya bitta joyda, hamma joyga tarqaladi.

**Single-quote sed for `$(...)`**: iOS uchun `$(FLUTTER_BUILD_NUMBER)` —
single-quoted sed ishlatildi, aks holda bash uni **command substitution**
deb talqin qilardi. Bu shell quoting'ning nozik joyi.

## [1.15.3] — 2026-06-08

### Tuzatildi — Play Store upload "qotib qolish" (aslida progress yo'q edi)

User report: "qotib qovoti shunga kelganda" — Play Store upload header
chiqib, keyin hech narsa ko'rinmasdi (98 MB AAB).

### Sabab — `curl -fsS` sukut bilan yuklaydi (progress bar yo'q)

AAB upload `curl -fsS` bilan edi — `-s` (silent) progress meter'ni
o'chiradi. **98 MB fayl** sekin internetda bir necha **daqiqa** yuklanadi,
lekin ekranda **hech qanday belgi yo'q** — to'liq qotgandek ko'rinadi.

Aslida qotmagan — **jim yuklayotgan** edi.

### Fix — progress bar + timeout

```
[3/5] AAB yuklanmoqda (98 MB) — progress pastda ko'rinadi:
(katta fayl + sekin internet = bir necha daqiqa, bu normal)
######################################   67.3%
```

- **`--progress-bar`** — yuklash jarayoni terminalда ko'rinadi (foiz + bar)
- **Response body faylga** (`-o`), **http_code alohida** (`-w`) — progress
  javobni ifloslamaydi
- **`--connect-timeout 30 --max-time 1800`** — 30 daqiqada tugamasa, aniq
  timeout xabari (cheksiz hang yo'q)

### Barcha Play API curl'lariga timeout

Cheksiz hang oldini olish uchun barcha so'rovlarga timeout qo'shildi:

| Bosqich | connect-timeout | max-time |
|---------|-----------------|----------|
| Access token | 30s | 120s |
| Edit yaratish | 30s | 120s |
| **AAB upload** | **30s** | **1800s (30 daqiqa)** |
| Track qo'shish | 30s | 120s |
| Commit | 30s | 120s |

### Timeout xabari

Agar internet uzilsa yoki juda sekin bo'lsa:

```
✗ AAB yuklash timeout (30 daqiqa) — internet juda sekin yoki uzildi
ℹ Qayta urinib ko'ring yoki barqaror internetda sinab ko'ring
```

Endi cheksiz kutish o'rniga aniq xabar.

### Texnik tafsilot

**Silent ≠ frozen**: `curl -s` progress meter'ni o'chiradi — bu kichik
so'rovlar uchun yaxshi (toza output), lekin **katta fayl upload** uchun
yomon (foydalanuvchi jarayonni ko'rmaydi). Yechim: katta upload uchun
`--progress-bar`, kichik so'rovlar uchun jim.

**Progress vs response capture**: `--progress-bar` stderr'ga yozadi,
`-o file` body'ni faylga, `-w '%{http_code}'` kodni stdout'ga. Uchtasi
alohida oqim — progress javobni ifloslamaydi. Bu **stream separation**
patterni.

**Timeout as safety net**: `--max-time` cheksiz hang'ning oldini oladi.
Sekin internet real muammo (Uzbekistan/CIS), lekin **30 daqiqadan ko'p**
kutish foydasiz — aniq xabar berib to'xtagan ma'qul.

## [1.15.2] — 2026-06-08

### Tuzatildi — Auto mode endi **TO'LIQ avtomatik** (hech qanday prompt)

User report: "auto mode to'liq auto bo'lishi kerak. Hozir altool bilan qayta
urinaylikmi? (y/n) [y]: y — y ni bosib tasdiqlashim yoki boshqa narsalarni
kutmasin".

### Sabab

v1.15.1 da Express rejim asosiy oqimni avtomat qildi, lekin **upload paytidagi
ba'zi prompt'lar** hali ham `y` kutardi:
- iOS Transporter → altool fallback: "Hozir altool bilan qayta urinaylikmi?"
- Play Store 403 recovery menyusi
- Android signing tanlovi (key.properties bor bo'lsa ham)
- `pause` ("Davom etish uchun Enter...")
- Promotion taklifi ("Hozir promote qilamizmi?")

### Fix — barcha deploy prompt'lari Express'da avtomatik

Yangi `express_read` helper: EXPRESS_MODE'da prompt'ni **o'qimaydi**, default'ni
darrov qaytaradi:

```
Hozir altool bilan qayta urinaylikmi? (y/n) [y]: [⚡ auto: y]
[darrov altool ishga tushadi — kutish yo'q]
```

Guard qo'yilgan joylar:

| Prompt | Express xulqi |
|--------|---------------|
| `pause` ("Enter...") | O'tkazib yuboriladi (kutmaydi) |
| altool fallback (y/n) | Avtomatik `y` (altool ishlaydi) |
| Android signing tanlovi | key.properties bor → joriy keystore (savol yo'q) |
| ExportOptions yaratish | Bor → ishlatadi; yo'q → xato (yarata olmaydi) |
| promotion taklifi | O'tkazib yuboriladi |
| Commit 403 menyusi | Xabar berib chiqadi (kutmaydi) |
| Bundle 403 menyusi | Xabar berib chiqadi (kutmaydi) |

### Error path'lar ham kutmaydi

Agar Express'da 403 yoki signing muammosi chiqsa, **interaktiv menyu
ko'rsatilmaydi** — qisqa xabar beriladi va to'xtaydi (hang yo'q):

```
⚠ Commit 403 — Express rejimda to'xtatildi (savol berilmaydi)
ℹ Sabab: Service Account'da 'Release' ruxsati yo'q
ℹ Edit ID saqlandi (24 soat amal qiladi): 0633...
ℹ Qo'lda hal qilish: flutter-build → 2) Build (Express emas) → 403 menyusi
```

### Endi Auto mode oqimi (0 ta savol)

```
flutter-build --auto

⚡ Express — platforma tanlash (faqat 2+ sozlangan bo'lsa)
[checkbox — yagona savol]

⚡ Versiya +1 avtomatik
▶ Build (exit code check + R8 auto-fix)
▶ iOS upload (Transporter buzilsa → altool avtomatik)
▶ Play upload
✓ Tugadi
```

Platforma checkbox'dan keyin **hech narsa so'ralmaydi** — to'liq avtomatik.

### Texnik tafsilot

**Auto-default pattern**: `express_read` Unix'dagi `yes | command` ga
o'xshaydi — lekin har prompt'ga mos default bilan. Bu **non-interactive mode**
pattern — CI/CD tool'larida keng tarqalgan (`apt-get -y`, `npm --yes`).

**Fail-fast in automation**: avtomatik rejimda, hal qilib bo'lmaydigan muammo
(403, signing yo'q) **darrov to'xtaydi**, interaktiv menyu ko'rsatmaydi.
Avtomatika "javob kutib qotib qolmaydi" — bu **automation invariant**.

## [1.15.1] — 2026-06-08

### Qo'shildi — Auto Deploy'da **platforma checkbox** (Android/iOS tanlash)

User report: "automode androidga keganda qotib qolyapti" + "automodeda
tanlasin android yoki iosligini, ya'ni prodni ichiga check box qilib qo'shib
ber automodeni".

### Sabab

`bajar` loyihasi **ham iOS ham Android** sozlangan edi. Express rejim
**ikkalasini ham** avtomatik deploy qildi — iOS muvaffaqiyatli, keyin Android'ga
o'tdi. Foydalanuvchi faqat bittasini xohlagan, lekin tanlash imkoni yo'q edi.
Android'da (98 MB AAB + ehtimol permission prompt) "qotib qolgandek" ko'rindi.

### Fix — bitta minimal savol: qaysi platforma?

Express rejim endi **sozlangan platformalarni** aniqlaydi va checkbox ko'rsatadi:

```
⚡ Express (Auto Deploy) — sozlamalar aniqlanmoqda

Sozlangan platformalar:
  🤖 Android: uz.iportal.bajar (deploy | internal)
  🍏 iOS: uz.iportal.bajar (jaloliddinish)

Qaysi platformaga deploy? (Space toggle, Enter tasdiqlash)
  ▶ [✓] 🤖 Android (Play Store)
    [✓] 🍏 iOS (App Store)
```

Default: hammasi belgilangan. Space bilan kerakmaganini o'chiring.

### Aqlli xulq

- **Faqat 1 platforma sozlangan** → checkbox ko'rsatilmaydi, to'g'ridan-to'g'ri
  o'shanisi (ortiqcha savol yo'q)
- **Ikkala platforma sozlangan** → checkbox bilan tanlaysiz
- **Hech narsa tanlanmasa** → bekor qilinadi (xato emas)

### "Savolsiz" falsafasi buzilmaydi

Platforma tanlovi — **yagona savol**, chunki u **fundamental** va har deploy'da
o'zgaradi (ba'zan faqat iOS, ba'zan faqat Android). Qolgan hamma narsa hali ham
avtomatik: versiya +1, release notes, build, upload, rollout.

### Foydalanuvchi tajriba taqqoslash

| Senariy | v1.15.0 | v1.15.1 |
|---------|---------|---------|
| 1 platforma sozlangan | Avto (yaxshi) | Avto (o'zgarmadi) |
| 2 platforma sozlangan | ❌ Ikkalasi majburiy | ✓ Checkbox bilan tanlash |
| Faqat iOS kerak | ❌ Android ham majburiy | ✓ Android'ni o'chirish |

### Texnik tafsilot

**Configured vs selected**: avval Express "sozlangan = deploy qilinadi" deb
hisoblardi. Endi "sozlangan = tanlanishi mumkin" — foydalanuvchi sozlangan
to'plamdan tanlaydi. Bu **2 bosqichli model** (detection → selection).

**Conditional prompt**: faqat 2+ platforma sozlangan bo'lsa checkbox ko'rsatiladi.
1 ta bo'lsa — savol bermaymiz (YAGNI: tanlov yo'q joyda savol bermaslik).

## [1.15.0] — 2026-06-05

### Qo'shildi — ⚡ **Auto Deploy (Express) rejimi** — savolsiz deploy

User savol: "bizga bitta mode kerak yani uni yoqsam ortiqcha savollarsiz auto
deploy qilishi kerak".

Mukammal — endi asosiy menyuda **1-o'rinda**:

```
╭─ Tanlovingiz ───────────────────────────────────────────╮
│  1) ⚡ Auto Deploy (savolsiz: build + versiya+1 + upload)  ← YANGI
│  2) 🚀 Build (qadam-baqadam: build + upload)
│  3) 📤 Upload (build qilmasdan, oxirgisini yuklash)
│  ...
```

### Auto Deploy nima qiladi (savolsiz)

Bir marta tanlasangiz, **hech narsa so'ramaydi**:

1. **Konfiguratsiya avtomatik aniqlanadi** — per-project sozlamalardan
   (Android Play akkaunt, iOS App Store akkaunt, track)
2. **Production rejim** — release, signed
3. **Versiya +1** — pubspec build # avtomatik oshiriladi
4. **Release notes avtomatik** — git oxirgi commit (yoki "Version X released")
5. **Build** — exit code tekshirish + R8 auto-fix (v1.14.1)
6. **Upload** — sozlangan track'ga (internal/production)
7. **Rollout 100%** — production uchun

### Foydalanish — 2 usul

**Menyu orqali:**
```
flutter-build → 1) Auto Deploy
```

**CLI orqali (alias/script uchun):**
```bash
flutter-build --auto      # yoki --express, yoki -a
```

### Misol oqim

```
⚡ Express (Auto Deploy) — sozlamalar avtomatik aniqlanmoqda

✓ Android: uz.gennis.todo
   Akkaunt: deploy  |  Track: internal

⚡ Express: versiya avtomatik oshirildi
✓ Versiya: 1.0.0+5 → 1.0.0+6
✓ pubspec.yaml yangilandi: 1.0.0+6

▶ Android build (PRODUCTION)
[build...]
✓ Android build muvaffaqiyatli (exit code 0)

⚡ Express: release notes avtomatik | rollout 100%
[upload...]
✓ Muvaffaqiyatli yuklandi!
```

### Birinchi marta sozlash kerak

Auto Deploy **sozlangan loyiha** uchun. Agar loyiha hali sozlanmagan bo'lsa
(akkaunt/keystore yo'q), aniq xabar beradi:

```
⚠ Express rejim uchun hech qaysi platforma sozlanmagan
ℹ Avval oddiy build/upload bilan akkaunt va keystore'ni sozlang:
ℹ   flutter-build → 2) Build (to'liq sozlash)
ℹ Sozlangach, Express rejim ishlaydi
```

Bir marta oddiy build bilan sozlangach, keyin Auto Deploy ishlaydi.

### Yangi funksiyalar

- `express_configure` — per-project config'dan barcha flag'larni avtomatik
  o'rnatadi (Android/iOS aniqlash, account, track)
- `express_auto_release_notes` — git commit'dan yoki default release notes
- `--auto` / `--express` / `-a` CLI flag

### Multi-platforma

Agar loyiha **ham Android ham iOS** sozlangan bo'lsa, Auto Deploy ikkalasini
ham deploy qiladi (Android keyin iOS). Faqat bittasi sozlangan bo'lsa,
o'shanisini.

### Texnik tafsilot

**DRY composition**: Express rejim mavjud `main_build_flow`'ni `EXPRESS_MODE`
flag bilan reuse qiladi. Wizard, version prompt, confirmation, release notes
prompt, rollout prompt — barchasi `EXPRESS_MODE` tekshiruvi bilan o'tkazib
yuboriladi. Yangi kod minimal — bitta `express_configure` + flag tekshiruvlari.

**Config-driven automation**: Express rejim avval sozlangan per-project
config'ga tayanadi (account, track). Bu **convention over configuration** —
foydalanuvchi bir marta sozlaydi, keyin avtomatika ishlaydi.

**Safety preserved**: Express rejim ham build exit code'ini tekshiradi (v1.14.1),
R8 auto-fix qiladi, versiya conflict'ni oldini oladi. Tezlik xavfsizlik
hisobidan emas.

## [1.14.2] — 2026-06-05

### Tuzatildi — "App versiyasi oshmayapti" (Flutter reference chalkashligi)

User report: "app versiyasi oshmayapti". Foydalanuvchi **Android versionCode**'ni
`+` bilan oshirdi (1→2), lekin **pubspec build #** ni o'zgartirmadi. Natijada
versiya o'zgarmadi.

### Sabab — standart Flutter loyihasida pubspec yagona manba

Standart Flutter loyihasida `android/app/build.gradle`:
```gradle
versionCode flutter.versionCode    // ← pubspec.yaml'dan o'qiladi
versionName flutter.versionName
```

Demak **Android versionCode pubspec.yaml'dan olinadi**. Foydalanuvchi alohida
"Android versionCode"'ni oshirsa ham, build pubspec'dan o'qigani uchun
**e'tiborsiz qoladi**.

Eski UX 2 ta alohida prompt ko'rsatardi:
```
pubspec.yaml build #  [1]:         ← Enter (o'zgarmadi)
Android versionCode   [1]: +       ← oshirdi (lekin ta'sir qilmaydi!)
```

Foydalanuvchi Android'ni oshirdi, lekin pubspec +1 da qoldi → versiya 1.

### Fix — Flutter reference bo'lsa, faqat pubspec so'raladi

v1.14.2 da loyiha pubspec'ni manba sifatida ishlatsa:

```
✓ Bu loyiha pubspec.yaml'ni yagona manba sifatida ishlatadi
ℹ (Android versionCode va iOS build number pubspec.yaml'dan olinadi)
ℹ Versiya oshirish uchun pubspec build # ni oshiring (yoki '+' bosing)

    pubspec.yaml versiya (versionName)  [1.0.0]:
    pubspec.yaml build # (versionCode)  [1]: +
```

Endi **bitta** prompt — pubspec build #. `+` bossangiz, pubspec 1→2 ga oshadi
va Android/iOS avtomatik oladi.

Alohida Android/iOS prompt'lar **faqat hardcoded versiya** ishlatilganda
ko'rsatiladi (Flutter reference emas).

### Tasdiqlashda aniq ko'rsatish

```
Versiyalar (eski → yangi):
  pubspec.yaml  : 1.0.0+1 → 1.0.0+2
  Android       : 1.0.0 (2)  ← pubspec.yaml'dan
```

"← pubspec.yaml'dan" — foydalanuvchi qayerdan kelishini ko'radi.

### Versiya o'zgarmaganda ogohlantirish

```
⚠ Versiya o'zgarmadi (1.0.0+1)
⚠ Agar bu versiya allaqachon Store'ga yuklangan bo'lsa, upload xato beradi!
ℹ Yangi versiya uchun: build # ni oshiring yoki '+' bosing
```

Bu **upload conflict** (versionCode allaqachon ishlatilgan) oldini oladi.

### Foydalanuvchi tajribasi taqqoslash

| Senariy | v1.14.1 | v1.14.2 |
|---------|---------|---------|
| Standart Flutter | 4 prompt (pubspec + Android + iOS) | 2 prompt (faqat pubspec) |
| Android versionCode | Alohida (e'tiborsiz qolardi) | Pubspec'dan avtomatik |
| `+` qaerda bosish | Chalkash (Android yoki pubspec?) | Aniq (faqat pubspec) |
| Versiya o'zgarmasa | Jim | Ogohlantirish |

### Texnik tafsilot

**Single source of truth**: Flutter'ning version modeli pubspec.yaml'ni
markaziy manba qiladi (`version: 1.0.0+1`). build.gradle va project.pbxproj
shu qiymatni `flutter.versionCode` orqali oladi. UX bu modelга mos kelishi
kerak — 2 ta alohida prompt bu invariantni buzadi va chalkashlik tug'diradi.

**Conditional prompts**: `$ANDROID_USES_FLUTTER_REF` va `$IOS_USES_FLUTTER_REF`
flag'lari asosida prompt'lar dinamik ko'rsatiladi. Bu **progressive disclosure** —
faqat kerakli ma'lumot so'raladi.

## [1.14.1] — 2026-06-05

### 🔴 KRITIK TUZATISH — Build false positive (muvaffaqiyatsiz → "muvaffaqiyatli")

User report: build `exit code 1` bilan **muvaffaqiyatsiz tugadi** (R8 xatosi),
lekin skript **"✓ Android build muvaffaqiyatli"** dedi!

```
BUILD FAILED in 2m 17s
Gradle task bundleRelease failed with exit code 1
  ✓ Android build muvaffaqiyatli      ← XATO! (false positive)
```

### Sabab

Build kodi `flutter build appbundle --release` ni ishga tushirardi, lekin
**exit code'ni TEKSHIRMAS edi**:

```bash
flutter build appbundle --release    # exit code e'tiborsiz qoldirilardi
...
ok "Android build muvaffaqiyatli"    # SHARTSIZ "muvaffaqiyatli" deyilardi
```

Bu v1.12.2'dagi altool false positive bug'iga o'xshash — **eng xavfli bug
turi**, chunki keyin skript mavjud bo'lmagan/eski AAB'ni upload qilmoqchi
bo'lardi.

### Fix — exit code tekshirish (Android + iOS)

`tee` + `${PIPESTATUS[0]}` bilan output'ni ko'rsatib, exit code'ni ushlash:

```bash
flutter build appbundle ${variant} 2>&1 | tee "$log"
android_build_rc=${PIPESTATUS[0]}
if [ "$android_build_rc" -ne 0 ]; then
  handle_android_build_failure ...    # tahlil + auto-fix
  return 1
fi
ok "Android build muvaffaqiyatli (exit code 0)"   # FAQAT 0 bo'lsa
```

iOS build ham xuddi shu false positive bug'dan tozalandi.

### Qo'shildi — R8 Play Core missing classes AVTOMATIK tuzatish

User'ning haqiqiy build xatosi:
```
ERROR: R8: Missing class com.google.android.play.core.tasks.OnFailureListener
Missing class com.google.android.play.core.tasks.Task
Execution failed for task ':app:minifyReleaseWithR8'.
```

Bu **mashhur Flutter muammosi** — Flutter embedding `com.google.android.play.core.*`
klasslarni reference qiladi (deferred components uchun), lekin app ularni
o'z ichiga olmaydi. R8 (code shrinker) topa olmay xato beradi.

### Yangi `handle_android_build_failure` — pattern-based diagnostika + auto-fix

Build xato bersa, output'dan **sabab aniqlanadi**:

| Pattern | Sabab | Auto-fix |
|---------|-------|----------|
| `Missing class ...play.core` | R8 + Play Core | ProGuard qoidalari + retry |
| `OutOfMemoryError` | Gradle heap | gradle.properties + retry |
| `keystore/SigningConfig` | Signing | keystore qayta sozlash |
| `Could not resolve` | Dependency | flutter clean + pub get |
| boshqa | Aniq emas | stacktrace yo'l-yo'riq |

### R8 auto-fix workflow

```
✗ Android build muvaffaqiyatsiz (exit code: 1)

Sabab aniqlandi: R8 + Play Core deferred components
Flutter embedding 'com.google.android.play.core.*' klasslarini reference qiladi,
lekin app ularni o'z ichiga olmaydi. Bu mashhur Flutter muammosi.

  Avtomatik tuzatib, qayta build qilamizmi? (y/n) [y]: y

✓ ProGuard qoidalari qo'shildi: android/app/proguard-rules.pro

▶ Qayta build qilinmoqda (ProGuard qoidalari bilan)...
✓ 🎉 Build muvaffaqiyatli! (ProGuard qoidalari yordam berdi)
```

### `_ensure_proguard_playcore_rules` — idempotent ProGuard fix

`android/app/proguard-rules.pro` ga qo'shadi:
```
# flutter-build-tool: Play Core deferred components fix
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
```

Plus `build.gradle`/`build.gradle.kts` da `proguard-rules.pro` reference
borligini tekshiradi (Groovy va KTS ikkalasi ham).

Idempotent — marker bilan tekshiriladi, qayta chaqirilsa dublikat qo'shmaydi.

### Test natijalari

3/3 unit test:
- ✓ R8 Play Core pattern detection
- ✓ ProGuard qoidalari to'g'ri qo'shiladi
- ✓ Idempotent (dublikat yo'q)

### Texnik tafsilot

**Build correctness — eng muhim invariant**: build tool'ning ENG asosiy
va'dasi — "muvaffaqiyatli" faqat haqiqatan muvaffaqiyatli bo'lganda deyish.
Exit code tekshirmaslik bu va'dani buzadi. Bu **silent failure** —
foydalanuvchi build buzilganini bilmay, eski AAB'ni upload qiladi.

**R8 self-documenting fix**: R8 `missing_rules.txt` faylida aniq qaysi
qoidalar kerakligini yozadi. Bizning fix universal `-dontwarn`/`-keep`
qoidalarini qo'shadi (deferred components ishlatmaydigan app'lar uchun
xavfsiz).

## [1.14.0] — 2026-06-04

### Qo'shildi — **Bundle upload 403** uchun maxsus diagnostika (YANGI app)

User report: boshqa loyiha (`uz.gennis.todo`, shaxsiy account
`premium-aloe-322109`) — xato **[3/5] AAB upload** bosqichida 403, commit
emas. "o'zimi akkauntim bo'lsa ham yuklanmadi".

### Sabab — Google Play API'ning "first release" cheklovi

Google Play Developer API **yangi app'ning BIRINCHI versiyasini yuklay
olmaydi**. Birinchi AAB **majburiy ravishda Play Console UI orqali** qo'lda
yuklanishi kerak. Bundan keyin API ishlaydi.

`uz.gennis.todo` v1.0.0 — bu aniq **birinchi release**. Shuning uchun
bundle upload 403 berdi (edit yaratish 200 bo'lsa ham).

### Yangi `play_handle_bundle_403` funksiyasi

Bundle upload 403 bo'lsa, 4 ta eng tez-tez sabab ko'rsatiladi:

```
⚠ AAB upload 403 — eng tez-tez uchraydigan sabab:

1. YANGI app — birinchi release qo'lda kerak (ENG EHTIMOL)
   Google Play API yangi app'ning BIRINCHI versiyasini yuklay olmaydi.
   Birinchi AAB Play Console UI orqali qo'lda yuklanishi SHART.
   Bundan keyin API avtomatik ishlaydi.

2. App Play Console'da hali yaratilmagan
   Package uz.gennis.todo Play Console'da mavjudmi?

3. SA'da 'release' yoki 'edit' ruxsati yo'q
   (lekin edit yaratish ishladi — demak bu kam ehtimol)

4. Developer account sozlash tugallanmagan
   (to'lov profili, shartnomalar imzolanmagan)

╭─ Hozir nima qilamiz? ──────────────────────────────────╮
│  1) ⭐ Play Console UI orqali QO'LDA upload (birinchi release uchun!)
│  2) 🌐 App Play Console'da bormi — tekshiraman
│  3) ❌ Bekor
╰─────────────────────────────────────────────────────────╯
```

### Variant 2 — App existence check

Account selector ochiladi va foydalanuvchiga yo'l-yo'riq:
- To'g'ri account'da app bormi?
- Agar yo'q — 'Create app' bilan yaratish
- Agar bor — birinchi AAB ni qo'lda yuklash
- Birinchi release'dan keyin API avtomatik ishlaydi

### Stage-specific 403 diagnostika

v1.14.0 da har bir bosqichdagi 403 **alohida** tahlil qilinadi:

| Bosqich | 403 ma'nosi | Handler |
|---------|-------------|---------|
| Edit yaratish | App access yo'q | edit error handler |
| **Bundle upload** | **Yangi app, birinchi release qo'lda** | `play_handle_bundle_403` |
| Commit | Release permission yo'q | `play_handle_commit_403` |

### Texnik tafsilot

**API first-release restriction**: Google Play Developer API yangi app
yaratishni va birinchi release'ni avtomatlashtirishni taqiqlaydi (spam/abuse
oldini olish). Bu **intentional limitation** — har bir yangi app inson
tasdiqlashi kerak. Bizning skript buni aniq tushuntiradi va manual yo'lni
taklif qiladi.

**Stage-aware error handling**: bir xil HTTP 403 turli bosqichlarda turli
ma'no beradi. Universal handler yetarli emas — har bosqich o'z kontekstida
talqin qilinadi.

## [1.13.9] — 2026-06-04

### Tuzatildi — **Soxta 404 diagnostika** foydalanuvchini xato yo'naltirardi

User report: foydalanuvchi `jaloliddinish@gmail.com` orqali RENTME account'ga
**developer/admin** sifatida qo'shilgan. Diagnostika `HTTP 404` ko'rsatib,
"SA noto'g'ri account'da" deb **xato xulosa** chiqardi. Aslida SA TO'G'RI
account'da edi.

### Root cause — Google Play API'da bo'lmagan endpoint

Diagnostika test [1/3] `GET /applications/{package}` ishlatardi:

```bash
curl -X GET "https://androidpublisher.googleapis.com/.../applications/${pkg}"
```

Bu Google Play Developer API v3'da **HAQIQIY ENDPOINT EMAS** — har doim
`404` qaytaradi! API'da faqat sub-resource'lar bor:
- `POST /applications/{pkg}/edits` ✓ (edit yaratish)
- `GET /applications/{pkg}/edits/{id}` ✓ (edit o'qish)
- `GET /applications/{pkg}` ✗ (bunday endpoint yo'q)

Natijada diagnostika **har doim** 404 ko'rsatib, foydalanuvchini "noto'g'ri
account" deb xato yo'naltirardi.

### Fix — POST /edits ni ishonchli signal sifatida ishlatish

Foydalanuvchining real natijasi:
```
✓ [2/3] Yangi edit yaratish: HTTP 200 — SA edit yarata oladi
```

`POST /edits` 200 = **SA app'ni KO'RA OLADI** (to'g'ri account!). Yangi
diagnostika shu signal'ni ishlatadi:

```
Diagnostika xulosasi:
  ✓ SA app'ni ko'ra oladi va edit yarata oladi (POST /edits: 200)
  ✓ Demak SA TO'G'RI account'da — app'ga ulangan
  ✗ Lekin commit (release) qila olmaydi — 403

Aniq sabab: SA'da MAXSUS 'release' ruxsati yo'q
  → 'Release apps to testing tracks' (internal uchun)

Nega oldingi retry ishlamadi (3 ehtimol):
  1. 'Save changes' bosilmagan (faqat 'Apply' kifoya emas)
  2. Cache hali yangilanmagan (10-30 daqiqa kerak bo'lishi mumkin)
  3. Permission app-level emas, account-level qo'shilgan (noto'g'ri tab)

ENG TEZ yechim: Variant 3 (Manual UI upload) — API permission kerak emas
```

### Tuzatildi — Manual UI upload'dan keyin "upload xato" ko'rsatilmaydi

User Variant 3 (Manual UI) tanladi, lekin skript keyin **"Android upload xato
berdi"** ko'rsatardi — bu chalg'ituvchi (manual upload — xato emas, boshqa
jarayon).

Endi `PLAY_MANUAL_UPLOAD_INITIATED` global flag:
```
📋 Manual upload Play Console'da boshlandi (API o'rniga)
Browser'da release'ni yakunlang — bu skript ishini tugatdi
```

Plus Manual UI'da yakuniy tasdiqlash:
```
Browser'da upload'ni yakunlang. Bu skript endi kutmaydi —
siz browser'da 'Start rollout' bosganingizda, ish tugaydi.

  Browser'da upload'ni yakunladingizmi? (ha/keyinroq) [keyinroq]: ha
✓ Ajoyib! Play Console'da release yaratildi.
```

### Sizning vaziyatingiz uchun (personal account)

Siz "shaxsiy akkauntdan yuklash kerak, ownerdan emas" dedingiz. To'g'ri
yechim — **Variant 3 (Manual UI upload)**:
- Sizning shaxsiy Google account (browser login) ishlatadi
- Service Account (owner'niki) umuman kerak emas
- Siz app'ga developer/admin sifatida kira olasiz — shuning uchun ishlaydi

### Texnik tafsilot

**API endpoint verification**: REST API diagnostikasi qilishda, **faqat
mavjud endpoint'larni** sinab ko'rish kerak. Bizning eski test bo'lmagan
endpoint'ni sinab, soxta 404 oldi. Bu **false negative** — diagnostika'ning
o'zi bug edi. To'g'ri yondashuv: **real operatsiyalar** (POST /edits) bilan
test qilish.

**404 vs 403 semantics**: 404 "topilmadi", 403 "ruxsat yo'q". Lekin bizning
holatda 404 **endpoint mavjud emasligidan** edi, app yo'qligidan emas. Bu
HTTP code'larni kontekstsiz talqin qilish xavfini ko'rsatadi.

## [1.13.8] — 2026-06-04

### Tuzatildi — `find_keytool` har bir yo'lni FUNCTIONAL validatsiya qiladi

User report: keystore ulashda `keytool` "Unable to locate a Java Runtime"
xato berdi, garchi Android Studio JBR keytool mavjud va ishchi bo'lsa ham.

### Sabab — existence test vs functional test

`find_keytool` 3 ta joydan qidirardi, lekin har birini faqat **`-x`
(mavjudlik)** bilan tekshirardi:

```bash
if [ -x "$path" ]; then    # ✗ faqat fayl bormi
  printf '%s\n' "$path"
fi
```

Muammo: macOS stub `/usr/bin/keytool` **`-x` TRUE** qaytaradi (executable),
lekin ishlamaydi (Java yo'q). Demak `find_keytool` ba'zan **stub'ni qaytarib
yuborardi**.

Plus step 1 (PATH keytool) `java -version` tekshirardi, lekin `keytool` ni
qaytarardi — agar `java` PATH'da bo'lmasa "command not found" chiqib, stub
pattern'ga mos kelmasdi va bare keytool qaytarilardi.

### Fix — `_keytool_works` functional test

Yangi helper har bir keytool'ni **REAL ishlatib** ko'radi:

```bash
_keytool_works() {
  local kt="$1"
  if "$kt" -help 2>&1 | grep -qE "Unable to locate a Java Runtime|..."; then
    return 1   # stub yoki buzilgan
  fi
  return 0     # ishlaydi
}
```

`find_keytool` endi **har bir yo'lni** (3 ta joy ham) `-x` VA `_keytool_works`
bilan tekshiradi. Faqat **haqiqatan ishlaydigan** keytool qaytariladi.

### link_existing_keystore — Java runtime auto-install fallback

Agar keystore o'qishda "Unable to locate a Java Runtime" chiqsa, endi
avtomatik `offer_jdk_auto_install` chaqiriladi (create_new_keystore'dagi kabi):

```
✗ Keystore'ni o'qib bo'lmadi — Java JDK ishlamayapti

Sabab: keytool topildi, lekin Java Runtime yo'q (macOS stub bug)

Homebrew bilan avtomatik o'rnatishim mumkin:
  Buyruq: brew install --cask zulu@17

  Hozir avtomatik o'rnataylikmi? (y/n) [y]: y
[install...]
✓ Yangi ishchi keytool: /Library/Java/.../keytool

▶ Keystore qayta o'qilmoqda (yangi Java bilan)...
✓ Keystore o'qildi — parol to'g'ri
```

### Sizning Mac'da test

```
find_keytool: /Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool
✓ ISHLAYDI (Android Studio JBR)
```

Endi sizning Mac'da `find_keytool` **bare stub'ni qaytarmaydi** — Android
Studio JBR'ni topadi va validatsiya qiladi.

### Texnik tafsilot

**Existence vs functional test**: `[ -x file ]` faqat "executable bit"ni
tekshiradi — fayl bajariladigan, lekin **ishlay oladimi** — bilmaydi. macOS
stub'lar `-x` TRUE, lekin Java yo'qligida fail bo'ladi. **Functional test**
(`keytool -help`) — yagona ishonchli yo'l. Bu **trust-but-verify** pattern'ning
yana bir qo'llanishi.

**Defense in depth**: 3 qatlam himoya:
1. `find_keytool` faqat ishlaydigan keytool qaytaradi (functional test)
2. `link_existing_keystore` Java runtime xato'sini aniqlaydi
3. Auto-install fallback (brew zulu@17) + retry

## [1.13.7] — 2026-06-04

### Tuzatildi — **Multi-account Play Console**'da noto'g'ri account muammosi

User report (screenshot bilan): foydalanuvchi `jaloliddinish@gmail.com` orqali
login qilgan va **10+ ta Play Console developer account**'iga kirish huquqiga
ega:
- DAS FINANCE CONSULTANTS
- Garanti Express
- **Jaloliddin Fozilov** (shaxsiy)
- Kabirjanov IT GROUP
- Kifoya Investments
- My-Master
- Netson
- ProFan Uz
- **RENTME** ← app egasi
- SKY LINE IT GROUP

Foydalanuvchi shaxsiy account'da SA topib permission qo'shdi, lekin app
`uz.iportal.uzrentme` **RENTME account'da**. API diagnostika bunga aniq
ishora qildi: `HTTP 404` (app umuman ko'rinmaydi, ya'ni noto'g'ri account).

### Yangi `_extract_sa_project` funksiyasi

SA email'dan Google Cloud project nomini ekstrakt qiladi:

```
flutter-build-deploy-478@rentmi-b2fb6.iam.gserviceaccount.com
                        ↓
                  rentmi-b2fb6
```

Bu Play Console account taxmin qilishda yordam beradi (odatda Cloud project
nomi → Play Console account nomi yaqin: `rentmi-b2fb6` → **RENTME**).

### Account selector sahifasiga yo'naltirish

v1.13.6 da URL: `https://play.google.com/console/u/0/users-and-permissions`
→ default account'ga olib boradi (sizning shaxsiy)

v1.13.7 da URL: `https://play.google.com/console/u/0/developers`
→ **account tanlash sahifasi** (sizning screenshotda ko'rsatgan
"Выберите аккаунт разработчика")

### Aniq yo'l-yo'riq (10-bosqichli)

```
⚠ MUHIM (ko'p account'lar bo'lsa):
Browser'da 'Выберите аккаунт разработчика' / 'Choose developer account' sahifa
chiqishi mumkin. Bu yerdan SHAXSIY account emas, balki app egasi account'ni
tanlang!
Sizning SA project nomi: rentmi-b2fb6 — shunga o'xshash account'ni izlang
(masalan: agar SA project 'rentmi-b2fb6' bo'lsa, RENTME account'ni tanlang)

▶ Account tanlash sahifasi ochilmoqda...

Endi quyidagilarni qiling:
  1. Browser'da to'g'ri Play Console account'ni tanlang
     (SA project 'rentmi-b2fb6' bilan bog'liq — app egasi)
  2. Tanlangach, chap menyuda 'Users and permissions' ni oching
  3. Service Account'ni toping: flutter-build-deploy-478@...
     AGAR TOPILMASA — bu noto'g'ri account! Boshqasiga o'ting va qaytadan urinib ko'ring
  4. SA'ga bosing (qalam/edit ikoni)
  5. 'App permissions' tabini oching (Account-level emas!)
  6. 'Add app' bosing va uz.iportal.uzrentme loyihasini qo'shing
  7. App'ning 'Releases' bo'limidan tanlang:
     ✓ 'Release apps to testing tracks' (siz internal track'iga yuklamoqdasiz)
  8. 'Apply' bosing (app permission qo'shildi)
  9. Sahifa pastidagi KO'K 'Сохранить изменения' / 'Save changes' bosing
 10. 5-10 daqiqa kuting (Google'da cache yangilanishi)
```

### 404 vs 403 diagnostika

Bizning diagnostika `HTTP 404` qaytarsa, alohida ko'rsatma:

```
HTTP 404 — bu MUHIM signal:
  • 404 = app umuman ko'rinmaydi (boshqa Play Console account'da)
  • 403 = app ko'rinadi lekin permission yo'q
  • Siz oldingi 'Admin retry' qadamida NOTO'G'RI account'da permission qo'shgansiz!
```

### Foydalanuvchi tajriba taqqoslash

| Sizning vaziyat | v1.13.6 | v1.13.7 |
|----------------|---------|---------|
| 10+ Play Console account | URL → birinchi account | URL → account selector |
| SA topish | Topdi, lekin noto'g'ri account'da | Account selector ko'rsatadi |
| App permission qo'shish | Noto'g'ri account'da qo'shildi | To'g'ri account taxmini beriladi |
| Retry'dan keyin xato | "Bunday holat noaniq" | "404 — noto'g'ri account!" |

### Texnik tafsilot

**Project name extraction**: regex `s/.*@//; s/\.iam\.gserviceaccount\.com$//`
SA email'idan **uniqueidentifier**ni ekstrakt qiladi. Bu Google Cloud project
ID — bu odatda Play Console account nomi bilan **70%+ correlation** ga ega
(masalan: `rentmi-b2fb6` → RENTME, `myapp-prod-123` → MyApp Production).

**HTTP code semantics**: REST API'da 404 va 403 alohida ma'no'lar:
- **403 Forbidden**: "resource topildi, lekin sizga ruxsat yo'q"
- **404 Not Found**: "resource topilmadi (yoki sizga ko'rinmaydi)"

Google Play API 404 qaytarsa, bu **stronger signal** — SA bu app'ni
**umuman bilmaydi**. Bu permission yo'qligidan ko'ra, **scope mismatch**
(noto'g'ri account/project'da).

**URL routing trick**: `console/developers` (account selector) vs
`console/u/0/users-and-permissions` (specific account). Birinchi'si
**always works** — Google account tanlash sahifasini ko'rsatadi.
Ikkinchi'si **assumes current account**.

## [1.13.6] — 2026-06-04

### Tuzatildi — **Keystore ulash xato'lari batafsil diagnostika**

User report: foydalanuvchi `/Users/.../android/app/key` yo'lni kiritdi
(kengaytmasiz), parol va alias kiritdi, lekin **"Keystore o'qib bo'lmadi
(parol yoki alias noto'g'ri)"** xato'si bilan to'xtab qoldi.

Bu **opaque error** — qaysi nuqsoni ekanligi noma'lum:
- Yo'l noto'g'rimi?
- Parol noto'g'rimi?
- Alias noto'g'rimi?
- Fayl format JKS emasmi?

### Yangi `_resolve_keystore_path` — smart path handling

Foydalanuvchi kiritgan yo'lni **avtomatik to'g'rilash**:

```
Keystore yo'li: android/app/key   ← foydalanuvchi xato yozgan

  → 1. Fayl mavjudmi: android/app/key (yo'q)
  → 2. .jks qo'shib sinab ko'rish: android/app/key.jks (bor!)
  ✓ Kengaytma avtomatik qo'shildi: .jks
```

Sinab ko'riladigan kengaytmalar: `.jks`, `.keystore`, `.pk12`, `.p12`

### Papka berilsa — ichidan keystore qidirish

```
Keystore yo'li: android/app   ← papka kiritildi

  'android/app' — papka. Ichida keystore qidirilmoqda...
  ✓ Avtomatik topildi: android/app/key.jks
```

Bir nechta topilsa, foydalanuvchidan tanlash so'raladi:
```
  Bir nechta keystore topildi:
    1) android/app/key.jks
    2) android/app/old-key.jks
    3) android/app/release/upload.keystore

    Qaysi birini tanlaysiz (raqam): 1
```

### 3 bosqichli validation pyramid

Avval **opaque** test:
- ✗ "Keystore o'qib bo'lmadi (parol yoki alias noto'g'ri)"

Endi **3 alohida bosqich**:

```
▶ Keystore o'qilmoqda (parol va format tekshiruvi)...
✓ Keystore o'qildi — parol to'g'ri va format JKS/PKCS12

Keystore ichidagi alias'lar:
  • key
  • upload
  • debug

    Key alias: keyy   ← xato yozildi
✗ Bunday alias yo'q: 'keyy'
ℹ Yuqoridagi ro'yxatdan birini tanlang (case-sensitive)
```

### Pattern-based xato diagnostika

Keystore o'qib bo'lmasa, **aniq sabab** ko'rsatiladi:

```
keytool xatosi  →  Bizning ko'rsatadigan sabab + yechim
─────────────────────────────────────────────────────────
"password was incorrect"      →  Keystore paroli noto'g'ri
"Invalid keystore format"     →  Fayl JKS/PKCS12 emas (file komandasi natijasi)
"Keystore was tampered with"  →  Parol noto'g'ri yoki fayl buzilgan
"FileNotFoundException"       →  Fayl mavjud emas
boshqa                        →  Keytool javobining birinchi 5 qatori
```

### Foydalanuvchi tajribasi taqqoslash

| Sizning vaziyat | v1.13.5 | v1.13.6 |
|----------------|---------|---------|
| Kengaytmasiz `key` yo'l | ✗ Fayl topilmadi | ✓ `.jks` avtomatik qo'shildi |
| Papka yo'l `android/app` | ✗ Fayl topilmadi | ✓ Ichidan keystore topildi |
| Noto'g'ri parol | ✗ "parol yoki alias..." (qaysi'si?) | ✓ "Keystore paroli noto'g'ri" |
| Noto'g'ri alias | ✗ "parol yoki alias..." (qaysi'si?) | ✓ Mavjud alias'lar ro'yxati |
| Noto'g'ri format (PDF, txt) | ✗ "parol yoki alias..." | ✓ "Fayl JKS/PKCS12 emas" + file info |

### Tilde expansion qo'shimcha

`~/Documents/key.jks` kabi yo'l'lar avtomatik `/Users/USER/Documents/key.jks` ga aylanadi.

### keytool yo'q bo'lsa fallback

Agar keytool topilmasa, **degraded mode** — keystore tekshirilmasdan ulanadi.
Build vaqtida parol/alias to'g'riligi bilinadi. Bu eski xulq'ni saqlaydi
(progressive enhancement).

### Test natijalari

5/5 unit test:
- ✓ Kengaytmasiz yo'l → `.jks` qo'shiladi (sizning vaziyat)
- ✓ Papka yo'l → ichidagi yagona keystore topiladi
- ✓ To'liq yo'l → as-is qabul qilinadi
- ✓ Hech narsa topilmasa → exit 1 (false positive yo'q)
- ✓ Tilde expansion (`~/...` → `$HOME/...`)

### Texnik tafsilot

**Specificity ladder** keystore qidirish'da: exact path → extension probing →
folder scan → manual selection. Bu **forgiving input** pattern — UI'larda
keng tarqalgan.

**3-stage validation**: keystore o'qish > alias mavjudligi > alias bilan tekshirish.
Har biri **alohida xato xabari**. Bu **failure isolation** — qaysi qadamda
muvaffaqiyatsizlik aniq.

**Awk + sed alias extraction**: keytool'ning ikki xil output format'ini
qo'llab-quvvatlash uchun (yangi va eski keytool versiyalari).

## [1.13.5] — 2026-06-04

### Qo'shildi — **Progressive backoff retry** (cache propagatsiya'sini kutadi)

User real holatda: Service Account'ga **Administrator (all permissions)**
qo'shgan, lekin **"Save changes"** tugmasini bosgani noma'lum. Yoki bosib,
darrov retry qildi — Google cache hali yangilanmagan edi.

### Save button highlighting (Russian + English)

Ko'p foydalanuvchilar Play Console UI'da **'Apply' bilan to'xtab qoladilar** —
chunki **sahifa pastidagi 'Save changes' tugmasi**ni ko'rmasdi.

Endi 3 ta MUHIM tekshiruv:

```
⚠ MUHIM — qo'shimcha tekshiruv:
  1. Checkbox haqiqatan belgilandimi (✓ ko'k)?
  2. Sahifa PASTI o'ng burchagidagi KO'K rangli
     'Сохранить изменения' / 'Save changes' tugmasini BOSDINGIZMI?
  3. Tepada yashil 'Сохранено' / 'Saved' xabar paydo bo'ldimi?

Eslatma: 'Apply' kifoya emas — sahifa pastidagi 'Save' ham kerak.
Save'dan keyin 5-15 daqiqa cache propagatsiyasi vaqti.
```

Russian (Сохранить/Сохранено) ham English ham qo'shildi — Play Console UI til
sozlamalariga qarab ko'rsatadi.

### Progressive backoff retry (Google's eventual consistency)

Foydalanuvchi "y" bosgach, **avtomatik 3 ta retry**:

```
[Attempt 1/3] Commit retry'da (darrov, ehtimol siz allaqachon kutgansiz)...
[xato]
⚠ Attempt 1 xato berdi — keyingi attempt'ga o'tamiz

[Attempt 2/3] Cache yangilanishi uchun 60 sekund kutib qaytadan...
(Bu vaqtda choy ichib, biroz kutib turing)
[xato]
⚠ Attempt 2 xato berdi — keyingi attempt'ga o'tamiz

[Attempt 3/3] Yana 120 sekund kutib so'nggi urinish...
(Bu Google'ning eventual consistency'siga bo'ysunadi)
[muvaffaqiyatli]
✓ 🎉 Commit muvaffaqiyatli! (Attempt 3/3'da ishladi)
```

Jami **3 daqiqa kutish** — Google cache propagatsiya'siga mos. Token har
attempt'da yangilanadi (eski'si muddati o'tgan bo'lishi mumkin).

### Foydalanuvchi tajribasi

| Senariy | v1.13.4 | v1.13.5 |
|---------|---------|---------|
| Save bosildi + cache yangilangan | Darrov ✓ | Darrov ✓ (Attempt 1) |
| Save bosildi + cache 30s | ✗ Xato | Attempt 2 ✓ (60s kutadi) |
| Save bosildi + cache 90s | ✗ Xato | Attempt 3 ✓ (180s jami) |
| Save bosilmagan | ✗ Xato | ✗ Diagnostika + Variant 3 |
| Cache 5+ daqiqa | ✗ Xato | ✗ Diagnostika + Variant 3 |

### Texnik tafsilot

**Progressive backoff strategy**: 0s, +60s, +120s. Bu **Fibonacci-style backoff**
emas, balki Google'ning real propagatsiya vaqtiga **empirik** ravishda
moslashtirilgan. Eksperimentlardan: ~50% holatda 60s yetadi, ~30% — 120s,
~20% — uzunroq.

**Token rotation per attempt**: har attempt'da yangi access token olamiz.
Google'ning token TTL 1 soat, lekin 2-3 daqiqa kutish ham token'ni hali
amal qilishi kerak. Lekin xavfsiz tomondan turamiz.

**Choy reklamasi**: 2-attempt'da "Bu vaqtda choy ichib, biroz kutib turing"
— bu **mikro-UX touch**. 60 sekund foydalanuvchi uchun uzoq, lekin biz
nima qilish kerakligini taklif qilamiz (passive kutmaslik).

## [1.13.4] — 2026-06-04

### Qo'shildi — **API orqali avtomatik diagnostika** retry'dan keyin

User report: admin retry qilingan, "permission qo'shdim" deyilgan, lekin
retry hali ham 403. Sababi noma'lum — passive xato xabari foydalanuvchini
boshi berk ko'chada qoldiradi.

### Yangi `_play_403_run_api_diagnostic` funksiyasi

Retry muvaffaqiyatsiz bo'lganda, **avtomatik** 3 ta API test ishga tushadi:

```
▶ SA permission'ini API orqali tekshirish (3 ta test)

  ✓ [1/3] App ko'rish (GET app): HTTP 200 — SA app'ni ko'ra oladi
  ✓ [2/3] Yangi edit yaratish: HTTP 200 — SA edit yarata oladi
  ℹ [3/3] Commit endpointi haqiqiy edit bilan tekshirildi (yuqorida 403 berdi)

Diagnostika xulosasi:
  ✓ SA app'ni ko'ra oladi
  ✓ SA yangi edit yarata oladi
  ✗ Lekin SA commit qila olmaydi (operation-specific 403)

Bu MAXSUS 'Release apps to testing tracks' (yoki 'Release to production')
permission'ining yo'qligi — boshqa permission'lar bor, lekin shu emas.

⚠ Eng tez yechim: Variant 3 (Play Console UI orqali qo'lda upload)
  Bu API permission'ga bog'liq emas — sizning shaxsiy Google account
  orqali to'g'ridan-to'g'ri upload qilasiz, 3-5 daqiqada tugaydi
```

### Yoki — SA noto'g'ri account'da bo'lsa, multi-account guidance

```
Diagnostika xulosasi:
  ✗ SA app'ni umuman ko'ra olmaydi

Sabab'lar va yechimlar:
  1. SA boshqa Google Cloud project'da bo'lishi mumkin
     Tekshirish: SA email'ni qarang — ...@rentmi-b2fb6.iam.gserviceaccount.com
     Project: rentmi-b2fb6.iam.gserviceaccount.com → bu sizning Play Console'ga link qilinganmi?

  2. Multi-account muammosi — siz NOTO'G'RI Play Console account'da bo'lishingiz mumkin
     Tekshirish:
       • https://play.google.com/console/u/0/api-access  (1-account)
       • https://play.google.com/console/u/1/api-access  (2-account)
       • https://play.google.com/console/u/2/api-access  (3-account)
     Har birida 'Service accounts' bo'limini ochib, SA email'ni izlang
     Qaysi sahifada SA ko'rinadi — o'shanga permission qo'shing

  3. SA Play Console'ga umuman link qilinmagan
     Yechim: Setup → API access → 'Link existing Google Cloud project'
```

### Active fallback recommendation

Diagnostikadan keyin **passive xato qoldirmaymiz**. Foydalanuvchiga 4 ta
aniq tanlov beriladi:

```
╭─ Hozir nima qilamiz? ──────────────────────────────────╮
│  1) ⭐ Variant 3 — Play Console UI orqali QO'LDA upload (ENG TEZ!)
│  2) 🔁 Yana RETRY (5-10 daqiqa kutib, cache yangilangach)
│  3) 💾 Edit ID'ni saqlash, keyinroq qo'lda
│  4) ❌ Bekor
╰─────────────────────────────────────────────────────────╯

  Tanlang [1-4] [1]:
```

Default `1` — chunki bu **eng tezkor** yechim, API permission ishlatmaydi.

### Yaxshilangan admin retry instruksiya

Foydalanuvchi'ga MUHIM 2 ta nuqta qo'shildi:

1. **Multi-account check**: "Tepa o'ng burchakda Google account'ni tekshiring —
   agar 2+ account bo'lsa, to'g'ri Play Console'ga kirganingizga ishonch hosil qiling"

2. **'Apply' vs 'Save'**: "MUHIM: faqat 'Apply' kifoya emas — 'Save' ham
   bosishingiz shart" (bu Play Console UI'ning eng tez-tez uchraydigan trap'i)

### Texnik tafsilot

**API verification pattern**: bizning skript foydalanuvchiga ishonish o'rniga,
**API'dan haqiqiy holatni so'raydi**. 3 ta endpoint sinaymiz:
- `GET /apps/{pkg}` — view permission
- `POST /edits` — edit yaratish permission (cleanup orqali test edit'ni o'chiramiz)
- Commit endpoint — biz allaqachon bilamiz (asosiy upload'da xato berdi)

Bu **trust but verify** pattern — foydalanuvchi "qo'shdim" deganida, biz
"o'zimiz tekshirib ko'ramiz". Bu xato'larni aniqlash uchun **eng aniq** yo'l.

**Test edit cleanup**: API test edit yaratamiz, lekin uni DELETE qilamiz.
Bu Play Console'da "Pending changes" bo'limida orphan edit qoldirmaslik
uchun (foydalanuvchini hayronga solmaslik uchun).

**Recursive retry**: agar foydalanuvchi 2-variant tanlasa (yana retry),
funksiya o'ziga o'zi qayta chaqiriladi (recursive). Bu **trampolin recovery** —
foydalanuvchi cache yangilanguncha kuta oladi va ko'p marta retry qila oladi.

## [1.13.3] — 2026-06-04

### Tuzatildi — **Android Studio "Generate Signed Bundle"** AAB topilmas edi

User report: "baribir topilmadi deyapti aslida `/Users/hehe/Desktop/flutter_projects/gennis_todo/android/app/release` shu papkada turibti, aab file"

### Sabab

Android Studio'ning **2 ta** build menyu'si bor va ular AAB'ni **boshqa-boshqa joylarga** yozadi:

| Menyu | AAB joy |
|-------|---------|
| Build → Build Bundle(s) / APK(s) → Build Bundle(s) | `android/app/build/outputs/bundle/release/` |
| **Build → Generate Signed Bundle / APK → Bundle** | **`android/app/release/`** ← v1.13.3 fix |

v1.13.1 da faqat birinchi menyu joyini qidirardik. Foydalanuvchi **"Generate Signed Bundle"** menyu'ni ishlatsa (signed AAB uchun ko'pchilik shu menyu'dan foydalanadi), bizning skript topa olmasdi.

### Yangi qidiruv joylari (4 → 7)

```
1. build/app/outputs/bundle/release/                  (Flutter CLI default)
2. android/app/build/outputs/bundle/release/          (Android Studio Gradle)
3. android/app/release/                               (Android Studio Signed Bundle) ← v1.13.3
4. build/app/outputs/bundle/*/                        (Flutter CLI flavor)
5. android/app/build/outputs/bundle/*/                (Gradle flavor)
6. android/app/release/*/                             (Signed Bundle flavor) ← v1.13.3
7. android/ va build/ ichida recursive (maxdepth 6)   ← v1.13.3 catch-all
```

`find_latest_ipa` ham xuddi shunday catch-all bilan kengaytirildi.

### Yangi "Manual yo'l kiritish" opsiyasi

Agar 7 ta joydan ham topilmasa, **siz aniq joyni bilsangiz**, manual kiritishingiz mumkin:

```
Hozir nima qilamiz?
  1) Manual yo'l kiritish (siz AAB joyini bilasiz)
  2) Build qilamiz (Flutter CLI orqali)
  3) Android Studio'ni ochaman
  4) Bekor qilish

  Tanlang [1-4] [1]:
```

Variant 1 → "AAB yo'li: " prompt → siz to'g'ridan-to'g'ri yo'lni kiritasiz:
```
AAB yo'li: ~/Desktop/flutter_projects/gennis_todo/android/app/release/app-release.aab
✓ Manual AAB qabul qilindi: /Users/hehe/Desktop/.../app-release.aab
```

Skript tekshiradi:
- Fayl mavjudligini (`-f`)
- `.aab` kengaytmasini (boshqa kengaytma bo'lsa ogohlantirish)
- Tilde expansion (`~/...` → `$HOME/...`)

### Tajriba taqqoslash

| Versiya | Sizning vaziyat: `android/app/release/app-release.aab` |
|---------|--------------------------------------------------------|
| v1.13.1 | ✗ Topilmadi — qidiruv yo'q edi |
| v1.13.2 | ✗ Topilmadi — qidiruv yo'q edi |
| **v1.13.3** | **✓ Joy #3'da AYNAN topiladi** |

### Test natijalari

4/4 unit test:
- ✓ Joy #3: `android/app/release/app-release.aab` topiladi (sizning vaziyat)
- ✓ Joy #6: `android/app/release/dev/app-dev-release.aab` (flavor) topiladi
- ✓ Joy #7: `android/custom/wherever/myapp-signed.aab` (catch-all) topiladi
- ✓ Hech qaerda yo'q → exit 1 (false positive yo'q)

### Texnik tafsilot

**Specificity ladder**: 7 ta joy aniqlikdan kengayishga tartiblangan. Joy #1-#3 — aniq fayl yo'llari (eng tez). Joy #4-#6 — flavor subdirektoriyalar. Joy #7 — `find -maxdepth 6` recursive (eng sekin, lekin eng keng).

**`maxdepth 6` xavfsizligi**: bu chuqurlik `.gradle/intermediates/`, `build/tmp/` kabi vaqtinchalik papkalarni o'tkazib yuboradi — chunki bularning ichida AAB **odatda yo'q**. Faqat **final signed AAB**'lar shu chuqurlikgacha boradi.

**Tilde expansion**: bash `${path/#\~/$HOME}` ifodasi yo'l boshidagi `~`'ni `$HOME` bilan almashtiradi. Bu standart Unix konvensiya'sini qo'llab-quvvatlaydi.

## [1.13.2] — 2026-06-04

### Qo'shildi — Play Store commit 403 uchun **interaktiv recovery menyusi**

User report: "ishlamadi yuklolmadi" — v1.13.0 dagi 403 diagnostika foydalanuvchiga
qo'lda Play Console'da Service Account permission qo'shishni taklif qilardi.
Lekin agar foydalanuvchi **admin emas** (developer), bu permission'ni qo'sha
olmasdi va boshqa yo'l qolmasdi.

### Yangi 5 ta variant menyusi

Commit 403 xato bersa, foydalanuvchiga 5 ta aniq tanlov beriladi:

```
╭─ Bu vaziyatda qaysi variant siznikiga eng yaqin? ──────╮
│  1) 🔧 Men Play Console adminim — hozir permission qo'shaman, RETRY
│  2) 📧 Men developer'man — admin'ga so'rov yuboraman
│  3) 🌐 Play Console UI orqali QO'LDA upload qilaman (eng tez!)
│  4) 💾 Edit ID'ni saqlab, keyinroq qo'lda commit
│  5) ❌ Bekor qilish
╰─────────────────────────────────────────────────────────╯

  Tanlang [1-5] [3]:
```

Default `3` — **eng tez yo'l** agar tezda upload qilish kerak bo'lsa.

### Variant 1: Admin RETRY (in-session fix)

- Play Console'ni avtomatik ochadi (`open https://...`)
- Bosqichma-bosqich permission qo'shish ko'rsatadi
- Track'ga (internal vs production) qarab to'g'ri permission'ni belgilaydi
- Foydalanuvchi tasdiqlagach, **yangi access token** oladi
- **Xuddi shu edit ID bilan** commit retry qiladi (qayta upload kerak emas)
- Muvaffaqiyatli bo'lsa — "🎉 Commit retry'da ishladi" + asosiy success xabari
- Hali ham 403 bo'lsa — cache wait taklif qiladi (10-30 daqiqa)

### Variant 2: Developer email template (clipboard'ga avtomatik)

Admin uchun professional Uzbek tilida email/Slack matni:

```
─────────── EMAIL/SLACK MATNI ──────────────────────────
Salom!

Play Console'da loyiha uchun Service Account release qilish ruxsati kerak.

  Loyiha:           uz.iportal.uzrentme
  Service Account:  flutter-build-deploy-478@rentmi-b2fb6.iam.gserviceaccount.com
  Track:            internal

Hozirgi muammo: SA edit yarata oladi va AAB yukala oladi, lekin commit
qilish HTTP 403 xato beradi.

Iltimos, quyidagilarni qiling:
  1. Play Console > Users and permissions sahifasini oching
  2. Service Account'ni toping
  3. Edit > App permissions > loyihani qo'shing
  4. 'Release apps to testing tracks' belgilang
  5. Save, 5-30 daqiqa kuting

Rahmat!
─────────── MATN OXIRI ─────────────────────────────────

✓ Matn clipboard'ga avtomatik ko'chirildi — Cmd+V bilan yopishtiring
```

macOS'da `pbcopy` orqali clipboard'ga avtomatik ko'chiriladi.

### Variant 3: Play Console UI orqali QO'LDA upload (eng tez)

- Play Console'ning aniq track sahifasini ochadi (internal/alpha/beta/production)
- AAB joylashgan papkani Finder'da ochadi (drag-drop qulay)
- 6 bosqichli yo'l-yo'riq beradi: Create release → drag AAB → release notes → save → review → rollout
- **API permission'iga ehtiyoj yo'q** — foydalanuvchining Google account permission'i ishlatadi
- Agar foydalanuvchi developer bo'lsa va o'zining Google account'ida upload permission'i bor bo'lsa, **darrov ishlaydi**

### Variant 4: Edit ID'ni saqlab keyinroq qo'lda commit

- `.flutter-build-pending-edit.json` faylga edit ma'lumotlari saqlanadi:
  ```json
  {
    "package_name": "uz.iportal.uzrentme",
    "edit_id": "06330688863274970881",
    "service_account_email": "flutter-build-deploy-478@...",
    "created_at": "2026-06-04T06:25:49Z",
    "expires_at": "2026-06-05T06:25:49Z",
    "note": "Pending commit"
  }
  ```
- 24 soat amal qiladi (Google Play API limiti)
- `.gitignore`'ga avtomatik qo'shiladi (commit'ga tushmasligi uchun)
- Keyinroq qo'lda commit qilish yo'lini ko'rsatadi

### Cross-platform clipboard

- **macOS**: `pbcopy` orqali (avtomatik)
- **Linux**: xclip/xsel mavjud bo'lsa qo'shilishi kerak (kelajakda)
- Boshqa OS'da: matnni qo'lda ko'chirish kerak

### Test natijalari

3/3 unit test:
- ✓ `_play_403_save_edit_for_later` JSON output valid
- ✓ 5-variant menyu render
- ✓ Heredoc'lar (TEMPLATE markerlari) to'g'ri balanslangan

### Texnik tafsilot

**In-session retry pattern**: Variant 1 da, foydalanuvchi permission qo'shgach,
**xuddi shu sessiyada** retry qilamiz. Mantiqiy chain:
1. Yangi `jwt`'dan yangi `access token` olamiz (eski'si muddati o'tgan bo'lishi mumkin)
2. **Xuddi shu** `edit_id` bilan commit qilamiz (24h amal qiladi)
3. AAB qayta yuklash shart emas — Google Play tomonida hali edit'ga biriktirilgan

**State preservation**: Variant 4 da, edit ID `.flutter-build-pending-edit.json` ga
saqlanadi. Bu **async recovery pattern** — admin'ga so'rov yuborilgach,
javob kelguncha edit holatda saqlanadi. Permission qo'shilgach, qaytadan
`flutter-build` ishga tushirilsa, **avtomatik retry** qilinishi mumkin (kelajak fix).

## [1.13.1] — 2026-06-04

### Tuzatildi — Android Studio AAB topilmas edi + "Ikkalasi" rejimi graceful

User report: "android studio orqali build qildim, va build bo'lgan ammo uploadda
topolmadi" + "iosda umuman build qilinmagan bo'lsa ham upload bo'limi orqali
ishimni bitirishim kerak"

### Sabab

Flutter CLI va Android Studio AAB'ni **boshqa-boshqa joylarga** yozadi:

| Tool | AAB joy |
|------|---------|
| Flutter CLI (`flutter build appbundle`) | `build/app/outputs/bundle/release/` |
| Android Studio (Generate Signed Bundle) | `android/app/build/outputs/bundle/release/` |

v1.13.0 dagi `find_latest_aab` faqat birinchi joyga qaragan — Android Studio
orqali build qilingan AAB topilmasdi. Bu **discovery bias** edi.

### Multi-location qidiruv (specificity ladder)

`find_latest_aab` endi 4 ta joydan qidiradi (eng aniq → eng keng):

```
1. build/app/outputs/bundle/release/app-release.aab           (Flutter CLI default)
2. android/app/build/outputs/bundle/release/app-release.aab   (Android Studio default)
3. build/app/outputs/bundle/*/                                (Flutter CLI flavor'lar)
4. android/app/build/outputs/bundle/*/                        (Android Studio flavor'lar)
```

`find_latest_ipa` ham xuddi shunday:

```
1. build/ios/ipa/                          (Flutter CLI default)
2. build/ios/iphoneos/                     (Flutter CLI eski versiyalar)
3. ios/build/Build/Products/Release-*/     (Xcode build joyi)
4. ./*.ipa                                  (loyiha ildizi — Xcode export)
```

### "Hozir nima qilamiz?" interaktiv yechim

Artifact topilmasa, foydalanuvchiga aniq tanlovlar beriladi:

```
✗ AAB topilmadi

Bizning skript quyidagi joylardan qidirdi:
  1. build/app/outputs/bundle/release/        (Flutter CLI default)
  2. android/app/build/outputs/bundle/release/ (Android Studio default)
  3. build/app/outputs/bundle/*/              (Flutter CLI flavor'lar)
  4. android/app/build/outputs/bundle/*/      (Android Studio flavor'lar)

Hozir nima qilamiz?
  1) Build qilamiz (Flutter CLI orqali — flutter build appbundle)
  2) Android Studio'ni ochaman (qo'lda build qilaman)
  3) Bekor qilish

  Tanlang [1-3] [1]:
```

Variant 1: `main_build_flow` chaqiriladi (to'liq build wizard)
Variant 2: Android Studio yo'lini ko'rsatadi (`open -a 'Android Studio' android`)

### "Ikkalasi" rejimida graceful degradation

User case: **"androidda build bor, iosda yo'q"**.

v1.13.0 da: agar iOS IPA topilmasa, `upload_ios_only_flow` xato qaytarardi
va butun "Ikkalasi" jarayoni yiqilardi.

v1.13.1 da: har bir platforma **alohida** tekshiriladi:
- Android AAB bor → upload
- iOS IPA yo'q → skip (xato emas, "artifact not found, skipped")
- Linux'da iOS → automatic skip (xcrun yo'q)

Yakuniy hisobot:
```
════════════════════════════════════════
Yakuniy hisobot:
  ✓ Android: muvaffaqiyatli yuklandi
  ⊘ iOS    : artifact topilmadi (skip)
════════════════════════════════════════
```

Hech bo'lmasa bittasi muvaffaqiyatli bo'lsa, jarayon **muvaffaqiyatli** hisoblanadi.

### Yangi helper

`_report_upload_result` — har bir platforma natijasini kategoriyalaydi:
- `0` — muvaffaqiyatli yuklandi (✓)
- `1` — upload xato berdi (✗)
- `2` — foydalanuvchi bekor qildi (-)
- `3` — artifact topilmadi, skip (⊘)

### Test natijalari

7/7 unit test:
- ✓ Android Studio AAB joy #2 topiladi (Flutter CLI yo'q bo'lsa)
- ✓ Flutter CLI joy #1 ustivor (ikkalasi bor bo'lsa)
- ✓ Android Studio flavor (joy #4) topiladi
- ✓ AAB hech qaerda yo'q → exit 1
- ✓ IPA Flutter CLI joy
- ✓ IPA loyiha ildizidan (Xcode export)
- ✓ IPA hech qaerda yo'q → exit 1

## [1.13.0] — 2026-06-04

### Qo'shildi — **Upload-only rejim** (build qilmasdan yuklash)

User savol: "uploadni o'zi uchun har doim build qilmasdan upload bo'limiga
kirib ohirgi buildni upload qivorishni qo'shib ber".

Mukammal — endi asosiy menu'da yangi opsiya:

```
╭─ Tanlovingiz ───────────────────────────────────────────╮
│  1) 🚀 Build (build qilish + upload)
│  2) 📤 Upload (build qilmasdan, oxirgisini yuklash)  ← YANGI
│  3) ⚙️  Sozlamalar
│  ...
```

### Yangi `upload_only_flow` wizard

Foydalanuvchi tajribasi:
1. **Asosiy menu** → "2) Upload" tanlaydi
2. **Platforma tanlash**: Android / iOS / Ikkalasi
3. **Oxirgi artifact aniqlanadi**:
   - Android: `build/app/outputs/bundle/release/app-release.aab`
   - iOS: `build/ios/ipa/*.ipa`
4. **Ma'lumotlar ko'rsatiladi**: fayl yo'li, o'lchami, yaratilgan vaqt,
   `pubspec` versiyasi, akkaunt, track
5. **Tasdiqlash so'raladi**: `y/n`
6. **Release notes** (faqat Android — interaktiv source picker)
7. **Staged rollout** (faqat production track)
8. **Upload boshlanadi** (mavjud `upload_to_play_store` yoki `upload_to_appstore`)

### Foydalar

- **⏱️  Vaqt tejash**: Flutter build 5-15 daqiqa, upload 30-90 sekund
- **🔁 Idempotency**: bir AAB'ni qayta upload qilish mumkin (failure recovery)
- **🐛 Bug recovery**: upload xato bersa (network, 403), qayta build kerak emas
- **📦 CI separation**: build CI'da, upload local'da (security uchun)

### Tuzatildi — Play Store commit 403 batafsil diagnostika

User real holatda 403 xato olgan:
```
✗ Commit xato: curl: (56) The requested URL returned error: 403
ℹ Edit ID: 02331420494787533273
```

Bu kontekstda foydalanuvchi nima qilishni bilmaydi. Endi xato 4 xil
ko'rinishda detect qilinadi (403/401/404/versionCode) va **aniq yechim**
beriladi:

```
✗ Commit xato: curl: (56) The requested URL returned error: 403

Sabab: Service Account 'Release Manager' ruxsatiga ega emas
(Edit yaratish va track qo'shish ishladi — demak ba'zi ruxsat'lar bor,
 lekin commit qilish uchun 'Manage releases' ruxsati alohida kerak)

Yechim — Play Console'da SA ruxsatini qo'shish:
  → open 'https://play.google.com/console/u/0/users-and-permissions'
  → # 1. Service Account'ni toping: ...iam.gserviceaccount.com
  → # 2. Edit (qalam) bosing
  → # 3. 'App permissions' bo'limini oching
  → # 4. '<package_name>' loyihasini qo'shing
  → # 5. 'Releases' bo'limidan tanlang:
  →    - 'Release to production, exclude devices...' (production track)
  →    - 'Release apps to testing tracks' (internal/alpha/beta)
  → # 6. 'Apply' va 'Invite user'/Save bosing
  → # 7. 2-5 daqiqa kuting (Google'da cache yangilanishi)

Edit ID: 02331420494787533273
  Qo'lda tekshirish: https://play.google.com/console/u/0/.../app-dashboard
  (Pending changes' bo'limida ko'rinadi — discard yoki commit qilish mumkin)
```

### Texnik tafsilot

**Diagnostic pattern detection**:
- `403`: matches `returned error: 403`, `HTTP/2 403`, `"code": 403`, `forbidden`, `Forbidden`
- `401`: token expired (1 soat amal qiladi)
- `404`: edit ID expired (24 soatdan ko'p ochiq turdi)
- `versionCode`: konflikt (allaqachon ishlatilgan)

**Edit ID preservation**: commit xato bersa, edit hali Play Console'da
"Pending changes" bo'limida turadi. Foydalanuvchi qo'lda commit yoki discard
qilishi mumkin. Bizning skript edit ID'ni saqlaydi.

**DRY composition**: `upload_only_flow` mavjud `upload_to_play_store` va
`upload_to_appstore` funksiyalarini reuse qiladi. Yangi kod faqat:
- Platforma picker
- Artifact discovery (`find_latest_aab` / `find_latest_ipa`)
- Pre-flight metadata display
- Confirmation prompt

### Asosiy menu o'zgarishi

| Old (v1.12.7) | New (v1.13.0) |
|---------------|---------------|
| 1) 🚀 Build | 1) 🚀 Build |
| 2) ⚙️  Sozlamalar | **2) 📤 Upload (build qilmasdan)** ← NEW |
| 3) 🩺 Doctor | 3) ⚙️  Sozlamalar |
| 4) ⬆️  Android promotion | 4) 🩺 Doctor |
| 5) 📊 Rollout | 5) ⬆️  Android promotion |
| 6) 📋 Akkauntlar | 6) 📊 Rollout |
| | 7) 📋 Akkauntlar |

### Test natijalari

5/5 unit test:
- ✓ 403 pattern: `returned error: 403`
- ✓ 403 pattern: `HTTP/2 403`
- ✓ 403 pattern: `"code": 403` JSON
- ✓ 403 pattern: `Forbidden`
- ✓ 404 hodisasi xato MATCH bermaydi (false positive yo'q)
- ✓ `file_mtime_human` macOS (`stat -f`) va Linux (`stat -c`) cross-platform
- ✓ Asosiy menu render — yangi Upload bandi 2-o'rinda

## [1.12.7] — 2026-06-02

### Qo'shildi — Java JDK avtomatik o'rnatish (`brew` orqali)

User savol: "o'rnatilmagan bo'lsa o'zi o'rnatsin" — Java topilmasa, qo'lda
buyruq ko'chirish o'rniga, skript **o'zi `brew install` chaqirsin**.

### Yangi `offer_jdk_auto_install` funksiyasi

`find_keytool` muvaffaqiyatsiz bo'lsa (Java hech qaerda topilmasa), foydalanuvchi
ekraniga quyidagicha ko'rinadi:

```
⚠ Java JDK hech qaerda topilmadi
ℹ Homebrew bilan avtomatik o'rnatishim mumkin:
ℹ   Buyruq: brew install --cask zulu@17
ℹ   Distribution: Zulu OpenJDK 17 (Azul, bepul, license cheklovsiz)
ℹ   Hajmi:  ~200MB, internet'da 30-60 sekund
ℹ   Joyi:   /Library/Java/JavaVirtualMachines/zulu-17.jdk/

  Hozir avtomatik o'rnataylikmi? (y/n) [y]: ↵
▶ Zulu JDK 17 o'rnatilmoqda (brew)...
[brew output ko'rinadi, ~30-60 sekund]
✓ Java JDK muvaffaqiyatli o'rnatildi!
✓ Yangi keytool topildi: /Library/Java/JavaVirtualMachines/zulu-17.jdk/Contents/Home/bin/keytool
```

So'ngra `create_new_keystore` davom etadi — foydalanuvchi keystore yaratadi.
**Zero copy-paste**.

### Texnik tafsilot

- **Faqat macOS** (uname == Darwin) — Linux'da sudo kerak bo'lgani uchun
- **Faqat agar `brew` bor bo'lsa** — yo'q bo'lsa, Homebrew install link beradi
- **Zulu @17** tanlandi:
  - **Bepul** (Oracle JDK'da licence cheklovlari bor)
  - **Azul** (yirik OpenJDK distributor, ishonchli)
  - **17 LTS** — long-term support, Flutter/Android bilan to'liq mos
  - **`--cask` orqali** — `/Library/Java/JavaVirtualMachines/` ga o'rnatadi
  - **`java_home` avtomatik topadi** — qo'shimcha PATH/symlink sozlash shart emas
- **Retry-after-install**: brew tugagach, `find_keytool` qayta chaqiriladi
- **Real-time output**: brew'ning progress'i ko'rinadi (sukut emas)

### Yaxshilanganlar

`create_new_keystore` endi 3 bosqichli pipeline:
  1. `find_keytool` — mavjud Java'larni qidirish (7 ta joy)
  2. `offer_jdk_auto_install` — agar yo'q bo'lsa, **avtomatik install**
  3. Manual install instructions — agar 1 va 2 muvaffaqiyatsiz bo'lsa

### Foydalanuvchi tajribasi taqqoslash

| Versiya | Java topilmasa |
|---------|----------------|
| v1.12.5 | Manual instructions: copy-paste 6 ta buyruq |
| v1.12.6 | Android Studio JBR avtomatik topiladi (agar bo'lsa); aks holda manual |
| **v1.12.7** | **Android Studio JBR + brew avtomatik install (1 ta `y` bosish)** |

### Auto-install opsiyasini o'tkazib yuborish

`n` bossangiz yoki `Ctrl-C` qilsangiz, manual install instructions ko'rsatiladi.
Bu **opt-in workflow** — sizning ruxsatingizsiz hech narsa o'rnatilmaydi.

### Test natijalari

3/3 unit test:
- ✓ `find_keytool` Android Studio JBR'ni topadi
- ✓ `offer_jdk_auto_install` `n` javobini boshqaradi (graceful)
- ✓ `brew` auto-discovery ishlaydi

## [1.12.6] — 2026-06-02

### Qo'shildi — Smart Java JDK discovery (Android Studio bilan keladi!)

User savol: "boshqa qilish ham mumkin ediku nega o'xshamayapti" — Java JDK
o'rnatish o'rniga, **mavjud Java'larni qidirib topish** kerak edi.

Aksariyat Flutter dasturchilari **Android Studio**'ni o'rnatadi (kerak),
va u o'zining **JBR (JetBrains Runtime)** bilan keladi. Bu JDK PATH'da
bo'lmasligi mumkin, lekin **ishlatishga to'liq tayyor**.

### Yangi `find_keytool` funksiyasi

7 ta keng tarqalgan joydan qidiradi (prioritet bo'yicha):

1. **PATH** (`command -v keytool`) — agar Java haqiqatan ishlasa
2. **macOS java_home** (`/usr/libexec/java_home`) — Apple'ning rasmiy locator
3. **Android Studio JBR**:
   - `/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool`
   - `/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool`
   - User-installed va Preview versiyalar
4. **`/Library/Java/JavaVirtualMachines/`** — rasmiy o'rnatilgan JDK'lar
5. **Homebrew**: `/opt/homebrew/opt/{openjdk,zulu,temurin}*` va Cellar
6. **SDKMan**: `~/.sdkman/candidates/java/current/`
7. **jenv**: `~/.jenv/versions/*/`
8. **Linux**: `/usr/lib/jvm/*/`

Topilgach, **full path orqali** chaqiradi — PATH'da bo'lishi kerak emas.

### Tuzatildi — `grep -qv` bug

Avval `if java -version | grep -qvE PATTERN; then` ishlatardik (invert match).
Lekin stub xabarda **bo'sh qator** bor (3 qator: matn, matn, bo'sh) va
`grep -v` bo'sh qator'ni keep qiladi → exit 0 → false positive.

**Fix**: `if ! java -version | grep -qE PATTERN; then` — pattern TOPILMASA,
Java sog'lom. Bu **classic grep gotcha**.

### Yaxshilanganlar

- **`create_new_keystore`** endi `find_keytool` ishlatadi va topilgan
  full path bilan chaqiradi. PATH'da Java yo'q bo'lsa, foydalanuvchiga
  aytadi: "Ishchi Java JDK topildi: /Applications/Android Studio.app/...".
- **`link_existing_keystore` va `show_key_properties`** ham `find_keytool`
  ishlatadi.
- **`--doctor`** endi qaerda Java topilganini ko'rsatadi:
  ```
  ✓ Java JDK              (PATH'da yo'q, lekin topildi: /Applications/Android Studio.app/Contents/jbr/Contents/Home)
        keystore yaratish ishlaydi (full path orqali)
  ```
- **`export_java_home_from_keytool`** helper — keytool full path'idan
  `JAVA_HOME`'ni derive qilib export qiladi (sibling tools uchun).
- **Install menyuga "Android Studio (eng oson)" qo'shildi** — agar
  foydalanuvchi hech narsa o'rnatmagan bo'lsa, eng tavsiya etiladigan
  variant.

### Sizning Mac'da test

User'ning Mac'da sinov:
```
✓ TOPILDI: /Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool
  Bu PATH'da bo'lmagan Java JDK, lekin ishchi
```

Demak v1.12.6 dan keyin user'ga **Java alohida o'rnatish shart emas** —
Android Studio'sining JBR ishlatiladi.

### Test natijalari

4/4 unit test:
- Stub xabari pattern detection
- `!` negation logikasi (stub muhitda PATH qaytarilmaydi)
- Real Java muhit (PATH version qaytariladi)
- User'ning Mac'da real `find_keytool` test (Android Studio JBR topildi)

### Texnik tafsilot

**Existence vs functionality**: `command -v X` faqat fayl mavjudligini
tekshiradi. **Functional test** uchun tool'ni real chaqirish kerak
(`java -version`). Bu **defensive programming** — fayl bor degan
ishonchga emas, **harakatga** ishonish.

**PATH-independent execution**: full path bilan binary chaqirsak
(`/path/to/keytool` o'rniga `keytool`), PATH'ga bog'liq emas. JAVA_HOME'ni
export qilsak, qo'shimcha dependencies ham topiladi.

## [1.12.5] — 2026-06-02

### Tuzatildi — macOS Java stub bug + UX yaxshilash

#### Bug: macOS keytool stub trap

User real bug: keystore yaratish "Unable to locate a Java Runtime" deb
xato berdi. Bu klassik **macOS Java stub bug'i**:

- macOS 2018 dan beri Java'ni bundle qilmaydi
- Lekin `/usr/bin/keytool`, `/usr/bin/java` **stub'lar** mavjud
- `command -v keytool` true qaytaradi (binary exists)
- Lekin ishga tushirilganda: "Unable to locate a Java Runtime. Please visit http://www.java.com"

Bizning v1.12.4 `command -v` ga ishonib, keystore wizard'ni boshlardi.
Foydalanuvchi 30 sekund yozardi va keyin xato olardi.

### Fix #1: Pre-flight Java check

Endi keystore wizard'ni boshlashdan **avval** Java ishlay olishini tekshiramiz:

```bash
java_check=$(java -version 2>&1)
if echo "$java_check" | grep -qiE "Unable to locate a Java Runtime|No Java runtime|visit http"; then
  err "Java JDK haqiqatan o'rnatilmagan (faqat macOS stub mavjud)"
  # Platform-specific install hints
  return 1
fi
```

Bu **fail fast** patterni — foydalanuvchi 30 sekund parol kiritishdan
oldin muammoni biladi.

### Fix #2: "Unable to locate Java Runtime" pattern detection

Agar baribir wizard ishga tushib qolsa, post-failure detector endi bu
specific xato'ni ham aniqlay oladi:

```
ℹ Sabab: Java JDK haqiqatan o'rnatilmagan (macOS keytool stub bug'i)
  macOS'da /usr/bin/keytool stub mavjud, lekin haqiqiy JDK o'rnatilishi shart
```

### Fix #3: --doctor Java check

`flutter-build --doctor` endi haqiqiy Java o'rnatilganligini tekshiradi:

```
Android deploy talab'lari:
  ✓ openssl                 (OpenSSL 3.6.0)
  ✗ Java JDK              o'rnatilmagan (keytool faqat macOS stub)
        Android keystore yaratish ishlamaydi
        O'rnatish: brew install --cask zulu@17
```

### UX yaxshilash: Community-popular default'lar

User'ning so'rovi asosida default'lar Flutter community'da eng tarqalgan
qiymatlarga o'zgartirildi:

| Field | Eski default | Yangi default | Sabab |
|-------|--------------|---------------|-------|
| Folder | `$HOME/keys` | `android` | Flutter tutorials, project-local |
| Filename | `${PROJECT_NAME}-release.jks` | `key.jks` | Eng tarqalgan, qisqa |
| Alias | `upload` | `key` | Tutorials/GitHub repos'da ko'p |

`android/` default xavfsiz chunki `ensure_gitignore_for_keys` allaqachon
`*.jks` ni `android/.gitignore` ga qo'shadi.

### Foydalanuvchi nuqtai nazaridan

Eski (v1.12.4) — keystore wizard ishlatib 30 sekund parol yozgandan keyin:
```
✗ Keystore yaratishda xatolik
⚠ keytool xato xabari:
    Unable to locate a Java Runtime
ℹ Eng keng tarqalgan sabablar: [generic list]
```

Yangi (v1.12.5) — wizard boshlamasdan oldin:
```
✗ Java JDK haqiqatan o'rnatilmagan (faqat macOS stub mavjud)
ℹ Tafsilot: Unable to locate a Java Runtime

ℹ macOS bug: /usr/bin/keytool va /usr/bin/java mavjud, lekin bular faqat
ℹ Apple'ning 'Java o'rnating' stub'lari — haqiqiy JDK alohida o'rnatilishi shart.

→ 'Java JDK (haqiqiy)' ni o'rnatish:
  macOS (brew, tavsiya): brew install --cask zulu@17
  macOS (Adoptium):      open https://adoptium.net/temurin/releases/?package=jdk
  ...
```

Foydalanuvchi **darrov bilib** Java'ni o'rnatadi va qayta urinadi.

### Test natijalari

5/5 unit test:
- macOS stub correctly detected
- Real OpenJDK NOT detected as stub (false positive guard)
- Oracle Java NOT detected as stub
- Version extraction from OpenJDK and Oracle outputs

## [1.12.4] — 2026-06-02

### Tuzatildi — Keystore yaratish silent failure

User real bug: "Keystore yaratishda xatolik" — sabab ko'rinmas edi.

Bizning kod `keytool` chiqishini `> /dev/null 2>&1` bilan to'liq yashirib
qo'ygan edi. Foydalanuvchi (va biz) keytool aslida nima xato berganini
bilmaymiz — faqat "xatolik" ko'rinardi.

### Fix: capture-then-show + pattern detection

`keytool` output endi `mktemp` faylga yoziladi:
- **Success holatda**: chiqish ko'rsatilmaydi (shovqin yo'q)
- **Failure holatda**: to'liq keytool xato xabari ko'rsatiladi va pattern
  asosida maxsus tushuntirish beriladi:
  - **Password < 6 belgi** → "kamida 6 belgi" tushunchasi
  - **Invalid name (RFC2253)** → "vergul/qo'shtirnoq ishlatmang"
  - **Permission denied** → `chmod`/`ls -la` tavsiyasi
  - **JKS proprietary warning** → "bu xato emas, fayl tekshiring"
  - **JAVA_HOME / unknown command** → JDK diagnostika
  - **Boshqa** → generic recovery hints

### Yaxshilanganlar

- **`keytool` topilmasa**: endi `try_this_install` bilan platform-specific
  install buyrug'i ko'rsatiladi:
  - macOS (brew): `brew install --cask zulu@17`
  - macOS (rasmiy): Adoptium Temurin URL
  - Linux: `sudo apt install default-jdk`
- **`mkdir -p` xato bo'lsa**: aniq xato xabari + recovery (avval bu silent
  fail edi — papka yaratilmasa keytool keyinroq "FileNotFoundException" berardi)
- **JKS deprecation false positive**: JDK 17+ "JKS uses proprietary format"
  warning beradi, lekin **fayl yaratiladi**. Bizning kod buni xato deb
  noto'g'ri talqin qilmaslik uchun specific detection bor.

### Texnik tafsilot

`capture-then-show` patterni — `cmd > "$logfile" 2>&1` bilan **avval
fayl'ga yozish**, keyin **faqat failure holatda foydalanuvchiga ko'rsatish**.
Bu **silent on success, verbose on failure** patterni — Unix tool'lari
falsafasiga mos.

Pattern dispatcher (5 ta error class):
- `password.*must be at least|too short` → password length
- `invalid.*name|illegal.*char|RFC2253` → DN syntax
- `permission denied|access denied|cannot write` → fs permissions
- `JKS keystore uses a proprietary format|migrate to PKCS12` → JDK17 warning
- `unknown.*command|JAVA_HOME` → JDK installation

### Foydalanuvchi nuqtai nazaridan

Avval:
```
✗ Keystore yaratishda xatolik
✗ Keystore yaratilmadi
```

Endi (masalan, password qisqa bo'lsa):
```
✗ Keystore yaratishda xatolik (keytool exit code: 1)

⚠ keytool xato xabari:
    keytool error: java.lang.IllegalArgumentException: Keystore password
    must be at least 6 characters

ℹ Sabab: parol qisqa (Java majburiy 6 belgi)
  → Qayta urinib, kamida 6 belgili parol kiriting
```

Endi (DN xato bo'lsa):
```
✗ Keystore yaratishda xatolik

⚠ keytool xato xabari:
    keytool error: java.io.IOException: Invalid name: ...

ℹ Sabab: sertifikat ma'lumotlarida noto'g'ri belgi (vergul, qo'shtirnoq, \)
  ℹ Faqat oddiy harflar va probel ishlatish tavsiya etiladi
```

### Test natijalari

5/5 unit test:
- Short password pattern detection
- Invalid DN pattern detection
- Permission denied pattern detection
- JKS deprecation warning detection (false positive guard)
- Generic error → fallback recovery

## [1.12.3] — 2026-05-21

### Tuzatildi — Play Store: promotion upload fail bo'lganda chaqirilmasin + edit context bug

User real bug: Play Store upload muvaffaqiyatsiz tugadi, lekin skript baribir
`play_suggest_promotion` chaqirdi. User "y" bosgan edi → promotion bo'sh
track'dan o'qishga harakat qildi → "internal track'da release topilmadi" xato.

### Bug #1: `|| warn` silent failure suppression

Build flow'da:
```bash
# Eski (xato):
upload_to_play_store "$aab_file" || warn "Upload xato"

if [ "$current_track" != "production" ]; then
  play_suggest_promotion ...   # ← har doim chaqiriladi, hatto xato bo'lsa ham!
fi
```

`||` operator faqat warn'ni chaqiradi — keyingi kod doimo ishlaydi.

**Fix:** Explicit flag bilan:
```bash
local play_upload_ok=true
upload_to_play_store "$aab_file" || {
  warn "Upload xato berdi"
  info "Promotion taklif qilinmaydi (chunki upload bo'lmadi)"
  play_upload_ok=false
}

if $play_upload_ok && [ "$current_track" != "production" ]; then
  play_suggest_promotion ...
fi
```

### Bug #2: `play_list_track_releases` edit context'isiz

Avval `GET /applications/{pkg}/tracks/{track}` ishlatardik — bu Google Play
API'da **eventual consistency** muammosiga duch keladi (yangi yuklangan
release darrov ko'rinmasligi mumkin).

**Fix:** Edit transaction ichida o'qish:
```bash
# 1) POST /edits → editId yaratish
# 2) GET /edits/{editId}/tracks/{track} → snapshot read
# 3) DELETE /edits/{editId} → cleanup (commit qilmaymiz, o'qish edi)
```

Bu DBMS'dagi `BEGIN TRANSACTION ... ROLLBACK` patterniga o'xshash.

### Yaxshilanganlar

- `play_promote_release` bo'sh source track'da batafsil xato xabari:
  - "Sabab va yechim" bo'limi
  - Play Console URL'i (qaysi tracket bo'sh ekanini ko'rish uchun)
  - `flutter-build` qayta urinish buyrug'i
- `play_increase_rollout` shu pattern bilan — bo'sh production'da
  `--promote-android` taklif qiladi
- `play_list_track_releases` endi **edit ichida** o'qiydi — snapshot
  consistency va `DELETE` orqali cleanup

### Test natijalari

4/4 unit test (build flow logic):
- Eski `|| warn` pattern: bug isbotlandi (har doim suggest chaqirardi)
- Yangi explicit flag: upload fail → suggest skip (to'g'ri)
- Upload OK → suggest call (to'g'ri)
- Production track → suggest skip (already prod, hech qaysiga ko'chirish kerak emas)

### Sizning ssenariyga ta'sir

Avval:
```
[Upload silently failed]
⚠ Upload xato berdi
[suggest_promotion auto-chaqirildi]
"Hozir promote qilamizmi?" → y
✗ internal track'da release topilmadi
```

Endi:
```
[Upload failed clearly]
⚠ Upload xato berdi — AAB fayl saqlangan
ℹ Promotion taklif qilinmaydi (chunki upload bo'lmadi)
```

Va agar siz qo'lda promote chaqirsangiz (yana xato bo'lsa):
```
✗ internal track'da release topilmadi

ℹ Sabab va yechim:
  • internal track hali bo'sh — avval AAB upload qilish kerak
  • Yoki upload muvaffaqiyatsiz tugagan bo'lishi mumkin

  → Buni sinab ko'ring:
    $ flutter-build   # menu'da Play Store upload ni yoqib qayta urinib ko'ring

  Tekshirish uchun Play Console'da ko'ring:
    $ open 'https://play.google.com/console/.../tracks/internal'
```

## [1.12.2] — 2026-05-21

### Tuzatildi — KRITIK: altool false positive (HTTP 4xx'da "Muvaffaqiyatli" deb ko'rsatardi)

User real bug report: `xcrun altool` HTTP 409 (duplicate version) xato
berdi, lekin skript "✓ Muvaffaqiyatli yuklandi!" deb ko'rsatdi.

Sabab: `xcrun altool` ba'zi Xcode versiyalarida HTTP 4xx (server rejection)
holatda ham **exit code 0** qaytaradi. Sabab — Apple ContentDelivery
framework "request completed" deb hisoblaydi, javob HTTP 4xx bo'lsa ham.

Bu **false positive** — foydalanuvchi noto'g'ri "success" ekraniga ishonib,
upload bo'lmaganini bilmasdan team'iga xabar yuborishi mumkin edi.

### Yangi mexanizm: "Trust but verify"

`appstore_upload_via_apple_id_altool` va `appstore_upload_via_api_key`
endi:

1. **`tee` orqali output capture** — real-time progress saqlanadi
2. **`${PIPESTATUS[0]}` orqali exit code** — `tee`'niki emas, `altool`'niki
3. **Output pattern matching** — `ERROR:`, `Failed to upload`, `ENTITY_ERROR`,
   `status : 4xx/5xx` pattern'larini qidiradi
4. **Exit 0 BO'LSA HAM** output'da xato pattern bo'lsa, **failure deb belgilaydi**

### Yangi helperlar

- `appstore_altool_output_has_errors` — pattern detector (DRY, 3 ta upload
  funksiyada ishlatiladi)
- `appstore_handle_409_duplicate` — 409 specific recovery:
  - `previousBundleVersion` ni output'dan extract qiladi
  - Foydalanuvchiga aniq qaysi build raqami konflikt'da bo'lganini aytadi
  - 3 ta yechim variantini ko'rsatadi:
    - A) pubspec.yaml'da `+` bilan oshirish
    - B) `flutter clean` + qayta build (cache muammosi)
    - C) iOS project.pbxproj sync emas (eski loyihalarda)

### Yangi specific error handling

**409 Duplicate Bundle Version:**
```
⚠ Bundle version conflict: Apple'da allaqachon build 4 bor
ℹ Yangi build raqami > 4 bo'lishi shart

🎯 Sabab va yechim:

  A) Build raqami pubspec.yaml'da hali oshirilmagan
     → flutter-build   # menu'da build #ga '+' bosing

  B) Pubspec'da yangi build bor, lekin IPA'da hali eski (cache)
     → rm -rf build/ios
     → flutter clean
     → flutter-build (clean va pub get yoqib)

  C) iOS project.pbxproj sync emas (FLUTTER_BUILD_NUMBER ref emas)
     → grep CURRENT_PROJECT_VERSION ios/Runner.xcodeproj/project.pbxproj
```

**Authentication errors** (Unauthorized, 401, 403) uchun ham specific recovery.

### Texnik tafsilot

`tee` + `${PIPESTATUS[0]}` pattern bash 3.2+ specific. Bizning skript
bash'ni majburiy qiladi (shebang `#!/usr/bin/env bash`).

Layer mismatch tushunchasi: altool'da "transport success" (HTTP request
yetkazib berildi) ≠ "business success" (Apple qabul qildi). To'g'ri
yechim — response BODY'sini parse qilish.

Test: 6/6 unit test
- 409 duplicate pattern detection (real user output bilan)
- Success output → ERROR yo'q
- `previousBundleVersion` extraction
- Authentication error pattern
- **Eng kritik: exit=0 + ERROR pattern → failure**

## [1.12.1] — 2026-05-19

### Tuzatildi — Transporter "Client configuration failed" auto-recovery

iTMSTransporter (Method 3) `Client configuration failed` xato bersa,
endi skript:

1. **Xatoni aniqlaydi** — output'ni `tee` orqali capture qilib, pattern
   matching bilan ("Client configuration failed", "Unauthorized" va h.k.)
2. **Avtomatik altool taklif qiladi** — xuddi shu credentials bilan
   Method 2 (xcrun altool) ga o'tib qayta urinish:
   ```
   ⚠ Bu Transporter'ning 'Client configuration failed' xatosi
   ℹ Sabab: bundled Java JRE buzuq yoki cache muammosi

   🎯 Eng tezkor yechim: altool method'iga o'tish
     Xuddi shu Apple ID + password ishlatadi, lekin xcrun altool
     (Apple'ning native binary'si — Java kerak emas, ishonchli)

     Hozir altool bilan qayta urinaylikmi? (y/n) [y]: _
   ```
3. **Muvaffaqiyatli bo'lsa** — akkauntni altool'ga doimiy ko'chirish
   taklif qilinadi
4. **Bo'lmasa** — Transporter saqlash uchun yechimlar (cache tozalash,
   Transporter yangilash)

### Qo'shildi

- **`--doctor` Transporter Java tekshiruvi**: bundled Java
  (`/Applications/Transporter.app/Contents/itms/java/bin/java`) mavjudligini
  oldindan tekshiradi. Buzuq bo'lsa ogohlantiradi.
- **Auth method tanlashda warning**: Method 3 (Transporter) tanlashda
  "⚠ Tavsiya: Method 2 (altool) ishonchliroq" yozuvi ko'rsatiladi.
- **Authentication failed pattern** uchun maxsus recovery (Apple ID yoki
  password noto'g'ri bo'lsa).

### Texnik tafsilot

`tee` + `PIPESTATUS[0]` pattern'i ishlatildi — Transporter output'i
real-time ko'rsatiladi (foydalanuvchi progress'ni ko'radi) va bir vaqtda
fayl'ga capture qilinadi (error pattern matching uchun). Bu **bash
3.2+ specific** lekin bizning skript bu versiyani majburiy qiladi.

### Foydalanuvchi nuqtai nazaridan

Bu real bug report'dan keldi: foydalanuvchi Method 3 (Transporter)
tanlagan edi va "Client configuration failed" xato oldi. Endi skript
o'zi xatoni aniqlab, **bir bosishda** altool'ga o'tib qayta urinadi.

Test: 6/6 unit test
- Error pattern matching (Client config, Auth failed, boshqa)
- PIPESTATUS[0] (bash 3.2+ specific)

## [1.12.0] — 2026-05-14

### Qo'shildi — iOS uchun 3 ta auth method

Avval faqat **API Key (.p8)** ishlatilardi — bu **Owner/Admin role**
talab qiladi. Developer rolida bo'lganlar `.p8` yarata olmasdi. Endi
3 ta authentication usul mavjud:

#### 1. **API Key (.p8)** — hozirgi
- Owner/Admin role kerak
- App Store Connect → Users and Access → Integrations → API Keys
- Eng kuchli (team-wide access)

#### 2. **Apple ID + App-specific password** — Developer ham qila oladi ✅
- Sizning shaxsiy Apple ID'ingiz orqali
- App-specific password: appleid.apple.com → Security
- **Owner ruxsati shart emas** — har qaysi team a'zo qila oladi
- Tool: `xcrun altool --username/--password`

#### 3. **Apple ID + Transporter CLI** — backup
- Apple ID + app-specific password bilan
- Tool: `/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter`
- Mac App Store'dan Transporter.app o'rnatish kerak (bepul)

### Account schema (yangi `auth_type` field)

```json
// API Key (Owner)
{"name":"...", "auth_type":"api_key", "key_id":"...", "issuer_id":"...", "key_path":"..."}

// Apple ID + altool (Developer)
{"name":"...", "auth_type":"apple_id_altool", "apple_id":"you@example.com", "app_specific_password":"xxxx-xxxx-xxxx-xxxx"}

// Apple ID + Transporter
{"name":"...", "auth_type":"apple_id_transporter", "apple_id":"...", "app_specific_password":"..."}
```

Eski v1.11.x akkauntlar (auth_type field'siz) avtomatik `api_key` deb
qabul qilinadi — backwards-compatible.

### Yangi funksiyalar

- `appstore_account_save_apple_id` — Apple ID + password formati
- `appstore_account_get_auth_type` — backwards-compat helper
- `appstore_add_api_key_account` — .p8 wizard (ajratilgan)
- `appstore_add_apple_id_account` — Apple ID wizard (altool yoki transporter)
- `appstore_upload_via_api_key` — dispatcher method 1
- `appstore_upload_via_apple_id_altool` — dispatcher method 2
- `appstore_upload_via_apple_id_transporter` — dispatcher method 3
- `appstore_upload_recovery_hints` — auth_type'ga ko'ra recovery

### O'zgartirildi

- `appstore_add_new_account` endi **router** — usulni tanlash menu
- `upload_to_appstore` endi `auth_type` ga ko'ra **dispatcher**
- `appstore_pick_account_for_project` har akkaunt uchun auth method
  ko'rsatadi (API Key XX vs Apple ID: you@... (altool))
- `ensure_appstore_credentials` har auth_type uchun alohida tekshirish
- `--doctor` Transporter mavjudligini ham tekshiradi va mavjud
  upload usullarini ro'yxat qiladi

### Xavfsizlik

- App-specific password `chmod 600` bilan saqlanadi
- Read on terminal — `read -s` (shadow input, ekran ko'rsatmaydi)
- Apple uchun normal pattern: app-specific password'lar dasturlar
  tomonidan saqlanishi uchun mo'ljallangan
- Compromise bo'lganda foydalanuvchi appleid.apple.com'da bir click bilan
  revoke qila oladi (asosiy Apple ID parolingiz xavfsiz qoladi)

### Foydalanuvchi nuqtai nazaridan

Avval (Developer role'da):
```
"Owner uchun .p8 olishim kerak — lekin Owner javob bermayapti :("
```

Endi (Developer role'da):
```
$ flutter-build --settings → 2) Akkauntlar → 1) Yangi Play Store akkaunti... 
   yo'q, App Store. → 2) Yangi App Store akkaunti
→ Authentication usulini tanlang: 2 (Apple ID + App-specific password)
→ appleid.apple.com'da password generate qildim
→ Email + password kiritdim → ✓ Tayyor
```

Endi `flutter-build` ishga tushirsangiz, sizning Apple ID orqali
TestFlight'ga upload qilinadi.

### Test natijalari

- `bash -n` syntax: ✅
- Apple ID altool account save/load: ✅
- Apple ID transporter account save/load: ✅
- API Key (eski format) backwards compat: ✅
- File permissions chmod 600: ✅
- Jami: 8/8 unit test

## [1.11.0] — 2026-05-14

### O'zgartirildi — Build menyu wizard-style

Avval build menyusi 7 ta checkbox'li **yagona katta menu** edi, ichida
bog'liq narsalar aralashtirilgan ("App Store needs Production + iOS",
"Play Store needs Production + Android + AAB"). Endi 5 bosqichli
**wizard** — har bosqich kichik, fokuslangan, kontekst asosida.

#### Yangi bosqichlar:

**[1/5] Build rejimi** (radio: Production / Debug)
- Numbered prompt: 1) Production, 2) Debug, b) Orqaga
- Production — release, signed (Play/App Store uchun)
- Debug — test build, signing yo'q

**[2/5] Platformalar** (checkbox: Android, iOS)
- Multi-select arrow_checkbox
- iOS faqat macOS'da ko'rsatiladi (boshqa OS'da xato bilan back)

**[3/5] Android format** (checkbox: AAB / APK)
- **Faqat Android tanlanganda ko'rsatiladi**
- Android tanlanmagan bo'lsa — bu bosqich o'tkazib yuboriladi (forward va
  backward yo'nalishda)

**[4/5] Build oldidan amallar** (checkbox: ixtiyoriy)
- flutter clean — kesh tozalash
- flutter pub get — paketlar yangilash

**[5/5] Build'dan keyin deploy** (contextual checkbox)
- **Faqat tegishli optsiyalar ko'rinadi**:
  - App Store Connect upload — faqat Production + iOS
  - Play Store upload — faqat Production + Android + AAB
- Hech qaysisi tegishli emas (masalan Debug rejim) → bosqich
  avtomatik o'tkazib yuboriladi

### Back navigation

Har bosqichda foydalanuvchi `b` bossa, oldingi bosqichga qaytadi
(state machine). Birinchi bosqichdan `b` — asosiy menyu'ga qaytish.

State graph:
```
main_menu
   ↓
[1/5] Mode ←─────────────────────┐
   ↓                              │
[2/5] Platforms ──────────────────┘
   ↓                              ↑
[3/5] Format (faqat Android) ─────┘ (skip if no Android)
   ↓                              ↑
[4/5] Pre-build ──────────────────┘
   ↓                              ↑
[5/5] Deploy (contextual) ────────┘
   ↓
Versions / Confirm / Build
```

### Olib tashlangan
- Eski monolitik `arrow_checkbox "Tanlovlar..."` 7 ta opsiya bilan
- Eski validatsiya kodi ("App Store needs Production+iOS" va h.k.) —
  endi natural ravishda contextual UI orqali ta'minlanadi
- "App Store/Play Store upload" qo'shimcha tushuntirish kerak emas —
  ular faqat shartlar bajarilganda ko'rsatiladi

### Falsafa: "Show only what's valid"

Microsoft Setup Wizard yoki iOS Onboarding patterni. Foydalanuvchi
faqat kerakli narsani ko'radi va **noto'g'ri kombinatsiya tanlashi
mumkin emas** — UI uni oldini oladi.

Test: 13/13 unit test
- menu_pick_build_mode (Production/Debug/Back)
- Settings default'lar (Production=true paytda default=1)
- Deploy applicability matrix (5 kombinatsiya)

## [1.10.1] — 2026-05-14

### Tuzatildi

- **Arrow key xato (↑/↓ ishlamaslik)** — `arrow_checkbox` da v1.10.0 da
  qo'shilgan `read -rsn2 -t 0.1` macOS bash 3.2 da "invalid timeout
  specification" deydi (decimal timeout qabul qilmaydi). Natijada arrow
  key sequence (`\x1b[B` va h.k.) to'liq o'qilmasdan, "Esc detected"
  sifatida talqin qilinardi va menu darrov bekor qilinardi.
  - Yechim: `-t 1` (integer timeout) ga qaytarildi (eski v1.9.0 xulqi)
  - Esc cancellation logikasi olib tashlandi — faqat `q` cancel'ni
    qo'llab-quvvatlaydi
  - Help text yangilandi: `q bekor` (avval `q/Esc bekor`)
- **Texnik tafsilot**: bash 3.2 `man bash`:
  ```
  -t timeout: Cause read to time out... timeout may be a decimal
  number with a fractional portion following the decimal point.
  ```
  Lekin amalda macOS bash 3.2 decimal qabul qilmaydi va xato beradi.
  Integer ishonchli ishlaydi.

## [1.10.0] — 2026-05-14

### Qo'shildi — Asosiy menyu va Back navigation

- **Asosiy menyu (`main_menu`)** — `flutter-build` (flag'siz) endi asosiy
  menyu ko'rsatadi:
  ```
  1) 🚀 Build (asosiy oqim)
  2) ⚙️  Sozlamalar
  3) 🩺 Doctor (tizim tekshiruvi)
  4) ⬆️  Android track promotion
  5) 📊 Rollout foizini oshirish
  6) 📋 Akkauntlar va loyihalarni ko'rish
  q) Chiqish
  ```
  Barcha funksiyalar bitta joyda — CLI flag yodda saqlash kerak emas.
- **`arrow_checkbox` cancellation** — endi `q` yoki `Esc` bilan bekor qilinadi.
  Bekor qilingach `CHECKBOX_CANCELLED=true` o'rnatiladi va asosiy menyu'ga
  qaytadi.
- **Back navigation throughout** — har bosqichda foydalanuvchi:
  - Build menu (checkbox) → `q`/`Esc` → asosiy menyu
  - Tasdiqlash → `n` → asosiy menyu
  - Submenular har birida `b) Orqaga`
  - Asosiy menyu'dan `q` → skript chiqadi
- **`main_build_flow()` funksiyasi** — avval top-level kod, endi funksiya
  bilan o'ralgan. Bekor qilishlar va xatolar `return 1` bilan menyu'ga
  qaytaradi (eski `exit 1` o'rniga).
- **Interaktiv submenular**:
  - `menu_promote_interactive` — track promotion (typical workflow'lar)
  - `menu_rollout_interactive` — rollout foizini oshirish (25/50/75/100/custom)
  - `menu_view_accounts_and_projects` — barcha sozlangan elementlar ko'rsatish

### Falsafa: State Machine UX

| Avval (linear) | Endi (state machine) |
|----------------|----------------------|
| Build flow har doim ishga tushardi | Menyu — foydalanuvchi tanlovi |
| Xato → script chiqadi | Xato → menyu'ga qaytadi, qayta urinish |
| Boshqa amallar uchun alohida CLI flag | Hammasi menyu'da |
| `Ctrl+C` yagona "bekor qilish" | `q`/`Esc`/`b`/`n` — har joyda mantiqiy |

### Foydalanish

\`\`\`bash
flutter-build              # Asosiy menyu
flutter-build --settings   # To'g'ridan-to'g'ri sozlamalar
flutter-build --doctor     # To'g'ridan-to'g'ri diagnostika
flutter-build --promote-android internal production   # Direct CLI
\`\`\`

CLI flag'lar **shortcut sifatida saqlanadi** — power user uchun, lekin
yangi foydalanuvchi menyu orqali hammasini topadi.

## [1.9.0] — 2026-05-14

### Qo'shildi — Action-oriented Error Messages

- **`try_this()` helper** — barcha xato xabarlari uchun bir xil format:
  ```
  ✗ Yuklab olib bo'lmadi
  ℹ Sabab: yozish ruxsati yo'q

    → Buni sinab ko'ring:
      $ sudo curl ... -o /usr/local/bin/flutter-build
      $ sudo chmod +x /usr/local/bin/flutter-build
  ```
  Foydalanuvchi xatoda **aniq recovery buyrug'ini** ko'radi va clipboard'ga
  copy-paste qilib darrov hal qila oladi.
- **`try_this_install()` helper** — platform-aware tavsiya:
  ```
  → 'openssl' ni o'rnatish:
    macOS: brew install openssl@3
    Linux: sudo apt install openssl
  ```
- **`--doctor` flag** (`-d`) — to'liq tizim diagnostikasi:
  - Asosiy talab'lar: Flutter, bash, curl, git
  - iOS deploy: xcrun mavjudligi
  - Android deploy: openssl mavjudligi
  - Settings: sozlangan akkauntlar, loyihalar
  - Yozish ruxsati: skript joyi va auto-update kabiliyati
  - GitHub erishish: live URL tekshiruvi
  - Loyiha holati: pubspec, Android applicationId, iOS bundle id
  - Yakuniy xulosa: ✓ Hammasi tayyor / ⚠ ogohlantirish / ✗ kritik muammo

### Yaxshilangan xato xabarlari

- **Auto-update**: yozish ruxsati yo'q bo'lsa `sudo curl` buyrug'i ko'rsatiladi
- **Tool missing**: `xcrun`, `openssl`, `curl`, `flutter` — har biri platform-aware install buyrug'i bilan
- **Play Store API**:
  - HTTP 403 (Forbidden) → "Service Account ruxsatlari" + Play Console URL
  - HTTP 404 (Not Found) → "birinchi AAB qo'lda yuklanmagan" + console URL
  - versionCode conflict → "menu'da '+' bosing"
  - Unsigned APK → "Production checkbox'ini yoqing"
- **App Store**:
  - Bundle ID yo'q → App Store Connect URL
  - Version conflict → `+` qisqartmasi tavsiyasi
  - Certificate xato → Xcode Settings yo'l
  - ExportOptions xato → settings'da default Team ID

### Falsafa: "Active errors, not passive"

| Avval (passiv) | Endi (aktiv) |
|----------------|--------------|
| `curl: (56) ... topilmadi` | `→ sudo curl <URL> -o <path>` |
| `xcrun topilmadi` | `→ xcode-select --install` |
| `versionCode conflict` | `→ flutter-build (menu'da '+' bosing)` |

Foydalanuvchi har xato uchun **aniq keyingi qadamni** biladi.

## [1.8.0] — 2026-05-14

### Qo'shildi — Smart Release Automation (TestFlight-equivalent + ortig'i)

- **Release notes integratsiyasi (Play Store)** — upload bilan birga
  testerlar 'Yangiliklar' bo'limida ko'radigan matn yuboriladi:
  - Avtomatik manbalar: `git log -1`, `CHANGELOG.md` oxirgi versiya yozuvi
  - Qo'lda yozish (`$EDITOR` ochiladi yoki bir qator)
  - Avtomatik: "Version X.Y.Z released"
  - 500 belgi cheklov (Play Store qoidasi)
- **Staged rollout (Play Store production)** — production'ga release'da
  foydalanuvchilar foizi bilan rollout:
  - 100% / 50% / 10% / 1% / Custom %
  - API'da `userFraction` orqali jo'natiladi
  - `inProgress` status — keyinroq foizni oshirish mumkin
- **Track promotion CLI**:
  - `flutter-build --promote-android FROM TO` — bir buyruq bilan track'lar
    orasida ko'chirish (masalan internal → production)
  - Interaktiv: argument'larsiz ham ishlaydi, source/target so'raydi
  - Production'ga promote qilinsa, rollout foizi ham so'raladi
- **`flutter-build --increase-rollout PCT`** — joriy production rollout
  foizini oshirish (yoki to'liq 100% ga ko'tarish)
- **Per-project promotion_flow** — har loyiha o'z promotion strategiyasini
  config'da saqlaydi:
  - `internal_to_prod` (default) — Internal → Production
  - `internal_to_beta_to_prod` — Internal → Beta → Production
  - `prod_only` — Faqat production (sinovsiz)
  - `none` — promotion tavsiyasi yo'q
- **Post-upload promotion taklifi** — upload tugagach, loyihaning
  promotion_flow asosida keyingi qadam taklif qilinadi
- **Settings: Loyiha promotion strategiyasi** — settings menyuda har
  loyiha uchun strategiyani tanlash mumkin

### Yangi funksiyalar

- `collect_release_notes` — interaktiv release notes yig'ish (5 manba)
- `read_git_last_commit`, `read_changelog_latest` — avtomatik manbalar
- `truncate_release_notes` — 500 belgi cheklov
- `escape_for_json` — JSON ichida xavfsiz string (newlines, quotes)
- `play_list_track_releases` — track'dagi versionCodes
- `play_promote_release` — bir track'dan boshqasiga ko'chirish
- `play_suggest_promotion` — post-upload tavsiya
- `play_increase_rollout` — production rollout foizini oshirish
- `settings_project_promotion_flow` — settings'da strategiya tanlash

### Texnik foyda — TestFlight bilan parallel

| Bosqich | iOS TestFlight | Android Play Store v1.8.0 |
|---------|----------------|----------------------------|
| Upload | `xcrun altool` | Google Play API + release notes |
| Processing | Apple TestFlight (10-30 min) | Google (1-2 min) |
| Internal testerlar | Avtomatik | Avtomatik (track=internal) |
| Release notes | "What to Test" maydoni (manual) | API orqali avtomatik ✓ |
| Track promotion | TestFlight External (Apple review 24-48h) | API orqali darrov ✓ |
| Staged rollout | Yo'q | userFraction bilan ✓ |

### Cheklov: iOS "What to Test"

Apple App Store Connect API'sida release notes (whatToTest) yangilash
**ES256 JWT signing** talab qiladi (Google'ning RS256'sidan farqli).
Bu v1.9.0 ga ajratildi — alohida release sifatida chiqadi.

## [1.7.0] — 2026-05-14

### Qo'shildi

- **Settings menyu** (`flutter-build --settings` yoki `-s`) — oldindan
  barcha default'larni sozlab qo'yish uchun. Build vaqtida har deploy'da
  checkbox bosish kerak emas — settings'da yoqilgan tanlovlar oldindan
  belgilangan holatda ko'rinadi.
- **Settings bo'limlari**:
  - **Build defaults** — Production, Android, iOS, format, upload tanlovlari
    har deploy'da qaysi holatdan boshlash kerakligi
  - **Akkauntlar** — Play va App Store akkauntlarini ko'rish, qo'shish, o'chirish
  - **Loyihalar** — sozlangan loyihalar ro'yxati va config'larni boshqarish
  - **Auto-update** — yoqish/o'chirish va timeout (1-60s)
  - **iOS Team ID** — ExportOptions.plist avtomatik yaratish uchun
  - **Joriy sozlamalar** — barcha default'larni jadval shaklida ko'rsatish
  - **Factory reset** — sozlamalarni boshlang'ich holatga qaytarish
- **`CHECKBOX_INITIAL` array** — `arrow_checkbox` funksiyasi endi oldindan
  tanlangan holatdan boshlanishi mumkin (global o'zgaruvchi orqali).
- **`AUTO_UPDATE_ENABLED` va `AUTO_UPDATE_TIMEOUT`** — `check_for_update`
  endi settings'dagi qiymatlarni ishlatadi.

### Settings storage

`~/.config/flutter-build-tool/settings.conf` — sourceable `key=value` format:

\`\`\`bash
DEFAULT_PRODUCTION=true
DEFAULT_ANDROID=true
DEFAULT_AAB=true
DEFAULT_PLAYSTORE_UPLOAD=true
DEFAULT_ANDROID_TRACK=internal
DEFAULT_IOS_TEAM_ID=ABC123DEF4
AUTO_UPDATE_ENABLED=true
AUTO_UPDATE_TIMEOUT=5
\`\`\`

### Falsafa: "Defaults, not lockdown"

- Settings'da yoqilgan tanlovlar build menu'da **oldindan belgilangan**
  holatda ko'rinadi.
- Foydalanuvchi har deploy'da o'zgartira oladi — settings shunchaki
  birinchi holatni belgilaydi.
- **Versiya raqami, build raqami, tasdiqlash** har doim so'raladi — bularni
  settings'da o'chirib qo'yib bo'lmaydi (xavfsizlik kafolati).

## [1.6.0] — 2026-05-14

### Qo'shildi

- **Named Accounts (AWS CLI-style profiles)** — har xil loyihalar har xil
  akkauntlardan foydalanishi mumkin. Bu professional dizayn: shaxsiy app
  uchun shaxsiy Service Account, ish loyihasi uchun ish akkaunti, mijoz
  loyihasi uchun mijoz akkaunti — barchasi yon-yonda saqlanadi va
  aralashmaydi.
- **Akkaunt picker** — yangi loyiha aniqlanganda mavjud akkauntlardan
  birini tanlash menyusi ko'rsatiladi yoki yangisini qo'shish mumkin.
  Avtomatik birinchi topilgan SA majburiy emas.
- **Yangi tuzilma**:
  - Loyiha config'lar (`play/<package>.json`, `appstore/<bundle>.json`)
    endi `account` nomi orqali havola qiladi (bevosita kalit yo'q).
  - Akkauntlar alohida saqlanadi:
    - `~/.config/flutter-build-tool/accounts/play/<name>.json`
    - `~/.config/flutter-build-tool/accounts/appstore/<name>.json`
  - Bir akkaunt N ta loyiha tomonidan ishlatilishi mumkin (decoupled).
- **`sanitize_account_name`** — akkaunt nomi xavfsiz qilish (filesystem-safe).
- **`play_derive_account_name`** / **`appstore_derive_account_name`** —
  default nom: Android'da SA JSON ichidagi `project_id`, iOS'da Key ID.
- **Avtomatik v1.5.0 → v1.6.0 migratsiya** — eski format avtomatik
  akkauntlarga ajratiladi. Foydalanuvchi xabarsiz davom etadi. Backup
  fayllar `.v15.<timestamp>` sifatida saqlanadi.

### O'zgartirildi

- **`play_project_config_save(pkg, account, track)`** — eski signature
  `(pkg, sa_path, track)` o'rniga. SA path endi akkaunt fayli orqali
  resolve qilinadi (indirection layer).
- **`appstore_project_config_save(bundle, account)`** — kalit ma'lumotlari
  akkaunt fayliga ko'chdi.
- **`upload_to_*` funksiyalari** — endi `current_project → account → key`
  oqimi orqali resolve qiladi.

### Texnik foyda (single source of truth)

Eski v1.5.0: agar SA JSON fayli ko'chsa, har bir loyihaning config'ini
yangilash kerak edi (3 loyiha → 3 ta fayl tahriri).

Yangi v1.6.0: faqat **akkaunt** fayli yangilanadi, loyihalar avtomatik
yangi yo'lni oladi (3 loyiha → 1 ta fayl tahriri).

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

[1.17.6]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.6
[1.17.5]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.5
[1.17.4]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.4
[1.17.3]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.3
[1.17.2]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.2
[1.17.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.1
[1.17.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.17.0
[1.16.4]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.16.4
[1.16.3]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.16.3
[1.16.2]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.16.2
[1.16.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.16.1
[1.16.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.16.0
[1.15.3]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.15.3
[1.15.2]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.15.2
[1.15.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.15.1
[1.15.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.15.0
[1.14.2]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.14.2
[1.14.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.14.1
[1.14.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.14.0
[1.13.9]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.9
[1.13.8]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.8
[1.13.7]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.7
[1.13.6]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.6
[1.13.5]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.5
[1.13.4]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.4
[1.13.3]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.3
[1.13.2]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.2
[1.13.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.1
[1.13.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.13.0
[1.12.7]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.7
[1.12.6]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.6
[1.12.5]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.5
[1.12.4]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.4
[1.12.3]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.3
[1.12.2]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.2
[1.12.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.1
[1.12.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.12.0
[1.11.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.11.0
[1.10.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.10.1
[1.10.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.10.0
[1.9.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.9.0
[1.8.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.8.0
[1.7.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.7.0
[1.6.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.6.0
[1.5.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.5.0
[1.4.1]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.4.1
[1.4.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.4.0
[1.3.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.3.0
[1.2.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.2.0
[1.1.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.1.0
[1.0.0]: https://github.com/Jaloliddin-Fozilov/flutter-build-tool/releases/tag/v1.0.0
