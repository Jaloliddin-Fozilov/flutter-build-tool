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
SCRIPT_VERSION="1.6.0"
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

# open_url <url>
#   Brauzerda URL ochish — open_file bilan bir xil platform fallback
open_url() {
  local url="$1"
  if command -v open > /dev/null 2>&1; then
    open "$url" > /dev/null 2>&1 && return 0
  fi
  if command -v xdg-open > /dev/null 2>&1; then
    (xdg-open "$url" > /dev/null 2>&1 &) && return 0
  fi
  if command -v explorer.exe > /dev/null 2>&1; then
    explorer.exe "$url" > /dev/null 2>&1 && return 0
  fi
  info "Brauzerda oching: $url"
  return 1
}

# Clipboard'dan o'qish (macOS pbpaste, Linux xclip/xsel)
read_clipboard() {
  if command -v pbpaste > /dev/null 2>&1; then
    pbpaste 2>/dev/null
  elif command -v xclip > /dev/null 2>&1; then
    xclip -o -selection clipboard 2>/dev/null
  elif command -v xsel > /dev/null 2>&1; then
    xsel -b 2>/dev/null
  fi
}

# Downloads papkasida yangi yuklangan fayl uchun kutish (polling + spinner)
# wait_for_download <pattern> <marker_file> [timeout_sec]
#   pattern: find -name argumenti (masalan "AuthKey_*.p8")
#   marker_file: shu vaqtdan keyin yaratilgan fayllarni qidiradi
#   timeout: default 60s
# Natija stdout'ga, diagnostika stderr ga.
wait_for_download() {
  local pattern="$1" marker="$2" timeout="${3:-60}"
  local downloads="${HOME}/Downloads"
  local elapsed=0
  local spinner_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local spinner_i=0

  if [ ! -d "$downloads" ]; then
    err "Downloads papkasi topilmadi: $downloads" >&2
    return 1
  fi

  while [ "$elapsed" -lt "$timeout" ]; do
    local found
    found=$(find "$downloads" -maxdepth 1 -name "$pattern" \
      -newer "$marker" 2>/dev/null | head -1)

    if [ -n "$found" ]; then
      printf "\r  ${GREEN}✓${NC} Topildi: %s%30s\n" "$found" " " >&2
      printf '%s\n' "$found"
      return 0
    fi

    local char="${spinner_chars:$spinner_i:1}"
    printf "\r  ${CYAN}%s${NC} Yuklab olishni kutmoqda... (%ds / %ds)" \
      "$char" "$elapsed" "$timeout" >&2
    spinner_i=$(( (spinner_i + 1) % 10 ))

    sleep 1
    elapsed=$((elapsed + 1))
  done

  echo >&2
  warn "Timeout (${timeout}s) — fayl Downloads'da topilmadi" >&2
  return 1
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

  local script_dir
  script_dir=$(dirname "$self")

  # Yozish ruxsatini tekshirish — /usr/local/bin/ kabi tizim joylarida
  # oddiy foydalanuvchi yozolmaydi. Bunday holda sudo bilan davom etamiz.
  local needs_sudo=false
  if [ ! -w "$script_dir" ] || [ ! -w "$self" ]; then
    needs_sudo=true
  fi

  # Yuklab olish uchun foydalanuvchi yozadigan vaqtinchalik joy
  local tmp
  if $needs_sudo; then
    tmp="/tmp/flutter_build.new.$$"
  else
    tmp="${self}.new.$$"
  fi

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

  if $needs_sudo; then
    echo
    warn "Skript tizim direktoriyasida joylashgan: $self"
    info "Ushbu joyga yozish uchun sudo (administrator paroli) kerak"
    echo
    if ! command -v sudo > /dev/null 2>&1; then
      err "'sudo' topilmadi — qo'lda yangilang:"
      echo -e "    ${BOLD}cp $tmp $self && chmod +x $self${NC}  (root sifatida)"
      return 1
    fi

    info "Sudo bilan o'rnatamiz (parol so'ralishi mumkin)..."
    if sudo cp "$self" "${self}.bak.$(date +%s)" \
       && sudo cp "$tmp" "$self" \
       && sudo chmod +x "$self"; then
      rm -f "$tmp"
      ok "Yangilandi! Skriptni qayta ishga tushiring:"
      echo "    $self"
      exit 0
    else
      err "Sudo bilan o'rnatish xato berdi"
      info "Qo'lda yangilang:"
      echo -e "    ${BOLD}sudo cp $tmp $self && sudo chmod +x $self${NC}"
      info "Yoki to'g'ridan-to'g'ri yuklab oling:"
      echo -e "    ${BOLD}sudo curl -fsSL ${SCRIPT_RAW_URL} -o $self && sudo chmod +x $self${NC}"
      return 1
    fi
  fi

  # Normal flow — yozish ruxsati mavjud
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

# Config yo'llari — v1.6.0 dan boshlab Named Accounts (AWS profile patterni)
# Loyiha: ~/.config/flutter-build-tool/appstore/<bundle>.json → account havolasi
# Akkaunt: ~/.config/flutter-build-tool/accounts/appstore/<account>.json → API Key
appstore_config_dir()    { echo "${HOME}/.config/flutter-build-tool"; }
appstore_projects_dir()  { echo "$(appstore_config_dir)/appstore"; }
appstore_accounts_dir()  { echo "$(appstore_config_dir)/accounts/appstore"; }
appstore_legacy_config() { echo "$(appstore_config_dir)/app_store_connect.json"; }

# Per-bundle config fayli (bundle_id bo'yicha)
appstore_project_config_file() {
  local bundle_id="$1"
  echo "$(appstore_projects_dir)/${bundle_id}.json"
}

# iOS bundle id ni project.pbxproj dan aniqlash
detect_ios_bundle_id() {
  local pbxproj="ios/Runner.xcodeproj/project.pbxproj"
  [ ! -f "$pbxproj" ] && return 1
  # PRODUCT_BUNDLE_IDENTIFIER birinchi uchragan Release config'dan
  grep "PRODUCT_BUNDLE_IDENTIFIER" "$pbxproj" 2>/dev/null \
    | grep -v "RunnerTests\|FLUTTER_BUILD" \
    | head -1 \
    | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*([^;]+);.*/\1/' \
    | tr -d '"' \
    | tr -d ' '
}

# Per-bundle qiymatni o'qish
appstore_project_config_get() {
  local bundle_id="$1" key="$2"
  local file
  file=$(appstore_project_config_file "$bundle_id")
  [ ! -f "$file" ] && return 1
  grep -E "\"${key}\"" "$file" | head -1 \
    | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# Per-bundle saqlash (v1.6.0: account nomi havola)
appstore_project_config_save() {
  local bundle_id="$1" account="$2"
  local file dir
  file=$(appstore_project_config_file "$bundle_id")
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"
  cat > "$file" <<JSON
{
  "bundle_id": "${bundle_id}",
  "account": "${account}"
}
JSON
  chmod 600 "$file"
}

# ─── Akkaunt funksiyalari ───────────────────────────────

appstore_account_file()   { echo "$(appstore_accounts_dir)/${1}.json"; }
appstore_account_exists() { [ -f "$(appstore_account_file "$1")" ]; }

appstore_account_get() {
  local name="$1" key="$2"
  local file
  file=$(appstore_account_file "$name")
  [ ! -f "$file" ] && return 1
  grep -E "\"${key}\"" "$file" | head -1 \
    | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

appstore_account_save() {
  local name="$1" key_id="$2" issuer_id="$3" key_path="$4"
  local file dir
  file=$(appstore_account_file "$name")
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"
  cat > "$file" <<JSON
{
  "name": "${name}",
  "key_id": "${key_id}",
  "issuer_id": "${issuer_id}",
  "key_path": "${key_path}"
}
JSON
  chmod 600 "$file"
}

# Akkaunt nomini Key ID dan derive qilish (Apple Key ID o'zi unique)
appstore_derive_account_name() {
  local key_id="$1"
  sanitize_account_name "${key_id}"
}

appstore_list_accounts() {
  local dir
  dir=$(appstore_accounts_dir)
  [ ! -d "$dir" ] && return 0
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    basename "$f" .json
  done
}

# ─── Migratsiyalar ──────────────────────────────────────

# v1.4.x yagona-fayl formatdan v1.6.0 ga
appstore_migrate_legacy_config() {
  local old
  old=$(appstore_legacy_config)
  [ ! -f "$old" ] && return 0

  local current_bundle
  current_bundle=$(detect_ios_bundle_id 2>/dev/null || echo "")

  local kid iid kp
  kid=$(grep '"key_id"' "$old" | sed -E 's/.*"key_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
  iid=$(grep '"issuer_id"' "$old" | sed -E 's/.*"issuer_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
  kp=$(grep '"key_path"' "$old" | sed -E 's/.*"key_path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)

  if [ -n "$kid" ] && [ -n "$iid" ]; then
    local account
    account=$(appstore_derive_account_name "$kid")
    appstore_account_exists "$account" || appstore_account_save "$account" "$kid" "$iid" "$kp"

    if [ -n "$current_bundle" ]; then
      local new
      new=$(appstore_project_config_file "$current_bundle")
      [ ! -f "$new" ] && appstore_project_config_save "$current_bundle" "$account"
      info "v1.4.x sozlamasi yangi formatga ko'chirildi: ${current_bundle} → ${account}"
    fi
  fi

  mv "$old" "${old}.legacy.$(date +%s)" 2>/dev/null || true
}

# v1.5.0 (key_id+issuer_id+key_path bevosita) → v1.6.0 (account havolasi)
appstore_migrate_v15_to_v16() {
  local dir
  dir=$(appstore_projects_dir)
  [ ! -d "$dir" ] && return 0

  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    grep -q '"key_id"' "$f" 2>/dev/null || continue
    grep -q '"account"' "$f" 2>/dev/null && continue

    local bundle kid iid kp
    bundle=$(grep '"bundle_id"' "$f" | sed -E 's/.*"bundle_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    kid=$(grep '"key_id"' "$f" | sed -E 's/.*"key_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    iid=$(grep '"issuer_id"' "$f" | sed -E 's/.*"issuer_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    kp=$(grep '"key_path"' "$f" | sed -E 's/.*"key_path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    [ -z "$bundle" ] && continue
    [ -z "$kid" ] && continue

    cp "$f" "${f}.v15.$(date +%s)" 2>/dev/null || true

    local account
    account=$(appstore_derive_account_name "$kid")
    appstore_account_exists "$account" || appstore_account_save "$account" "$kid" "$iid" "$kp"

    appstore_project_config_save "$bundle" "$account"
    info "v1.5.0 → v1.6.0: ${bundle} → akkaunt '${account}'"
  done
}

# Joriy bundle uchun konfiguratsiyani ko'rsatish
# ─── v1.6.0 Account-asosli sozlash flow (iOS) ──────────

# Wizard yordamida .p8 ni topish va Key ID + Issuer ID ni yig'ish.
# Stdout natija: 'key_id:issuer_id:key_path' formatida tuple.
# Stderr: diagnostik xabarlar.
appstore_wizard_collect_credentials() {
  info "─ [1/3] App Store Connect API Key yarating ───────────" >&2
  info "Brauzerda App Store Connect ochiladi..." >&2
  info "  1) ${BOLD}Generate API Key${NC}" >&2
  info "  2) Name: ${BOLD}flutter-build-deploy${NC}" >&2
  info "  3) Access: ${BOLD}App Manager${NC}" >&2
  info "  4) ${BOLD}Generate${NC} → '.p8' fayl avtomatik yuklanadi" >&2
  echo >&2

  local marker="/tmp/.fbt_appstore.$$"
  touch "$marker"
  open_url "https://appstoreconnect.apple.com/access/integrations/api" >&2
  echo >&2

  info "─ [2/3] .p8 faylni topyapmiz ─────────────────────────" >&2
  local p8_file
  p8_file=$(wait_for_download "AuthKey_*.p8" "$marker" 90 || true)
  rm -f "$marker"

  if [ -z "$p8_file" ] || [ ! -f "$p8_file" ]; then
    warn ".p8 fayl avtomatik topilmadi" >&2
    read -p "  Fayl yo'lini qo'lda kiriting (yoki Enter — bekor): " p8_file
    p8_file="${p8_file/#\~/$HOME}"
    [ -z "$p8_file" ] && { warn "Bekor qilindi" >&2; return 1; }
    [ ! -f "$p8_file" ] && { err "Fayl topilmadi: $p8_file" >&2; return 1; }
  fi

  local key_id
  key_id=$(basename "$p8_file" | sed -E 's/^AuthKey_(.*)\.p8$/\1/')
  ok "Key ID aniqlandi: ${BOLD}${key_id}${NC}" >&2

  # Apple konvensiyasiga ko'chirish
  local target_dir="${HOME}/.appstoreconnect/private_keys"
  mkdir -p "$target_dir"
  chmod 700 "$target_dir"
  local target_path="${target_dir}/$(basename "$p8_file")"
  if [ "$p8_file" != "$target_path" ]; then
    mv "$p8_file" "$target_path"
    chmod 600 "$target_path"
    ok "Apple konvensiyasi yo'liga ko'chirildi: $target_path" >&2
  fi

  # [3/3] Issuer ID
  echo >&2
  info "─ [3/3] Issuer ID ─────────────────────────────────────" >&2
  info "Yuqorida ochilgan sahifaning yuqori chap qismida 'Issuer ID' bor" >&2
  info "UUID format: 12345678-1234-1234-1234-123456789abc" >&2
  echo >&2

  local issuer_id clip
  clip=$(read_clipboard)
  if [[ "$clip" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    info "Clipboard'da UUID topildi: ${YELLOW}${clip}${NC}" >&2
    read -p "  Shu UUID ni Issuer ID sifatida ishlatamizmi? (y/n) [y]: " confirm
    [[ ! "$confirm" =~ ^[Nn]$ ]] && issuer_id="$clip"
  fi
  [ -z "$issuer_id" ] && read -p "    Issuer ID: " issuer_id

  if [[ ! "$issuer_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    warn "UUID formatga to'g'ri kelmadi — davom etamiz" >&2
  fi

  # Natija
  printf '%s:%s:%s\n' "$key_id" "$issuer_id" "$target_path"
}

# Yangi App Store akkaunti qo'shish — wizard yoki qo'lda
appstore_add_new_account() {
  local bundle="$1"  # ixtiyoriy

  step "Yangi App Store akkaunti qo'shish"
  echo
  echo -e "  ${BOLD}Sozlash usulini tanlang:${NC}"
  echo -e "    ${CYAN}1${NC}) Avtomatik wizard ${GREEN}(tavsiya)${NC} — brauzer ochiladi, .p8 auto-detect"
  echo -e "    ${CYAN}2${NC}) Qo'lda kiritish — Key ID, Issuer ID, .p8 yo'l"
  echo
  read -p "  Tanlang [1-2]: " choice

  local key_id issuer_id key_path tuple
  case "$choice" in
    1|"")
      tuple=$(appstore_wizard_collect_credentials) || return 1
      key_id="${tuple%%:*}"
      local rest="${tuple#*:}"
      issuer_id="${rest%%:*}"
      key_path="${rest#*:}"
      ;;
    2)
      read -p "    Key ID (masalan AB12CD34): " key_id
      [ -z "$key_id" ] && { err "Key ID bo'sh"; return 1; }
      read -p "    Issuer ID (UUID): " issuer_id
      [ -z "$issuer_id" ] && { err "Issuer ID bo'sh"; return 1; }
      local default_path="${HOME}/.appstoreconnect/private_keys/AuthKey_${key_id}.p8"
      read -p "    .p8 fayl yo'li [${default_path}]: " key_path
      key_path="${key_path:-$default_path}"
      [ ! -f "$key_path" ] && { err ".p8 topilmadi: $key_path"; return 1; }
      ;;
    *)
      return 1
      ;;
  esac

  # Akkaunt nomi
  echo
  local default_name name
  default_name=$(appstore_derive_account_name "$key_id")
  echo -e "  ${BOLD}Akkaunt nomi${NC} — bu credentials uchun foydalanuvchi-do'st label"
  info "Misol: 'personal', 'work-apple', 'client-xyz'"
  read -p "  Akkaunt nomi [${default_name}]: " name
  name="${name:-$default_name}"
  name=$(sanitize_account_name "$name")

  if appstore_account_exists "$name"; then
    warn "Akkaunt '${name}' allaqachon mavjud"
    read -p "  Qayta yozamizmi? (y/n) [n]: " replace
    [[ ! "$replace" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }
  fi

  appstore_account_save "$name" "$key_id" "$issuer_id" "$key_path"
  ok "Akkaunt qo'shildi: ${BOLD}${name}${NC}"

  # Loyihaga bog'lash
  if [ -n "$bundle" ]; then
    appstore_project_config_save "$bundle" "$name"
    ok "Loyiha bog'landi: ${bundle} → '${name}'"
  fi
}

# Akkaunt picker
appstore_pick_account_for_project() {
  local bundle="$1"

  local accounts=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && accounts+=("$name")
  done < <(appstore_list_accounts)

  if [ ${#accounts[@]} -eq 0 ]; then
    info "Hali App Store akkaunti qo'shilmagan"
    appstore_add_new_account "$bundle"
    return $?
  fi

  echo
  echo -e "  ${BOLD}╭─ Mavjud App Store akkauntlari ──────────────────────${NC}"
  local i=1 acc_name kid iid
  for acc_name in "${accounts[@]}"; do
    kid=$(appstore_account_get "$acc_name" "key_id")
    iid=$(appstore_account_get "$acc_name" "issuer_id")
    printf "  ${BOLD}│${NC}  ${CYAN}%d${NC}) ${BOLD}%-22s${NC} Key %s / Issuer %s…\n" \
      "$i" "$acc_name" "$kid" "${iid:0:8}"
    i=$((i + 1))
  done
  echo -e "  ${BOLD}├──────────────────────────────────────────────────────${NC}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%d${NC}) ${GREEN}➕ Yangi akkaunt qo'shish${NC}\n" "$i"
  local cancel_i=$((i + 1))
  printf  "  ${BOLD}│${NC}  ${CYAN}%d${NC}) Bekor qilish\n" "$cancel_i"
  echo -e "  ${BOLD}╰──────────────────────────────────────────────────────${NC}"
  echo

  read -p "  Bundle '${bundle}' uchun akkaunt tanlang [1-${cancel_i}]: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    warn "Bekor qilindi"
    return 1
  fi

  if [ "$choice" -ge 1 ] && [ "$choice" -le "${#accounts[@]}" ]; then
    local picked="${accounts[$((choice - 1))]}"
    info "Akkaunt tanlandi: ${BOLD}${picked}${NC}"
    appstore_project_config_save "$bundle" "$picked"
    ok "Bog'landi: ${bundle} → '${picked}'"
    return 0
  fi

  if [ "$choice" -eq "$i" ]; then
    appstore_add_new_account "$bundle"
    return $?
  fi

  warn "Bekor qilindi"
  return 1
}

# Backwards-compat shim'lar
setup_appstore_credentials() { appstore_add_new_account "$1"; }
appstore_setup_wizard() { appstore_add_new_account "$1"; }

ensure_appstore_credentials() {
  appstore_migrate_legacy_config
  appstore_migrate_v15_to_v16

  local current_bundle
  current_bundle=$(detect_ios_bundle_id)
  if [ -z "$current_bundle" ]; then
    err "iOS bundle id aniqlanmadi (ios/Runner.xcodeproj/project.pbxproj)"
    return 1
  fi

  local cfg
  cfg=$(appstore_project_config_file "$current_bundle")

  if [ -f "$cfg" ]; then
    local account
    account=$(appstore_project_config_get "$current_bundle" "account")

    if [ -z "$account" ]; then
      warn "Loyiha config buzuq (akkaunt yo'q), qayta sozlaymiz"
      rm -f "$cfg"
    elif ! appstore_account_exists "$account"; then
      warn "Akkaunt '${account}' topilmadi — qayta tanlash kerak"
      appstore_pick_account_for_project "$current_bundle" || return 1
      return 0
    else
      local kid kp
      kid=$(appstore_account_get "$account" "key_id")
      kp=$(appstore_account_get "$account" "key_path")
      if [ ! -f "$kp" ]; then
        warn "Akkaunt '${account}' ning .p8 fayli yo'qolgan: $kp"
        appstore_add_new_account "" || return 1
        appstore_pick_account_for_project "$current_bundle" || return 1
        return 0
      fi
      ok "App Store: ${BOLD}${current_bundle}${NC} → '${BOLD}${account}${NC}' (Key ${YELLOW}${kid}${NC}) ${CYAN}(saqlangan)${NC}"
      return 0
    fi
  fi

  info "Yangi loyiha: ${BOLD}${current_bundle}${NC}"
  appstore_pick_account_for_project "$current_bundle" || return 1
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

  # Bundle → akkaunt → key resolve
  local bundle_id account kid iid
  bundle_id=$(detect_ios_bundle_id)
  if [ -z "$bundle_id" ]; then
    err "iOS bundle id aniqlanmadi"
    return 1
  fi

  account=$(appstore_project_config_get "$bundle_id" "account")
  if [ -z "$account" ]; then
    err "Bundle '${bundle_id}' uchun akkaunt belgilanmagan"
    return 1
  fi
  if ! appstore_account_exists "$account"; then
    err "Akkaunt '${account}' topilmadi"
    return 1
  fi

  kid=$(appstore_account_get "$account" "key_id")
  iid=$(appstore_account_get "$account" "issuer_id")

  if [ -z "$kid" ] || [ -z "$iid" ]; then
    err "App Store Connect API sozlanmagan (akkaunt: ${account})"
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

# ─── Android Play Store deploy yordamchi funksiyalari ─────
# Direct Google Play Developer API (curl + openssl, hech qanday Ruby/Python/Node yo'q)
# JWT RS256 signing pure bash'da, base64url encoding RFC 7515 ga muvofiq.

# Config yo'llari — v1.6.0 dan boshlab Named Accounts (AWS profile patterni)
# Loyiha: ~/.config/flutter-build-tool/play/<package>.json  → account nomiga havola
# Akkaunt: ~/.config/flutter-build-tool/accounts/play/<account>.json → SA credentials
play_config_dir()      { echo "${HOME}/.config/flutter-build-tool"; }
play_projects_dir()    { echo "$(play_config_dir)/play"; }
play_accounts_dir()    { echo "$(play_config_dir)/accounts/play"; }
play_legacy_config()   { echo "$(play_config_dir)/play_store.json"; }

# Akkaunt nomini fayl tizimiga xavfsiz qilish (faqat alnum, dash, underscore)
sanitize_account_name() {
  printf '%s' "$1" | tr -c 'a-zA-Z0-9_-' '_' | cut -c 1-64
}

# Per-project config fayli (package_name bo'yicha)
play_project_config_file() {
  local pkg="$1"
  echo "$(play_projects_dir)/${pkg}.json"
}

# Loyihaga oid qiymatni o'qish
play_project_config_get() {
  local pkg="$1" key="$2"
  local file
  file=$(play_project_config_file "$pkg")
  [ ! -f "$file" ] && return 1
  grep -E "\"${key}\"" "$file" | head -1 \
    | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# Loyiha konfiguratsiyasini saqlash (v1.6.0: account nomi orqali havola)
play_project_config_save() {
  local pkg="$1" account="$2" track="$3"
  local file dir
  file=$(play_project_config_file "$pkg")
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"
  cat > "$file" <<JSON
{
  "account": "${account}",
  "package_name": "${pkg}",
  "track": "${track}"
}
JSON
  chmod 600 "$file"
}

# ─── Akkaunt funksiyalari (v1.6.0+) ─────────────────────

# Akkaunt fayli yo'li
play_account_file() {
  local name="$1"
  echo "$(play_accounts_dir)/${name}.json"
}

# Akkaunt mavjudligini tekshirish
play_account_exists() {
  [ -f "$(play_account_file "$1")" ]
}

# Akkaunt field'ini o'qish
play_account_get() {
  local name="$1" key="$2"
  local file
  file=$(play_account_file "$name")
  [ ! -f "$file" ] && return 1
  grep -E "\"${key}\"" "$file" | head -1 \
    | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# Akkauntni saqlash — SA JSON dan client_email va project_id avtomatik o'qiladi
play_account_save() {
  local name="$1" sa_path="$2"
  local file dir client_email project_id
  file=$(play_account_file "$name")
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"

  client_email=$(sa_json_get_simple "$sa_path" "client_email")
  project_id=$(sa_json_get_simple "$sa_path" "project_id")

  cat > "$file" <<JSON
{
  "name": "${name}",
  "service_account_path": "${sa_path}",
  "client_email": "${client_email}",
  "project_id": "${project_id}"
}
JSON
  chmod 600 "$file"
}

# Akkaunt nomini SA JSON'dan derive qilish — project_id eng ma'noli
play_derive_account_name() {
  local sa_path="$1"
  local pid
  pid=$(sa_json_get_simple "$sa_path" "project_id")
  if [ -n "$pid" ]; then
    sanitize_account_name "$pid"
  else
    sanitize_account_name "$(basename "$sa_path" .json)"
  fi
}

# Barcha akkauntlar ro'yxati
play_list_accounts() {
  local dir
  dir=$(play_accounts_dir)
  [ ! -d "$dir" ] && return 0
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    basename "$f" .json
  done
}

# ─── Migratsiyalar ──────────────────────────────────────

# v1.4.x yagona-fayl formatdan per-project formatga (idempotent)
play_migrate_legacy_config() {
  local old
  old=$(play_legacy_config)
  [ ! -f "$old" ] && return 0

  local old_pkg sa_path track
  old_pkg=$(grep '"package_name"' "$old" 2>/dev/null \
    | sed -E 's/.*"package_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)

  if [ -z "$old_pkg" ]; then
    mv "$old" "${old}.legacy.$(date +%s)" 2>/dev/null || true
    return 0
  fi

  sa_path=$(grep '"service_account_path"' "$old" \
    | sed -E 's/.*"service_account_path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
  track=$(grep '"track"' "$old" \
    | sed -E 's/.*"track"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)

  # v1.6.0 schema: akkaunt yaratamiz, keyin loyiha unga havola qiladi
  if [ -n "$sa_path" ] && [ -f "$sa_path" ]; then
    local account
    account=$(play_derive_account_name "$sa_path")
    play_account_exists "$account" || play_account_save "$account" "$sa_path"

    local new
    new=$(play_project_config_file "$old_pkg")
    if [ ! -f "$new" ]; then
      play_project_config_save "$old_pkg" "$account" "${track:-internal}"
      info "v1.4.x sozlamasi yangi formatga ko'chirildi: ${old_pkg} → ${account}"
    fi
  fi

  mv "$old" "${old}.legacy.$(date +%s)" 2>/dev/null || true
}

# v1.5.0 (service_account_path bevosita) → v1.6.0 (account havolasi)
# Idempotent: faqat eski format topilsa o'tkazadi.
play_migrate_v15_to_v16() {
  local dir
  dir=$(play_projects_dir)
  [ ! -d "$dir" ] && return 0

  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    # v1.5.0 detector: "service_account_path" bor lekin "account" yo'q
    grep -q '"service_account_path"' "$f" 2>/dev/null || continue
    grep -q '"account"' "$f" 2>/dev/null && continue

    local pkg sa_path track
    pkg=$(grep '"package_name"' "$f" | sed -E 's/.*"package_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    sa_path=$(grep '"service_account_path"' "$f" | sed -E 's/.*"service_account_path"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    track=$(grep '"track"' "$f" | sed -E 's/.*"track"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    [ -z "$pkg" ] && continue
    [ -z "$sa_path" ] && continue

    # Avval v1.5.0 ni .v15 backup'ga ko'chiramiz
    cp "$f" "${f}.v15.$(date +%s)" 2>/dev/null || true

    # Akkaunt yaratish (yoki mavjudidan foydalanish)
    local account
    if [ -f "$sa_path" ]; then
      account=$(play_derive_account_name "$sa_path")
      play_account_exists "$account" || play_account_save "$account" "$sa_path"
    else
      # SA fayli yo'q — orphan account yaratamiz, foydalanuvchi keyin tuzatishi mumkin
      account=$(sanitize_account_name "$(basename "$sa_path" .json)")
      play_account_exists "$account" || {
        mkdir -p "$(play_accounts_dir)"
        chmod 700 "$(play_accounts_dir)"
        cat > "$(play_account_file "$account")" <<JSON
{
  "name": "${account}",
  "service_account_path": "${sa_path}",
  "client_email": "",
  "project_id": ""
}
JSON
        chmod 600 "$(play_account_file "$account")"
      }
    fi

    # Project file'ni v1.6.0 formatga qayta yozish
    play_project_config_save "$pkg" "$account" "${track:-internal}"
    info "v1.5.0 → v1.6.0: ${pkg} → akkaunt '${account}'"
  done
}

# Sozlangan barcha loyihalarni ro'yxati (debug)
play_list_projects() {
  local dir
  dir=$(play_projects_dir)
  [ ! -d "$dir" ] && return 0
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local pkg track account
    pkg=$(basename "$f" .json)
    account=$(grep '"account"' "$f" | sed -E 's/.*"account"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    track=$(grep '"track"' "$f" | sed -E 's/.*"track"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
    echo "  • ${pkg} → ${account} → ${track}"
  done
}

# Service Account JSON dan oddiy string qiymat o'qish
sa_json_get_simple() {
  local file="$1" key="$2"
  grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" \
    | head -1 \
    | sed -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# Service Account JSON dan private_key ni o'qish va \n escape'larni real
# newlinega aylantirish (printf %b orqali).
sa_json_get_private_key() {
  local file="$1"
  local raw
  raw=$(grep -o '"private_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" \
    | sed -E 's/^"private_key"[[:space:]]*:[[:space:]]*"//; s/"$//')
  printf '%b' "$raw"
}

# base64url encoding (RFC 7515): standard base64 + tr + padding olib tashlash
# String argument uchun
b64url_encode_str() {
  printf '%s' "$1" | openssl base64 -A | tr -d '=' | tr '/+' '_-'
}

# Stdin dan binary data uchun (signature uchun)
b64url_encode_stream() {
  openssl base64 -A | tr -d '=' | tr '/+' '_-'
}

# RS256 JWT yaratish — Google API uchun
play_generate_jwt() {
  local sa_json="$1"
  local client_email private_key now exp

  client_email=$(sa_json_get_simple "$sa_json" "client_email")
  private_key=$(sa_json_get_private_key "$sa_json")

  if [ -z "$client_email" ] || [ -z "$private_key" ]; then
    err "Service Account JSON noto'g'ri yoki bo'sh"
    return 1
  fi

  now=$(date +%s)
  exp=$((now + 3600))

  local header='{"alg":"RS256","typ":"JWT"}'
  local payload
  payload=$(printf '{"iss":"%s","scope":"https://www.googleapis.com/auth/androidpublisher","aud":"https://oauth2.googleapis.com/token","exp":%d,"iat":%d}' \
    "$client_email" "$exp" "$now")

  local header_b64 payload_b64 signing_input
  header_b64=$(b64url_encode_str "$header")
  payload_b64=$(b64url_encode_str "$payload")
  signing_input="${header_b64}.${payload_b64}"

  # private_key'ni vaqtinchalik faylga yozish (openssl PEM fayl/stdin oladi)
  local key_file signature
  key_file=$(mktemp)
  chmod 600 "$key_file"
  printf '%s' "$private_key" > "$key_file"

  signature=$(printf '%s' "$signing_input" \
    | openssl dgst -sha256 -sign "$key_file" -binary 2>/dev/null \
    | b64url_encode_stream)

  rm -f "$key_file"

  if [ -z "$signature" ]; then
    err "JWT imzolash xato berdi (openssl)"
    return 1
  fi

  printf '%s.%s\n' "$signing_input" "$signature"
}

# JWT ni access_token ga ayirboshlash (OAuth2)
play_get_access_token() {
  local jwt="$1"
  local response token

  response=$(curl -fsS -X POST "https://oauth2.googleapis.com/token" \
    --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
    --data-urlencode "assertion=${jwt}" 2>&1) || {
      err "Access token so'rovi xato berdi: $response"
      return 1
    }

  token=$(printf '%s' "$response" \
    | grep -o '"access_token"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed -E 's/.*"access_token"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')

  if [ -z "$token" ]; then
    err "access_token javobda topilmadi"
    err "Javob: $response"
    return 1
  fi

  printf '%s' "$token"
}

# pubspec/gradle dan package name (applicationId) ni aniqlash
detect_android_package_name() {
  local pkg=""
  if [ -f "android/app/build.gradle.kts" ]; then
    pkg=$(grep -oE 'applicationId[[:space:]]*=[[:space:]]*"[^"]*"' android/app/build.gradle.kts \
      | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
  fi
  if [ -z "$pkg" ] && [ -f "android/app/build.gradle" ]; then
    pkg=$(grep -oE 'applicationId[[:space:]]+"[^"]*"' android/app/build.gradle \
      | head -1 | sed -E 's/applicationId[[:space:]]+"([^"]*)"/\1/')
  fi
  echo "$pkg"
}

# ─── v1.6.0 Account-asosli sozlash flow ─────────────────────

# playstore_wizard_download_sa: brauzer + polling orqali SA JSON ni topish.
# Hech narsa saqlamaydi — faqat fayl yo'lini stdout'ga qaytaradi.
# (avvalgi to'liq wizard'dan ajratilgan toza komponent)
playstore_wizard_download_sa() {
  info "─ [1/4] Google Play Android Developer API ni yoqing ──" >&2
  info "Brauzerda Cloud Console API library ochiladi..." >&2
  info "Sahifada: ${BOLD}Enable${NC} tugmasini bosing" >&2
  echo >&2

  open_url "https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com" >&2
  read -p "  Yoqilgandan keyin Enter bosing: " _

  echo >&2
  info "─ [2/4] Service Account yarating ─────────────────────" >&2
  info "Brauzerda Service Accounts sahifasi ochiladi..." >&2
  info "  1) ${BOLD}+ Create Service Account${NC}" >&2
  info "  2) Name: ${BOLD}flutter-build-deploy${NC}" >&2
  info "  3) ${BOLD}Done${NC} (Grant access qadamini skip)" >&2
  echo >&2

  open_url "https://console.cloud.google.com/iam-admin/serviceaccounts" >&2
  read -p "  Yaratganingizdan keyin Enter bosing: " _

  echo >&2
  info "─ [3/4] JSON Key yuklab oling ────────────────────────" >&2
  info "Service Account'ga kiring:" >&2
  info "  1) ${BOLD}Keys${NC} → ${BOLD}Add Key${NC} → ${BOLD}Create new key${NC}" >&2
  info "  2) ${BOLD}JSON${NC} → ${BOLD}Create${NC}" >&2
  info "  3) Fayl Downloads'ga yuklanadi" >&2
  echo >&2

  local marker="/tmp/.fbt_play.$$"
  touch "$marker"
  read -p "  Tayyor bo'lsangiz Enter bosing: " _
  echo >&2

  # JSON faylni topish (Service Account marker bilan filter)
  local sa_candidate sa_file
  for sa_candidate in $(find "$HOME/Downloads" -maxdepth 1 -name "*.json" \
      -newer "$marker" 2>/dev/null); do
    if grep -q '"type": "service_account"' "$sa_candidate" 2>/dev/null; then
      sa_file="$sa_candidate"
    fi
  done
  rm -f "$marker"

  if [ -z "$sa_file" ]; then
    warn "Service Account JSON Downloads'da topilmadi" >&2
    read -p "  Fayl yo'li (Enter — bekor): " sa_file
    sa_file="${sa_file/#\~/$HOME}"
    [ -z "$sa_file" ] && { warn "Bekor qilindi" >&2; return 1; }
    [ ! -f "$sa_file" ] && { err "Fayl topilmadi: $sa_file" >&2; return 1; }
  fi

  # JSON tuzilishini tasdiqlash
  local client_email
  client_email=$(sa_json_get_simple "$sa_file" "client_email")
  if [[ ! "$client_email" =~ \.iam\.gserviceaccount\.com$ ]]; then
    err "Bu Service Account JSON ko'rinmaydi: $sa_file" >&2
    return 1
  fi
  ok "JSON aniqlandi: $client_email" >&2

  # Standart akkaunt papkasiga ko'chirish (har akkaunt o'z faylida)
  local keys_dir="${HOME}/.config/flutter-build-tool/keys/play"
  mkdir -p "$keys_dir"
  chmod 700 "$keys_dir"

  # Fayl nomini akkaunt nomidan derive qilamiz
  local default_name
  default_name=$(play_derive_account_name "$sa_file")
  local target="${keys_dir}/${default_name}.json"

  # Agar bir xil nomda allaqachon bo'lsa, suffix qo'shamiz
  if [ -f "$target" ] && [ "$sa_file" != "$target" ]; then
    target="${keys_dir}/${default_name}-$(date +%s).json"
  fi

  if [ "$sa_file" != "$target" ]; then
    mv "$sa_file" "$target"
    chmod 600 "$target"
    ok "Ko'chirildi: $target (chmod 600)" >&2
  fi

  # [4/4] Play Console ruxsatlari ko'rsatmasi
  echo >&2
  info "─ [4/4] Play Console ruxsatlari ──────────────────────" >&2
  info "Brauzerda Play Console API access sahifasi ochiladi..." >&2
  info "  1) ${BOLD}${client_email}${NC} ni toping" >&2
  info "  2) ${BOLD}Grant access${NC}" >&2
  info "  3) App permissions: faqat kerakli app'lar" >&2
  info "  4) Account permissions: ${BOLD}Releases${NC} barchasini yoqing" >&2
  info "  5) ${BOLD}Apply${NC}" >&2
  echo >&2

  open_url "https://play.google.com/console/u/0/api-access" >&2
  read -p "  Apply qilganingizdan keyin Enter bosing: " _

  # Yagona natija: SA fayl yo'li (stdout)
  printf '%s\n' "$target"
}

# Yangi akkaunt qo'shish — wizard yoki qo'lda.
# Argument: ixtiyoriy package_name — yangi akkaunt yaratilgach loyihaga bog'lanadi.
play_add_new_account() {
  local pkg="$1"

  step "Yangi Play Store akkaunti qo'shish"
  echo
  echo -e "  ${BOLD}Sozlash usulini tanlang:${NC}"
  echo -e "    ${CYAN}1${NC}) Avtomatik wizard ${GREEN}(tavsiya)${NC} — brauzer ochiladi, JSON auto-detect"
  echo -e "    ${CYAN}2${NC}) Qo'lda kiritish — JSON yo'lini siz yozasiz"
  echo
  read -p "  Tanlang [1-2]: " choice

  local sa_path
  case "$choice" in
    1|"")
      sa_path=$(playstore_wizard_download_sa) || return 1
      ;;
    2)
      read -p "    Service Account JSON yo'li: " sa_path
      sa_path="${sa_path/#\~/$HOME}"
      if [ ! -f "$sa_path" ]; then
        err "Fayl topilmadi: $sa_path"
        return 1
      fi
      local ce
      ce=$(sa_json_get_simple "$sa_path" "client_email")
      if [[ ! "$ce" =~ \.iam\.gserviceaccount\.com$ ]]; then
        err "Bu Service Account JSON ko'rinmaydi"
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac

  # Akkaunt nomi (project_id'dan default)
  echo
  local default_name name
  default_name=$(play_derive_account_name "$sa_path")
  echo -e "  ${BOLD}Akkaunt nomi${NC} — bu shu credentials'ga foydalanuvchi-do'st label"
  info "Misol: 'personal', 'work-acme', 'client-xyz'"
  read -p "  Akkaunt nomi [${default_name}]: " name
  name="${name:-$default_name}"
  name=$(sanitize_account_name "$name")

  # Mavjud akkauntni qayta yozmaslik
  if play_account_exists "$name"; then
    warn "Akkaunt '${name}' allaqachon mavjud"
    read -p "  Qayta yozamizmi? (y/n) [n]: " replace
    [[ ! "$replace" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }
  fi

  play_account_save "$name" "$sa_path"
  ok "Akkaunt qo'shildi: ${BOLD}${name}${NC}"

  # Loyihaga bog'lash (agar pkg berilgan bo'lsa)
  if [ -n "$pkg" ]; then
    echo
    local track
    read -p "    Loyiha '${pkg}' uchun default track [internal]: " track
    track="${track:-internal}"
    play_project_config_save "$pkg" "$name" "$track"
    ok "Loyiha bog'landi: ${pkg} → '${name}' → ${track}"
  fi
}

# Akkaunt picker — mavjud akkauntlardan birini tanlash yoki yangi qo'shish.
# Tanlangan akkaunt loyihaga bog'lanadi.
play_pick_account_for_project() {
  local pkg="$1"

  # Mavjud akkauntlar ro'yxati
  local accounts=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && accounts+=("$name")
  done < <(play_list_accounts)

  # Bo'sh bo'lsa darrov yangi yaratamiz
  if [ ${#accounts[@]} -eq 0 ]; then
    info "Hali Play Store akkaunti qo'shilmagan"
    play_add_new_account "$pkg"
    return $?
  fi

  # Picker UI
  echo
  echo -e "  ${BOLD}╭─ Mavjud Play Store akkauntlari ─────────────────────${NC}"
  local i=1 acc_name email
  for acc_name in "${accounts[@]}"; do
    email=$(play_account_get "$acc_name" "client_email")
    printf "  ${BOLD}│${NC}  ${CYAN}%d${NC}) ${BOLD}%-22s${NC} %s\n" "$i" "$acc_name" "$email"
    i=$((i + 1))
  done
  echo -e "  ${BOLD}├──────────────────────────────────────────────────────${NC}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%d${NC}) ${GREEN}➕ Yangi akkaunt qo'shish${NC}\n" "$i"
  local cancel_i=$((i + 1))
  printf  "  ${BOLD}│${NC}  ${CYAN}%d${NC}) Bekor qilish\n" "$cancel_i"
  echo -e "  ${BOLD}╰──────────────────────────────────────────────────────${NC}"
  echo

  read -p "  Loyiha '${pkg}' uchun akkaunt tanlang [1-${cancel_i}]: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    warn "Bekor qilindi"
    return 1
  fi

  # Mavjud akkaunt tanlandi
  if [ "$choice" -ge 1 ] && [ "$choice" -le "${#accounts[@]}" ]; then
    local picked="${accounts[$((choice - 1))]}"
    info "Akkaunt tanlandi: ${BOLD}${picked}${NC}"
    local track
    read -p "    Default track [internal]: " track
    track="${track:-internal}"
    play_project_config_save "$pkg" "$picked" "$track"
    ok "Loyiha bog'landi: ${pkg} → '${picked}' → ${track}"
    return 0
  fi

  # Yangi akkaunt
  if [ "$choice" -eq "$i" ]; then
    play_add_new_account "$pkg"
    return $?
  fi

  warn "Bekor qilindi"
  return 1
}

# Backwards-compat shim'lar — eski API'ni saqlash uchun
setup_play_credentials() { play_add_new_account "$1"; }
playstore_setup_wizard() { play_add_new_account "$1"; }

ensure_play_credentials() {
  # Eski formatlardan migratsiya (idempotent)
  play_migrate_legacy_config    # v1.4.x → v1.6.0
  play_migrate_v15_to_v16       # v1.5.0 → v1.6.0

  # Hozirgi loyiha package'ini aniqlash
  local current_pkg
  current_pkg=$(detect_android_package_name)
  if [ -z "$current_pkg" ]; then
    err "Android applicationId aniqlanmadi (android/app/build.gradle*)"
    return 1
  fi

  local cfg
  cfg=$(play_project_config_file "$current_pkg")

  # Sozlangan loyiha — silent davom etish
  if [ -f "$cfg" ]; then
    local account track
    account=$(play_project_config_get "$current_pkg" "account")
    track=$(play_project_config_get "$current_pkg" "track")

    if [ -z "$account" ]; then
      warn "Loyiha config buzuq (akkaunt belgilanmagan), qayta sozlaymiz"
      rm -f "$cfg"
      # fall through
    elif ! play_account_exists "$account"; then
      warn "Akkaunt '${account}' topilmadi — qayta tanlash kerak"
      play_pick_account_for_project "$current_pkg" || return 1
      return 0
    else
      local sa_path
      sa_path=$(play_account_get "$account" "service_account_path")
      if [ ! -f "$sa_path" ]; then
        warn "Akkaunt '${account}' ning JSON fayli yo'qolgan: $sa_path"
        info "Akkaunt uchun yangi JSON kerak"
        play_add_new_account "" || return 1
        # Akkauntni qayta tanlash
        play_pick_account_for_project "$current_pkg" || return 1
        return 0
      fi
      ok "Play Store: ${BOLD}${current_pkg}${NC} → '${BOLD}${account}${NC}' → ${YELLOW}${track}${NC} ${CYAN}(saqlangan)${NC}"
      return 0
    fi
  fi

  # Yangi loyiha — akkaunt picker
  info "Yangi loyiha: ${BOLD}${current_pkg}${NC}"
  play_pick_account_for_project "$current_pkg" || return 1
}

# Build natijasidan AAB faylini topish
find_latest_aab() {
  local dir="build/app/outputs/bundle/release"
  [ ! -d "$dir" ] && return 1
  local aab
  aab=$(find "$dir" -maxdepth 1 -name "*.aab" -type f 2>/dev/null | head -1)
  [ -z "$aab" ] && return 1
  echo "$aab"
}

# JSON javobdan qiymat ekstraksiya qilish (oddiy parsing)
extract_json_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed -E "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/"
}

# JSON javobdan raqamli qiymat ekstraksiya
extract_json_number() {
  local json="$1" field="$2"
  printf '%s' "$json" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*[0-9]*" \
    | head -1 \
    | sed -E "s/.*:[[:space:]]*([0-9]+).*/\1/"
}

# 4 ta API call orqali AAB ni Play Store'ga yuklash
upload_to_play_store() {
  local aab="$1"

  step "Play Store ga yuklash"

  if ! command -v openssl > /dev/null 2>&1; then
    err "openssl topilmadi (JWT signing uchun kerak)"
    return 1
  fi
  if ! command -v curl > /dev/null 2>&1; then
    err "curl topilmadi"
    return 1
  fi

  # Loyiha → akkaunt → SA path resolve
  local package_name account sa_path track
  package_name=$(detect_android_package_name)
  if [ -z "$package_name" ]; then
    err "Android applicationId aniqlanmadi"
    return 1
  fi

  account=$(play_project_config_get "$package_name" "account")
  track=$(play_project_config_get "$package_name" "track")
  track="${track:-internal}"

  if [ -z "$account" ]; then
    err "Loyiha '${package_name}' uchun akkaunt belgilanmagan"
    return 1
  fi
  if ! play_account_exists "$account"; then
    err "Akkaunt '${account}' topilmadi"
    return 1
  fi

  sa_path=$(play_account_get "$account" "service_account_path")
  if [ -z "$sa_path" ] || [ ! -f "$sa_path" ]; then
    err "Akkaunt '${account}' ning JSON fayli topilmadi: $sa_path"
    return 1
  fi
  if [ ! -f "$aab" ]; then
    err "AAB topilmadi: $aab"
    return 1
  fi

  local size_mb sa_email
  size_mb=$(du -m "$aab" | cut -f1)
  sa_email=$(sa_json_get_simple "$sa_path" "client_email")

  info "AAB:          $aab (${size_mb} MB)"
  info "Package:      $package_name"
  info "Track:        $track"
  info "Service Acc:  $sa_email"
  echo

  local api_base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${package_name}"
  local upload_base="https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${package_name}"

  # [1/5] Access token
  info "[1/5] Access token olinmoqda..."
  local jwt token
  jwt=$(play_generate_jwt "$sa_path") || return 1
  token=$(play_get_access_token "$jwt") || return 1
  ok "Access token olindi"

  # [2/5] Edit yaratish
  info "[2/5] Edit yaratilmoqda..."
  local edit_response edit_id
  edit_response=$(curl -fsS -X POST "${api_base}/edits" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>&1) || {
      err "Edit yaratish xato: $edit_response"
      return 1
    }
  edit_id=$(extract_json_field "$edit_response" "id")
  if [ -z "$edit_id" ]; then
    err "edit_id javobdan topilmadi"
    err "Javob: $edit_response"
    return 1
  fi
  ok "Edit yaratildi: $edit_id"

  # [3/5] AAB yuklash
  info "[3/5] AAB yuklanmoqda (${size_mb} MB)..."
  local upload_response version_code
  upload_response=$(curl -fsS -X POST \
    "${upload_base}/edits/${edit_id}/bundles?uploadType=media" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${aab}" 2>&1) || {
      err "AAB yuklash xato: $upload_response"
      return 1
    }
  version_code=$(extract_json_number "$upload_response" "versionCode")
  if [ -z "$version_code" ]; then
    err "versionCode javobdan topilmadi"
    err "Javob: $upload_response"
    return 1
  fi
  ok "AAB yuklandi, versionCode=$version_code"

  # [4/5] Track'ga qo'shish
  info "[4/5] Track'ga qo'shilmoqda: $track..."
  local track_payload track_response
  track_payload=$(printf '{"releases":[{"versionCodes":["%s"],"status":"completed"}]}' "$version_code")
  track_response=$(curl -fsS -X PUT \
    "${api_base}/edits/${edit_id}/tracks/${track}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d "$track_payload" 2>&1) || {
      err "Track qo'shish xato: $track_response"
      return 1
    }
  ok "Track'ga qo'shildi: $track"

  # [5/5] Commit
  info "[5/5] Edit commit qilinmoqda..."
  local commit_response
  commit_response=$(curl -fsS -X POST \
    "${api_base}/edits/${edit_id}:commit" \
    -H "Authorization: Bearer ${token}" 2>&1) || {
      err "Commit xato: $commit_response"
      info "Edit ID: $edit_id (qo'lda Play Console'da tekshirish mumkin)"
      return 1
    }

  echo
  ok "Muvaffaqiyatli yuklandi!"
  info "Track:       $track"
  info "versionCode: $version_code"
  info "Play Console: https://play.google.com/console/u/0/developers/-/app/${package_name}/tracks/${track}"
  info "Internal track'ga 1-2 daqiqada, beta/production'ga 1-2 soatda paydo bo'ladi"
  return 0
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
  "App Store Connect upload (Production + iOS bilan)" \
  "Play Store upload (Production + Android + AAB bilan)"

IS_PROD="${CHECKBOX_RESULT[0]}"
BUILD_ANDROID="${CHECKBOX_RESULT[1]}"
BUILD_IOS="${CHECKBOX_RESULT[2]}"
DO_CLEAN="${CHECKBOX_RESULT[3]}"
DO_PUBGET="${CHECKBOX_RESULT[4]}"
DO_APPSTORE_UPLOAD="${CHECKBOX_RESULT[5]}"
DO_PLAYSTORE_UPLOAD="${CHECKBOX_RESULT[6]}"

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

if $DO_PLAYSTORE_UPLOAD; then
  if ! $IS_PROD; then
    err "Play Store upload faqat Production rejimda ishlaydi"
    exit 1
  fi
  if ! $BUILD_ANDROID; then
    err "Play Store upload uchun Android tanlanishi kerak"
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

  if $DO_PLAYSTORE_UPLOAD && ! $BUILD_AAB; then
    err "Play Store upload uchun AAB format tanlanishi kerak (APK qabul qilinmaydi)"
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

# ─── 7c. Play Store upload pre-check (Production + Android) ─
if $DO_PLAYSTORE_UPLOAD; then
  step "Play Store upload sozlamalarini tekshirish"
  ensure_play_credentials || { err "Play Store sozlanmadi"; exit 1; }
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

# ─── 9c. Play Store ga upload ─────────────────────────────
if $DO_PLAYSTORE_UPLOAD; then
  aab_file=$(find_latest_aab) || {
    err "AAB fayl topilmadi build/app/outputs/bundle/release/ ichida"
    exit 1
  }
  upload_to_play_store "$aab_file" || warn "Upload xato berdi — AAB fayl saqlangan: $aab_file"
fi

# ─── 10. Build natijalarini ochish (macOS/Linux/WSL) ──────
step "Build natijalarini ochish"
for path in "${BUILD_PATHS[@]}"; do
  open_file "$path" || true
done

banner "Hammasi tayyor! Versiya: ${new_pname}+${new_pbuild}"
