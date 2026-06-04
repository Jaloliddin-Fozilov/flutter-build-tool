# Changelog

Loyihaning barcha muhim o'zgarishlari shu faylga yoziladi.

Format [Keep a Changelog](https://keepachangelog.com/uz/1.1.0/) asosida,
versiyalash esa [Semantic Versioning](https://semver.org/lang/uz/) qoidasiga rioya qiladi.

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
