#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  Flutter Universal Build Script
#  Foydalanish:
#    1. Skriptni Flutter loyihasi ildiziga ko'chiring (yoki istalgan
#       joydan to'liq path bilan ishga tushiring)
#    2. ./flutter_build.sh
#
#  Skript:
#    - Hozirgi versiyalarni ko'rsatadi (pubspec / iOS / Android)
#    - Yangi versiyalarni so'raydi (Enter — eski qiymatni saqlaydi)
#    - Debug yoki Production build qiladi
#    - Android va iOS ni alohida tanlash imkonini beradi
#    - AAB yoki APK formatlarini tanlash imkonini beradi
#    - Android signing ni avtomatik sozlaydi (keystore yaratish/ulash)
#    - Tugagandan keyin natijani Finder da ochadi
#
#  Repo:    https://github.com/Jaloliddin-Fozilov/flutter-build-tool
#  License: MIT
# ════════════════════════════════════════════════════════════════

set -eo pipefail

# ─── Skript ma'lumotlari ──────────────────────────────────
SCRIPT_VERSION="1.1.0"
SCRIPT_REPO="Jaloliddin-Fozilov/flutter-build-tool"
SCRIPT_RAW_URL="https://raw.githubusercontent.com/${SCRIPT_REPO}/main/flutter_build.sh"

# ─── Ranglar ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ─── UI yordamchilari ─────────────────────────────────────
banner() {
  echo
  echo -e "${BOLD}${MAGENTA}╔═══════════════════════════════════════════════════════╗${NC}"
  printf  "${BOLD}${MAGENTA}║${NC}  %-53s${BOLD}${MAGENTA}║${NC}\n" "$1"
  echo -e "${BOLD}${MAGENTA}╚═══════════════════════════════════════════════════════╝${NC}"
  echo
}
step() { echo -e "\n${BOLD}${BLUE}▶${NC} ${BOLD}$1${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}ℹ${NC} $1"; }

# ─── Umumiy yordamchilar ──────────────────────────────────

# resolve_version_input <input> <old>
#   "" (Enter)  → old
#   "+"         → old ning oxirgi raqamli qismini +1 (1.0.23 → 1.0.24, 34 → 35)
#   <boshqa>    → input ni qaytaradi
# Diagnostika xabarlari stderr ga yoziladi — natija stdout dan o'qiladi.
resolve_version_input() {
  local input="$1" old="$2"

  [ -z "$input" ] && { printf '%s\n' "$old"; return 0; }

  if [ "$input" = "+" ]; then
    if [[ "$old" =~ ^[0-9]+$ ]]; then
      printf '%s\n' "$((old + 1))"
      return 0
    fi
    if [[ "$old" =~ ^(.*[^0-9])([0-9]+)$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}$((BASH_REMATCH[2] + 1))"
      return 0
    fi
    warn "'+' ishlatildi, lekin '${old}' da raqamli qism topilmadi — eski qiymat saqlandi" >&2
    printf '%s\n' "$old"
    return 0
  fi

  printf '%s\n' "$input"
}

# open_file <path>
#   macOS: open, Linux: xdg-open, WSL: explorer.exe, aks holda — path ni ko'rsatadi
open_file() {
  local path="$1"
  if [ ! -d "$path" ] && [ ! -f "$path" ]; then
    warn "Topilmadi: $path"
    return 1
  fi
  if command -v open >/dev/null 2>&1; then
    open "$path" 2>/dev/null && { ok "Ochildi: $path"; return 0; }
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    (xdg-open "$path" >/dev/null 2>&1 &) && { ok "Ochildi (xdg-open): $path"; return 0; }
  fi
  if command -v explorer.exe >/dev/null 2>&1; then
    local winpath
    if command -v wslpath >/dev/null 2>&1; then
      winpath=$(wslpath -w "$path" 2>/dev/null || echo "$path")
    else
      winpath="$path"
    fi
    explorer.exe "$winpath" 2>/dev/null && { ok "Ochildi (explorer): $path"; return 0; }
  fi
  info "Yo'l: $path (qo'lda oching)"
  return 1
}

# ─── Auto-update tekshiruvi ───────────────────────────────
check_for_update() {
  command -v curl > /dev/null 2>&1 || return 0

  local latest
  latest=$(curl -fsSL --max-time 5 "$SCRIPT_RAW_URL" 2>/dev/null \
    | grep '^SCRIPT_VERSION=' | head -1 \
    | sed -E 's/SCRIPT_VERSION="?([^"]+)"?/\1/')

  [ -z "$latest" ] && return 0
  [ "$latest" = "$SCRIPT_VERSION" ] && return 0

  echo
  warn "Yangi versiya mavjud: ${YELLOW}${latest}${NC} (joriy: ${SCRIPT_VERSION})"
  info "Repo: https://github.com/${SCRIPT_REPO}"
  read -p "  Hozir yangilamoqchimisiz? (y/n): " upd
  if [[ "${upd}" =~ ^[Yy]$ ]]; then
    perform_self_update
  fi
}

perform_self_update() {
  local self="$0"
  if command -v realpath > /dev/null 2>&1; then
    self=$(realpath "$self" 2>/dev/null || echo "$0")
  fi

  local tmp="${self}.new.$$"
  step "Yangi versiya yuklab olinmoqda..."

  if ! curl -fsSL --max-time 30 "$SCRIPT_RAW_URL" -o "$tmp"; then
    err "Yuklab olib bo'lmadi (network yoki repo muammosi)"
    rm -f "$tmp"
    return 1
  fi

  if ! bash -n "$tmp" 2>/dev/null; then
    err "Yangi versiyada sintaksis xatosi — yangilash bekor qilindi"
    rm -f "$tmp"
    return 1
  fi

  cp "$self" "${self}.bak.$(date +%s)"
  mv "$tmp" "$self"
  chmod +x "$self"

  ok "Yangilandi! Skriptni qayta ishga tushiring:"
  echo "    $self"
  exit 0
}

# ─── Argumentlarni tahlil qilish ──────────────────────────
SKIP_UPDATE=false
for arg in "$@"; do
  case "$arg" in
    --no-update-check|--skip-update)
      SKIP_UPDATE=true
      ;;
    --version|-v)
      echo "${SCRIPT_VERSION}"
      exit 0
      ;;
    --help|-h)
      cat <<EOF
Flutter Build Tool v${SCRIPT_VERSION}

Foydalanish:
  ./flutter_build.sh                    Interaktiv build
  ./flutter_build.sh --version          Versiyani ko'rsatish
  ./flutter_build.sh --no-update-check  Yangilanish tekshiruvisiz ishga tushirish
  ./flutter_build.sh --help             Bu ma'lumot

Repo: https://github.com/${SCRIPT_REPO}
EOF
      exit 0
      ;;
  esac
done

# Yangilanish tekshiruvi (validatsiyadan oldin)
$SKIP_UPDATE || check_for_update

# ─── Arrow-key checkbox menyusi ───────────────────────────
# Foydalanish: arrow_checkbox "Sarlavha" "Item 1" "Item 2" ...
# Natija: CHECKBOX_RESULT[] global array, har bir element "true" yoki "false"
# Boshqaruv: ↑/↓ harakat, Space toggle, Enter tasdiqlash
#
# Tor terminallar uchun:
#  - tput sc/rc/ed bilan render zonasini har gal to'liq tozalaymiz
#    (wrap bo'lgan qatorlar ham tozalanadi)
#  - Opsiya matni terminal kengligiga truncate qilinadi (har opsiya = 1 qator)
arrow_checkbox() {
  local title="$1"
  shift
  local options=("$@")
  local n=${#options[@]}
  local checked=()
  local i
  for ((i = 0; i < n; i++)); do checked+=("false"); done
  local cursor=0

  # Terminal kengligi va opsiya max uzunligi
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  # Prefiks: "  ▶ [✓] " ≈ 8 belgi + 2 zaxira = 10 belgi
  local max_label=$((cols - 10))
  [ "$max_label" -lt 16 ] && max_label=16

  echo
  echo -e "${BOLD}${BLUE}▶${NC} ${BOLD}${title}${NC}"
  echo -e "  ${CYAN}↑/↓${NC} ${CYAN}Space${NC} ${CYAN}Enter${NC}"
  echo

  tput civis 2>/dev/null
  trap 'tput cnorm 2>/dev/null; exit 130' INT

  # Render zonasi boshlanish nuqtasini saqlaymiz
  tput sc 2>/dev/null

  while true; do
    # Saqlangan nuqtaga qaytib, oxirigacha tozalaymiz (wrap qoldiqlari ham)
    tput rc 2>/dev/null
    tput ed 2>/dev/null

    for ((i = 0; i < n; i++)); do
      local label="${options[$i]}"
      # Terminal kengligiga sig'dirib qisqartirish (har opsiya = 1 qator)
      if [ "${#label}" -gt "$max_label" ]; then
        label="${label:0:$((max_label - 1))}…"
      fi

      if [ "$i" -eq "$cursor" ]; then
        printf "  ${BOLD}${MAGENTA}▶${NC} "
      else
        printf "    "
      fi
      if [ "${checked[$i]}" = "true" ]; then
        printf "${GREEN}[✓]${NC} ${BOLD}%s${NC}\n" "$label"
      else
        printf "[ ] %s\n" "$label"
      fi
    done

    IFS= read -rsn1 key
    case "$key" in
      "")
        break
        ;;
      " ")
        if [ "${checked[$cursor]}" = "true" ]; then
          checked[$cursor]="false"
        else
          checked[$cursor]="true"
        fi
        ;;
      $'\x1b')
        IFS= read -rsn2 -t 1 rest 2>/dev/null || true
        case "$rest" in
          "[A") cursor=$((cursor - 1)); [ "$cursor" -lt 0 ] && cursor=$((n - 1)) ;;
          "[B") cursor=$((cursor + 1)); [ "$cursor" -ge "$n" ] && cursor=0 ;;
        esac
        ;;
      "k"|"K") cursor=$((cursor - 1)); [ "$cursor" -lt 0 ] && cursor=$((n - 1)) ;;
      "j"|"J") cursor=$((cursor + 1)); [ "$cursor" -ge "$n" ] && cursor=0 ;;
    esac
  done

  tput cnorm 2>/dev/null
  trap - INT
  CHECKBOX_RESULT=("${checked[@]}")
}

# ─── Versiya yangilash funksiyalari ───────────────────────
update_pubspec_version() {
  local v="$1" b="$2"
  sed -i.bak "s/^version:.*/version: ${v}+${b}/" pubspec.yaml
  rm -f pubspec.yaml.bak
}

update_ios_version() {
  local file="$1" v="$2" b="$3"
  sed -i.bak "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = ${v};/g" "$file"
  sed -i.bak "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = ${b};/g" "$file"
  rm -f "$file.bak"
}

update_android_version() {
  local file="$1" v="$2" b="$3"
  if [[ "$file" == *.kts ]]; then
    sed -i.bak -E "s/versionCode[[:space:]]*=[[:space:]]*[0-9]+/versionCode = ${b}/" "$file"
    sed -i.bak -E "s/versionName[[:space:]]*=[[:space:]]*\"[^\"]*\"/versionName = \"${v}\"/" "$file"
  else
    sed -i.bak -E "s/versionCode[[:space:]]+[0-9]+/versionCode ${b}/" "$file"
    sed -i.bak -E "s/versionName[[:space:]]+\"[^\"]*\"/versionName \"${v}\"/" "$file"
  fi
  rm -f "$file.bak"
}

# ─── Android signing yordamchi funksiyalari ───────────────

# Parolni yashirish: "12345678" -> "12******"
mask_password() {
  local pwd="$1"
  local len=${#pwd}
  if [ "$len" -le 4 ]; then
    printf "****"
  else
    printf "%s%s" "${pwd:0:2}" "$(printf '%*s' "$((len - 2))" '' | tr ' ' '*')"
  fi
}

# key.properties dan qiymat o'qish
read_key_property() {
  local key="$1" file="${2:-android/key.properties}"
  [ -f "$file" ] || return 1
  grep -E "^${key}[[:space:]]*=" "$file" | head -1 | sed -E "s/^${key}[[:space:]]*=[[:space:]]*//"
}

# Joriy key.properties ni ko'rsatish (parollar yashirilgan)
show_key_properties() {
  if [ ! -f "android/key.properties" ]; then
    err "android/key.properties topilmadi"
    return 1
  fi

  local sp kp al sf
  sp=$(read_key_property storePassword)
  kp=$(read_key_property keyPassword)
  al=$(read_key_property keyAlias)
  sf=$(read_key_property storeFile)

  echo
  echo -e "  ${BOLD}╭─ Joriy android/key.properties ──────────────╮${NC}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-15s${NC} ${YELLOW}%s${NC}\n" "storeFile"     "$sf"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-15s${NC} ${YELLOW}%s${NC}\n" "keyAlias"      "$al"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-15s${NC} ${YELLOW}%s${NC}\n" "storePassword" "$(mask_password "$sp")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-15s${NC} ${YELLOW}%s${NC}\n" "keyPassword"   "$(mask_password "$kp")"
  echo -e "  ${BOLD}╰────────────────────────────────────────────────╯${NC}"

  if [ -z "$sf" ]; then
    err "storeFile bo'sh"
    return 1
  fi

  if [ ! -f "$sf" ]; then
    err "Keystore fayli topilmadi: $sf"
    return 1
  fi

  ok "Keystore fayli mavjud: $sf"

  # Keystoreni o'qib alias va expiry ni ko'rsatish
  if command -v keytool > /dev/null 2>&1; then
    local kt_out
    kt_out=$(keytool -list -v -keystore "$sf" -alias "$al" -storepass "$sp" 2>&1) || {
      warn "Keystore o'qib bo'lmadi (parol yoki alias noto'g'ri bo'lishi mumkin)"
      return 1
    }
    local expiry sha1
    expiry=$(echo "$kt_out" | grep -E "Valid from|Valid until|until:" | head -1)
    sha1=$(echo "$kt_out" | grep -E "SHA1:" | head -1 | sed 's/^[[:space:]]*//')
    [ -n "$expiry" ] && info "$(echo "$expiry" | sed 's/^[[:space:]]*//')"
    [ -n "$sha1" ] && info "$sha1"
  fi
}

# key.properties yozish
write_key_properties() {
  local sp="$1" kp="$2" al="$3" sf="$4"
  mkdir -p android
  cat > android/key.properties <<EOF
storePassword=${sp}
keyPassword=${kp}
keyAlias=${al}
storeFile=${sf}
EOF
  ok "android/key.properties yaratildi"
}

# .gitignore ga signing fayllarni qo'shish
ensure_gitignore_for_keys() {
  local gi="android/.gitignore"
  [ ! -f "$gi" ] && touch "$gi"
  local entries=("key.properties" "*.jks" "*.keystore")
  local added=()
  local e
  for e in "${entries[@]}"; do
    if ! grep -qxF "$e" "$gi"; then
      echo "$e" >> "$gi"
      added+=("$e")
    fi
  done
  if [ ${#added[@]} -gt 0 ]; then
    ok ".gitignore ga qo'shildi: ${added[*]}"
  else
    info ".gitignore allaqachon to'g'ri sozlangan"
  fi
}

# Yangi keystore yaratish (interaktiv, keytool orqali)
create_new_keystore() {
  if ! command -v keytool > /dev/null 2>&1; then
    err "keytool topilmadi (Java JDK o'rnatilganligini tekshiring)"
    return 1
  fi

  step "Yangi Android keystore yaratilmoqda"

  local default_dir="$HOME/keys"
  local default_name="${PROJECT_NAME}-release.jks"

  read -p "    Keystore papkasi [${default_dir}]: " kdir
  kdir="${kdir:-$default_dir}"
  read -p "    Keystore fayl nomi [${default_name}]: " kname
  kname="${kname:-$default_name}"

  local kpath="${kdir}/${kname}"

  if [ -f "$kpath" ]; then
    warn "Bu fayl allaqachon mavjud: $kpath"
    warn "MUHIM: Keystore yo'qolsa, Play Store da ilovani yangilab bo'lmaydi."
    read -p "    Eski keystore backup qilinib, yangisi yaratilsinmi? (y/n): " ovw
    [[ ! "${ovw}" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }
    local backup_path="${kpath}.bak.$(date +%s)"
    mv "$kpath" "$backup_path"
    ok "Eski keystore backup qilindi: $backup_path"
  fi

  mkdir -p "$kdir"

  local al sp sp2 kp
  read -p "    Key alias [upload]: " al
  al="${al:-upload}"

  while true; do
    read -s -p "    Keystore parol (kamida 6 belgi): " sp; echo
    if [ "${#sp}" -lt 6 ]; then
      err "Parol kamida 6 belgi bo'lishi kerak"
      continue
    fi
    read -s -p "    Parolni qayta kiriting: " sp2; echo
    if [ "$sp" != "$sp2" ]; then
      err "Parollar mos kelmadi"
      continue
    fi
    break
  done

  read -s -p "    Key parol [keystore parol bilan bir xil]: " kp; echo
  kp="${kp:-$sp}"

  echo
  info "Sertifikat ma'lumotlari (Enter = 'Unknown')"
  local cn org loc cc
  read -p "    Ism va familiya (CN): " cn
  read -p "    Tashkilot (O): " org
  read -p "    Shahar (L): " loc
  read -p "    Davlat kodi (C, masalan UZ) [UZ]: " cc
  cc="${cc:-UZ}"

  local dname="CN=${cn:-Unknown}, O=${org:-Unknown}, L=${loc:-Unknown}, C=${cc}"

  step "Keystore yaratilmoqda..."
  if keytool -genkeypair -v \
    -keystore "$kpath" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias "$al" \
    -storepass "$sp" \
    -keypass "$kp" \
    -dname "$dname" > /dev/null 2>&1; then
    ok "Keystore yaratildi: $kpath"
  else
    err "Keystore yaratishda xatolik"
    return 1
  fi

  write_key_properties "$sp" "$kp" "$al" "$kpath"
  ensure_gitignore_for_keys
  ensure_gradle_signing_config

  echo
  warn "MUHIM: Keystore va parolni xavfsiz joyga BACKUP qiling!"
  warn "Yo'qotsangiz, ilovani Play Store da yangilab bo'lmaydi."
}

# Mavjud keystoreni ulash (foydalanuvchi yo'lini va parollarini kiritadi)
link_existing_keystore() {
  step "Mavjud keystoreni ulash"

  local kpath al sp kp
  read -p "    Keystore fayliga to'liq yo'l: " kpath
  if [ ! -f "$kpath" ]; then
    err "Fayl topilmadi: $kpath"
    return 1
  fi

  read -p "    Key alias: " al
  read -s -p "    Keystore parol: " sp; echo
  read -s -p "    Key parol [keystore parol bilan bir xil]: " kp; echo
  kp="${kp:-$sp}"

  if command -v keytool > /dev/null 2>&1; then
    if ! keytool -list -keystore "$kpath" -alias "$al" -storepass "$sp" > /dev/null 2>&1; then
      err "Keystore o'qib bo'lmadi (parol yoki alias noto'g'ri)"
      return 1
    fi
    ok "Keystore tekshirildi: alias '$al' topildi"
  fi

  write_key_properties "$sp" "$kp" "$al" "$kpath"
  ensure_gitignore_for_keys
  ensure_gradle_signing_config
}

# build.gradle (Groovy) ga signing config inject qilish
inject_signing_config_groovy() {
  local file="$1"
  cp "$file" "${file}.bak.$(date +%s)"

  local tmp="${file}.tmp.$$"
  local has_props_load=false
  local injected_signing=false

  if grep -q "keystoreProperties" "$file"; then
    has_props_load=true
  fi

  # 1) Fayl boshiga properties yuklamasini qo'shish (agar yo'q bo'lsa)
  if ! $has_props_load; then
    cat > "$tmp" <<'EOF'
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

EOF
  else
    : > "$tmp"
  fi

  # 2) buildTypes dan oldin signingConfigs blokini inject qilamiz
  #    va signingConfigs.debug -> signingConfigs.release
  while IFS= read -r line || [ -n "$line" ]; do
    if ! $injected_signing && [[ "$line" =~ ^[[:space:]]*buildTypes[[:space:]]*\{ ]]; then
      cat >> "$tmp" <<'EOF'
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

EOF
      injected_signing=true
    fi
    line="${line//signingConfigs.debug/signingConfigs.release}"
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"

  if ! $injected_signing; then
    err "buildTypes bloki topilmadi — signing config inject qilinmadi"
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$file"
  ok "${file} yangilandi (backup: ${file}.bak.*)"
}

# build.gradle.kts (Kotlin DSL) ga signing config inject qilish
inject_signing_config_kts() {
  local file="$1"
  cp "$file" "${file}.bak.$(date +%s)"

  local tmp="${file}.tmp.$$"
  local has_props_load=false
  local injected_signing=false

  if grep -q "keystoreProperties" "$file"; then
    has_props_load=true
  fi

  if ! $has_props_load; then
    cat > "$tmp" <<'EOF'
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

EOF
  else
    : > "$tmp"
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    if ! $injected_signing && [[ "$line" =~ ^[[:space:]]*buildTypes[[:space:]]*\{ ]]; then
      cat >> "$tmp" <<'EOF'
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

EOF
      injected_signing=true
    fi
    # Kotlin DSL: signingConfigs.getByName("debug") -> getByName("release")
    line="${line//signingConfigs.getByName(\"debug\")/signingConfigs.getByName(\"release\")}"
    printf '%s\n' "$line" >> "$tmp"
  done < "$file"

  if ! $injected_signing; then
    err "buildTypes bloki topilmadi — signing config inject qilinmadi"
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$file"
  ok "${file} yangilandi (backup: ${file}.bak.*)"
}

# build.gradle ni signing uchun sozlash (agar kerak bo'lsa)
ensure_gradle_signing_config() {
  if [ -z "$ANDROID_GRADLE" ]; then
    warn "android/app/build.gradle topilmadi"
    return 1
  fi

  if grep -q "keystoreProperties" "$ANDROID_GRADLE" && \
     grep -q "signingConfigs.release\|getByName(\"release\")" "$ANDROID_GRADLE"; then
    ok "${ANDROID_GRADLE}: signing config allaqachon sozlangan"
    return 0
  fi

  step "build.gradle signing config qo'shilmoqda"
  warn "${ANDROID_GRADLE} fayli o'zgartiriladi (backup .bak. fayl yaratiladi)"
  read -p "  Davom etamizmi? (y/n): " gconfirm
  [[ ! "${gconfirm}" =~ ^[Yy]$ ]] && { warn "Gradle inject bekor qilindi"; return 1; }

  if [[ "$ANDROID_GRADLE" == *.kts ]]; then
    inject_signing_config_kts "$ANDROID_GRADLE"
  else
    inject_signing_config_groovy "$ANDROID_GRADLE"
  fi
}

# Asosiy interaktiv menyu — Production Android signing setup
setup_android_signing() {
  step "Android signing tekshiruvi"

  local has_props=false
  [ -f "android/key.properties" ] && has_props=true

  if $has_props; then
    info "android/key.properties topildi"
    show_key_properties || true
    echo
    echo -e "  ${BOLD}Tanlovlar:${NC}"
    echo -e "    ${CYAN}1${NC}) Davom etish (joriy keystore bilan build qilish)"
    echo -e "    ${CYAN}2${NC}) Yangi keystore yaratish (eskini almashtirish)"
    echo -e "    ${CYAN}3${NC}) Boshqa mavjud keystoreni ulash"
    echo -e "    ${CYAN}4${NC}) Bekor qilish"
    echo
    read -p "  Tanlang [1-4]: " choice

    case "$choice" in
      1) ok "Joriy keystore bilan davom etamiz" ;;
      2) create_new_keystore || { err "Keystore yaratilmadi"; exit 1; } ;;
      3) link_existing_keystore || { err "Keystore ulanmadi"; exit 1; } ;;
      4|*) err "Bekor qilindi"; exit 1 ;;
    esac
  else
    warn "android/key.properties topilmadi"
    warn "Production Android build uchun signing keys kerak"
    echo
    echo -e "  ${BOLD}Tanlovlar:${NC}"
    echo -e "    ${CYAN}1${NC}) Yangi keystore yaratish (tavsiya etiladi)"
    echo -e "    ${CYAN}2${NC}) Mavjud keystoreni ulash (boshqa loyihadan)"
    echo -e "    ${CYAN}3${NC}) Debug signing bilan davom etish ${YELLOW}(Play Store ga yaramaydi)${NC}"
    echo -e "    ${CYAN}4${NC}) Bekor qilish"
    echo
    read -p "  Tanlang [1-4]: " choice

    case "$choice" in
      1) create_new_keystore || { err "Keystore yaratilmadi"; exit 1; } ;;
      2) link_existing_keystore || { err "Keystore ulanmadi"; exit 1; } ;;
      3) warn "Debug signing bilan davom etamiz — bu APK Play Store da ishlamaydi" ;;
      4|*) err "Bekor qilindi"; exit 1 ;;
    esac
  fi
}

# ─── iOS App Store Connect deploy yordamchi funksiyalari ──

# Config fayl yo'li: ~/.config/flutter-build-tool/app_store_connect.json
appstore_config_dir()  { echo "${HOME}/.config/flutter-build-tool"; }
appstore_config_file() { echo "$(appstore_config_dir)/app_store_connect.json"; }

# Config dan qiymat o'qish (key_id, issuer_id, key_path)
# jq talab qilmaydi — sodda regex bilan
appstore_config_get() {
  local key="$1"
  local file
  file=$(appstore_config_file)
  [ ! -f "$file" ] && return 1
  grep -E "\"${key}\"" "$file" | head -1 \
    | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# Joriy konfiguratsiyani ko'rsatish (sezgir ma'lumotlar yashirilgan)
show_appstore_config() {
  local kid iid kp
  kid=$(appstore_config_get "key_id")
  iid=$(appstore_config_get "issuer_id")
  kp=$(appstore_config_get "key_path")

  echo
  echo -e "  ${BOLD}╭─ App Store Connect API ───────────────────────╮${NC}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-12s${NC} ${YELLOW}%s${NC}\n" "Key ID"    "${kid}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-12s${NC} ${YELLOW}%s…${NC}\n" "Issuer ID" "${iid:0:8}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-12s${NC} ${YELLOW}%s${NC}\n" "Key path"  "${kp}"
  echo -e "  ${BOLD}╰────────────────────────────────────────────────╯${NC}"
}

# Interaktiv sozlash — yangi API Key kiritish
setup_appstore_credentials() {
  step "App Store Connect API Key sozlash"
  info "App Store Connect → Users and Access → Integrations → API Keys'da yarating"
  info "'.p8' faylni yuklab olib, xavfsiz joyga saqlang (faqat bir marta yuklanadi!)"
  echo

  local key_id issuer_id key_path default_path
  read -p "    Key ID (masalan AB12CD34): " key_id
  if [ -z "$key_id" ]; then
    err "Key ID bo'sh bo'lishi mumkin emas"
    return 1
  fi

  read -p "    Issuer ID (UUID format, masalan 12345678-1234-...): " issuer_id
  if [ -z "$issuer_id" ]; then
    err "Issuer ID bo'sh bo'lishi mumkin emas"
    return 1
  fi

  default_path="${HOME}/.appstoreconnect/private_keys/AuthKey_${key_id}.p8"
  read -p "    .p8 fayl yo'li [${default_path}]: " key_path
  key_path="${key_path:-$default_path}"

  if [ ! -f "$key_path" ]; then
    warn ".p8 fayl topilmadi: $key_path"
    info "Faylni quyidagi joyga ko'chiring (Apple konvensiyasi):"
    info "  ${default_path}"
    return 1
  fi

  # Config faylni yozish (chmod 600 — faqat egasi o'qiy oladi)
  local dir
  dir=$(appstore_config_dir)
  mkdir -p "$dir"
  chmod 700 "$dir"

  local cfg
  cfg=$(appstore_config_file)
  cat > "$cfg" <<JSON
{
  "key_id": "${key_id}",
  "issuer_id": "${issuer_id}",
  "key_path": "${key_path}"
}
JSON
  chmod 600 "$cfg"
  ok "Sozlandi: $cfg"
}

# Konfiguratsiyani ta'minlash — mavjud bo'lsa tekshiradi, yo'q bo'lsa sozlashni taklif qiladi
ensure_appstore_credentials() {
  local cfg kid iid kp
  cfg=$(appstore_config_file)

  if [ -f "$cfg" ]; then
    kid=$(appstore_config_get "key_id")
    iid=$(appstore_config_get "issuer_id")
    kp=$(appstore_config_get "key_path")

    info "Mavjud App Store Connect API sozlamasi topildi"
    show_appstore_config

    if [ ! -f "$kp" ]; then
      warn ".p8 fayl yo'qolgan: $kp"
      read -p "  Yangi sozlovni kiritamizmi? (y/n): " redo
      [[ "$redo" =~ ^[Yy]$ ]] && setup_appstore_credentials || return 1
      return 0
    fi

    echo
    read -p "  Shu sozlamalar bilan davom etamizmi? (y/n): " usecur
    if [[ ! "$usecur" =~ ^[Yy]$ ]]; then
      setup_appstore_credentials || return 1
    fi
  else
    info "App Store Connect API hali sozlanmagan"
    read -p "  Hozir sozlaymizmi? (y/n): " setup_now
    if [[ "$setup_now" =~ ^[Yy]$ ]]; then
      setup_appstore_credentials || return 1
    else
      return 1
    fi
  fi
}

# ExportOptions.plist mavjudligini ta'minlash (yo'q bo'lsa, yaratish)
ensure_export_options() {
  local plist="ios/ExportOptions.plist"

  if [ -f "$plist" ]; then
    ok "ExportOptions.plist mavjud: $plist"
    return 0
  fi

  warn "${plist} topilmadi"
  info "Bu fayl 'flutter build ipa --export-options-plist' uchun kerak"
  echo
  read -p "  Yaratib beraymi? (y/n): " create
  [[ ! "$create" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }

  local team_id
  read -p "    Apple Team ID (10 belgi, Apple Developer hisobingizdan): " team_id
  if [ -z "$team_id" ]; then
    err "Team ID bo'sh bo'lishi mumkin emas"
    return 1
  fi

  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>${team_id}</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST
  ok "Yaratildi: $plist"
  info "Agar manual signing kerak bo'lsa, signingStyle ni 'manual' ga o'zgartiring"
}

# IPA fayl yo'lini topish (build/ios/ipa/ dan)
find_latest_ipa() {
  local dir="build/ios/ipa"
  [ ! -d "$dir" ] && return 1
  # Eng yangi .ipa faylni topish (mtime bo'yicha)
  local ipa
  ipa=$(find "$dir" -maxdepth 1 -name "*.ipa" -type f 2>/dev/null \
        | head -1)
  [ -z "$ipa" ] && return 1
  echo "$ipa"
}

# xcrun altool orqali App Store Connect ga yuklash
upload_to_appstore() {
  local ipa="$1"

  step "App Store Connect ga yuklash"

  if ! command -v xcrun > /dev/null 2>&1; then
    err "xcrun topilmadi — Xcode Command Line Tools o'rnatilganmi?"
    return 1
  fi

  local kid iid
  kid=$(appstore_config_get "key_id")
  iid=$(appstore_config_get "issuer_id")

  if [ -z "$kid" ] || [ -z "$iid" ]; then
    err "App Store Connect API sozlanmagan"
    return 1
  fi

  if [ ! -f "$ipa" ]; then
    err "IPA fayl topilmadi: $ipa"
    return 1
  fi

  local size_kb
  size_kb=$(du -k "$ipa" | cut -f1)
  info "IPA:    $ipa ($((size_kb / 1024)) MB)"
  info "Key ID: $kid"
  info "Jarayon 5-30 daqiqa davom etishi mumkin. Ulanish uzilmasligi muhim."
  echo

  # altool sahna ortida API Key faylini ~/.appstoreconnect/private_keys/ dan topadi
  # (yoki ./private_keys/, yoki shunga o'xshash yo'llardan)
  if xcrun altool --upload-app \
       --type ios \
       --file "$ipa" \
       --apiKey "$kid" \
       --apiIssuer "$iid"; then
    echo
    ok "Muvaffaqiyatli yuklandi!"
    info "TestFlight processing 10-30 daqiqa davom etadi"
    info "Status uchun email kuting yoki: https://appstoreconnect.apple.com/apps"
    return 0
  else
    echo
    err "Yuklash xato berdi — yuqorida xato matnini ko'ring"
    info "Eng keng tarqalgan sabablar:"
    info "  - Bundle ID App Store Connect'da yaratilmagan"
    info "  - Versiya raqami avval yuklangan bilan bir xil"
    info "  - Distribution certificate yaroqsiz/eskirgan"
    info "  - ExportOptions.plist'da noto'g'ri Team ID"
    return 1
  fi
}

# ─── Validatsiya ──────────────────────────────────────────
if [ ! -f "pubspec.yaml" ]; then
  err "pubspec.yaml topilmadi. Skript Flutter loyihasi ildizidan ishga tushishi kerak."
  exit 1
fi

if ! command -v flutter &> /dev/null; then
  err "Flutter o'rnatilmagan yoki PATH da yo'q."
  exit 1
fi

PROJECT_NAME=$(awk -F: '/^name:/{v=$2; sub(/#.*/,"",v); gsub(/[" ]/,"",v); print v; exit}' pubspec.yaml)
banner "Flutter Build Tool — ${PROJECT_NAME}"

# ─── 1. Hozirgi versiyalarni o'qish ───────────────────────
step "Hozirgi versiyalar o'qilmoqda"

PUBSPEC_LINE=$(awk '/^version:/{v=$0; sub(/^version:[[:space:]]*/,"",v); sub(/#.*/,"",v); gsub(/[" ]/,"",v); print v; exit}' pubspec.yaml)
PUBSPEC_NAME="${PUBSPEC_LINE%+*}"
PUBSPEC_BUILD="${PUBSPEC_LINE#*+}"
[ "$PUBSPEC_NAME" = "$PUBSPEC_BUILD" ] && PUBSPEC_BUILD="1"

# iOS — agar Flutter referencesidan foydalansa, pubspec qiymatini ko'rsatadi
IOS_PROJECT="ios/Runner.xcodeproj/project.pbxproj"
IOS_VERSION="$PUBSPEC_NAME"
IOS_BUILD="$PUBSPEC_BUILD"
IOS_USES_FLUTTER_REF=true

if [ -f "$IOS_PROJECT" ]; then
  iv=$(grep -m 1 "MARKETING_VERSION" "$IOS_PROJECT" 2>/dev/null | sed 's/.*= *//; s/;//; s/[" ]//g' || true)
  ib=$(grep -m 1 "CURRENT_PROJECT_VERSION" "$IOS_PROJECT" 2>/dev/null | sed 's/.*= *//; s/;//; s/[" ]//g' || true)
  if [ -n "$iv" ] && [[ "$iv" != *"FLUTTER_BUILD_NAME"* ]]; then
    IOS_VERSION="$iv"
    IOS_USES_FLUTTER_REF=false
  fi
  if [ -n "$ib" ] && [[ "$ib" != *"FLUTTER_BUILD_NUMBER"* ]]; then
    IOS_BUILD="$ib"
    IOS_USES_FLUTTER_REF=false
  fi
fi

# Android — ikkala build.gradle va build.gradle.kts ni qo'llab-quvvatlaydi
ANDROID_GRADLE=""
[ -f "android/app/build.gradle.kts" ] && ANDROID_GRADLE="android/app/build.gradle.kts"
[ -z "$ANDROID_GRADLE" ] && [ -f "android/app/build.gradle" ] && ANDROID_GRADLE="android/app/build.gradle"

ANDROID_VERSION="$PUBSPEC_NAME"
ANDROID_BUILD="$PUBSPEC_BUILD"
ANDROID_USES_FLUTTER_REF=true

if [ -n "$ANDROID_GRADLE" ]; then
  av=$(grep "versionName" "$ANDROID_GRADLE" 2>/dev/null | head -1 || true)
  ab=$(grep "versionCode" "$ANDROID_GRADLE" 2>/dev/null | head -1 || true)
  if [ -n "$av" ] && [[ "$av" != *"flutter"* ]] && [[ "$av" != *"localProperties"* ]]; then
    parsed=$(echo "$av" | sed -E 's/.*versionName[[:space:]]*=?[[:space:]]*//; s/[",]//g' | tr -d ' ')
    [ -n "$parsed" ] && { ANDROID_VERSION="$parsed"; ANDROID_USES_FLUTTER_REF=false; }
  fi
  if [ -n "$ab" ] && [[ "$ab" != *"flutter"* ]] && [[ "$ab" != *"localProperties"* ]]; then
    parsed=$(echo "$ab" | sed -E 's/.*versionCode[[:space:]]*=?[[:space:]]*//; s/[",]//g' | tr -d ' ')
    [ -n "$parsed" ] && { ANDROID_BUILD="$parsed"; ANDROID_USES_FLUTTER_REF=false; }
  fi
fi

echo
echo -e "  ${BOLD}╭─ Topilgan versiyalar ──────────────────────────╮${NC}"
printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "pubspec.yaml"        "${PUBSPEC_NAME}+${PUBSPEC_BUILD}"
printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "iOS version"         "${IOS_VERSION}"
printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "iOS build number"    "${IOS_BUILD}"
printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "Android versionName" "${ANDROID_VERSION}"
printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "Android versionCode" "${ANDROID_BUILD}"
echo -e "  ${BOLD}╰──────────────────────────────────────────────────╯${NC}"

# ─── 2. Tanlovlar (yagona checkbox menyu) ─────────────────
arrow_checkbox "Tanlovlar (Debug = Production yoqilmasa)" \
  "Production" \
  "Android" \
  "iOS" \
  "flutter clean" \
  "flutter pub get" \
  "App Store Connect upload (Production + iOS bilan)"

IS_PROD="${CHECKBOX_RESULT[0]}"
BUILD_ANDROID="${CHECKBOX_RESULT[1]}"
BUILD_IOS="${CHECKBOX_RESULT[2]}"
DO_CLEAN="${CHECKBOX_RESULT[3]}"
DO_PUBGET="${CHECKBOX_RESULT[4]}"
DO_APPSTORE_UPLOAD="${CHECKBOX_RESULT[5]}"

if $IS_PROD; then MODE_LABEL="PRODUCTION"; else MODE_LABEL="DEBUG"; fi

if ! $BUILD_ANDROID && ! $BUILD_IOS; then
  err "Hech qaysi platforma tanlanmadi"
  exit 1
fi

if $BUILD_IOS && [ "$(uname)" != "Darwin" ]; then
  err "iOS build faqat macOS da ishlaydi"
  exit 1
fi

if $DO_APPSTORE_UPLOAD; then
  if ! $IS_PROD; then
    err "App Store upload faqat Production rejimda ishlaydi"
    exit 1
  fi
  if ! $BUILD_IOS; then
    err "App Store upload uchun iOS tanlanishi kerak"
    exit 1
  fi
fi

# ─── 2b. Android format tanlovi ───────────────────────────
BUILD_AAB=false
BUILD_APK=false
if $BUILD_ANDROID; then
  arrow_checkbox "Android format (AAB = Play Store, APK = sideload)" \
    "AAB" \
    "APK"
  BUILD_AAB="${CHECKBOX_RESULT[0]}"
  BUILD_APK="${CHECKBOX_RESULT[1]}"

  if ! $BUILD_AAB && ! $BUILD_APK; then
    err "Android tanlandi, lekin format tanlanmadi (AAB yoki APK)"
    exit 1
  fi
fi

# Tanlangan platformalarni inson o'qiy oladigan satrga to'plash
selected=""
if $BUILD_ANDROID; then
  if $BUILD_AAB && $BUILD_APK; then
    android_fmt="AAB+APK"
  elif $BUILD_AAB; then
    android_fmt="AAB"
  else
    android_fmt="APK"
  fi
  selected="${selected}Android(${android_fmt}) "
fi
$BUILD_IOS && selected="${selected}iOS"

ok "Rejim: ${MAGENTA}${MODE_LABEL}${NC}  |  Platformalar: ${selected}"
$DO_CLEAN && ok "flutter clean: ${GREEN}yoqilgan${NC}" || info "flutter clean: o'tkazib yuboriladi"
$DO_PUBGET && ok "flutter pub get: ${GREEN}yoqilgan${NC}" || info "flutter pub get: o'tkazib yuboriladi"

# ─── 4. Yangi versiyalar (qo'lda kiritish) ────────────────
step "Yangi versiyalarni kiriting"
info "Enter — hozirgi qiymatni saqlaydi  |  + — oxirgi raqamni +1 ga oshirish"
echo

read -p "    pubspec.yaml versiya  [${PUBSPEC_NAME}]: " new_pname
read -p "    pubspec.yaml build #  [${PUBSPEC_BUILD}]: " new_pbuild
new_pname=$(resolve_version_input "$new_pname" "$PUBSPEC_NAME")
new_pbuild=$(resolve_version_input "$new_pbuild" "$PUBSPEC_BUILD")

new_iversion=""; new_ibuild=""
if $BUILD_IOS; then
  echo
  read -p "    iOS versiya           [${IOS_VERSION}]: " new_iversion
  read -p "    iOS build number      [${IOS_BUILD}]: " new_ibuild
  new_iversion=$(resolve_version_input "$new_iversion" "$IOS_VERSION")
  new_ibuild=$(resolve_version_input "$new_ibuild" "$IOS_BUILD")
fi

new_aversion=""; new_abuild=""
if $BUILD_ANDROID; then
  echo
  read -p "    Android versionName   [${ANDROID_VERSION}]: " new_aversion
  read -p "    Android versionCode   [${ANDROID_BUILD}]: " new_abuild
  new_aversion=$(resolve_version_input "$new_aversion" "$ANDROID_VERSION")
  new_abuild=$(resolve_version_input "$new_abuild" "$ANDROID_BUILD")
fi

# ─── 5. Tasdiqlash ────────────────────────────────────────
step "Tasdiqlash"
echo
echo -e "  ${BOLD}Loyiha:${NC}        ${PROJECT_NAME}"
echo -e "  ${BOLD}Rejim:${NC}         ${MAGENTA}${MODE_LABEL}${NC}"
echo -e "  ${BOLD}Platformalar:${NC}  ${selected}"
echo
echo -e "  ${BOLD}Versiyalar (eski → yangi):${NC}"
echo -e "    pubspec.yaml  : ${YELLOW}${PUBSPEC_NAME}+${PUBSPEC_BUILD}${NC} → ${GREEN}${new_pname}+${new_pbuild}${NC}"
$BUILD_IOS     && echo -e "    iOS           : ${YELLOW}${IOS_VERSION} (${IOS_BUILD})${NC} → ${GREEN}${new_iversion} (${new_ibuild})${NC}"
$BUILD_ANDROID && echo -e "    Android       : ${YELLOW}${ANDROID_VERSION} (${ANDROID_BUILD})${NC} → ${GREEN}${new_aversion} (${new_abuild})${NC}"
echo
read -p "  Davom etamizmi? (y/n): " confirm
[[ ! "${confirm}" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; exit 0; }

# ─── 6. Fayllarni yangilash (faqat o'zgargan bo'lsa) ──────
step "Versiya fayllari tekshirilmoqda"

if [ "$new_pname" != "$PUBSPEC_NAME" ] || [ "$new_pbuild" != "$PUBSPEC_BUILD" ]; then
  update_pubspec_version "$new_pname" "$new_pbuild"
  ok "pubspec.yaml yangilandi: ${new_pname}+${new_pbuild}"
else
  info "pubspec.yaml o'zgarmadi: ${PUBSPEC_NAME}+${PUBSPEC_BUILD}"
fi

if $BUILD_IOS && [ -f "$IOS_PROJECT" ]; then
  if $IOS_USES_FLUTTER_REF; then
    info "iOS Flutter reference larini ishlatadi → pubspec.yaml dan olinadi"
  elif [ "$new_iversion" != "$IOS_VERSION" ] || [ "$new_ibuild" != "$IOS_BUILD" ]; then
    update_ios_version "$IOS_PROJECT" "$new_iversion" "$new_ibuild"
    ok "iOS project.pbxproj yangilandi: ${new_iversion} (${new_ibuild})"
  else
    info "iOS project.pbxproj o'zgarmadi: ${IOS_VERSION} (${IOS_BUILD})"
  fi
fi

if $BUILD_ANDROID && [ -n "$ANDROID_GRADLE" ]; then
  if $ANDROID_USES_FLUTTER_REF; then
    info "Android Flutter reference larini ishlatadi → pubspec.yaml dan olinadi"
  elif [ "$new_aversion" != "$ANDROID_VERSION" ] || [ "$new_abuild" != "$ANDROID_BUILD" ]; then
    update_android_version "$ANDROID_GRADLE" "$new_aversion" "$new_abuild"
    ok "${ANDROID_GRADLE} yangilandi: ${new_aversion} (${new_abuild})"
  else
    info "${ANDROID_GRADLE} o'zgarmadi: ${ANDROID_VERSION} (${ANDROID_BUILD})"
  fi
fi

# ─── 7. Production tekshiruvi (Android signing) ───────────
if $IS_PROD && $BUILD_ANDROID; then
  setup_android_signing
fi

# ─── 7b. App Store upload pre-check (Production + iOS) ────
if $DO_APPSTORE_UPLOAD; then
  step "App Store Connect upload sozlamalarini tekshirish"
  ensure_appstore_credentials || { err "App Store Connect sozlanmadi"; exit 1; }
  ensure_export_options || { err "ExportOptions.plist sozlanmadi"; exit 1; }
fi

# ─── 8. Flutter tayyorlash ────────────────────────────────
if $DO_CLEAN || $DO_PUBGET; then
  step "Loyiha tayyorlanmoqda"
  if $DO_CLEAN; then
    info "flutter clean"
    flutter clean > /dev/null 2>&1
    ok "flutter clean bajarildi"
  fi
  if $DO_PUBGET; then
    info "flutter pub get"
    flutter pub get
    ok "flutter pub get bajarildi"
  fi
fi

# ─── 9. Build ─────────────────────────────────────────────
BUILD_PATHS=()

if $BUILD_ANDROID; then
  step "Android build (${MODE_LABEL})"
  if $IS_PROD; then
    if $BUILD_AAB; then
      info "flutter build appbundle --release"
      flutter build appbundle --release
      BUILD_PATHS+=("$(pwd)/build/app/outputs/bundle/release")
    fi
    if $BUILD_APK; then
      info "flutter build apk --release"
      flutter build apk --release
      BUILD_PATHS+=("$(pwd)/build/app/outputs/flutter-apk")
    fi
  else
    if $BUILD_AAB; then
      info "flutter build appbundle --debug"
      flutter build appbundle --debug
      BUILD_PATHS+=("$(pwd)/build/app/outputs/bundle/debug")
    fi
    if $BUILD_APK; then
      info "flutter build apk --debug"
      flutter build apk --debug
      BUILD_PATHS+=("$(pwd)/build/app/outputs/flutter-apk")
    fi
  fi
  ok "Android build muvaffaqiyatli"
fi

if $BUILD_IOS; then
  step "iOS build (${MODE_LABEL})"
  if $IS_PROD; then
    if $DO_APPSTORE_UPLOAD; then
      info "flutter build ipa --release --export-options-plist ios/ExportOptions.plist"
      flutter build ipa --release --export-options-plist ios/ExportOptions.plist
    else
      info "flutter build ipa --release"
      flutter build ipa --release
    fi
    BUILD_PATHS+=("$(pwd)/build/ios/ipa")
  else
    info "flutter build ios --debug --no-codesign"
    flutter build ios --debug --no-codesign
    BUILD_PATHS+=("$(pwd)/build/ios/iphoneos")
  fi
  ok "iOS build muvaffaqiyatli"
fi

# ─── 9b. App Store Connect ga upload ──────────────────────
if $DO_APPSTORE_UPLOAD; then
  ipa_file=$(find_latest_ipa) || {
    err "IPA fayl topilmadi build/ios/ipa/ ichida"
    exit 1
  }
  upload_to_appstore "$ipa_file" || warn "Upload xato berdi — IPA fayl saqlangan: $ipa_file"
fi

# ─── 10. Build natijalarini ochish (macOS/Linux/WSL) ──────
step "Build natijalarini ochish"
for path in "${BUILD_PATHS[@]}"; do
  open_file "$path" || true
done

banner "Hammasi tayyor! Versiya: ${new_pname}+${new_pbuild}"
