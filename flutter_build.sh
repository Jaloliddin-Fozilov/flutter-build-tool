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
SCRIPT_VERSION="1.15.3"
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

# pause — foydalanuvchi Enter bosishini kutish (menyu o'qilishi uchun)
pause() {
  # v1.15.2: Express rejimda kutmaymiz (to'liq avtomatik)
  [ "${EXPRESS_MODE:-false}" = "true" ] && return 0
  echo
  read -p "  ${1:-Davom etish uchun Enter...}" _
}

# v1.15.2: Express rejimda prompt'larni avtomatik default bilan tasdiqlash.
# EXPRESS_MODE=true bo'lsa: default qiymatni o'zgaruvchiga qo'yadi (read qilmaydi,
# kutmaydi). Aks holda: oddiy read -p bilan so'raydi.
# Args: <varname> <default> <prompt_text>
express_read() {
  local __ervar="$1" __erdef="$2" __erprompt="$3"
  if [ "${EXPRESS_MODE:-false}" = "true" ]; then
    printf '%s%s[⚡ auto: %s]%s\n' "$__erprompt" "${BOLD}" "$__erdef" "${NC}" >&2
    printf -v "$__ervar" '%s' "$__erdef"
  else
    read -p "$__erprompt" "$__ervar"
  fi
}

# try_this — xatodan keyin foydalanuvchiga aniq recovery buyrug'(lar)ni ko'rsatish.
# Foydalanish: try_this "cmd1" ["cmd2" ...]
# Bir necha buyruqni ketma-ket bermoq mumkin.
try_this() {
  echo
  echo -e "  ${BOLD}${YELLOW}→ Buni sinab ko'ring:${NC}"
  local cmd
  for cmd in "$@"; do
    echo -e "    ${CYAN}\$${NC} ${BOLD}${cmd}${NC}"
  done
  echo
}

# try_this_install — dependency o'rnatish bo'yicha platform-aware tavsiya
# Foydalanish: try_this_install "openssl" "macOS" "brew install openssl@3" "Linux" "sudo apt install openssl"
try_this_install() {
  local tool="$1"; shift
  echo
  echo -e "  ${BOLD}${YELLOW}→ '${tool}' ni o'rnatish:${NC}"
  while [ "$#" -ge 2 ]; do
    local platform="$1" cmd="$2"
    echo -e "    ${CYAN}${platform}:${NC} ${BOLD}${cmd}${NC}"
    shift 2
  done
  echo
}

# v1.12.6: ishchi keytool'ni topish — PATH va boshqa keng tarqalgan joylar
# Foydalanuvchi PATH'da Java o'rnatmagan bo'lsa ham, Android Studio ichidagi
# JBR yoki boshqa o'rnatilgan JDK ishlatilishi mumkin.
#
# Returns:
#   0 + stdout: keytool fayl yo'li (full path yoki shunchaki "keytool")
#   1: hech qaerda topilmadi
# v1.13.8: keytool haqiqatan ishlashini tekshirish (functional test)
# Stub bo'lsa "Unable to locate a Java Runtime" chiqaradi.
# Returns: 0 = ishlaydi, 1 = stub yoki buzilgan
_keytool_works() {
  local kt="$1"
  if "$kt" -help 2>&1 | grep -qE "Unable to locate a Java Runtime|No Java runtime|visit (http|www)\.java\.com|couldn.t be completed"; then
    return 1
  fi
  return 0
}

find_keytool() {
  # v1.13.8: har bir nomzodni _keytool_works bilan VALIDATSIYA qilamiz.
  # Avval faqat -x (mavjudlik) tekshirardik — lekin macOS stub -x TRUE bo'ladi,
  # ammo ishlamaydi. Endi har bir yo'lni REAL ishlatib ko'ramiz (functional test).

  # 1) PATH'dagi keytool
  if command -v keytool > /dev/null 2>&1; then
    if _keytool_works "keytool"; then
      printf '%s\n' "keytool"
      return 0
    fi
  fi

  # 2) macOS: /usr/libexec/java_home — Apple'ning rasmiy JDK locator
  if [ -x "/usr/libexec/java_home" ]; then
    local jh
    jh=$(/usr/libexec/java_home 2>/dev/null)
    if [ -n "$jh" ] && [ -x "$jh/bin/keytool" ] && _keytool_works "$jh/bin/keytool"; then
      printf '%s\n' "$jh/bin/keytool"
      return 0
    fi
  fi

  # 3) Keng tarqalgan joylar (glob bilan)
  local path
  for path in \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    "/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool" \
    "/Applications/Android Studio.app/Contents/jre/jdk/Contents/Home/bin/keytool" \
    "/Applications/Android Studio Preview.app/Contents/jbr/Contents/Home/bin/keytool" \
    "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    /Library/Java/JavaVirtualMachines/*/Contents/Home/bin/keytool \
    "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home/bin/keytool \
    /opt/homebrew/opt/openjdk*/bin/keytool \
    /opt/homebrew/opt/openjdk@*/bin/keytool \
    /opt/homebrew/opt/zulu*/bin/keytool \
    /opt/homebrew/opt/temurin*/bin/keytool \
    /opt/homebrew/Cellar/openjdk/*/bin/keytool \
    /usr/local/opt/openjdk*/bin/keytool \
    /usr/local/Cellar/openjdk/*/bin/keytool \
    "$HOME/.sdkman/candidates/java/current/bin/keytool" \
    "$HOME/.jenv/versions"/*/bin/keytool \
    /usr/lib/jvm/*/bin/keytool
  do
    # Glob expansion: agar pattern mos kelmasa, literal qoladi -> -x false
    # v1.13.8: -x VA _keytool_works ikkalasi ham tekshiriladi
    if [ -x "$path" ] && _keytool_works "$path"; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  return 1
}

# JAVA_HOME ni keytool yo'lidan derive qilib export qilish (sibling tools uchun)
# keytool yo'li: /path/to/jdk/bin/keytool  →  JAVA_HOME=/path/to/jdk
export_java_home_from_keytool() {
  local kt_path="$1"
  [ "$kt_path" = "keytool" ] && return 0  # PATH version — JAVA_HOME sozlangan
  local jdk_home
  jdk_home=$(dirname "$(dirname "$kt_path")")
  if [ -d "$jdk_home" ]; then
    export JAVA_HOME="$jdk_home"
  fi
}

# v1.12.7: Java JDK ni avtomatik o'rnatish (macOS via Homebrew cask)
# Foydalanuvchidan tasdiqlash so'raydi va brew install --cask zulu@17 chaqiradi.
#
# Returns:
#   0 + stdout: yangi keytool yo'li (find_keytool natijasi)
#   1: install qilinmadi/xato berdi
offer_jdk_auto_install() {
  if [ "$(uname)" != "Darwin" ]; then
    info "Avtomatik install hozir faqat macOS uchun (brew orqali)" >&2
    info "Linux foydalanuvchilari uchun: sudo apt install default-jdk" >&2
    return 1
  fi
  if ! command -v brew > /dev/null 2>&1; then
    warn "Homebrew topilmadi — avtomatik install qila olmayman" >&2
    info "Avval Homebrew o'rnating, keyin qayta urinib ko'ring:" >&2
    info "  ${BOLD}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}" >&2
    return 1
  fi

  echo >&2
  warn "Java JDK hech qaerda topilmadi" >&2
  info "Homebrew bilan avtomatik o'rnatishim mumkin:" >&2
  info "  Buyruq: ${BOLD}brew install --cask zulu@17${NC}" >&2
  info "  Distribution: Zulu OpenJDK 17 (Azul, bepul, license cheklovsiz)" >&2
  info "  Hajmi:  ~200MB, internet'da 30-60 sekund" >&2
  info "  Joyi:   /Library/Java/JavaVirtualMachines/zulu-17.jdk/" >&2
  info "  Kelajak: keystore yaratish, signing va boshqalar uchun avtomatik topiladi" >&2
  echo >&2

  local yn
  read -p "  Hozir avtomatik o'rnataylikmi? (y/n) [y]: " yn
  if [[ "$yn" =~ ^[Nn]$ ]]; then
    info "Bekor qilindi — qo'lda o'rnatib qayta urinib ko'ring" >&2
    return 1
  fi

  echo >&2
  step "Zulu JDK 17 o'rnatilmoqda (brew)..." >&2
  info "(brew'ning chiqishi pastda ko'rinadi, 30-60 sekund kuting)" >&2
  echo >&2

  # brew install — real-time output ko'rsatamiz (foydalanuvchi jarayonni kuzatadi)
  if brew install --cask zulu@17; then
    echo >&2
    ok "Java JDK muvaffaqiyatli o'rnatildi!" >&2

    # find_keytool ni qayta chaqirish (yangi JDK java_home orqali topilishi kerak)
    local new_keytool
    new_keytool=$(find_keytool)
    if [ -n "$new_keytool" ]; then
      ok "Yangi keytool topildi: ${BOLD}${new_keytool}${NC}" >&2
      printf '%s\n' "$new_keytool"
      return 0
    fi

    # Bu kam ehtimol — brew install muvaffaqiyatli, lekin find_keytool topmadi
    warn "Java o'rnatildi, lekin keytool darrov topilmadi" >&2
    info "PATH yangilanishi uchun yangi terminal sessiya oching" >&2
    info "Keyin qaytadan urinib ko'ring: flutter-build" >&2
    return 1
  else
    echo >&2
    err "Brew install xato berdi" >&2
    info "Yuqorida xato xabarini ko'ring (network, license, va h.k.)" >&2
    info "Qo'lda urinib ko'ring:" >&2
    try_this "brew install --cask zulu@17"
    return 1
  fi
}

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

# ─── Settings (foydalanuvchi default'lari) ──────────────
# Saqlash: ~/.config/flutter-build-tool/settings.conf — sourceable key=value format

settings_file() { echo "${HOME}/.config/flutter-build-tool/settings.conf"; }

# Factory default qiymatlar (settings.conf yo'q bo'lsa ishlatiladi)
set_factory_defaults() {
  DEFAULT_PRODUCTION="${DEFAULT_PRODUCTION:-false}"
  DEFAULT_ANDROID="${DEFAULT_ANDROID:-false}"
  DEFAULT_IOS="${DEFAULT_IOS:-false}"
  DEFAULT_FLUTTER_CLEAN="${DEFAULT_FLUTTER_CLEAN:-false}"
  DEFAULT_FLUTTER_PUB_GET="${DEFAULT_FLUTTER_PUB_GET:-false}"
  DEFAULT_AAB="${DEFAULT_AAB:-true}"
  DEFAULT_APK="${DEFAULT_APK:-false}"
  DEFAULT_APPSTORE_UPLOAD="${DEFAULT_APPSTORE_UPLOAD:-false}"
  DEFAULT_PLAYSTORE_UPLOAD="${DEFAULT_PLAYSTORE_UPLOAD:-false}"
  DEFAULT_ANDROID_TRACK="${DEFAULT_ANDROID_TRACK:-internal}"
  DEFAULT_IOS_TEAM_ID="${DEFAULT_IOS_TEAM_ID:-}"
  AUTO_UPDATE_ENABLED="${AUTO_UPDATE_ENABLED:-true}"
  AUTO_UPDATE_TIMEOUT="${AUTO_UPDATE_TIMEOUT:-5}"
}

# Settings'ni yuklash — fayl bo'lsa source qiladi, so'ng factory default'larni
# o'rnatilmagan o'zgaruvchilarga qo'yadi.
load_settings() {
  local file
  file=$(settings_file)
  # shellcheck disable=SC1090
  [ -f "$file" ] && source "$file"
  set_factory_defaults
}

# Settings'ni faylga yozish (atomic: avval tmp ga, keyin mv)
save_settings() {
  local file dir tmp
  file=$(settings_file)
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"
  tmp="${file}.tmp.$$"
  cat > "$tmp" <<CONF
# flutter-build-tool sozlamalari
# Ushbu fayl 'source' bilan o'qiladi. Qo'lda tahrirlash mumkin.
# Avtomatik yangilash: flutter-build --settings

DEFAULT_PRODUCTION=${DEFAULT_PRODUCTION}
DEFAULT_ANDROID=${DEFAULT_ANDROID}
DEFAULT_IOS=${DEFAULT_IOS}
DEFAULT_FLUTTER_CLEAN=${DEFAULT_FLUTTER_CLEAN}
DEFAULT_FLUTTER_PUB_GET=${DEFAULT_FLUTTER_PUB_GET}
DEFAULT_AAB=${DEFAULT_AAB}
DEFAULT_APK=${DEFAULT_APK}
DEFAULT_APPSTORE_UPLOAD=${DEFAULT_APPSTORE_UPLOAD}
DEFAULT_PLAYSTORE_UPLOAD=${DEFAULT_PLAYSTORE_UPLOAD}
DEFAULT_ANDROID_TRACK=${DEFAULT_ANDROID_TRACK}
DEFAULT_IOS_TEAM_ID=${DEFAULT_IOS_TEAM_ID}
AUTO_UPDATE_ENABLED=${AUTO_UPDATE_ENABLED}
AUTO_UPDATE_TIMEOUT=${AUTO_UPDATE_TIMEOUT}
CONF
  chmod 600 "$tmp"
  mv "$tmp" "$file"
}

# Joriy settings'ni jadval shaklida ko'rsatish
show_settings_summary() {
  echo
  echo -e "  ${BOLD}╭─ Joriy default'lar ──────────────────────────────${NC}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "Production"          "$(_yn "$DEFAULT_PRODUCTION")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "Android"             "$(_yn "$DEFAULT_ANDROID")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "iOS"                 "$(_yn "$DEFAULT_IOS")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "flutter clean"       "$(_yn "$DEFAULT_FLUTTER_CLEAN")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "flutter pub get"     "$(_yn "$DEFAULT_FLUTTER_PUB_GET")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "AAB format"          "$(_yn "$DEFAULT_AAB")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "APK format"          "$(_yn "$DEFAULT_APK")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "App Store upload"    "$(_yn "$DEFAULT_APPSTORE_UPLOAD")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "Play Store upload"   "$(_yn "$DEFAULT_PLAYSTORE_UPLOAD")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "Android track"       "$DEFAULT_ANDROID_TRACK"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%s${NC}\n" "iOS Team ID"         "${DEFAULT_IOS_TEAM_ID:-<sozlanmagan>}"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} %s\n" "Auto-update"         "$(_yn "$AUTO_UPDATE_ENABLED")"
  printf  "  ${BOLD}│${NC}  ${CYAN}%-22s${NC} ${YELLOW}%ss${NC}\n" "Auto-update timeout" "$AUTO_UPDATE_TIMEOUT"
  echo -e "  ${BOLD}╰─────────────────────────────────────────────────${NC}"
}

# Boolean qiymat uchun ✓/✗
_yn() {
  if [ "$1" = "true" ]; then printf "${GREEN}✓ yoqilgan${NC}"; else printf "${RED}✗ o'chirilgan${NC}"; fi
}

# ─── Diagnostika (flutter-build --doctor) ────────────────

# Tool versiyasini qisqa olib chiqish
_tool_version() {
  local tool="$1" version=""
  case "$tool" in
    flutter) version=$(flutter --version 2>/dev/null | head -1 | awk '{print $2}') ;;
    bash)    version="${BASH_VERSION%%(*}" ;;
    curl)    version=$(curl --version 2>/dev/null | head -1 | awk '{print $2}') ;;
    openssl) version=$(openssl version 2>/dev/null | awk '{print $1, $2}') ;;
    xcrun)   version=$(xcrun --version 2>/dev/null | awk '{print $2}') ;;
    git)     version=$(git --version 2>/dev/null | awk '{print $3}') ;;
  esac
  echo "$version"
}

# Diagnostic check — barcha tool'lar va sozlamalarni ko'rib chiqadi
run_diagnostics() {
  banner "Flutter Build Tool — Doctor"
  local fails=0 warns=0

  echo -e "  ${BOLD}Asosiy talab'lar:${NC}"

  # Flutter
  if command -v flutter > /dev/null 2>&1; then
    ok "Flutter SDK             ($(_tool_version flutter))"
  else
    err "Flutter SDK             topilmadi"
    info "       Build qila olmaymiz"
    fails=$((fails + 1))
  fi

  # bash
  ok "bash                    ($(_tool_version bash))"

  # curl
  if command -v curl > /dev/null 2>&1; then
    ok "curl                    ($(_tool_version curl))"
  else
    err "curl                    topilmadi"
    info "       Auto-update va deploy ishlamaydi"
    fails=$((fails + 1))
  fi

  # git (release notes uchun)
  if command -v git > /dev/null 2>&1; then
    ok "git                     ($(_tool_version git))"
  else
    warn "git                     topilmadi (release notes uchun ixtiyoriy)"
    warns=$((warns + 1))
  fi

  echo
  echo -e "  ${BOLD}iOS deploy talab'lari (macOS):${NC}"

  if [ "$(uname)" = "Darwin" ]; then
    if command -v xcrun > /dev/null 2>&1; then
      ok "xcrun                   ($(_tool_version xcrun))"
    else
      err "xcrun                   topilmadi"
      info "       iOS App Store upload ishlamaydi"
      fails=$((fails + 1))
    fi

    # Transporter.app mavjudligi (3-method uchun)
    local itms="/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter"
    local trans_java="/Applications/Transporter.app/Contents/itms/java/bin/java"
    if [ -x "$itms" ]; then
      ok "Transporter.app         (iTMSTransporter CLI mavjud)"
      # Bundled Java tekshiruvi (Client configuration failed muammosi sababi)
      if [ -x "$trans_java" ]; then
        ok "       Bundled Java OK   (iTMSTransporter ishlay olishi kerak)"
      else
        warn "       Bundled Java buzuq — 'Client configuration failed' xato berishi mumkin"
        info "       Yechim: App Store'dan Transporter.app yangilang yoki altool method'ini ishlating"
        warns=$((warns + 1))
      fi
    else
      info "Transporter.app yo'q   (ixtiyoriy — Apple ID upload uchun backup)"
      info "       Mac App Store'da bepul"
    fi

    # Mavjud iOS auth methods xulosasi
    echo
    echo -e "  ${BOLD}iOS upload uchun mumkin bo'lgan usullar:${NC}"
    ok "1) API Key (.p8)        — Owner/Admin role kerak"
    if command -v xcrun > /dev/null 2>&1; then
      ok "2) Apple ID + altool    — Developer ham qila oladi ${GREEN}(siz uchun)${NC}"
    fi
    if [ -x "$itms" ]; then
      ok "3) Apple ID + Transporter — alternativ backup"
    else
      info "3) Apple ID + Transporter — Transporter.app o'rnatilmagan"
    fi
  else
    info "  (macOS emas — iOS deploy talab'lari skip)"
  fi

  echo
  echo -e "  ${BOLD}Android deploy talab'lari:${NC}"

  if command -v openssl > /dev/null 2>&1; then
    ok "openssl                 ($(_tool_version openssl))"
  else
    err "openssl                 topilmadi"
    info "       Play Store upload uchun JWT signing ishlamaydi"
    fails=$((fails + 1))
  fi

  # v1.12.6: ishchi keytool (PATH, Android Studio, Homebrew va boshqa joylar)
  local kt_doctor_bin
  kt_doctor_bin=$(find_keytool)
  if [ -n "$kt_doctor_bin" ]; then
    if [ "$kt_doctor_bin" = "keytool" ]; then
      local java_check java_ver
      java_check=$(java -version 2>&1)
      java_ver=$(echo "$java_check" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
      ok "Java JDK              (${java_ver:-mavjud}, PATH'da, keystore yaratish ishlaydi)"
    else
      # PATH'da yo'q, lekin boshqa joyda topildi
      local jdk_dir
      jdk_dir=$(dirname "$(dirname "$kt_doctor_bin")")
      ok "Java JDK              (PATH'da yo'q, lekin topildi: $jdk_dir)"
      info "       keystore yaratish ishlaydi (full path orqali)"
    fi
  else
    err "Java JDK              hech qaerda topilmadi"
    info "       Android keystore yaratish ishlamaydi"
    info "       Tekshirilgan: PATH, java_home, Android Studio, Homebrew, SDKMan, jenv"
    info "       O'rnatish: brew install --cask zulu@17"
    fails=$((fails + 1))
  fi

  echo
  echo -e "  ${BOLD}Settings va akkauntlar:${NC}"

  local sfile
  sfile=$(settings_file)
  if [ -f "$sfile" ]; then
    ok "Settings fayli          ($sfile)"
  else
    info "Settings fayli yo'q     (factory default'lar ishlatiladi)"
    info "       Sozlash uchun: flutter-build --settings"
  fi

  # Play Store akkauntlari — hardcoded path (avoid forward-reference to later-defined function)
  local play_acc_dir="${HOME}/.config/flutter-build-tool/accounts/play"
  local pcount=0
  if [ -d "$play_acc_dir" ]; then
    pcount=$(find "$play_acc_dir" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$pcount" -gt 0 ]; then
    ok "Play Store akkauntlari  (${pcount} ta sozlangan)"
  else
    info "Play Store akkauntlari  (yo'q — birinchi build'da so'raladi)"
  fi

  # App Store akkauntlari
  local appstore_acc_dir="${HOME}/.config/flutter-build-tool/accounts/appstore"
  local acount=0
  if [ -d "$appstore_acc_dir" ]; then
    acount=$(find "$appstore_acc_dir" -name "*.json" -type f 2>/dev/null | wc -l | tr -d ' ')
  fi
  if [ "$acount" -gt 0 ]; then
    ok "App Store akkauntlari   (${acount} ta sozlangan)"
  else
    info "App Store akkauntlari   (yo'q — birinchi build'da so'raladi)"
  fi

  echo
  echo -e "  ${BOLD}Yozish ruxsati (auto-update uchun):${NC}"

  local self="$0"
  if command -v realpath > /dev/null 2>&1; then
    self=$(realpath "$self" 2>/dev/null || echo "$0")
  fi

  if [ -w "$self" ] && [ -w "$(dirname "$self")" ]; then
    ok "Skript joyi             (${self}, foydalanuvchi yozolinadi)"
  else
    warn "Skript joyi             (${self}, root-egalik)"
    info "       Auto-update sudo bilan ishlaydi (avtomatik so'raydi)"
    warns=$((warns + 1))
  fi

  echo
  echo -e "  ${BOLD}Auto-update:${NC}"
  if [ "${AUTO_UPDATE_ENABLED:-true}" = "true" ]; then
    ok "Auto-update             yoqilgan (${AUTO_UPDATE_TIMEOUT:-5}s timeout)"
  else
    info "Auto-update             o'chirilgan"
  fi

  # Live raw URL access check
  if command -v curl > /dev/null 2>&1; then
    if curl -fsSL --max-time 3 -o /dev/null "$SCRIPT_RAW_URL" 2>/dev/null; then
      ok "GitHub raw URL          erishish mumkin"
    else
      warn "GitHub raw URL          erishib bo'lmadi (tarmoq yoki SSL?)"
      warns=$((warns + 1))
    fi
  fi

  echo
  echo -e "  ${BOLD}Loyiha holati:${NC}"
  if [ -f "pubspec.yaml" ]; then
    local pname
    pname=$(awk -F: '/^name:/{v=$2; sub(/#.*/,"",v); gsub(/[" ]/,"",v); print v; exit}' pubspec.yaml 2>/dev/null)
    ok "pubspec.yaml mavjud     ($pname)"

    # Android applicationId — inline regex (avoid forward-reference)
    local apkg=""
    if [ -f "android/app/build.gradle.kts" ]; then
      apkg=$(grep -oE 'applicationId[[:space:]]*=[[:space:]]*"[^"]*"' android/app/build.gradle.kts \
        | head -1 | sed -E 's/.*"([^"]*)".*/\1/')
    fi
    if [ -z "$apkg" ] && [ -f "android/app/build.gradle" ]; then
      apkg=$(grep -oE 'applicationId[[:space:]]+"[^"]*"' android/app/build.gradle \
        | head -1 | sed -E 's/applicationId[[:space:]]+"([^"]*)"/\1/')
    fi
    [ -n "$apkg" ] && ok "Android applicationId   ($apkg)"

    # iOS bundle id — inline (avoid forward-reference)
    local ibundle=""
    if [ -f "ios/Runner.xcodeproj/project.pbxproj" ]; then
      ibundle=$(grep "PRODUCT_BUNDLE_IDENTIFIER" "ios/Runner.xcodeproj/project.pbxproj" 2>/dev/null \
        | grep -v "RunnerTests\|FLUTTER_BUILD" \
        | head -1 \
        | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*([^;]+);.*/\1/' \
        | tr -d '"' | tr -d ' ')
    fi
    [ -n "$ibundle" ] && ok "iOS bundle id           ($ibundle)"
  else
    info "pubspec.yaml topilmadi  (Flutter loyihasi ildizidan ishga tushiring)"
  fi

  echo
  if [ "$fails" -eq 0 ] && [ "$warns" -eq 0 ]; then
    echo -e "  ${BOLD}${GREEN}✓ Hammasi tayyor!${NC}"
  elif [ "$fails" -eq 0 ]; then
    echo -e "  ${BOLD}${YELLOW}⚠ ${warns} ta ogohlantirish — kritik emas${NC}"
  else
    echo -e "  ${BOLD}${RED}✗ ${fails} ta kritik muammo, ${warns} ta ogohlantirish${NC}"
  fi
  echo
}

# ─── Release notes (testerlar uchun "Yangiliklar") ──────

# Git oxirgi commit message'ni o'qish (multi-line OK)
read_git_last_commit() {
  command -v git > /dev/null 2>&1 || return 1
  git rev-parse --git-dir > /dev/null 2>&1 || return 1
  # %B = subject + body (full message)
  git log -1 --pretty=%B 2>/dev/null | head -20
}

# v1.15.0: Express rejim uchun release notes'ni avtomatik tanlash (savolsiz)
# Prioritet: git oxirgi commit (birinchi qator) → "Version X" default
express_auto_release_notes() {
  local version="$1"
  local git_msg
  git_msg=$(read_git_last_commit 2>/dev/null | head -1)
  if [ -n "$git_msg" ]; then
    truncate_release_notes "$git_msg" 500
  else
    printf 'Version %s released' "$version"
  fi
}

# CHANGELOG.md dan eng yangi versiya yozuvi (## [X.Y.Z] orasidan)
# Format: Keep a Changelog
read_changelog_latest() {
  [ ! -f "CHANGELOG.md" ] && return 1
  # Birinchi ## [...] dan keyingi ## [...] gacha
  awk '
    /^## \[/ { count++; if (count == 1) {next}; if (count == 2) exit }
    count == 1 { print }
  ' CHANGELOG.md | head -30
}

# Matnni Play Store/App Store cheklovlariga qisqartirish
# Play Store: 500 belgi
# App Store TestFlight: 4000 belgi (lekin biz 500 belgini ishlatamiz)
truncate_release_notes() {
  local text="$1" max="${2:-500}"
  local len=${#text}
  if [ "$len" -le "$max" ]; then
    printf '%s' "$text"
  else
    printf '%s…' "${text:0:$((max - 1))}"
  fi
}

# JSON ichida xavfsiz string sifatida escape qilish
# (newlines, quotes, backslash)
escape_for_json() {
  local s="$1"
  # \\, \", \n ni escape qilamiz
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Interaktiv release notes yig'ish
# Argumentlar: version (1.0.24), build (42)
# Natija: release notes matn (stdout), bo'sh bo'lishi mumkin
collect_release_notes() {
  local version="$1" build="$2"

  echo >&2
  step "Release notes (testerlar 'Yangiliklar' bo'limida ko'radi)" >&2
  echo >&2

  # Avtomatik manba'larni oldindan ko'rib chiqamiz
  local git_msg changelog_msg
  git_msg=$(read_git_last_commit 2>/dev/null || true)
  changelog_msg=$(read_changelog_latest 2>/dev/null || true)

  echo -e "  ${BOLD}Manba tanlang:${NC}" >&2
  if [ -n "$git_msg" ]; then
    info "  ${CYAN}1${NC}) Git oxirgi commit:" >&2
    # Birinchi qator preview
    info "        \"$(printf '%s' "$git_msg" | head -1 | cut -c 1-60)\"" >&2
  fi
  if [ -n "$changelog_msg" ]; then
    info "  ${CYAN}2${NC}) CHANGELOG.md oxirgi versiya:" >&2
    info "        \"$(printf '%s' "$changelog_msg" | grep -m1 -v '^$' | cut -c 1-60)\"" >&2
  fi
  info "  ${CYAN}3${NC}) Qo'lda yozish (editor ochiladi yoki bir qator)" >&2
  info "  ${CYAN}4${NC}) Avtomatik (\"Version ${version} released\")" >&2
  info "  ${CYAN}5${NC}) Bo'sh qoldirish" >&2
  echo >&2

  local choice notes
  read -p "  Tanlang [1-5] [4]: " choice
  choice="${choice:-4}"

  case "$choice" in
    1) notes="$git_msg" ;;
    2) notes="$changelog_msg" ;;
    3)
      if [ -n "$EDITOR" ] && command -v "$EDITOR" > /dev/null 2>&1; then
        local tmp
        tmp=$(mktemp)
        echo "# Release notes — bu qatorlar olib tashlanadi" > "$tmp"
        echo "# Quyida release notes yozing va saqlab chiqing" >> "$tmp"
        echo "" >> "$tmp"
        "$EDITOR" "$tmp"
        notes=$(grep -v '^#' "$tmp")
        rm -f "$tmp"
      else
        info "  (Editor topilmadi — bir qator kiriting)" >&2
        read -p "    Release notes: " notes
      fi
      ;;
    4) notes="Version ${version} released" ;;
    5|*) notes="" ;;
  esac

  # 500 belgi cheklov
  notes=$(truncate_release_notes "$notes" 500)

  if [ -n "$notes" ]; then
    info "Release notes:" >&2
    info "  $(printf '%s' "$notes" | head -3 | sed 's/^/  /')" >&2
  fi

  printf '%s' "$notes"
}

# ─── Settings menyulari ─────────────────────────────────

settings_main_menu() {
  while true; do
    banner "Flutter Build Tool — Sozlamalar"

    echo -e "  ${BOLD}╭─ Bo'limlar ─────────────────────────────────────────╮${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) Build defaults    — checkbox oldindan tanlovlar     ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) Akkauntlar        — Play va App Store boshqaruvi   ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) Loyihalar         — sozlangan ro'yxat, tahrirlash  ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}4${NC}) Auto-update       — yoqish/o'chirish, timeout      ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}5${NC}) iOS Team ID       — ExportOptions.plist uchun      ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}6${NC}) Joriy sozlamalar  — ro'yxatda ko'rish               ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}7${NC}) Factory reset     — barchasini boshlang'ich holatga ${BOLD}│${NC}"
    echo -e "  ${BOLD}├─────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}q${NC}) Chiqish                                              ${BOLD}│${NC}"
    echo -e "  ${BOLD}╰─────────────────────────────────────────────────────${NC}"
    echo
    read -p "  Tanlang [1-7, q]: " choice

    case "$choice" in
      1) settings_build_defaults ;;
      2) settings_accounts_menu ;;
      3) settings_projects_menu ;;
      4) settings_auto_update ;;
      5) settings_ios_team_id ;;
      6) show_settings_summary; read -p "  Davom etish uchun Enter..." _ ;;
      7) settings_factory_reset ;;
      q|Q|"") return 0 ;;
      *) warn "Noto'g'ri tanlov" ;;
    esac
  done
}

# Build defaults — checkbox menyusi orqali
settings_build_defaults() {
  banner "Build defaults — har deploy'da oldindan tanlanadi"

  info "Bu sozlamalar build menyu birinchi marta ko'rsatilganda"
  info "default checkbox holatlarini belgilaydi. Foydalanuvchi"
  info "har deploy'da o'zgartira oladi."
  echo

  CHECKBOX_INITIAL=(
    "$DEFAULT_PRODUCTION"
    "$DEFAULT_ANDROID"
    "$DEFAULT_IOS"
    "$DEFAULT_FLUTTER_CLEAN"
    "$DEFAULT_FLUTTER_PUB_GET"
    "$DEFAULT_AAB"
    "$DEFAULT_APK"
    "$DEFAULT_APPSTORE_UPLOAD"
    "$DEFAULT_PLAYSTORE_UPLOAD"
  )
  arrow_checkbox "Default tanlovlarni belgilang (Space toggle, Enter saqlash)" \
    "Production" \
    "Android" \
    "iOS" \
    "flutter clean" \
    "flutter pub get" \
    "AAB format (Android)" \
    "APK format (Android)" \
    "App Store Connect upload" \
    "Play Store upload"

  DEFAULT_PRODUCTION="${CHECKBOX_RESULT[0]}"
  DEFAULT_ANDROID="${CHECKBOX_RESULT[1]}"
  DEFAULT_IOS="${CHECKBOX_RESULT[2]}"
  DEFAULT_FLUTTER_CLEAN="${CHECKBOX_RESULT[3]}"
  DEFAULT_FLUTTER_PUB_GET="${CHECKBOX_RESULT[4]}"
  DEFAULT_AAB="${CHECKBOX_RESULT[5]}"
  DEFAULT_APK="${CHECKBOX_RESULT[6]}"
  DEFAULT_APPSTORE_UPLOAD="${CHECKBOX_RESULT[7]}"
  DEFAULT_PLAYSTORE_UPLOAD="${CHECKBOX_RESULT[8]}"

  # Android track ham
  echo
  info "Android Play Store default track (internal/alpha/beta/production)"
  info "Hozirgi: ${BOLD}${DEFAULT_ANDROID_TRACK}${NC}"
  read -p "    Yangi track [${DEFAULT_ANDROID_TRACK}]: " track
  if [ -n "$track" ]; then
    case "$track" in
      internal|alpha|beta|production)
        DEFAULT_ANDROID_TRACK="$track"
        ;;
      *)
        warn "Noto'g'ri track — o'zgartirilmadi (${DEFAULT_ANDROID_TRACK} qoladi)"
        ;;
    esac
  fi

  save_settings
  ok "Build defaults saqlandi"
  echo
  read -p "  Davom etish uchun Enter..." _
}

# Akkauntlar boshqaruv menyusi
settings_accounts_menu() {
  while true; do
    banner "Akkauntlar boshqaruvi"

    echo -e "  ${BOLD}╭─ Mavjud akkauntlar ────────────────────────────────${NC}"
    echo -e "  ${BOLD}│${NC}  ${BOLD}Play Store:${NC}"
    local count=0
    local name email
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      email=$(play_account_get "$name" "client_email")
      printf "  ${BOLD}│${NC}     • ${CYAN}%-20s${NC} %s\n" "$name" "$email"
      count=$((count + 1))
    done < <(play_list_accounts)
    [ "$count" -eq 0 ] && echo -e "  ${BOLD}│${NC}     ${YELLOW}(yo'q)${NC}"

    echo -e "  ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${BOLD}App Store:${NC}"
    count=0
    local kid iid
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      kid=$(appstore_account_get "$name" "key_id")
      iid=$(appstore_account_get "$name" "issuer_id")
      printf "  ${BOLD}│${NC}     • ${CYAN}%-20s${NC} Key %s / %s…\n" "$name" "$kid" "${iid:0:8}"
      count=$((count + 1))
    done < <(appstore_list_accounts)
    [ "$count" -eq 0 ] && echo -e "  ${BOLD}│${NC}     ${YELLOW}(yo'q)${NC}"
    echo -e "  ${BOLD}╰────────────────────────────────────────────────────${NC}"

    echo
    echo -e "  ${BOLD}Amallar:${NC}"
    echo -e "    ${CYAN}1${NC}) Yangi Play Store akkaunti qo'shish"
    echo -e "    ${CYAN}2${NC}) Yangi App Store akkaunti qo'shish"
    echo -e "    ${CYAN}3${NC}) Play Store akkauntini o'chirish"
    echo -e "    ${CYAN}4${NC}) App Store akkauntini o'chirish"
    echo -e "    ${CYAN}b${NC}) Orqaga"
    echo
    read -p "  Tanlang [1-4, b]: " choice

    case "$choice" in
      1) play_add_new_account "" ;;
      2) appstore_add_new_account "" ;;
      3) settings_delete_play_account ;;
      4) settings_delete_appstore_account ;;
      b|B|"") return 0 ;;
      *) warn "Noto'g'ri tanlov" ;;
    esac
  done
}

settings_delete_play_account() {
  local accounts=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && accounts+=("$name")
  done < <(play_list_accounts)

  if [ ${#accounts[@]} -eq 0 ]; then
    warn "Play Store akkauntlari yo'q"
    return 0
  fi

  echo
  info "O'chirishni xohlagan akkauntni tanlang:"
  local i=1
  for name in "${accounts[@]}"; do
    printf "    ${CYAN}%d${NC}) %s\n" "$i" "$name"
    i=$((i + 1))
  done
  printf "    ${CYAN}%d${NC}) Bekor qilish\n" "$i"
  echo
  read -p "  Tanlang [1-${i}]: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#accounts[@]}" ]; then
    local target="${accounts[$((choice - 1))]}"
    warn "Akkaunt '${target}' o'chiriladi (loyihalar config'i ham buziladi!)"
    read -p "  Aniqmi? (y/n) [n]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      rm -f "$(play_account_file "$target")"
      ok "Akkaunt o'chirildi: ${target}"
      info "Eslatma: shu akkauntga ulangan loyihalar config'i endi ishlamaydi"
    fi
  fi
}

settings_delete_appstore_account() {
  local accounts=()
  local name
  while IFS= read -r name; do
    [ -n "$name" ] && accounts+=("$name")
  done < <(appstore_list_accounts)

  if [ ${#accounts[@]} -eq 0 ]; then
    warn "App Store akkauntlari yo'q"
    return 0
  fi

  echo
  info "O'chirishni xohlagan akkauntni tanlang:"
  local i=1
  for name in "${accounts[@]}"; do
    printf "    ${CYAN}%d${NC}) %s\n" "$i" "$name"
    i=$((i + 1))
  done
  printf "    ${CYAN}%d${NC}) Bekor qilish\n" "$i"
  echo
  read -p "  Tanlang [1-${i}]: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#accounts[@]}" ]; then
    local target="${accounts[$((choice - 1))]}"
    warn "Akkaunt '${target}' o'chiriladi (loyihalar config'i ham buziladi!)"
    read -p "  Aniqmi? (y/n) [n]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      rm -f "$(appstore_account_file "$target")"
      ok "Akkaunt o'chirildi: ${target}"
    fi
  fi
}

# Loyihalar boshqaruv menyusi
settings_projects_menu() {
  banner "Sozlangan loyihalar"

  echo -e "  ${BOLD}Android (Play Store):${NC}"
  local count=0 line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    echo "$line"
    count=$((count + 1))
  done < <(play_list_projects)
  [ "$count" -eq 0 ] && echo -e "    ${YELLOW}(yo'q)${NC}"

  echo
  echo -e "  ${BOLD}iOS (App Store):${NC}"
  count=0
  local dir
  dir=$(appstore_projects_dir)
  if [ -d "$dir" ]; then
    local f bundle account
    for f in "$dir"/*.json; do
      [ -f "$f" ] || continue
      grep -q '"v15.bak"' "$f" 2>/dev/null && continue
      bundle=$(basename "$f" .json)
      account=$(grep '"account"' "$f" | sed -E 's/.*"account"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      [ -n "$account" ] && echo "  • ${bundle} → ${account}" && count=$((count + 1))
    done
  fi
  [ "$count" -eq 0 ] && echo -e "    ${YELLOW}(yo'q)${NC}"

  echo
  echo -e "  ${BOLD}Amallar:${NC}"
  echo -e "    ${CYAN}f${NC}) Loyiha promotion strategiyasini tanlash"
  echo -e "    ${CYAN}d${NC}) Loyiha config'ini o'chirish (qayta sozlash uchun)"
  echo -e "    ${CYAN}b${NC}) Orqaga"
  echo
  read -p "  Tanlang [f, d, b]: " choice

  case "$choice" in
    f|F) settings_project_promotion_flow ;;
    d|D) settings_delete_project ;;
    *)   return 0 ;;
  esac
}

# Loyiha promotion strategiyasini tanlash
settings_project_promotion_flow() {
  banner "Loyiha promotion strategiyasi"

  # Mavjud Android loyihalar
  local projects=()
  local dir
  dir=$(play_projects_dir)
  if [ -d "$dir" ]; then
    local f pkg
    for f in "$dir"/*.json; do
      [ -f "$f" ] || continue
      pkg=$(basename "$f" .json)
      projects+=("$pkg")
    done
  fi

  if [ ${#projects[@]} -eq 0 ]; then
    warn "Sozlangan Android loyihalar yo'q"
    echo
    read -p "  Davom etish uchun Enter..." _
    return 0
  fi

  echo
  info "Loyihani tanlang (faqat Android):"
  local i=1 p
  for p in "${projects[@]}"; do
    local cur_flow
    cur_flow=$(play_project_config_get "$p" "promotion_flow")
    printf "    ${CYAN}%d${NC}) %-30s [hozir: ${YELLOW}%s${NC}]\n" "$i" "$p" "${cur_flow:-internal_to_prod}"
    i=$((i + 1))
  done
  printf "    ${CYAN}%d${NC}) Bekor qilish\n" "$i"
  echo
  read -p "  Tanlang [1-${i}]: " pick

  if ! [[ "$pick" =~ ^[0-9]+$ ]] || [ "$pick" -lt 1 ] || [ "$pick" -gt "${#projects[@]}" ]; then
    return 0
  fi
  local target="${projects[$((pick - 1))]}"

  echo
  echo -e "  ${BOLD}Promotion strategiyani tanlang:${NC}"
  echo -e "    ${CYAN}1${NC}) ${BOLD}internal_to_prod${NC}         — Internal → Production (default)"
  echo -e "    ${CYAN}2${NC}) ${BOLD}internal_to_beta_to_prod${NC} — Internal → Beta → Production (3 bosqich)"
  echo -e "    ${CYAN}3${NC}) ${BOLD}prod_only${NC}                — Faqat Production (sinovsiz)"
  echo -e "    ${CYAN}4${NC}) ${BOLD}none${NC}                     — Promotion tavsiyasi yo'q"
  echo
  read -p "  Tanlang [1-4]: " flow_pick

  local flow
  case "$flow_pick" in
    1) flow="internal_to_prod" ;;
    2) flow="internal_to_beta_to_prod" ;;
    3) flow="prod_only" ;;
    4) flow="none" ;;
    *) warn "Bekor qilindi"; return 0 ;;
  esac

  # Joriy sozlamalarni o'qib qayta yozish (account va track saqlanadi)
  local account track
  account=$(play_project_config_get "$target" "account")
  track=$(play_project_config_get "$target" "track")
  play_project_config_save "$target" "$account" "${track:-internal}" "$flow"
  ok "Loyiha '${target}' promotion strategiyasi: ${flow}"

  echo
  read -p "  Davom etish uchun Enter..." _
}

settings_delete_project() {
  echo
  info "Qaysi platforma loyihasini o'chirasiz?"
  echo -e "    ${CYAN}1${NC}) Android (Play Store)"
  echo -e "    ${CYAN}2${NC}) iOS (App Store)"
  read -p "  Tanlang [1-2]: " plat

  local dir
  case "$plat" in
    1) dir=$(play_projects_dir) ;;
    2) dir=$(appstore_projects_dir) ;;
    *) return 0 ;;
  esac

  [ ! -d "$dir" ] && { warn "Hech qanday loyiha topilmadi"; return 0; }

  local items=()
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    items+=("$(basename "$f" .json)")
  done

  if [ ${#items[@]} -eq 0 ]; then
    warn "Loyihalar yo'q"
    return 0
  fi

  echo
  local i=1
  for f in "${items[@]}"; do
    printf "    ${CYAN}%d${NC}) %s\n" "$i" "$f"
    i=$((i + 1))
  done
  printf "    ${CYAN}%d${NC}) Bekor qilish\n" "$i"
  echo
  read -p "  Tanlang [1-${i}]: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
    local target="${items[$((choice - 1))]}"
    read -p "  Loyiha '${target}' config'ini o'chiramizmi? (y/n) [n]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      rm -f "$dir/${target}.json"
      ok "Loyiha config o'chirildi: $target"
      info "Keyingi build'da qayta sozlash so'raladi"
    fi
  fi
}

# Auto-update sozlamalari
settings_auto_update() {
  banner "Auto-update sozlamalari"

  echo
  echo -e "  ${BOLD}Joriy holat:${NC}"
  echo -e "    Yoqilgan:    $(_yn "$AUTO_UPDATE_ENABLED")"
  echo -e "    Timeout:     ${YELLOW}${AUTO_UPDATE_TIMEOUT}s${NC}"
  echo

  echo -e "  ${BOLD}Amallar:${NC}"
  echo -e "    ${CYAN}1${NC}) Yoqish/o'chirish"
  echo -e "    ${CYAN}2${NC}) Timeout o'zgartirish"
  echo -e "    ${CYAN}b${NC}) Orqaga"
  echo
  read -p "  Tanlang [1-2, b]: " choice

  case "$choice" in
    1)
      if [ "$AUTO_UPDATE_ENABLED" = "true" ]; then
        AUTO_UPDATE_ENABLED=false
        ok "Auto-update o'chirildi"
      else
        AUTO_UPDATE_ENABLED=true
        ok "Auto-update yoqildi"
      fi
      save_settings
      ;;
    2)
      read -p "  Yangi timeout (sekundlarda, hozir: ${AUTO_UPDATE_TIMEOUT}): " newt
      if [[ "$newt" =~ ^[0-9]+$ ]] && [ "$newt" -ge 1 ] && [ "$newt" -le 60 ]; then
        AUTO_UPDATE_TIMEOUT="$newt"
        save_settings
        ok "Timeout: ${newt}s"
      else
        warn "Noto'g'ri qiymat (1-60 oralig'ida bo'lishi kerak)"
      fi
      ;;
  esac

  echo
  read -p "  Davom etish uchun Enter..." _
}

# iOS Team ID sozlamasi
settings_ios_team_id() {
  banner "iOS Team ID — ExportOptions.plist uchun"

  echo
  info "Bu Team ID ios/ExportOptions.plist avtomatik yaratilganda"
  info "ishlatiladi. Apple Developer hisobingizdan oling:"
  info "https://developer.apple.com/account → Membership → Team ID"
  echo
  echo -e "  Hozirgi: ${YELLOW}${DEFAULT_IOS_TEAM_ID:-<sozlanmagan>}${NC}"
  echo

  read -p "  Yangi Team ID (10 belgi, Enter — saqlamaslik): " newt
  if [ -z "$newt" ]; then
    warn "O'zgartirilmadi"
  elif [[ "$newt" =~ ^[A-Z0-9]{10}$ ]]; then
    DEFAULT_IOS_TEAM_ID="$newt"
    save_settings
    ok "Team ID saqlandi: $newt"
  else
    warn "Team ID 10 ta katta harf/raqamdan iborat bo'lishi kerak"
  fi

  echo
  read -p "  Davom etish uchun Enter..." _
}

# Factory reset
settings_factory_reset() {
  banner "Factory reset"
  warn "Bu sozlamalar va akkauntlar JADVALINI BUZADI:"
  warn "  • Build defaults (Production, Android, iOS, va h.k.)"
  warn "  • Auto-update sozlamalari"
  warn "  • Team ID"
  warn "Akkauntlar va loyiha config'lari SAQLANADI."
  echo
  read -p "  Aniqmi? (yes/n): " confirm
  if [ "$confirm" = "yes" ]; then
    rm -f "$(settings_file)"
    # Factory default qiymatlarni qayta o'rnatish
    unset DEFAULT_PRODUCTION DEFAULT_ANDROID DEFAULT_IOS DEFAULT_FLUTTER_CLEAN
    unset DEFAULT_FLUTTER_PUB_GET DEFAULT_AAB DEFAULT_APK
    unset DEFAULT_APPSTORE_UPLOAD DEFAULT_PLAYSTORE_UPLOAD
    unset DEFAULT_ANDROID_TRACK DEFAULT_IOS_TEAM_ID
    unset AUTO_UPDATE_ENABLED AUTO_UPDATE_TIMEOUT
    set_factory_defaults
    save_settings
    ok "Factory default'lar tiklandi"
  else
    info "Bekor qilindi"
  fi
  echo
  read -p "  Davom etish uchun Enter..." _
}

# ─── Asosiy menyu (v1.10.0) ─────────────────────────────

# Asosiy menyu — flutter-build (flag'siz) ishga tushganda ko'rinadi
# Foydalanuvchi tanlovni amalga oshiradi, tugaganda menyu qaytadi
main_menu() {
  while true; do
    banner "Flutter Build Tool — Asosiy menu (v${SCRIPT_VERSION})"

    echo -e "  ${BOLD}╭─ Tanlovingiz ───────────────────────────────────────────╮${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) ${BOLD}⚡ Auto Deploy${NC} (savolsiz: build + versiya+1 + upload)  ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) ${BOLD}🚀 Build${NC} (qadam-baqadam: build + upload)             ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) ${BOLD}📤 Upload${NC} (build qilmasdan, oxirgisini yuklash)    ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}4${NC}) ⚙️  Sozlamalar                                          ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}5${NC}) 🩺 Doctor (tizim tekshiruvi)                            ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}6${NC}) ⬆️  Android track promotion                              ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}7${NC}) 📊 Rollout foizini oshirish                              ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}8${NC}) 📋 Akkauntlar va loyihalarni ko'rish                     ${BOLD}│${NC}"
    echo -e "  ${BOLD}├─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}q${NC}) Chiqish                                                   ${BOLD}│${NC}"
    echo -e "  ${BOLD}╰─────────────────────────────────────────────────────────${NC}"
    echo
    read -p "  Tanlang [1-8, q] [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
      1)
        # v1.15.0: Express (Auto Deploy) — savolsiz auto deploy
        EXPRESS_MODE=true
        if main_build_flow; then
          EXPRESS_MODE=false
          exit 0
        else
          EXPRESS_MODE=false
          echo
          warn "Auto Deploy bekor qilindi yoki xato berdi — menyu'ga qaytdik"
          pause
        fi
        ;;
      2)
        # Build flow — main_build_flow chaqiriladi (skript pastida aniqlangan)
        EXPRESS_MODE=false
        if main_build_flow; then
          # Build muvaffaqiyatli — skript chiqadi
          exit 0
        else
          # Bekor qilindi yoki xato — menyu'ga qaytamiz
          echo
          warn "Build bekor qilindi yoki xato berdi — menyu'ga qaytdik"
          pause
        fi
        ;;
      3)
        # v1.13.0: Upload-only — build qilmasdan oxirgi artifact'ni yuklash
        if upload_only_flow; then
          echo
          info "Upload yakunlandi — menu'ga qaytdik"
          pause
        else
          echo
          warn "Upload bekor qilindi yoki xato berdi — menu'ga qaytdik"
          pause
        fi
        ;;
      4)
        settings_main_menu
        ;;
      5)
        run_diagnostics
        pause
        ;;
      6)
        menu_promote_interactive
        ;;
      7)
        menu_rollout_interactive
        ;;
      8)
        menu_view_accounts_and_projects
        ;;
      q|Q)
        info "Xayr!"
        exit 0
        ;;
      *)
        warn "Noto'g'ri tanlov: '$choice'"
        sleep 1
        ;;
    esac
  done
}

# Interaktiv Android track promotion (--promote-android'ning menyu varianti)
menu_promote_interactive() {
  banner "Android Play Store track promotion"

  if [ ! -f "pubspec.yaml" ]; then
    err "pubspec.yaml topilmadi"
    info "Flutter loyihasi ildizidan ishga tushiring"
    pause
    return 0
  fi

  echo
  info "Track'lar: internal, alpha, beta, production"
  echo
  echo -e "  ${BOLD}Tipik strategiyalar:${NC}"
  echo -e "    ${CYAN}1${NC}) internal → production"
  echo -e "    ${CYAN}2${NC}) internal → beta"
  echo -e "    ${CYAN}3${NC}) beta → production"
  echo -e "    ${CYAN}4${NC}) Custom (siz kiritasiz)"
  echo -e "    ${CYAN}b${NC}) Orqaga"
  echo
  read -p "  Tanlang [1-4, b]: " strat

  local from to
  case "$strat" in
    1) from="internal"; to="production" ;;
    2) from="internal"; to="beta" ;;
    3) from="beta"; to="production" ;;
    4)
      read -p "    Source track: " from
      read -p "    Target track: " to
      ;;
    b|B|"") return 0 ;;
    *) warn "Noto'g'ri tanlov"; sleep 1; return 0 ;;
  esac

  if ! [[ "$from" =~ ^(internal|alpha|beta|production)$ ]]; then
    err "Noto'g'ri source track: $from"
    pause
    return 0
  fi
  if ! [[ "$to" =~ ^(internal|alpha|beta|production)$ ]]; then
    err "Noto'g'ri target track: $to"
    pause
    return 0
  fi

  local fraction="1.0"
  if [ "$to" = "production" ]; then
    echo
    read -p "  Production rollout (1-100%) [10]: " pct
    pct="${pct:-10}"
    if [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -ge 1 ] && [ "$pct" -le 100 ]; then
      fraction=$(awk "BEGIN{printf \"%.4f\", $pct / 100}")
    fi
  fi

  play_promote_release "$from" "$to" "$fraction"
  pause
}

# Interaktiv rollout oshirish (--increase-rollout'ning menyu varianti)
menu_rollout_interactive() {
  banner "Production rollout foizini oshirish"

  if [ ! -f "pubspec.yaml" ]; then
    err "pubspec.yaml topilmadi"
    pause
    return 0
  fi

  echo
  echo -e "  ${BOLD}Yangi rollout foizi:${NC}"
  echo -e "    ${CYAN}1${NC}) 25%"
  echo -e "    ${CYAN}2${NC}) 50%"
  echo -e "    ${CYAN}3${NC}) 75%"
  echo -e "    ${CYAN}4${NC}) 100% (to'liq rollout)"
  echo -e "    ${CYAN}5${NC}) Custom %"
  echo -e "    ${CYAN}b${NC}) Orqaga"
  echo
  read -p "  Tanlang [1-5, b]: " pick

  local pct
  case "$pick" in
    1) pct=25 ;;
    2) pct=50 ;;
    3) pct=75 ;;
    4) pct=100 ;;
    5) read -p "  Foiz (1-100): " pct ;;
    b|B|"") return 0 ;;
    *) warn "Noto'g'ri tanlov"; sleep 1; return 0 ;;
  esac

  play_increase_rollout "$pct"
  pause
}

# Akkauntlar va loyihalar ro'yxati (read-only)
menu_view_accounts_and_projects() {
  banner "Akkauntlar va loyihalar"

  echo
  echo -e "  ${BOLD}Play Store akkauntlari:${NC}"
  local count=0 name email
  local play_acc_dir="${HOME}/.config/flutter-build-tool/accounts/play"
  if [ -d "$play_acc_dir" ]; then
    for f in "$play_acc_dir"/*.json; do
      [ -f "$f" ] || continue
      name=$(basename "$f" .json)
      email=$(grep '"client_email"' "$f" 2>/dev/null | sed -E 's/.*"client_email"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      printf "    • ${CYAN}%-20s${NC} %s\n" "$name" "$email"
      count=$((count + 1))
    done
  fi
  [ "$count" -eq 0 ] && echo -e "    ${YELLOW}(yo'q)${NC}"

  echo
  echo -e "  ${BOLD}App Store akkauntlari:${NC}"
  count=0
  local app_acc_dir="${HOME}/.config/flutter-build-tool/accounts/appstore"
  if [ -d "$app_acc_dir" ]; then
    for f in "$app_acc_dir"/*.json; do
      [ -f "$f" ] || continue
      name=$(basename "$f" .json)
      local kid iid
      kid=$(grep '"key_id"' "$f" | sed -E 's/.*"key_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      iid=$(grep '"issuer_id"' "$f" | sed -E 's/.*"issuer_id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      printf "    • ${CYAN}%-20s${NC} Key %s / %s…\n" "$name" "$kid" "${iid:0:8}"
      count=$((count + 1))
    done
  fi
  [ "$count" -eq 0 ] && echo -e "    ${YELLOW}(yo'q)${NC}"

  echo
  echo -e "  ${BOLD}Sozlangan loyihalar (Play Store):${NC}"
  count=0
  local play_proj_dir="${HOME}/.config/flutter-build-tool/play"
  if [ -d "$play_proj_dir" ]; then
    for f in "$play_proj_dir"/*.json; do
      [ -f "$f" ] || continue
      local pkg account track flow
      pkg=$(basename "$f" .json)
      account=$(grep '"account"' "$f" | sed -E 's/.*"account"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      track=$(grep '"track"' "$f" | sed -E 's/.*"track"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      flow=$(grep '"promotion_flow"' "$f" | sed -E 's/.*"promotion_flow"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      printf "    • ${CYAN}%-30s${NC} → ${BOLD}%s${NC} → %s (%s)\n" "$pkg" "$account" "$track" "${flow:-internal_to_prod}"
      count=$((count + 1))
    done
  fi
  [ "$count" -eq 0 ] && echo -e "    ${YELLOW}(yo'q)${NC}"

  echo
  echo -e "  ${BOLD}Sozlangan loyihalar (App Store):${NC}"
  count=0
  local app_proj_dir="${HOME}/.config/flutter-build-tool/appstore"
  if [ -d "$app_proj_dir" ]; then
    for f in "$app_proj_dir"/*.json; do
      [ -f "$f" ] || continue
      local bundle account
      bundle=$(basename "$f" .json)
      account=$(grep '"account"' "$f" | sed -E 's/.*"account"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' | head -1)
      printf "    • ${CYAN}%-30s${NC} → ${BOLD}%s${NC}\n" "$bundle" "$account"
      count=$((count + 1))
    done
  fi
  [ "$count" -eq 0 ] && echo -e "    ${YELLOW}(yo'q)${NC}"

  echo
  info "Tahrirlash: ${BOLD}--settings${NC} → 2) Akkauntlar yoki 3) Loyihalar"
  pause
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
  # Settings'da yoqilganmi?
  [ "${AUTO_UPDATE_ENABLED:-true}" = "true" ] || return 0
  command -v curl > /dev/null 2>&1 || return 0

  local latest timeout
  timeout="${AUTO_UPDATE_TIMEOUT:-5}"
  latest=$(curl -fsSL --max-time "$timeout" "$SCRIPT_RAW_URL" 2>/dev/null \
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
    err "Yuklab olib bo'lmadi"
    rm -f "$tmp"

    # Yozish ruxsatini tekshirib, mosroq tavsiya beramiz
    if $needs_sudo 2>/dev/null && [ ! -w "$(dirname "$self")" ]; then
      info "Sabab: yozish ruxsati yo'q (skript ${self} root-egalik)"
      try_this \
        "sudo curl -fsSL ${SCRIPT_RAW_URL} -o ${self}" \
        "sudo chmod +x ${self}"
    else
      info "Sabab: tarmoq, GitHub mavjud emas yoki SSL muammosi"
      try_this \
        "curl -v -fsSL ${SCRIPT_RAW_URL}    # batafsil log uchun" \
        "ping raw.githubusercontent.com      # tarmoqni tekshirish"
    fi
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
      err "'sudo' topilmadi"
      info "Root sifatida ishga tushiring:"
      try_this \
        "cp $tmp $self" \
        "chmod +x $self"
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
      err "Sudo bilan o'rnatish xato berdi (parol noto'g'ri yoki bekor qilindi?)"
      info "Qo'lda yangilang:"
      try_this \
        "sudo cp $tmp $self" \
        "sudo chmod +x $self"
      info "Yoki to'g'ridan-to'g'ri internetdan:"
      try_this "sudo curl -fsSL ${SCRIPT_RAW_URL} -o $self && sudo chmod +x $self"
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
SETTINGS_MODE=false
DOCTOR_MODE=false
PROMOTE_MODE=false
PROMOTE_FROM=""
PROMOTE_TO=""
INCREASE_ROLLOUT_MODE=false
INCREASE_ROLLOUT_PCT=""
EXPRESS_MODE=false
EXPRESS_CLI=false   # v1.15.0: --auto flag bilan to'g'ridan-to'g'ri express
i=0
args=("$@")
while [ "$i" -lt "${#args[@]}" ]; do
  arg="${args[$i]}"
  case "$arg" in
    --no-update-check|--skip-update)
      SKIP_UPDATE=true
      ;;
    --auto|--express|-a)
      EXPRESS_CLI=true
      ;;
    --settings|-s)
      SETTINGS_MODE=true
      ;;
    --doctor|-d)
      DOCTOR_MODE=true
      ;;
    --promote-android)
      PROMOTE_MODE=true
      # Keyingi 2 ta argument: from to (ixtiyoriy — bo'lmasa interaktiv so'raydi)
      if [ "$((i + 1))" -lt "${#args[@]}" ] && [ "$((i + 2))" -lt "${#args[@]}" ]; then
        PROMOTE_FROM="${args[$((i + 1))]}"
        PROMOTE_TO="${args[$((i + 2))]}"
        i=$((i + 2))
      fi
      ;;
    --increase-rollout)
      INCREASE_ROLLOUT_MODE=true
      if [ "$((i + 1))" -lt "${#args[@]}" ]; then
        INCREASE_ROLLOUT_PCT="${args[$((i + 1))]}"
        i=$((i + 1))
      fi
      ;;
    --version|-v)
      echo "${SCRIPT_VERSION}"
      exit 0
      ;;
    --help|-h)
      cat <<EOF
Flutter Build Tool v${SCRIPT_VERSION}

Foydalanish:
  ./flutter_build.sh                              Interaktiv build
  ./flutter_build.sh --auto, --express, -a        ⚡ Savolsiz auto deploy (build + versiya+1 + upload)
  ./flutter_build.sh --settings, -s               Sozlamalar menyusi
  ./flutter_build.sh --doctor, -d                 Tizim diagnostikasi (nima ishlamayotganini ko'rish)
  ./flutter_build.sh --promote-android FROM TO    Track promotion (Android)
                                                  Misol: --promote-android internal production
  ./flutter_build.sh --increase-rollout PCT       Production rollout foizini oshirish
                                                  Misol: --increase-rollout 50
  ./flutter_build.sh --version, -v                Versiyani ko'rsatish
  ./flutter_build.sh --no-update-check            Yangilanish tekshiruvisiz
  ./flutter_build.sh --help, -h                   Bu ma'lumot

Repo: https://github.com/${SCRIPT_REPO}
EOF
      exit 0
      ;;
  esac
  i=$((i + 1))
done

# Settings'ni yuklash (har doim — build flow va settings menyu ham ishlatadi)
load_settings

# Yangilanish tekshiruvi (validatsiyadan oldin)
$SKIP_UPDATE || check_for_update

# Settings menyu rejimi — build'ga o'tmaymiz
if $SETTINGS_MODE; then
  settings_main_menu
  exit 0
fi

# Doctor rejimi — diagnostika ko'rsatish va chiqish
if $DOCTOR_MODE; then
  run_diagnostics
  exit 0
fi

# Track promotion rejimi (--promote-android)
if $PROMOTE_MODE; then
  if [ ! -f "pubspec.yaml" ]; then
    err "pubspec.yaml topilmadi (Flutter loyihasi ildizidan ishga tushiring)"
    exit 1
  fi
  if [ -z "$PROMOTE_FROM" ] || [ -z "$PROMOTE_TO" ]; then
    # Interaktiv tanlash
    banner "Android Play Store track promotion"
    info "Track'lar: internal, alpha, beta, production"
    echo
    read -p "  Source track: " PROMOTE_FROM
    read -p "  Target track: " PROMOTE_TO
  fi
  if ! [[ "$PROMOTE_FROM" =~ ^(internal|alpha|beta|production)$ ]]; then
    err "Noto'g'ri source track: $PROMOTE_FROM"
    exit 1
  fi
  if ! [[ "$PROMOTE_TO" =~ ^(internal|alpha|beta|production)$ ]]; then
    err "Noto'g'ri target track: $PROMOTE_TO"
    exit 1
  fi
  # Production'ga ko'chirilsa, rollout so'raymiz
  fraction="1.0"
  if [ "$PROMOTE_TO" = "production" ]; then
    echo
    read -p "  Production rollout (1-100%) [10]: " pct
    pct="${pct:-10}"
    if [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -ge 1 ] && [ "$pct" -le 100 ]; then
      fraction=$(awk "BEGIN{printf \"%.4f\", $pct / 100}")
    fi
  fi
  play_promote_release "$PROMOTE_FROM" "$PROMOTE_TO" "$fraction"
  exit $?
fi

# Increase rollout rejimi (--increase-rollout)
if $INCREASE_ROLLOUT_MODE; then
  if [ ! -f "pubspec.yaml" ]; then
    err "pubspec.yaml topilmadi"
    exit 1
  fi
  if [ -z "$INCREASE_ROLLOUT_PCT" ]; then
    read -p "  Yangi rollout foizi (1-100): " INCREASE_ROLLOUT_PCT
  fi
  play_increase_rollout "$INCREASE_ROLLOUT_PCT"
  exit $?
fi

# v1.15.0: Express CLI rejimi (--auto) — to'g'ridan-to'g'ri savolsiz deploy
if $EXPRESS_CLI; then
  if [ ! -f "pubspec.yaml" ]; then
    err "pubspec.yaml topilmadi (Flutter loyihasi ildizidan ishga tushiring)"
    exit 1
  fi
  EXPRESS_MODE=true
  if main_build_flow; then
    exit 0
  else
    exit 1
  fi
fi

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
  # CHECKBOX_INITIAL global array — agar belgilangan bo'lsa, undagi qiymatlarni
  # ishlatamiz (true/false). Yo'q joylar uchun "false".
  for ((i = 0; i < n; i++)); do
    if [ "$i" -lt "${#CHECKBOX_INITIAL[@]}" ]; then
      checked+=("${CHECKBOX_INITIAL[$i]:-false}")
    else
      checked+=("false")
    fi
  done
  # Keyingi chaqiruv uchun reset (default = bo'sh)
  CHECKBOX_INITIAL=()
  CHECKBOX_CANCELLED=false
  local cursor=0

  # Terminal kengligi va opsiya max uzunligi
  local cols
  cols=$(tput cols 2>/dev/null || echo 80)
  # Prefiks: "  ▶ [✓] " ≈ 8 belgi + 2 zaxira = 10 belgi
  local max_label=$((cols - 10))
  [ "$max_label" -lt 16 ] && max_label=16

  echo
  echo -e "${BOLD}${BLUE}▶${NC} ${BOLD}${title}${NC}"
  echo -e "  ${CYAN}↑/↓${NC} harakat   ${CYAN}Space${NC} tanlash   ${CYAN}Enter${NC} tasdiqlash   ${CYAN}q${NC} bekor"
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
        # Enter — tasdiqlash
        break
        ;;
      " ")
        if [ "${checked[$cursor]}" = "true" ]; then
          checked[$cursor]="false"
        else
          checked[$cursor]="true"
        fi
        ;;
      "q"|"Q")
        # 'q' bilan bekor qilish
        CHECKBOX_CANCELLED=true
        break
        ;;
      $'\x1b')
        # Strelka tugmasi (terminal yuboradi: \x1b[A va h.k.)
        # Note: sof Esc'ni bekor qilish sifatida tushunmaymiz, chunki
        # bash 3.2 (macOS) da decimal timeout reliable emas va arrow
        # key sequence to'g'ri o'qilishi uchun -t 1 kerak. Cancellation
        # uchun 'q' tugmasini ishlating.
        IFS= read -rsn2 -t 1 rest 2>/dev/null || rest=""
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

  # Keystoreni o'qib alias va expiry ni ko'rsatish (find_keytool ishlatamiz)
  local kt_bin
  kt_bin=$(find_keytool)
  if [ -n "$kt_bin" ]; then
    local kt_out
    kt_out=$("$kt_bin" -list -v -keystore "$sf" -alias "$al" -storepass "$sp" 2>&1) || {
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
  # v1.12.6: ishchi keytool'ni topish — PATH, java_home, Android Studio JBR,
  # Homebrew, SDKMan, jenv va boshqa keng tarqalgan joylardan
  local keytool_bin
  keytool_bin=$(find_keytool)

  # v1.12.7: agar topilmasa, AVTOMATIK install taklif qilamiz (brew via macOS)
  # Foydalanuvchi yes desa, biz brew install --cask zulu@17 chaqiramiz va
  # keyin find_keytool'ni qayta chaqiramiz. Bu manual install'dan oldin.
  if [ -z "$keytool_bin" ]; then
    keytool_bin=$(offer_jdk_auto_install)
  fi

  if [ -z "$keytool_bin" ]; then
    err "Ishchi keytool topilmadi"
    echo
    info "Quyidagi joylar tekshirildi:"
    info "  • PATH (\`which keytool\`)"
    info "  • macOS java_home (/usr/libexec/java_home)"
    info "  • Android Studio (/Applications/Android Studio.app/Contents/jbr/)"
    info "  • /Library/Java/JavaVirtualMachines/"
    info "  • Homebrew (openjdk, zulu, temurin)"
    info "  • SDKMan (~/.sdkman/candidates/java/)"
    info "  • jenv (~/.jenv/versions/)"
    echo
    info "${BOLD}macOS bug:${NC} /usr/bin/keytool va /usr/bin/java mavjud bo'lishi mumkin,"
    info "lekin bular Apple'ning 'Java o'rnating' stub'lari — haqiqiy JDK alohida kerak."
    echo
    try_this_install "Java JDK (haqiqiy)" \
      "Android Studio (eng oson)" "open 'https://developer.android.com/studio'" \
      "macOS (brew, tavsiya)"     "brew install --cask zulu@17" \
      "macOS (Adoptium)"          "open 'https://adoptium.net/temurin/releases/?package=jdk'" \
      "macOS (Oracle)"            "open 'https://www.oracle.com/java/technologies/downloads/'" \
      "Linux (Debian/Ubuntu)"     "sudo apt install default-jdk" \
      "Linux (Fedora/RHEL)"       "sudo dnf install java-17-openjdk-devel"
    info "O'rnatgandan keyin tekshirish: ${BOLD}java -version${NC} (versiya raqami chiqishi kerak)"
    return 1
  fi

  # Topilgan keytool PATH'da bo'lmasa, foydalanuvchiga aytamiz
  if [ "$keytool_bin" != "keytool" ]; then
    info "Ishchi Java JDK topildi: ${BOLD}$(dirname "$(dirname "$keytool_bin")")${NC}"
    info "(PATH'da Java yo'q, lekin shu yo'l orqali ishlaymiz)"
    export_java_home_from_keytool "$keytool_bin"
  fi

  step "Yangi Android keystore yaratilmoqda"

  # v1.12.5: Flutter community-popular default'lar
  # Folder: android/ (project root ichida) — .gitignore avtomatik *.jks qo'shadi
  # Filename: key.jks — Flutter tutorials va Stack Overflow'da eng tarqalgan
  # Alias: key — qisqa, ko'pchilik tutorials shuni ishlatadi
  local default_dir="android"
  local default_name="key.jks"

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

  # mkdir -p — papka yaratish (yozish ruxsati bo'lmasa explicit xato)
  if ! mkdir -p "$kdir" 2>/dev/null; then
    err "Keystore papkasini yaratib bo'lmadi: $kdir"
    info "Sabab: yozish ruxsati yo'q yoki yo'l noto'g'ri"
    try_this \
      "ls -la \"$(dirname "$kdir" 2>/dev/null || echo "$HOME")\"   # papka holatini ko'rish" \
      "mkdir -p \"$kdir\"                                          # qo'lda urinib ko'rish"
    return 1
  fi

  local al sp sp2 kp
  # v1.12.5: 'key' default — Flutter community'da eng tarqalgan
  # (rasmiy doc'da 'upload', lekin tutorials va GitHub repos'da 'key' ko'p uchraydi)
  read -p "    Key alias [key]: " al
  al="${al:-key}"

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

  # v1.12.4: keytool output'ni capture qilamiz — fail bo'lsa foydalanuvchiga ko'rsatamiz
  local keytool_log
  keytool_log=$(mktemp)

  if "$keytool_bin" -genkeypair -v \
    -keystore "$kpath" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -alias "$al" \
    -storepass "$sp" \
    -keypass "$kp" \
    -dname "$dname" > "$keytool_log" 2>&1; then
    ok "Keystore yaratildi: $kpath"
    rm -f "$keytool_log"
  else
    local rc=$?
    err "Keystore yaratishda xatolik (keytool exit code: $rc)"
    echo
    warn "${BOLD}keytool xato xabari:${NC}"
    sed 's/^/    /' "$keytool_log"
    echo

    # Specific error patterns
    local kt_out
    kt_out=$(cat "$keytool_log")
    rm -f "$keytool_log"

    if echo "$kt_out" | grep -qiE "keystore password|password.*must be at least|too short"; then
      info "${BOLD}Sabab:${NC} parol qisqa (Java majburiy 6 belgi)"
      try_this "Qayta urinib, kamida 6 belgili parol kiriting"
    elif echo "$kt_out" | grep -qiE "invalid.*name|illegal.*char|RFC2253"; then
      info "${BOLD}Sabab:${NC} sertifikat ma'lumotlarida noto'g'ri belgi (vergul, qo'shtirnoq, \\)"
      info "Faqat oddiy harflar va probel ishlatish tavsiya etiladi"
      try_this "Qayta urinib, CN/O/L'da maxsus belgilar yoki vergullar ishlatmang"
    elif echo "$kt_out" | grep -qiE "permission denied|access denied|cannot write|read-only"; then
      info "${BOLD}Sabab:${NC} fayl yoki papka yozish ruxsati yo'q"
      try_this \
        "ls -la \"$(dirname "$kpath")\"   # ruxsatlarni ko'rish" \
        "chmod u+w \"$(dirname "$kpath")\" # yozish ruxsati berish"
    elif echo "$kt_out" | grep -qiE "JKS keystore uses a proprietary format|migrate to PKCS12"; then
      info "${BOLD}Sabab:${NC} JDK 17+ JKS o'rniga PKCS12 talab qiladi"
      info "Bu ogohlantirish, lekin xato emas — keystore yaratilgan bo'lishi mumkin"
      try_this "ls -la \"$kpath\"   # fayl bormi tekshirish"
    elif echo "$kt_out" | grep -qiE "Unable to locate a Java Runtime|No Java runtime|JRE.*not found|visit http://www.java.com"; then
      info "${BOLD}Sabab:${NC} Java JDK haqiqatan o'rnatilmagan (macOS keytool stub bug'i)"
      info "macOS'da /usr/bin/keytool stub mavjud, lekin haqiqiy JDK o'rnatilishi shart"
      try_this_install "Java JDK" \
        "macOS (brew, tavsiya)" "brew install --cask zulu@17" \
        "macOS (Adoptium)"      "open https://adoptium.net/temurin/releases/?package=jdk" \
        "Linux (Debian)"        "sudo apt install default-jdk"
    elif echo "$kt_out" | grep -qiE "unknown.*command|unrecognized|JAVA_HOME"; then
      info "${BOLD}Sabab:${NC} JDK noto'g'ri o'rnatilgan yoki JAVA_HOME muammosi"
      try_this \
        "java -version    # Java versiyasini ko'rish" \
        "which keytool    # keytool yo'lini ko'rish" \
        "echo \$JAVA_HOME  # JAVA_HOME tekshirish"
    else
      info "Eng keng tarqalgan sabablar:"
      info "  • Parol kamida 6 belgi bo'lishi kerak"
      info "  • Sertifikat ma'lumotlarida noto'g'ri belgi (vergul, qo'shtirnoq)"
      info "  • Papka yozish ruxsati yo'q"
      info "  • JDK noto'g'ri o'rnatilgan"
      try_this \
        "java -version" \
        "keytool -help"
    fi
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
# v1.13.6: Smart keystore yo'lini hal qilish — kengaytma'lar va papka qidiruvi
# Foydalanuvchi `key` deb yozsa, biz `key.jks`, `key.keystore` ham sinab ko'ramiz.
# Agar papka berilsa, ichidagi keystore fayl'larni topib ko'rsatamiz.
#
# Returns: 0 + stdout yangi yo'l, 1 + stderr xato
_resolve_keystore_path() {
  local input="$1"
  # Tilde expansion
  input="${input/#\~/$HOME}"

  # 1. To'g'ridan-to'g'ri fayl
  if [ -f "$input" ]; then
    printf '%s\n' "$input"
    return 0
  fi

  # 2. Kengaytma qo'shib sinab ko'rish (eng tez-tez)
  local ext
  for ext in .jks .keystore .pk12 .p12; do
    if [ -f "${input}${ext}" ]; then
      info "Kengaytma avtomatik qo'shildi: ${BOLD}${ext}${NC}" >&2
      printf '%s\n' "${input}${ext}"
      return 0
    fi
  done

  # 3. Papka bo'lsa — ichidagi keystore'larni topish
  if [ -d "$input" ]; then
    info "'$input' — papka. Ichida keystore qidirilmoqda..." >&2
    local candidates count
    candidates=$(find "$input" -maxdepth 3 -type f \
      \( -name "*.jks" -o -name "*.keystore" -o -name "*.pk12" -o -name "*.p12" \) 2>/dev/null)
    if [ -z "$candidates" ]; then
      err "Bu papka ichida keystore fayli (.jks/.keystore/.p12) topilmadi" >&2
      info "Papka ichidagi fayllar:" >&2
      ls -la "$input" 2>/dev/null | head -15 >&2
      return 1
    fi

    count=$(echo "$candidates" | wc -l | tr -d ' ')
    if [ "$count" = "1" ]; then
      ok "Avtomatik topildi: ${BOLD}${candidates}${NC}" >&2
      printf '%s\n' "$candidates"
      return 0
    fi

    # Bir nechta — foydalanuvchidan tanlash
    echo >&2
    info "Bir nechta keystore topildi:" >&2
    local i=1 line
    while IFS= read -r line; do
      echo "    ${i}) ${line}" >&2
      i=$((i + 1))
    done <<< "$candidates"
    echo >&2
    local sel
    read -p "    Qaysi birini tanlaysiz (raqam): " sel </dev/tty
    local selected
    selected=$(echo "$candidates" | sed -n "${sel}p")
    if [ -z "$selected" ] || [ ! -f "$selected" ]; then
      err "Noto'g'ri tanlov: $sel" >&2
      return 1
    fi
    printf '%s\n' "$selected"
    return 0
  fi

  # 4. Hech narsa topilmadi
  err "Fayl yoki papka topilmadi: $input" >&2
  info "Tekshiring: ${BOLD}ls -la \"$(dirname "$input" 2>/dev/null || echo "$HOME")\"${NC}" >&2
  return 1
}

link_existing_keystore() {
  step "Mavjud keystoreni ulash"

  local kpath al sp kp raw_path
  read -p "    Keystore fayliga to'liq yo'l: " raw_path

  # v1.13.6: Smart path resolution (kengaytma, papka, tilde)
  kpath=$(_resolve_keystore_path "$raw_path") || {
    err "Keystore yo'lini hal qilib bo'lmadi"
    return 1
  }

  # v1.13.6: keytool topish — agar yo'q bo'lsa, qisqartirilgan workflow
  local lk_bin
  lk_bin=$(find_keytool)
  if [ -z "$lk_bin" ]; then
    warn "keytool topilmadi — keystore tekshirib bo'lmaydi (skip mode)"
    info "Keystore baribir ulanadi, lekin parol/alias to'g'riligi build vaqtida bilinadi"
    echo
    read -p "    Key alias: " al
    read -s -p "    Keystore parol: " sp; echo
    read -s -p "    Key parol [keystore parol bilan bir xil]: " kp; echo
    kp="${kp:-$sp}"
    write_key_properties "$sp" "$kp" "$al" "$kpath"
    ensure_gitignore_for_keys
    ensure_gradle_signing_config
    return 0
  fi

  # v1.13.6: Avval keystore parol'ini test qilamiz (alias'siz)
  # Bu bizga 3 ta narsa beradi: (a) parol to'g'rimi, (b) format to'g'rimi, (c) alias'lar ro'yxati
  read -s -p "    Keystore parol: " sp; echo

  echo
  step "Keystore o'qilmoqda (parol va format tekshiruvi)..."
  local keystore_test rc
  keystore_test=$("$lk_bin" -list -keystore "$kpath" -storepass "$sp" 2>&1)
  rc=$?

  # v1.13.8: Java runtime stub aniqlash — find_keytool xato qaytargan bo'lishi mumkin
  # (yoki keytool ishlatilgan vaqtda Java yo'qoldi). Auto-install taklif qilamiz.
  if [ $rc -ne 0 ] && echo "$keystore_test" | grep -qiE "Unable to locate a Java Runtime|No Java runtime|couldn.t be completed|visit (http|www)\.java\.com"; then
    err "Keystore'ni o'qib bo'lmadi — Java JDK ishlamayapti"
    echo
    info "${BOLD}Sabab:${NC} keytool topildi, lekin Java Runtime yo'q (macOS stub bug)"
    info "keytool yo'li: ${lk_bin}"
    echo
    # Auto-install taklif (create_new_keystore'dagi kabi)
    local new_kt
    new_kt=$(offer_jdk_auto_install)
    if [ -n "$new_kt" ]; then
      ok "Yangi ishchi keytool: ${BOLD}${new_kt}${NC}"
      lk_bin="$new_kt"
      export_java_home_from_keytool "$lk_bin"
      # Qayta urinib ko'ramiz
      echo
      step "Keystore qayta o'qilmoqda (yangi Java bilan)..."
      keystore_test=$("$lk_bin" -list -keystore "$kpath" -storepass "$sp" 2>&1)
      rc=$?
    else
      info "Java o'rnatilmadi — keystore tekshirilmasdan davom etamiz (skip mode)"
      info "Parol/alias to'g'riligi build vaqtida bilinadi"
      echo
      read -p "    Key alias: " al
      read -s -p "    Key parol [keystore parol bilan bir xil]: " kp; echo
      kp="${kp:-$sp}"
      write_key_properties "$sp" "$kp" "$al" "$kpath"
      ensure_gitignore_for_keys
      ensure_gradle_signing_config
      return 0
    fi
  fi

  if [ $rc -ne 0 ]; then
    err "Keystore'ni o'qib bo'lmadi"
    echo
    # Aniq sabab'ni topish (pattern-based)
    if echo "$keystore_test" | grep -qiE "password was incorrect|keystore password was incorrect|Keystore was tampered"; then
      info "${BOLD}Sabab:${NC} Keystore paroli NOTO'G'RI"
      info "Aniq xato xabari:"
      echo "$keystore_test" | head -3 | sed 's/^/    /'
      echo
      info "Yechim'lar:"
      info "  1. Parolingizni qayta tekshiring (caps lock, klaviatura tili)"
      info "  2. Boshqa parol urinib ko'ring"
      info "  3. Keystore yaratilganda yozib qo'ygan parol fayli bo'lsa qarang"
    elif echo "$keystore_test" | grep -qiE "Invalid keystore format|magic number|not a Java keystore"; then
      info "${BOLD}Sabab:${NC} Fayl JKS/PKCS12 format emas"
      info "Fayl ma'lumotlari:"
      file "$kpath" 2>/dev/null | sed 's/^/    /'
      info "Yechim: to'g'ri keystore fayl yo'lini kiriting (.jks yoki .keystore)"
    elif echo "$keystore_test" | grep -qiE "FileNotFoundException|NoSuchFileException"; then
      info "${BOLD}Sabab:${NC} Fayl mavjud emas (lekin biz uni topgan edik — g'alati holat)"
      info "Yo'l: $kpath"
    else
      info "${BOLD}Sabab:${NC} aniq emas — keytool javobi:"
      echo "$keystore_test" | head -5 | sed 's/^/    /'
    fi
    return 1
  fi

  ok "Keystore o'qildi — parol to'g'ri va format JKS/PKCS12"

  # Mavjud alias'larni ekstrakt qilish
  # keytool output format:
  #   Your keystore contains N entries
  #
  #   alias1, date, PrivateKeyEntry,
  #   Certificate fingerprint (SHA-256): XX:XX:...
  local available_aliases
  available_aliases=$(echo "$keystore_test" | awk -F',' '/, PrivateKey/ {print $1}' | sed 's/^ *//')

  if [ -z "$available_aliases" ]; then
    # Boshqa format'da urinish (eski keytool versiyalar)
    available_aliases=$(echo "$keystore_test" | grep -E "^[a-zA-Z0-9_-]+," | cut -d',' -f1)
  fi

  if [ -n "$available_aliases" ]; then
    echo
    info "${BOLD}Keystore ichidagi alias'lar:${NC}"
    echo "$available_aliases" | while IFS= read -r a; do
      [ -n "$a" ] && info "  • ${BOLD}$a${NC}"
    done
    echo
  else
    warn "Keystore o'qildi, lekin alias'larni avtomatik ekstrakt qila olmadik"
    info "keytool javobi:"
    echo "$keystore_test" | head -10 | sed 's/^/    /'
    echo
  fi

  read -p "    Key alias: " al

  # Alias mavjudligini tekshirish
  if [ -n "$available_aliases" ]; then
    if ! echo "$available_aliases" | grep -qFx "$al"; then
      err "Bunday alias yo'q: '${BOLD}${al}${NC}'"
      info "Yuqoridagi ro'yxatdan birini tanlang (case-sensitive)"
      info "Mavjud alias'lar:"
      echo "$available_aliases" | while IFS= read -r a; do
        [ -n "$a" ] && info "  • $a"
      done
      return 1
    fi
  fi

  read -s -p "    Key parol [keystore parol bilan bir xil]: " kp; echo
  kp="${kp:-$sp}"

  # Alias bilan to'liq tekshiruv (key parolini ham sinab ko'rish)
  local alias_test alias_rc
  alias_test=$("$lk_bin" -list -keystore "$kpath" -alias "$al" -storepass "$sp" 2>&1)
  alias_rc=$?
  if [ $alias_rc -ne 0 ]; then
    err "Alias bilan tekshirib bo'lmadi"
    echo "$alias_test" | head -3 | sed 's/^/    /'
    return 1
  fi

  ok "Keystore va alias to'liq tekshirildi: ${BOLD}${al}${NC}"
  info "Keystore yo'li: ${kpath}"

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

  # v1.15.2: Express rejim — key.properties bor bo'lsa, savol bermaymiz (joriy
  # keystore bilan davom). Yo'q bo'lsa, express avtomatik yarata olmaydi (parol
  # kerak) — xato berib chiqamiz.
  if [ "${EXPRESS_MODE:-false}" = "true" ]; then
    if $has_props; then
      info "android/key.properties topildi — joriy keystore bilan davom (Express)"
      return 0
    else
      err "android/key.properties topilmadi — Express rejim signing'siz davom eta olmaydi"
      info "Avval bir marta oddiy build bilan keystore sozlang:"
      info "  ${BOLD}flutter-build${NC} → 2) Build → Android → keystore yarating/ulang"
      exit 1
    fi
  fi

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

# v1.12.0: API Key (.p8) — Owner/Admin uchun
# Eski API saqlanadi (backwards-compat) lekin endi auth_type field bilan
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
  "auth_type": "api_key",
  "key_id": "${key_id}",
  "issuer_id": "${issuer_id}",
  "key_path": "${key_path}"
}
JSON
  chmod 600 "$file"
}

# v1.12.0: Apple ID + App-specific password — Developer ham qila oladi
# Argument 'via' = "altool" (xcrun) yoki "transporter" (iTMSTransporter)
appstore_account_save_apple_id() {
  local name="$1" apple_id="$2" app_pwd="$3" via="${4:-altool}"
  local file dir auth_type
  auth_type="apple_id_${via}"
  file=$(appstore_account_file "$name")
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"
  cat > "$file" <<JSON
{
  "name": "${name}",
  "auth_type": "${auth_type}",
  "apple_id": "${apple_id}",
  "app_specific_password": "${app_pwd}"
}
JSON
  chmod 600 "$file"
}

# Backwards-compat: eski format'da auth_type yo'q bo'lsa "api_key" deb qabul qilamiz
appstore_account_get_auth_type() {
  local name="$1"
  local at
  at=$(appstore_account_get "$name" "auth_type")
  [ -z "$at" ] && at="api_key"
  printf '%s' "$at"
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
  echo -e "  ${BOLD}Authentication usulini tanlang:${NC}"
  echo
  echo -e "    ${CYAN}1${NC}) ${BOLD}API Key (.p8)${NC} ${YELLOW}— Owner/Admin role kerak${NC}"
  echo -e "          App Store Connect → Users and Access → Integrations → Keys"
  echo -e "          ${GREEN}(eng kuchli, team-wide)${NC}"
  echo
  echo -e "    ${CYAN}2${NC}) ${BOLD}Apple ID + App-specific password${NC} ${GREEN}— Developer ham qila oladi${NC}"
  echo -e "          appleid.apple.com → Security → App-Specific Passwords"
  echo -e "          ${YELLOW}(sizning shaxsiy Apple ID, Owner ruxsati shart emas)${NC}"
  echo
  echo -e "    ${CYAN}3${NC}) ${BOLD}Apple ID + Transporter app${NC}"
  echo -e "          Transporter.app o'rnatilgan bo'lsa (Mac App Store, free)"
  echo -e "          ${YELLOW}(Apple ID + app-specific password bilan, ammo iTMSTransporter CLI orqali)${NC}"
  echo -e "          ${RED}⚠ Tavsiya: Method 2 (altool) ishonchliroq — Transporter Java muammolari bo'lishi mumkin${NC}"
  echo
  echo -e "    ${CYAN}b${NC}) Orqaga"
  echo
  read -p "  Tanlang [1-3, b]: " method

  case "$method" in
    1)   appstore_add_api_key_account "$bundle" ;;
    2)   appstore_add_apple_id_account "$bundle" "altool" ;;
    3)   appstore_add_apple_id_account "$bundle" "transporter" ;;
    b|B|"") return 1 ;;
    *) warn "Noto'g'ri tanlov"; return 1 ;;
  esac
}

# .p8 API Key bilan akkaunt qo'shish (Owner/Admin)
appstore_add_api_key_account() {
  local bundle="$1"

  echo
  echo -e "  ${BOLD}API Key (.p8) sozlash usulini tanlang:${NC}"
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
  echo -e "  ${BOLD}Akkaunt nomi${NC} — credentials uchun foydalanuvchi-do'st label"
  read -p "  Akkaunt nomi [${default_name}]: " name
  name="${name:-$default_name}"
  name=$(sanitize_account_name "$name")

  if appstore_account_exists "$name"; then
    warn "Akkaunt '${name}' allaqachon mavjud"
    read -p "  Qayta yozamizmi? (y/n) [n]: " replace
    [[ ! "$replace" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }
  fi

  appstore_account_save "$name" "$key_id" "$issuer_id" "$key_path"
  ok "Akkaunt qo'shildi: ${BOLD}${name}${NC} (API Key)"

  if [ -n "$bundle" ]; then
    appstore_project_config_save "$bundle" "$name"
    ok "Loyiha bog'landi: ${bundle} → '${name}'"
  fi
}

# Apple ID + App-specific password bilan akkaunt qo'shish
# Argument 'via': "altool" (xcrun) yoki "transporter" (iTMSTransporter)
appstore_add_apple_id_account() {
  local bundle="$1" via="$2"

  echo
  step "Apple ID bilan akkaunt qo'shish (${via})"
  echo
  info "Bu usul ${BOLD}Developer rolida ham ishlaydi${NC} — Owner ruxsati shart emas."
  info "Sizning shaxsiy Apple ID'ingiz orqali team app'ingizga upload qiladi."
  echo
  echo -e "  ${BOLD}App-specific password yaratish:${NC}"
  info "  1. appleid.apple.com → Sign In"
  info "  2. ${BOLD}Security${NC} bo'limi → ${BOLD}App-Specific Passwords${NC}"
  info "  3. ${BOLD}Generate Password${NC} → Label: 'flutter-build'"
  info "  4. Yaratilgan parol formati: ${YELLOW}xxxx-xxxx-xxxx-xxxx${NC} (4 ta 4-belgili guruh)"
  info "  5. Parolni clipboard'ga ko'chiring (bu yerda kiritamiz)"
  echo
  read -p "  Brauzerda ochaymi? (y/n) [y]: " openit
  if [[ ! "$openit" =~ ^[Nn]$ ]]; then
    open_url "https://appleid.apple.com/account/manage"
    pause "  App-specific password yaratganingizdan keyin Enter..."
  fi

  # Transporter tanlanganda binary'ni tekshiramiz
  if [ "$via" = "transporter" ]; then
    local itms="/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter"
    if [ ! -x "$itms" ]; then
      err "Transporter.app topilmadi"
      info "Mac App Store'dan Transporter o'rnating (free, Apple rasmiy):"
      try_this "open 'macappstore://itunes.apple.com/app/id1450874784'"
      return 1
    fi
    ok "Transporter CLI topildi: $itms"
  fi

  # Apple ID va parolni kiritish
  local apple_id app_pwd
  echo
  read -p "    Apple ID (email): " apple_id
  if [[ ! "$apple_id" =~ @ ]]; then
    err "Apple ID email shaklida bo'lishi kerak (masalan: you@example.com)"
    return 1
  fi

  read -s -p "    App-specific password (xxxx-xxxx-xxxx-xxxx): " app_pwd
  echo
  if [ -z "$app_pwd" ]; then
    err "Parol bo'sh bo'lishi mumkin emas"
    return 1
  fi

  # Format validation (warning, lekin block emas)
  if [[ ! "$app_pwd" =~ ^[a-zA-Z]{4}-[a-zA-Z]{4}-[a-zA-Z]{4}-[a-zA-Z]{4}$ ]]; then
    warn "Parol formati standart emas (xxxx-xxxx-xxxx-xxxx kutilgan)"
    info "Asosiy Apple ID parolingiz EMAS, app-specific password ishlatish kerak"
    read -p "  Davom etamizmi shu parol bilan? (y/n) [n]: " cont
    [[ ! "$cont" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }
  fi

  # Akkaunt nomi
  echo
  local default_name name
  default_name=$(sanitize_account_name "${apple_id%%@*}")
  echo -e "  ${BOLD}Akkaunt nomi${NC} — credentials uchun foydalanuvchi-do'st label"
  read -p "  Akkaunt nomi [${default_name}]: " name
  name="${name:-$default_name}"
  name=$(sanitize_account_name "$name")

  if appstore_account_exists "$name"; then
    warn "Akkaunt '${name}' allaqachon mavjud"
    read -p "  Qayta yozamizmi? (y/n) [n]: " replace
    [[ ! "$replace" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }
  fi

  appstore_account_save_apple_id "$name" "$apple_id" "$app_pwd" "$via"
  ok "Akkaunt qo'shildi: ${BOLD}${name}${NC} (Apple ID via ${via})"
  warn "App-specific password ${YELLOW}~/.config/flutter-build-tool/accounts/appstore/${name}.json${NC} da saqlanadi (chmod 600)"

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
  local i=1 acc_name auth_type display
  for acc_name in "${accounts[@]}"; do
    auth_type=$(appstore_account_get_auth_type "$acc_name")
    # Auth method'ga ko'ra display
    case "$auth_type" in
      api_key)
        local kid iid
        kid=$(appstore_account_get "$acc_name" "key_id")
        iid=$(appstore_account_get "$acc_name" "issuer_id")
        display="API Key ${kid} / ${iid:0:8}…"
        ;;
      apple_id_altool)
        local aid
        aid=$(appstore_account_get "$acc_name" "apple_id")
        display="Apple ID: ${aid} (altool)"
        ;;
      apple_id_transporter)
        local aid
        aid=$(appstore_account_get "$acc_name" "apple_id")
        display="Apple ID: ${aid} (transporter)"
        ;;
      *)
        display="(noma'lum auth: $auth_type)"
        ;;
    esac
    printf "  ${BOLD}│${NC}  ${CYAN}%d${NC}) ${BOLD}%-22s${NC} %s\n" \
      "$i" "$acc_name" "$display"
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
      # Auth_type'ga ko'ra tekshirish
      local auth_type
      auth_type=$(appstore_account_get_auth_type "$account")

      case "$auth_type" in
        api_key)
          local kid kp
          kid=$(appstore_account_get "$account" "key_id")
          kp=$(appstore_account_get "$account" "key_path")
          if [ ! -f "$kp" ]; then
            warn "Akkaunt '${account}' ning .p8 fayli yo'qolgan: $kp"
            appstore_add_new_account "" || return 1
            appstore_pick_account_for_project "$current_bundle" || return 1
            return 0
          fi
          ok "App Store: ${BOLD}${current_bundle}${NC} → '${BOLD}${account}${NC}' (API Key ${YELLOW}${kid}${NC}) ${CYAN}(saqlangan)${NC}"
          ;;
        apple_id_altool|apple_id_transporter)
          local aid via
          aid=$(appstore_account_get "$account" "apple_id")
          via="${auth_type#apple_id_}"
          if [ "$via" = "transporter" ] && [ ! -x "/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter" ]; then
            warn "Akkaunt '${account}' Transporter ishlatmoqchi, lekin Transporter.app topilmadi"
            try_this "open 'macappstore://itunes.apple.com/app/id1450874784'"
            return 1
          fi
          ok "App Store: ${BOLD}${current_bundle}${NC} → '${BOLD}${account}${NC}' (Apple ID ${YELLOW}${aid}${NC} via ${via}) ${CYAN}(saqlangan)${NC}"
          ;;
        *)
          warn "Akkaunt '${account}' noma'lum auth_type'ga ega: $auth_type"
          info "Qayta sozlash uchun: flutter-build --settings"
          return 1
          ;;
      esac
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

  # v1.15.2: Express rejim — plist yo'q bo'lsa avtomatik yarata olmaydi (Team ID kerak)
  if [ "${EXPRESS_MODE:-false}" = "true" ]; then
    err "${plist} topilmadi — Express rejim avtomatik yarata olmaydi (Team ID kerak)"
    info "Avval bir marta oddiy build bilan sozlang:"
    info "  ${BOLD}flutter-build${NC} → 2) Build → iOS → ExportOptions yarating"
    return 1
  fi

  warn "${plist} topilmadi"
  info "Bu fayl 'flutter build ipa --export-options-plist' uchun kerak"
  echo
  read -p "  Yaratib beraymi? (y/n): " create
  [[ ! "$create" =~ ^[Yy]$ ]] && { warn "Bekor qilindi"; return 1; }

  local team_id
  # Settings'dan saqlangan default Team ID, agar bor bo'lsa
  local default_team="${DEFAULT_IOS_TEAM_ID:-}"
  if [ -n "$default_team" ]; then
    read -p "    Apple Team ID (10 belgi) [${default_team}]: " team_id
    team_id="${team_id:-$default_team}"
  else
    read -p "    Apple Team ID (10 belgi, Apple Developer hisobingizdan): " team_id
  fi
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

# IPA fayl yo'lini topish — multi-location qidirish.
# Flutter CLI va Xcode IPA'ni turli joylarga yozadi.
# v1.13.3: 5 ta joydan qidiradi (catch-all recursive qo'shildi)
#
#   1. Flutter CLI default:    build/ios/ipa/
#   2. Flutter CLI eski:       build/ios/iphoneos/
#   3. Xcode build joyi:       ios/build/
#   4. Loyiha ildizi:          ./ (Xcode export'i odatda shu yerga)
#   5. Catch-all recursive:    build/ va ios/ ichida har qaerda
find_latest_ipa() {
  # 1. Flutter CLI default
  local d1="build/ios/ipa"
  if [ -d "$d1" ]; then
    local ipa
    ipa=$(find "$d1" -maxdepth 1 -name "*.ipa" -type f 2>/dev/null | head -1)
    if [ -n "$ipa" ]; then
      printf '%s\n' "$ipa"
      return 0
    fi
  fi

  # 2. Flutter CLI ba'zi eski versiyalar
  local d2="build/ios/iphoneos"
  if [ -d "$d2" ]; then
    local ipa
    ipa=$(find "$d2" -maxdepth 1 -name "*.ipa" -type f 2>/dev/null | head -1)
    if [ -n "$ipa" ]; then
      printf '%s\n' "$ipa"
      return 0
    fi
  fi

  # 3. Xcode build joyi
  if [ -d "ios/build" ]; then
    local ipa
    ipa=$(find "ios/build" -maxdepth 5 -name "*.ipa" -type f 2>/dev/null | head -1)
    if [ -n "$ipa" ]; then
      printf '%s\n' "$ipa"
      return 0
    fi
  fi

  # 4. Loyiha ildizi (Xcode export)
  local ipa
  ipa=$(find . -maxdepth 2 -name "*.ipa" -type f 2>/dev/null | head -1)
  if [ -n "$ipa" ]; then
    printf '%s\n' "$ipa"
    return 0
  fi

  # 5. v1.13.3: Catch-all recursive — build/ va ios/ ichida har qaerda
  if [ -d "build" ]; then
    ipa=$(find "build" -maxdepth 6 -name "*.ipa" -type f 2>/dev/null | head -1)
    if [ -n "$ipa" ]; then
      printf '%s\n' "$ipa"
      return 0
    fi
  fi
  if [ -d "ios" ]; then
    ipa=$(find "ios" -maxdepth 6 -name "*.ipa" -type f 2>/dev/null | head -1)
    if [ -n "$ipa" ]; then
      printf '%s\n' "$ipa"
      return 0
    fi
  fi

  return 1
}

# v1.12.2: altool output'da xato pattern'larini aniqlash
# xcrun altool ba'zan HTTP 4xx holatda ham exit code 0 qaytaradi.
# Bu false positive — output'ni parse qilib haqiqiy holatni aniqlaymiz.
#
# Returns:
#   0 — haqiqatan muvaffaqiyatli (no error patterns)
#   1 — output'da xato pattern topildi (false positive himoyalandi)
appstore_altool_output_has_errors() {
  local output="$1"
  # Apple ContentDelivery / altool xato pattern'lari
  echo "$output" | grep -qE "^[0-9-]+ +[0-9:.]+ ERROR:|Failed to upload|ENTITY_ERROR|status : [45][0-9][0-9]"
}

# 409 Duplicate version'ni aniqlash va batafsil recovery taklif qilish
appstore_handle_409_duplicate() {
  local output="$1"
  local prev_ver
  prev_ver=$(echo "$output" | grep -o "previousBundleVersion[[:space:]]*:[[:space:]]*[0-9]*" \
    | head -1 | grep -o "[0-9]*$")
  [ -z "$prev_ver" ] && prev_ver="?"

  echo
  warn "Bundle version conflict: Apple'da allaqachon build ${BOLD}${prev_ver}${NC} bor"
  info "Yangi build raqami ${BOLD}> ${prev_ver}${NC} bo'lishi shart"
  echo
  info "${BOLD}🎯 Sabab va yechim:${NC}"
  info ""
  info "  ${BOLD}A) Build raqami pubspec.yaml'da hali oshirilmagan${NC}"
  try_this \
    "flutter-build   # menu'da build #ga '+' bosing (avtomatik +1)" \
    "# yoki: pubspec.yaml'da version: X.Y.Z+N → N+1 ga qo'lda o'zgartiring"
  echo
  info "  ${BOLD}B) Pubspec'da yangi build bor, lekin IPA'da hali eski (cache)${NC}"
  info "       Bu Flutter build cache muammosi — eski IPA qayta upload bo'lyapti"
  try_this \
    "rm -rf build/ios   # eski IPA o'chirish" \
    "flutter clean       # to'liq cache tozalash" \
    "flutter-build       # qayta build (menu'da 'flutter clean' va 'flutter pub get' yoqing)"
  echo
  info "  ${BOLD}C) iOS project.pbxproj sync emas${NC}"
  info "       Eski iOS loyihalarda CFBundleVersion hardcoded bo'lishi mumkin"
  info "       (Flutter reference \$(FLUTTER_BUILD_NUMBER) ishlatmagan)"
  try_this \
    "grep CURRENT_PROJECT_VERSION ios/Runner.xcodeproj/project.pbxproj   # tekshirish"
}

# Upload xato bo'lganda umumiy recovery tavsiyalari (auth_type'ga qarab)
appstore_upload_recovery_hints() {
  local auth_type="$1"
  echo
  info "Eng keng tarqalgan sabablar va yechimlar:"
  info "  ${BOLD}• Bundle ID App Store Connect'da yaratilmagan${NC}"
  try_this "open https://appstoreconnect.apple.com/apps   # 'New App' tugmasini bosing"
  info "  ${BOLD}• Versiya raqami avval yuklangan${NC}"
  try_this "flutter-build   # menu'da versiyaga '+' bosing (+1 oshiradi)"
  info "  ${BOLD}• Distribution certificate yaroqsiz/eskirgan${NC}"
  try_this "open 'Xcode → Settings → Accounts → Manage Certificates'"
  info "  ${BOLD}• ExportOptions.plist'da Team ID noto'g'ri${NC}"
  try_this \
    "rm ios/ExportOptions.plist                # qayta yaratish uchun" \
    "flutter-build --settings                   # Team ID ni global default qiling"

  if [[ "$auth_type" == apple_id* ]]; then
    info "  ${BOLD}• App-specific password noto'g'ri yoki eskirgan${NC}"
    try_this \
      "open https://appleid.apple.com/account/manage   # Security → App-Specific Passwords" \
      "flutter-build --settings   # → 2) Akkauntlar → o'chirib, yangidan qo'shing"
    info "  ${BOLD}• Sizning Apple ID team'ga qo'shilmagan${NC}"
    info "       Owner sizni App Store Connect → Users and Access da qo'shishi kerak"
  else
    info "  ${BOLD}• API Key (.p8) o'chirilgan yoki eskirgan${NC}"
    try_this "open https://appstoreconnect.apple.com/access/integrations/api"
  fi
}

# v1.12.0: Multi-method upload — auth_type'ga ko'ra dispatcher
upload_to_appstore() {
  local ipa="$1"

  step "App Store Connect ga yuklash"

  if ! command -v xcrun > /dev/null 2>&1; then
    err "xcrun topilmadi — Xcode Command Line Tools o'rnatilmagan"
    try_this_install "Xcode Command Line Tools" \
      "macOS" "xcode-select --install"
    return 1
  fi

  # Bundle → akkaunt resolve
  local bundle_id account auth_type
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

  if [ ! -f "$ipa" ]; then
    err "IPA fayl topilmadi: $ipa"
    return 1
  fi

  auth_type=$(appstore_account_get_auth_type "$account")

  local size_kb size_mb
  size_kb=$(du -k "$ipa" | cut -f1)
  size_mb=$((size_kb / 1024))
  info "IPA:        $ipa (${size_mb} MB)"
  info "Akkaunt:    ${BOLD}${account}${NC}"
  info "Auth usuli: ${BOLD}${auth_type}${NC}"

  # Auth method'ga ko'ra dispatch
  case "$auth_type" in
    api_key)
      appstore_upload_via_api_key "$ipa" "$account"
      ;;
    apple_id_altool)
      appstore_upload_via_apple_id_altool "$ipa" "$account"
      ;;
    apple_id_transporter)
      appstore_upload_via_apple_id_transporter "$ipa" "$account"
      ;;
    *)
      err "Noma'lum auth_type: $auth_type"
      info "Akkauntni qayta sozlang:"
      try_this "flutter-build --settings   # → 2) Akkauntlar → o'chirib, qayta qo'shing"
      return 1
      ;;
  esac
}

# Method 1: API Key (.p8) — Owner/Admin
# v1.12.2: output capture + false positive guard
appstore_upload_via_api_key() {
  local ipa="$1" account="$2"
  local kid iid
  kid=$(appstore_account_get "$account" "key_id")
  iid=$(appstore_account_get "$account" "issuer_id")

  if [ -z "$kid" ] || [ -z "$iid" ]; then
    err "API Key sozlamasi to'liq emas (Key ID yoki Issuer ID yo'q)"
    return 1
  fi

  info "Key ID:     $kid"
  info "Jarayon 5-30 daqiqa davom etishi mumkin. Ulanish uzilmasligi muhim."
  echo

  # tee orqali real-time output + capture
  local output_file rc output
  output_file=$(mktemp)

  xcrun altool --upload-app \
       --type ios \
       --file "$ipa" \
       --apiKey "$kid" \
       --apiIssuer "$iid" 2>&1 | tee "$output_file"
  rc=${PIPESTATUS[0]}

  output=$(cat "$output_file")
  rm -f "$output_file"

  # CRITICAL: altool ba'zan exit 0 qaytaradi HTTP 4xx holatda ham (false positive)
  if [ "$rc" -eq 0 ] && ! appstore_altool_output_has_errors "$output"; then
    echo
    ok "Muvaffaqiyatli yuklandi!"
    info "TestFlight processing 10-30 daqiqa davom etadi"
    info "Status uchun email kuting yoki: https://appstoreconnect.apple.com/apps"
    return 0
  fi

  # Failure
  echo
  err "Yuklash xato berdi (rc=${rc}, output'da ERROR pattern topildi)"
  if [ "$rc" -eq 0 ]; then
    warn "altool exit code = 0 lekin output'da xato bor — false positive himoyalandi"
  fi

  # Specific: 409 duplicate version
  if echo "$output" | grep -qE "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE|already been used|previousBundleVersion"; then
    appstore_handle_409_duplicate "$output"
    return 1
  fi

  # Specific: API Key authentication errors
  if echo "$output" | grep -qE "Unauthorized|Invalid.*Key|status : 40[13]"; then
    echo
    warn "API Key authentication xato"
    try_this "open https://appstoreconnect.apple.com/access/integrations/api"
    return 1
  fi

  appstore_upload_recovery_hints "api_key"
  return 1
}

# Method 2: Apple ID + App-specific password orqali xcrun altool
# v1.12.2: output capture + false positive guard (altool ba'zan 4xx'da ham 0 qaytaradi)
appstore_upload_via_apple_id_altool() {
  local ipa="$1" account="$2"
  local apple_id app_pwd
  apple_id=$(appstore_account_get "$account" "apple_id")
  app_pwd=$(appstore_account_get "$account" "app_specific_password")

  if [ -z "$apple_id" ] || [ -z "$app_pwd" ]; then
    err "Apple ID yoki app-specific password yo'q (akkaunt: ${account})"
    return 1
  fi

  info "Apple ID:   ${apple_id}"
  info "Tool:       xcrun altool"
  info "Jarayon 5-30 daqiqa davom etishi mumkin. Ulanish uzilmasligi muhim."
  echo

  # tee orqali real-time output + capture
  local output_file rc output
  output_file=$(mktemp)

  xcrun altool --upload-app \
       --type ios \
       --file "$ipa" \
       --username "$apple_id" \
       --password "$app_pwd" 2>&1 | tee "$output_file"
  rc=${PIPESTATUS[0]}

  output=$(cat "$output_file")
  rm -f "$output_file"

  # CRITICAL: altool ba'zan exit 0 qaytaradi HTTP 4xx holatda ham (false positive)
  # Output'da xato pattern bo'lsa, false positive deb hisoblaymiz
  if [ "$rc" -eq 0 ] && ! appstore_altool_output_has_errors "$output"; then
    echo
    ok "Muvaffaqiyatli yuklandi!"
    info "TestFlight processing 10-30 daqiqa davom etadi"
    info "Status uchun email kuting yoki: https://appstoreconnect.apple.com/apps"
    return 0
  fi

  # Failure
  echo
  err "Yuklash xato berdi (rc=${rc}, output'da ERROR pattern topildi)"
  if [ "$rc" -eq 0 ]; then
    warn "altool exit code = 0 lekin output'da xato bor — false positive himoyalandi"
  fi

  # Specific: 409 duplicate version
  if echo "$output" | grep -qE "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE|already been used|previousBundleVersion"; then
    appstore_handle_409_duplicate "$output"
    return 1
  fi

  # Specific: authentication errors
  if echo "$output" | grep -qE "Unauthorized|Authentication failed|Invalid password|status : 40[13]"; then
    echo
    warn "Authentication xato — Apple ID yoki app-specific password noto'g'ri"
    info "App-specific password tekshiruvi:"
    info "  • Apple asosiy paroli EMAS (xxxx-xxxx-xxxx-xxxx format'da)"
    info "  • Eskirgan yoki revoke qilingan bo'lishi mumkin"
    try_this \
      "open https://appleid.apple.com/account/manage   # Security → App-Specific Passwords" \
      "flutter-build --settings   # → 2) Akkauntlar → o'chirib yangidan qo'shing"
    return 1
  fi

  # Generic recovery
  appstore_upload_recovery_hints "apple_id_altool"
  return 1
}

# Method 3: Apple ID + iTMSTransporter CLI (Transporter.app)
appstore_upload_via_apple_id_transporter() {
  local ipa="$1" account="$2"
  local apple_id app_pwd itms

  apple_id=$(appstore_account_get "$account" "apple_id")
  app_pwd=$(appstore_account_get "$account" "app_specific_password")
  itms="/Applications/Transporter.app/Contents/itms/bin/iTMSTransporter"

  if [ -z "$apple_id" ] || [ -z "$app_pwd" ]; then
    err "Apple ID yoki app-specific password yo'q"
    return 1
  fi
  if [ ! -x "$itms" ]; then
    err "iTMSTransporter binary topilmadi: $itms"
    info "Mac App Store'dan Transporter.app o'rnating:"
    try_this "open 'macappstore://itunes.apple.com/app/id1450874784'"
    return 1
  fi

  info "Apple ID:   ${apple_id}"
  info "Tool:       iTMSTransporter (Transporter.app CLI)"
  info "Jarayon 5-30 daqiqa davom etishi mumkin"
  echo

  # v1.12.1: Output'ni ham ko'rsatamiz, ham capture qilamiz (tee orqali)
  # — real-time progress yoqotmaymiz, lekin error pattern'larni topa olamiz
  local output_file rc
  output_file=$(mktemp)

  "$itms" -m upload \
       -u "$apple_id" \
       -p "$app_pwd" \
       -assetFile "$ipa" 2>&1 | tee "$output_file"
  rc=${PIPESTATUS[0]}

  if [ "$rc" -eq 0 ]; then
    rm -f "$output_file"
    echo
    ok "Muvaffaqiyatli yuklandi (Transporter)!"
    info "TestFlight processing 10-30 daqiqa davom etadi"
    return 0
  fi

  # Xato — pattern aniqlash va auto-fallback taklifi
  local output
  output=$(cat "$output_file")
  rm -f "$output_file"

  err "Transporter yuklash xato berdi (rc=$rc)"

  # Specific error: "Client configuration failed" — Transporter ichki muammosi
  if echo "$output" | grep -q "Client configuration failed"; then
    echo
    warn "Bu Transporter'ning '${BOLD}Client configuration failed${NC}' xatosi"
    info "Sabab odatda quyidagilardan biri:"
    info "  • Bundled Java JRE buzuq yoki eskirgan (Transporter.app ichidagi)"
    info "  • ~/.itmstransporter/ ruxsatlari yoki cache muammosi"
    info "  • Transporter.app versiyasi eskirgan"
    echo
    info "${BOLD}🎯 Eng tezkor yechim: altool method'iga o'tish${NC}"
    info "  Xuddi shu Apple ID + password ishlatadi, lekin xcrun altool"
    info "  (Apple'ning native binary'si — Java kerak emas, ishonchli)"
    echo
    express_read try_altool "y" "  Hozir altool bilan qayta urinaylikmi? (y/n) [y]: "
    if [[ ! "$try_altool" =~ ^[Nn]$ ]]; then
      echo
      info "altool bilan qayta urinish..."
      echo
      appstore_upload_via_apple_id_altool "$ipa" "$account"
      local altool_rc=$?
      if [ "$altool_rc" -eq 0 ]; then
        echo
        ok "✓ altool muvaffaqiyatli ishladi!"
        info "Tavsiya: ${BOLD}akkauntni altool method'iga o'tkazing${NC} (Transporter kerak emas):"
        try_this \
          "flutter-build --settings   # → 2) Akkauntlar → ${account} o'chirib qayta yarating" \
          "# Bu safar: 2 (Apple ID + altool) tanlang"
      fi
      return $altool_rc
    fi
    echo
    info "Boshqa yechimlar (Transporter saqlash uchun):"
    try_this \
      "open '/Applications/Transporter.app'   # qo'lda ochib drag-drop sinab ko'rish" \
      "rm -rf ~/.itmstransporter && retry      # cache tozalash" \
      "open 'macappstore://itunes.apple.com/app/id1450874784'   # Transporter yangilash"
    return 1
  fi

  # Specific error: Authentication / Unauthorized
  if echo "$output" | grep -qE "Unauthorized|Authentication failed|Invalid password|401"; then
    echo
    warn "Authentication xato — Apple ID yoki password noto'g'ri"
    info "App-specific password tekshiruvi:"
    info "  • Apple asosiy paroli EMAS (xxxx-xxxx-xxxx-xxxx format'da)"
    info "  • Eskirgan yoki revoked bo'lishi mumkin"
    try_this \
      "open https://appleid.apple.com/account/manage   # Security → App-Specific Passwords" \
      "flutter-build --settings   # → 2) Akkauntlar → o'chirib yangidan qo'shing"
    return 1
  fi

  # Boshqa xatolar — umumiy recovery
  appstore_upload_recovery_hints "apple_id_transporter"
  return 1
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
# v1.8.0: promotion_flow qo'shildi — qaysi tartibda promote qilish kerakligi
#   - "internal_to_prod"           — internal → production (default)
#   - "internal_to_beta_to_prod"   — internal → beta → production
#   - "prod_only"                  — faqat production (sinovsiz)
#   - "none"                       — promotion tavsiya etilmaydi
play_project_config_save() {
  local pkg="$1" account="$2" track="$3" promotion_flow="${4:-internal_to_prod}"
  local file dir
  file=$(play_project_config_file "$pkg")
  dir=$(dirname "$file")
  mkdir -p "$dir"
  chmod 700 "$dir"
  cat > "$file" <<JSON
{
  "account": "${account}",
  "package_name": "${pkg}",
  "track": "${track}",
  "promotion_flow": "${promotion_flow}"
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
    --connect-timeout 30 --max-time 120 \
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

# ─── v1.8.0: Track promotion va rollout boshqaruvi ─────

# Track'dagi joriy release'larni olish. Natija: versionCode raqamlar (har qator).
# v1.12.3: edit context ichida o'qiymiz — bu Google Play API'ning to'g'ri patterni.
# Avval edit'siz GET ishlatardik, lekin u eventual consistency muammosiga duch
# kelishi mumkin (yangi yuklangan release darrov ko'rinmasligi).
play_list_track_releases() {
  local token="$1" package_name="$2" track="$3"
  local api_base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${package_name}"

  # 1) Edit yaratish (read-only ishlatish uchun)
  local edit_response edit_id
  edit_response=$(curl -fsS -X POST "${api_base}/edits" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null) || return 1
  edit_id=$(extract_json_field "$edit_response" "id")
  [ -z "$edit_id" ] && return 1

  # 2) Track holatini edit ichida o'qish (snapshot — ishonchli)
  local response
  response=$(curl -fsS \
    "${api_base}/edits/${edit_id}/tracks/${track}" \
    -H "Authorization: Bearer ${token}" 2>/dev/null)

  # 3) Edit'ni o'chirib tashlaymiz (o'zgartirish qilmadik — commit kerak emas)
  #    Bu Play Console'da "dangling draft" qoldirmaslik uchun.
  curl -fsS -X DELETE "${api_base}/edits/${edit_id}" \
    -H "Authorization: Bearer ${token}" > /dev/null 2>&1 || true

  [ -z "$response" ] && return 1

  # versionCodes ni parse qilamiz
  printf '%s' "$response" | grep -oE '"versionCodes":[[:space:]]*\[[^]]+\]' | head -1 \
    | grep -oE '"[0-9]+"' | tr -d '"'
}

# Track promotion: bir track'dan boshqasiga ko'chirish
# Argumentlar: from_track, to_track, user_fraction (optional, default 1.0)
play_promote_release() {
  local from_track="$1" to_track="$2" user_fraction="${3:-1.0}"

  # Loyihaning package_name'i va akkauntini aniqlash
  local package_name account sa_path
  package_name=$(detect_android_package_name)
  if [ -z "$package_name" ]; then
    err "Android applicationId aniqlanmadi"
    return 1
  fi

  account=$(play_project_config_get "$package_name" "account")
  if [ -z "$account" ] || ! play_account_exists "$account"; then
    err "Loyiha '${package_name}' uchun akkaunt sozlanmagan"
    return 1
  fi

  sa_path=$(play_account_get "$account" "service_account_path")
  if [ ! -f "$sa_path" ]; then
    err "Service Account JSON yo'qolgan: $sa_path"
    return 1
  fi

  step "Track promotion: ${from_track} → ${to_track}"

  # Access token
  info "[1/4] Access token olinmoqda..."
  local jwt token
  jwt=$(play_generate_jwt "$sa_path") || return 1
  token=$(play_get_access_token "$jwt") || return 1

  # Source track'dagi versionCodes
  info "[2/4] ${from_track} track release'lari o'qilmoqda..."
  local version_codes
  version_codes=$(play_list_track_releases "$token" "$package_name" "$from_track")
  if [ -z "$version_codes" ]; then
    err "${from_track} track'da release topilmadi"
    echo
    info "${BOLD}Sabab va yechim:${NC}"
    info "  • ${from_track} track hali bo'sh — avval AAB upload qilish kerak"
    info "  • Yoki upload muvaffaqiyatsiz tugagan bo'lishi mumkin"
    try_this \
      "flutter-build   # menu'da Play Store upload ni yoqib qayta urinib ko'ring"
    info ""
    info "Tekshirish uchun Play Console'da ko'ring:"
    try_this \
      "open 'https://play.google.com/console/u/0/developers/-/app/${package_name}/tracks/${from_track}'"
    return 1
  fi
  # Bir nechta versionCode bo'lsa, eng kattasini olamiz
  local latest_vc
  latest_vc=$(echo "$version_codes" | sort -n | tail -1)
  ok "Topildi: versionCode=${latest_vc}"

  # Edit yaratish
  info "[3/4] Edit yaratilmoqda..."
  local api_base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${package_name}"
  local edit_id
  edit_id=$(curl -fsS -X POST "${api_base}/edits" \
    -H "Authorization: Bearer ${token}" -d '{}' 2>/dev/null \
    | extract_json_field /dev/stdin "id" 2>/dev/null)
  # ^ Hack: extract_json_field stdout dan o'qiy olmaydi, qayta ishlatamiz:
  local edit_response
  edit_response=$(curl -fsS -X POST "${api_base}/edits" \
    -H "Authorization: Bearer ${token}" -d '{}' 2>&1)
  edit_id=$(extract_json_field "$edit_response" "id")
  [ -z "$edit_id" ] && { err "Edit yaratish xato"; return 1; }

  # Target track'ga qo'shish
  info "[4/4] ${to_track} track'ga qo'shilmoqda..."
  local release_status="completed" user_fraction_json=""
  if [ "$to_track" = "production" ] && [ "$user_fraction" != "1.0" ] && [ "$user_fraction" != "1" ]; then
    release_status="inProgress"
    user_fraction_json=",\"userFraction\":${user_fraction}"
  fi
  local payload
  payload="{\"releases\":[{\"versionCodes\":[\"${latest_vc}\"],\"status\":\"${release_status}\"${user_fraction_json}}]}"

  curl -fsS -X PUT "${api_base}/edits/${edit_id}/tracks/${to_track}" \
    -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || { err "Track qo'shish xato"; return 1; }

  # Commit
  curl -fsS -X POST "${api_base}/edits/${edit_id}:commit" \
    -H "Authorization: Bearer ${token}" > /dev/null 2>&1 || { err "Commit xato"; return 1; }

  echo
  ok "Promote qilindi: ${from_track} (v${latest_vc}) → ${to_track}"
  if [ -n "$user_fraction_json" ]; then
    info "Rollout: $(awk "BEGIN{printf \"%.0f\", $user_fraction * 100}")%"
  fi
}

# Post-upload promotion taklifi (per-project flow asosida)
play_suggest_promotion() {
  local pkg="$1" current_track="$2"
  # v1.15.2: Express rejim — promotion taklif qilmaymiz (savolsiz auto deploy)
  [ "${EXPRESS_MODE:-false}" = "true" ] && return 0
  local flow
  flow=$(play_project_config_get "$pkg" "promotion_flow")
  flow="${flow:-internal_to_prod}"

  # Tavsiya etiladigan keyingi track
  local next_track=""
  case "$flow" in
    internal_to_prod)
      [ "$current_track" = "internal" ] && next_track="production"
      ;;
    internal_to_beta_to_prod)
      [ "$current_track" = "internal" ] && next_track="beta"
      [ "$current_track" = "beta" ] && next_track="production"
      ;;
    prod_only|none)
      return 0
      ;;
  esac

  [ -z "$next_track" ] && return 0

  echo
  info "Loyihangiz promotion strategiyasi: ${BOLD}${flow}${NC}"
  info "Keyingi qadam: ${current_track} → ${BOLD}${next_track}${NC}"
  echo
  read -p "  Hozir promote qilamizmi? (y/n) [n]: " do_promote
  if [[ "$do_promote" =~ ^[Yy]$ ]]; then
    local user_fraction="1.0"
    if [ "$next_track" = "production" ]; then
      echo
      read -p "  Production rollout (1-100%) [10]: " pct
      pct="${pct:-10}"
      if [[ "$pct" =~ ^[0-9]+$ ]] && [ "$pct" -ge 1 ] && [ "$pct" -le 100 ]; then
        user_fraction=$(awk "BEGIN{printf \"%.4f\", $pct / 100}")
      fi
    fi
    play_promote_release "$current_track" "$next_track" "$user_fraction"
  fi
}

# Production rollout foizini oshirish (in-progress release'ni)
play_increase_rollout() {
  local new_pct="$1"

  if ! [[ "$new_pct" =~ ^[0-9]+$ ]] || [ "$new_pct" -lt 1 ] || [ "$new_pct" -gt 100 ]; then
    err "Foiz 1-100 oralig'ida bo'lishi kerak"
    return 1
  fi

  local package_name account sa_path
  package_name=$(detect_android_package_name)
  account=$(play_project_config_get "$package_name" "account")
  if [ -z "$account" ] || ! play_account_exists "$account"; then
    err "Loyiha sozlanmagan"
    return 1
  fi
  sa_path=$(play_account_get "$account" "service_account_path")

  step "Production rollout: ${new_pct}% ga oshiriladi"

  local jwt token
  jwt=$(play_generate_jwt "$sa_path") || return 1
  token=$(play_get_access_token "$jwt") || return 1

  local api_base="https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${package_name}"

  # Joriy production releaseni olish
  local version_codes
  version_codes=$(play_list_track_releases "$token" "$package_name" "production")
  if [ -z "$version_codes" ]; then
    err "Production track'da release topilmadi"
    info "Rollout oshirish uchun avval production'ga release bo'lishi kerak"
    try_this \
      "flutter-build --promote-android internal production   # internal'dan promote" \
      "# yoki Play Console'da qo'lda upload"
    return 1
  fi
  local latest_vc
  latest_vc=$(echo "$version_codes" | sort -n | tail -1)

  # Edit + PATCH
  local edit_response edit_id
  edit_response=$(curl -fsS -X POST "${api_base}/edits" \
    -H "Authorization: Bearer ${token}" -d '{}' 2>&1)
  edit_id=$(extract_json_field "$edit_response" "id")
  [ -z "$edit_id" ] && { err "Edit yaratish xato"; return 1; }

  local fraction
  fraction=$(awk "BEGIN{printf \"%.4f\", $new_pct / 100}")
  local release_status="inProgress"
  [ "$new_pct" -eq 100 ] && release_status="completed"

  local payload
  payload="{\"releases\":[{\"versionCodes\":[\"${latest_vc}\"],\"status\":\"${release_status}\""
  [ "$release_status" = "inProgress" ] && payload="${payload},\"userFraction\":${fraction}"
  payload="${payload}}]}"

  curl -fsS -X PUT "${api_base}/edits/${edit_id}/tracks/production" \
    -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || { err "Track yangilash xato"; return 1; }

  curl -fsS -X POST "${api_base}/edits/${edit_id}:commit" \
    -H "Authorization: Bearer ${token}" > /dev/null 2>&1 || { err "Commit xato"; return 1; }

  ok "Production rollout endi ${new_pct}% (versionCode=${latest_vc})"
}

# Build natijasidan AAB faylini topish — multi-location qidirish.
# Flutter CLI, Android Studio Gradle, va Android Studio "Generate Signed Bundle"
# AAB'ni turli joylarga yozadi. Bu funksiya 7 ta joydan qidiradi (specificity
# ladder — eng aniq birinchi):
#
#   1. Flutter CLI default:                   build/app/outputs/bundle/release/
#   2. Android Studio Gradle default:         android/app/build/outputs/bundle/release/
#   3. Android Studio "Generate Signed Bundle": android/app/release/   (v1.13.3)
#   4. Flutter CLI flavor:                    build/app/outputs/bundle/*/
#   5. Android Studio Gradle flavor:          android/app/build/outputs/bundle/*/
#   6. Android Studio Signed Bundle flavor:   android/app/release/*/  (v1.13.3)
#   7. Catch-all recursive scan:              android/ va build/ ichida  (v1.13.3)
#
# v1.13.1: 4 ta joydan qidirardi (Android Studio Gradle default qo'shildi)
# v1.13.3: 7 ta joydan qidiradi (Android Studio "Generate Signed Bundle" qo'shildi +
#          recursive catch-all — har qanday custom build joyi)
find_latest_aab() {
  # 1. Flutter CLI default
  local p1="build/app/outputs/bundle/release/app-release.aab"
  if [ -f "$p1" ]; then
    printf '%s\n' "$p1"
    return 0
  fi

  # 2. Android Studio Gradle default (Build → Build Bundle(s))
  local p2="android/app/build/outputs/bundle/release/app-release.aab"
  if [ -f "$p2" ]; then
    printf '%s\n' "$p2"
    return 0
  fi

  # 3. v1.13.3: Android Studio "Generate Signed Bundle / APK" default
  # Bu menyu Build → Generate Signed Bundle / APK orqali ishlaydi va
  # default destinatsiya `android/app/release/` papkasidir.
  local p3="android/app/release/app-release.aab"
  if [ -f "$p3" ]; then
    printf '%s\n' "$p3"
    return 0
  fi

  # 4. Flutter CLI flavor (build/app/outputs/bundle/devRelease/, etc.)
  local f
  if [ -d "build/app/outputs/bundle" ]; then
    f=$(find "build/app/outputs/bundle" -maxdepth 2 -name "*.aab" -type f 2>/dev/null \
        | head -1)
    if [ -n "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  fi

  # 5. Android Studio Gradle flavor
  if [ -d "android/app/build/outputs/bundle" ]; then
    f=$(find "android/app/build/outputs/bundle" -maxdepth 2 -name "*.aab" -type f 2>/dev/null \
        | head -1)
    if [ -n "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  fi

  # 6. v1.13.3: Android Studio "Generate Signed Bundle" flavor
  # (foydalanuvchi flavor tanlasa, app/release/<flavor>/*.aab ga yoziladi)
  if [ -d "android/app/release" ]; then
    f=$(find "android/app/release" -maxdepth 2 -name "*.aab" -type f 2>/dev/null \
        | head -1)
    if [ -n "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  fi

  # 7. v1.13.3: Catch-all recursive scan
  # Yuqorida sanalmagan joylarni topish uchun — masalan, custom build_type yoki
  # bizning ma'lumotlar ro'yxatidan tashqaridagi build script. maxdepth 6 ham
  # to'liq qamrov, ham xavfsiz (.gradle/ va intermediates'ga juda chuqur kirmaydi).
  if [ -d "android" ]; then
    f=$(find "android" -maxdepth 6 -name "*.aab" -type f 2>/dev/null | head -1)
    if [ -n "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  fi
  if [ -d "build" ]; then
    f=$(find "build" -maxdepth 6 -name "*.aab" -type f 2>/dev/null | head -1)
    if [ -n "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  fi

  return 1
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

# v1.14.0: Bundle upload 403 handler — YANGI app uchun maxsus
# Bundle upload bosqichida 403 ko'pincha "birinchi release qo'lda kerak" degani.
# Google Play API yangi app'ning BIRINCHI versiyasini yuklay olmaydi.
#
# Args: package_name aab_path track
# Returns:
#   0 — manual upload boshlandi (xato emas)
#   1 — bekor qilindi
play_handle_bundle_403() {
  local package_name="$1" aab_path="$2" track="$3"

  # v1.15.2: Express rejim — interaktiv menyu emas, xabar berib chiqamiz (kutmaymiz)
  if [ "${EXPRESS_MODE:-false}" = "true" ]; then
    echo
    warn "${BOLD}AAB upload 403${NC} — Express rejimda to'xtatildi (savol berilmaydi)"
    info "Eng ehtimol: yangi app — birinchi release Play Console UI orqali qo'lda kerak"
    info "Yoki SA'da 'release' ruxsati yo'q"
    info "Qo'lda hal qilish: ${BOLD}flutter-build${NC} → 2) Build (Express emas) → 403 menyusi"
    return 1
  fi

  echo
  warn "${BOLD}AAB upload 403 — eng tez-tez uchraydigan sabab:${NC}"
  echo
  info "${BOLD}1. YANGI app — birinchi release qo'lda kerak (ENG EHTIMOL)${NC}"
  info "   Google Play API ${BOLD}yangi app'ning BIRINCHI versiyasini${NC} yuklay olmaydi."
  info "   Birinchi AAB Play Console UI orqali qo'lda yuklanishi SHART."
  info "   Bundan keyin API avtomatik ishlaydi."
  echo
  info "${BOLD}2. App Play Console'da hali yaratilmagan${NC}"
  info "   Package ${BOLD}${package_name}${NC} Play Console'da mavjudmi?"
  echo
  info "${BOLD}3. SA'da 'release' yoki 'edit' ruxsati yo'q${NC}"
  info "   (lekin edit yaratish ishladi — demak bu kam ehtimol)"
  echo
  info "${BOLD}4. Developer account sozlash tugallanmagan${NC}"
  info "   (to'lov profili, shartnomalar imzolanmagan)"
  echo

  echo -e "  ${BOLD}╭─ Hozir nima qilamiz? ──────────────────────────────────╮${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) ⭐ ${BOLD}Play Console UI orqali QO'LDA upload${NC} (birinchi release uchun!) ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) 🌐 App Play Console'da bormi — tekshiraman                  ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) ❌ Bekor                                                      ${BOLD}│${NC}"
  echo -e "  ${BOLD}╰─────────────────────────────────────────────────────────╯${NC}"
  echo

  local choice
  read -p "  Tanlang [1-3] [1]: " choice
  case "${choice:-1}" in
    1)
      _play_403_manual_ui_upload "$package_name" "$aab_path" "$track"
      return 0
      ;;
    2)
      echo
      step "Play Console — app holatini tekshirish"
      local url="https://play.google.com/console/u/0/developers"
      info "Account selector ochilmoqda — to'g'ri account'ni tanlang"
      open_url "$url"
      echo
      info "Tekshiring:"
      info "  1. To'g'ri account'da ${BOLD}${package_name}${NC} app bormi?"
      info "  2. Agar YO'Q — 'Create app' bosib yangi app yarating"
      info "  3. Agar BOR — 'Release' → 'Internal testing' → 'Create new release'"
      info "     birinchi AAB ni qo'lda yuklang"
      info "  4. Birinchi release'dan keyin bizning skript API orqali ishlaydi"
      echo
      # Finder'da AAB papkasi
      if [ "$(uname)" = "Darwin" ] && command -v open > /dev/null 2>&1; then
        info "AAB papkasi Finder'da ochilmoqda (drag-drop uchun)..."
        open "$(dirname "$aab_path")"
      fi
      PLAY_MANUAL_UPLOAD_INITIATED=true
      return 0
      ;;
    *)
      info "Bekor qilindi"
      return 1
      ;;
  esac
}

# 4 ta API call orqali AAB ni Play Store'ga yuklash
# v1.13.2: Commit 403 uchun interaktiv recovery menyusi.
# SA permission qo'shish admin huquqi — agar foydalanuvchi developer bo'lsa,
# admin'ga so'rov yuborishi yoki Play Console UI orqali qo'lda upload qilishi mumkin.
#
# Args: edit_id api_base jwt package_name sa_email aab_path track
# Returns:
#   0 — retry muvaffaqiyatli (commit ishladi)
#   1 — boshqa yo'l bilan davom etildi (qo'lda yoki saqlandi)
play_handle_commit_403() {
  local edit_id="$1" api_base="$2" jwt="$3" package_name="$4" sa_email="$5" aab_path="$6" track="$7"

  # v1.15.2: Express rejim — interaktiv menyu emas, xabar berib chiqamiz (kutmaymiz)
  if [ "${EXPRESS_MODE:-false}" = "true" ]; then
    echo
    warn "${BOLD}Commit 403${NC} — Express rejimda to'xtatildi (savol berilmaydi)"
    info "Sabab: Service Account'da 'Release' ruxsati yo'q"
    info "Edit ID saqlandi (24 soat amal qiladi): ${BOLD}${edit_id}${NC}"
    info "Qo'lda hal qilish: ${BOLD}flutter-build${NC} → 2) Build (Express emas) → 403 menyusi"
    return 1
  fi

  echo
  echo -e "  ${BOLD}╭─ Bu vaziyatda qaysi variant siznikiga eng yaqin? ──────╮${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) 🔧 Men Play Console adminim — hozir permission qo'shaman, RETRY ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) 📧 Men developer'man — admin'ga so'rov yuboraman              ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) 🌐 Play Console UI orqali QO'LDA upload qilaman (eng tez!)    ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}4${NC}) 💾 Edit ID'ni saqlab, keyinroq qo'lda commit                  ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}5${NC}) ❌ Bekor qilish                                                ${BOLD}│${NC}"
  echo -e "  ${BOLD}╰─────────────────────────────────────────────────────────╯${NC}"
  echo

  local choice
  read -p "  Tanlang [1-5] [3]: " choice
  choice="${choice:-3}"

  case "$choice" in
    1) _play_403_admin_retry "$edit_id" "$api_base" "$jwt" "$package_name" "$sa_email" "$track" "$aab_path" ;;
    2) _play_403_developer_template "$package_name" "$sa_email" "$track"; return 1 ;;
    3) _play_403_manual_ui_upload "$package_name" "$aab_path" "$track"; return 1 ;;
    4) _play_403_save_edit_for_later "$edit_id" "$package_name" "$sa_email"; return 1 ;;
    *) info "Bekor qilindi"; return 1 ;;
  esac
}

# v1.13.9: API orqali SA permission'ini sinab ko'rish
# MUHIM TUZATISH: avval GET /applications/{package} ishlatardik — bu Google Play
# API'da HAQIQIY ENDPOINT EMAS, doim 404 qaytaradi! Bu foydalanuvchini "noto'g'ri
# account" deb XATO yo'naltirardi. To'g'ri signal: POST /edits.
#   - POST /edits 200  = SA app'ni KO'RA OLADI (edit yarata oladi)
#   - POST /edits 403/404 = SA app'ga kira olmaydi (noto'g'ri account/link yo'q)
#   - commit 403 (alohida) = release permission yo'q (lekin app access bor)
_play_403_run_api_diagnostic() {
  local api_base="$1" token="$2" package_name="$3" sa_email="$4" track="$5"

  echo
  step "SA permission'ini API orqali tekshirish"
  echo

  # Yagona ishonchli test: edit yaratish (real endpoint)
  # 200 = SA app'ga kira oladi; 403/404 = kira olmaydi
  local edit_test_resp code_edit
  edit_test_resp=$(curl -sS -X POST "${api_base}/edits" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    -d '{}' -w '\nHTTP_CODE:%{http_code}' 2>/dev/null)
  code_edit=$(echo "$edit_test_resp" | grep '^HTTP_CODE:' | cut -d: -f2)

  # Cleanup: test edit yaratilgan bo'lsa, o'chiramiz
  if [ "$code_edit" = "200" ]; then
    local test_eid
    test_eid=$(echo "$edit_test_resp" | grep -v '^HTTP_CODE:' | extract_json_field "id" 2>/dev/null)
    if [ -n "$test_eid" ]; then
      curl -sS -X DELETE "${api_base}/edits/${test_eid}" \
        -H "Authorization: Bearer ${token}" > /dev/null 2>&1 || true
    fi
  fi

  local sa_project
  sa_project=$(_extract_sa_project "$sa_email")

  echo
  info "${BOLD}Diagnostika xulosasi:${NC}"

  if [ "$code_edit" = "200" ]; then
    # SA app'ga kira oladi (edit yarata oladi), lekin commit 403 berdi
    ok "  ✓ SA app'ni ko'ra oladi va edit yarata oladi (POST /edits: 200)"
    info "  ✓ Demak SA TO'G'RI account'da — app'ga ulangan"
    err "  ✗ Lekin commit (release) qila olmaydi — 403"
    echo
    info "${BOLD}Aniq sabab:${NC} SA'da MAXSUS '${BOLD}release${NC}' ruxsati yo'q"
    info "Boshqa ruxsat'lar bor (edit, upload), lekin 'release' alohida kerak:"
    if [ "$track" = "production" ]; then
      info "  → '${BOLD}Release to production${NC}'"
    else
      info "  → '${BOLD}Release apps to testing tracks${NC}' (${track} uchun)"
    fi
    echo
    info "${BOLD}Nega oldingi retry ishlamadi (3 ehtimol):${NC}"
    info "  1. 'Save changes' bosilmagan (faqat 'Apply' kifoya emas)"
    info "  2. Cache hali yangilanmagan (10-30 daqiqa kerak bo'lishi mumkin)"
    info "  3. Permission app-level emas, account-level qo'shilgan (noto'g'ri tab)"
    echo
    warn "${BOLD}ENG TEZ yechim:${NC} Variant 3 (Manual UI upload) — API permission kerak emas"
    info "  Sizning ${BOLD}shaxsiy Google account${NC} orqali browser'da upload qilasiz"
    info "  (siz app'ga developer/admin sifatida kira olasiz — shuning uchun ishlaydi)"
    return 0

  elif [ "$code_edit" = "404" ] || [ "$code_edit" = "403" ]; then
    err "  ✗ SA app'ga kira olmaydi (POST /edits: ${code_edit})"
    echo
    info "Bu degani: SA '${BOLD}${package_name}${NC}' app'iga ulanmagan"
    info "SA project: ${BOLD}${sa_project}${NC}"
    echo
    info "${BOLD}Sabab'lar:${NC}"
    info "  1. SA noto'g'ri Play Console account'da (multi-account)"
    info "     Account selector: ${BOLD}https://play.google.com/console/u/0/developers${NC}"
    info "  2. SA app'ga permission qo'shilmagan"
    echo
    warn "${BOLD}ENG TEZ yechim:${NC} Variant 3 (Manual UI upload) — SA umuman kerak emas"
    return 1

  else
    warn "  ? Kutilmagan HTTP kod: ${code_edit}"
    info "  Edit yaratish javobi: $(echo "$edit_test_resp" | grep -v '^HTTP_CODE:' | head -2)"
    echo
    warn "${BOLD}TAVSIYA:${NC} Variant 3 (Manual UI upload) — eng ishonchli yo'l"
    return 0
  fi
}

# v1.13.7: SA email'dan Google Cloud project nomini ekstrakt qilish
# flutter-build-deploy-478@rentmi-b2fb6.iam.gserviceaccount.com → rentmi-b2fb6
# Bu Play Console account taxmin qilishda yordam beradi
_extract_sa_project() {
  local sa_email="$1"
  echo "$sa_email" | sed -e 's/.*@//' -e 's/\.iam\.gserviceaccount\.com$//'
}

# Variant 1: Admin — Play Console'ni ochib permission qo'shish, keyin retry
_play_403_admin_retry() {
  local edit_id="$1" api_base="$2" jwt="$3" package_name="$4" sa_email="$5" track="$6"
  local aab_path="$7"  # v1.13.4: Variant 3'ga o'tish uchun kerak

  # v1.13.7: SA project'idan account taxmin qilish
  local sa_project
  sa_project=$(_extract_sa_project "$sa_email")

  echo
  step "Play Console — TO'G'RI DEVELOPER ACCOUNT tanlash"
  info "Sizning SA Google Cloud project'i: ${BOLD}${sa_project}${NC}"
  info "(bu SA shu Cloud project'da yaratilgan va bu project bilan bog'liq Play Console account)"
  echo

  warn "${BOLD}MUHIM (ko'p account'lar bo'lsa):${NC}"
  warn "Browser'da '${BOLD}Выберите аккаунт разработчика${NC}' / '${BOLD}Choose developer account${NC}' sahifa chiqishi mumkin."
  warn "Bu yerdan ${BOLD}SHAXSIY account emas${NC}, balki ${BOLD}app egasi${NC} account'ni tanlang!"
  warn "Sizning SA project nomi: ${BOLD}${sa_project}${NC} — shunga o'xshash account'ni izlang"
  warn "(masalan: agar SA project 'rentmi-b2fb6' bo'lsa, RENTME account'ni tanlang)"
  echo

  # Account selector sahifasini ochamiz — foydalanuvchi to'g'ri account'ni tanlasin
  step "Account tanlash sahifasi ochilmoqda..."
  open_url "https://play.google.com/console/u/0/developers"
  echo

  info "${BOLD}Endi quyidagilarni qiling:${NC}"
  info "  1. ${BOLD}Browser'da to'g'ri Play Console account'ni tanlang${NC}"
  info "     (SA project '${sa_project}' bilan bog'liq — app egasi)"
  info "  2. Tanlangach, chap menyuda '${BOLD}Users and permissions${NC}' (yoki 'Пользователи и разрешения') ni oching"
  info "  3. Service Account'ni toping: ${BOLD}${sa_email}${NC}"
  info "     ${BOLD}AGAR TOPILMASA${NC} — bu noto'g'ri account! Boshqasiga o'ting va qaytadan urinib ko'ring"
  info "  4. SA'ga bosing (qalam/edit ikoni)"
  info "  5. ${BOLD}'App permissions' tabini oching${NC} (Account-level emas!)"
  info "  6. ${BOLD}'Add app'${NC} bosing va ${BOLD}${package_name}${NC} loyihasini qo'shing"
  info "  7. App'ning 'Releases' bo'limidan tanlang:"
  if [ "$track" = "production" ]; then
    info "     ✓ '${BOLD}Release to production, exclude devices...${NC}' (siz production'ga yuklamoqdasiz)"
  else
    info "     ✓ '${BOLD}Release apps to testing tracks${NC}' (siz ${track} track'iga yuklamoqdasiz)"
  fi
  info "  8. ${BOLD}'Apply'${NC} bosing (app permission qo'shildi)"
  info "  9. ${BOLD}Sahifa pastidagi KO'K 'Сохранить изменения' / 'Save changes' bosing${NC}"
  info " 10. ${BOLD}5-10 daqiqa kuting${NC} (Google'da cache yangilanishi)"
  echo

  # v1.13.5: 3 ta MUHIM tekshiruv (foydalanuvchilar 'Apply' bilan to'xtab qolishadi)
  echo
  echo -e "  ${BOLD}⚠ MUHIM — qo'shimcha tekshiruv:${NC}"
  echo -e "    ${CYAN}1.${NC} Checkbox haqiqatan belgilandimi (✓ ko'k)?"
  echo -e "    ${CYAN}2.${NC} ${BOLD}Sahifa PASTI o'ng burchagidagi KO'K rangli${NC}"
  echo -e "       ${BOLD}'Сохранить изменения' / 'Save changes' tugmasini BOSDINGIZMI?${NC}"
  echo -e "    ${CYAN}3.${NC} Tepada yashil '${BOLD}Сохранено${NC}' / '${BOLD}Saved${NC}' xabar paydo bo'ldimi?"
  echo
  echo -e "  ${BOLD}Eslatma:${NC} 'Apply' kifoya emas — sahifa pastidagi 'Save' ham kerak."
  echo -e "  Save'dan keyin ${BOLD}5-15 daqiqa${NC} cache propagatsiyasi vaqti."
  echo

  local retry
  read -p "  Hammasi bajarildi, RETRY qilamizmi? (y/n) [y]: " retry
  if [[ "$retry" =~ ^[Nn]$ ]]; then
    info "Bekor qilindi — keyinroq qaytadan urinib ko'ring"
    info "Edit ID hali 24 soat amal qiladi: ${BOLD}${edit_id}${NC}"
    return 1
  fi

  # v1.13.5: Progressive backoff retry — cache propagatsiyasini kutadi
  # Strategiya: darrov urinib ko'rish (foydalanuvchi allaqachon kutgan bo'lishi mumkin),
  # keyin +60s, +120s. Jami ~3 daqiqa.
  local new_token retry_response delay attempt
  new_token=$(play_get_access_token "$jwt") || {
    err "Yangi token olib bo'lmadi"
    return 1
  }
  ok "Yangi token olindi"

  for attempt in 1 2 3; do
    echo
    case "$attempt" in
      1) step "[Attempt 1/3] Commit retry'da (darrov, ehtimol siz allaqachon kutgansiz)..." ;;
      2) step "[Attempt 2/3] Cache yangilanishi uchun 60 sekund kutib qaytadan..."
         info "(Bu vaqtda choy ichib, biroz kutib turing)"
         sleep 60
         # Yangi token ham olamiz (eski'si muddati o'tgan bo'lishi mumkin)
         new_token=$(play_get_access_token "$jwt") || return 1
         ;;
      3) step "[Attempt 3/3] Yana 120 sekund kutib so'nggi urinish..."
         info "(Bu Google'ning eventual consistency'siga bo'ysunadi)"
         sleep 120
         new_token=$(play_get_access_token "$jwt") || return 1
         ;;
    esac

    retry_response=$(curl -fsS -X POST \
      "${api_base}/edits/${edit_id}:commit" \
      -H "Authorization: Bearer ${new_token}" 2>&1)

    if [ $? -eq 0 ]; then
      echo
      ok "🎉 Commit muvaffaqiyatli! (Attempt $attempt/3'da ishladi)"
      info "Permission to'g'ri qo'shilgan va cache yangilangan."
      return 0
    fi

    # Xato — keyingi attempt'ga o'tamiz (yoki tugadi)
    if [ "$attempt" = "3" ]; then
      err "Barcha 3 ta urinish xato berdi: $retry_response"
    else
      warn "Attempt $attempt xato berdi — keyingi attempt'ga o'tamiz"
    fi
  done

  # v1.13.4: Avtomatik diagnostika
  _play_403_run_api_diagnostic "$api_base" "$new_token" "$package_name" "$sa_email" "$track"

  # Foydalanuvchiga keyingi qadamlarni taklif qilamiz
  echo
  echo -e "  ${BOLD}╭─ Hozir nima qilamiz? ──────────────────────────────────╮${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) ⭐ ${BOLD}Variant 3 — Play Console UI orqali QO'LDA upload${NC} (ENG TEZ!) ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) 🔁 Yana RETRY (5-10 daqiqa kutib, cache yangilangach)        ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) 💾 Edit ID'ni saqlash, keyinroq qo'lda                       ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}4${NC}) ❌ Bekor                                                       ${BOLD}│${NC}"
  echo -e "  ${BOLD}╰─────────────────────────────────────────────────────────╯${NC}"
  echo

  local next
  read -p "  Tanlang [1-4] [1]: " next
  next="${next:-1}"
  case "$next" in
    1) _play_403_manual_ui_upload "$package_name" "$aab_path" "$track"; return 1 ;;
    2)
      # Loop back: yana bir retry
      info "5 daqiqa kuting, keyin Enter bosing (Ctrl+C bilan to'xtatish)"
      sleep 1
      _play_403_admin_retry "$edit_id" "$api_base" "$jwt" "$package_name" "$sa_email" "$track" "$aab_path"
      return $?
      ;;
    3) _play_403_save_edit_for_later "$edit_id" "$package_name" "$sa_email"; return 1 ;;
    *) info "Bekor qilindi"; return 1 ;;
  esac
}

# Variant 2: Developer — admin'ga email/Slack uchun template ko'rsatish
_play_403_developer_template() {
  local package="$1" sa_email="$2" track="$3"

  echo
  step "Admin'ga so'rov uchun matn (copy-paste qiling)"
  echo
  echo "─────────── EMAIL/SLACK MATNI ──────────────────────────"
  cat << TEMPLATE
Salom!

Play Console'da loyiha uchun Service Account release qilish ruxsati kerak.

  Loyiha:           ${package}
  Service Account:  ${sa_email}
  Track:            ${track}

Hozirgi muammo: SA edit yarata oladi va AAB yukala oladi, lekin commit
qilish HTTP 403 xato beradi. Permission yetishmayotgani uchun.

Iltimos, quyidagilarni qiling:

  1. Play Console'da Users and permissions sahifasini oching:
     https://play.google.com/console/u/0/users-and-permissions

  2. Service Account'ni toping: ${sa_email}

  3. Edit (qalam ikoni) bosing

  4. 'App permissions' bo'limida ${package} loyihasini qo'shing

  5. 'Releases' bo'limidan quyidagi permission'ni belgilang:
TEMPLATE
  if [ "$track" = "production" ]; then
    echo "     ✓ 'Release to production, exclude devices...'"
  else
    echo "     ✓ 'Release apps to testing tracks' (internal/alpha/beta uchun)"
  fi
  cat << 'TEMPLATE'

  6. 'Apply' va 'Invite user'/Save bosing

  7. Cache yangilanishi uchun 5-30 daqiqa kuting

Rahmat!
TEMPLATE
  echo "─────────── MATN OXIRI ─────────────────────────────────"
  echo

  # macOS pbcopy bilan clipboard'ga avtomatik ko'chirish
  if command -v pbcopy > /dev/null 2>&1; then
    {
      cat << TEMPLATE
Salom!

Play Console'da loyiha uchun Service Account release qilish ruxsati kerak.

  Loyiha: ${package}
  Service Account: ${sa_email}
  Track: ${track}

Hozirgi muammo: SA edit yarata oladi va AAB yukala oladi, lekin commit qilish HTTP 403 xato beradi. Permission yetishmayotgani uchun.

Iltimos, quyidagilarni qiling:
1. Play Console > Users and permissions: https://play.google.com/console/u/0/users-and-permissions
2. SA'ni toping: ${sa_email}
3. Edit (qalam) > App permissions > ${package} qo'shing
4. Releases bo'limida 'Release apps to testing tracks' (yoki production) belgilang
5. Save, 5-30 daqiqa kuting

Rahmat!
TEMPLATE
    } | pbcopy
    info "${BOLD}✓ Matn clipboard'ga avtomatik ko'chirildi${NC} — Cmd+V bilan yopishtiring"
  else
    info "Yuqoridagi matnni qo'lda ko'chiring va admin'ga yuboring"
  fi

  echo
  info "Admin permission qo'shgach, qaytadan flutter-build ishga tushiring"
  info "Eski edit'ni shu Edit ID bilan retry qilish mumkin (24 soat amal qiladi)"
}

# Variant 3: Play Console UI orqali QO'LDA upload (eng tez yo'l, API permission ishlatmaydi)
_play_403_manual_ui_upload() {
  local package="$1" aab_path="$2" track="$3"

  echo
  step "Play Console UI — qo'lda upload (eng tez yo'l)"
  info "Bu yo'lda Service Account permission'i kerak emas — sizning Google account'ingiz"
  info "ishlatadi (siz developer bo'lsangiz, sizda upload permission bor)."
  echo

  local url="https://play.google.com/console/u/0/developers/-/app/${package}/tracks/${track}"
  info "Play Console ochilmoqda: ${BOLD}${track}${NC} track sahifasi"
  open_url "$url"
  echo

  info "${BOLD}Endi quyidagilarni qiling:${NC}"
  info "  1. ${BOLD}'Create new release'${NC} bosing (yoki 'Edit release')"
  info "  2. AAB faylni drag-drop qiling:"
  info "     ${BOLD}${aab_path}${NC}"
  info "  3. Release notes yozing (yoki avval bizning skript so'ragan notes'larni copy-paste)"
  info "  4. ${BOLD}'Save'${NC} va ${BOLD}'Next'${NC} bosing"
  info "  5. ${BOLD}'Review release'${NC} bosing"
  info "  6. ${BOLD}'Start rollout to ${track}'${NC} bosing"
  echo

  # AAB joyini Finder/Files'da ochish — drag-drop osonroq
  if [ "$(uname)" = "Darwin" ] && command -v open > /dev/null 2>&1; then
    info "AAB joylashgan papka Finder'da ochilmoqda (drag-drop uchun)..."
    open "$(dirname "$aab_path")"
  fi

  echo
  info "Bu jarayonda permission'ga ehtiyoj yo'q — to'g'ridan-to'g'ri Google account orqali"
  info "AAB allaqachon bizning skript tomonidan to'g'ri build qilingan ($([ -f "$aab_path" ] && du -h "$aab_path" | cut -f1))"

  # v1.13.9: Global flag — caller "upload xato" ko'rsatmasligi uchun
  # (manual upload — bu xato emas, balki boshqa jarayon)
  PLAY_MANUAL_UPLOAD_INITIATED=true

  echo
  info "${BOLD}Browser'da upload'ni yakunlang.${NC} Bu skript endi kutmaydi —"
  info "siz browser'da 'Start rollout' bosganingizda, ish tugaydi."
  echo
  local done_manual
  read -p "  Browser'da upload'ni yakunladingizmi? (ha/keyinroq) [keyinroq]: " done_manual
  if [[ "$done_manual" =~ ^(ha|y|yes|ok|tugadi)$ ]]; then
    ok "Ajoyib! Play Console'da release yaratildi."
    info "Internal track'ga 1-2 daqiqada, beta/production'ga 1-2 soatda paydo bo'ladi"
  else
    info "Yaxshi — browser'da o'z vaqtingizda yakunlang."
    info "Sahifa: ${BOLD}https://play.google.com/console/u/0/developers/-/app/${package}/tracks/${track}${NC}"
  fi
}

# Variant 4: Edit ID'ni saqlab, keyinroq qo'lda commit (yoki bizning skript orqali retry)
_play_403_save_edit_for_later() {
  local edit_id="$1" package="$2" sa_email="$3"

  local marker_file=".flutter-build-pending-edit.json"
  local expires_at
  if [ "$(uname)" = "Darwin" ]; then
    expires_at=$(date -u -v+24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  else
    expires_at=$(date -u -d '+24 hours' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  fi

  cat > "$marker_file" << EOF
{
  "package_name": "${package}",
  "edit_id": "${edit_id}",
  "service_account_email": "${sa_email}",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "expires_at": "${expires_at:-24 hours from now}",
  "note": "Bu edit Play Store'ga to'liq yuborilgan, faqat commit bosqichida 403 xato. Permission qo'shilgach, qo'lda commit qilish mumkin."
}
EOF

  echo
  ok "Edit ID saqlandi: ${BOLD}${marker_file}${NC}"
  info "Fayl ichidagi ma'lumotlar:"
  info "  • Package:     ${package}"
  info "  • Edit ID:     ${edit_id}"
  info "  • SA:          ${sa_email}"
  info "  • Amal qiladi: 24 soat (gacha: ${expires_at:-?})"
  echo
  info "${BOLD}Keyinroq qo'lda commit qilish uchun:${NC}"
  info "  1. Play Console'da Pending changes'ni tekshiring:"
  info "     ${BOLD}https://play.google.com/console/u/0/developers/-/app/${package}/app-dashboard${NC}"
  info "  2. 'Pending changes' bo'limida edit'ni topib commit qiling"
  info "  3. Yoki bizning skript bilan: ${BOLD}flutter-build${NC} (yangi edit yaratiladi, eskisi avtomatik discard bo'ladi)"
  echo
  info "${BOLD}MUHIM:${NC} ${marker_file} fayli .gitignore'ga qo'shilishi kerak"
  if [ -f ".gitignore" ] && ! grep -q "flutter-build-pending-edit" .gitignore; then
    echo ".flutter-build-pending-edit.json" >> .gitignore
    ok ".gitignore'ga avtomatik qo'shildi"
  fi
}

# AAB ni Play Store'ga yuklash — 5 bosqichli API pipeline
upload_to_play_store() {
  local aab="$1"

  step "Play Store ga yuklash"

  if ! command -v openssl > /dev/null 2>&1; then
    err "openssl topilmadi (JWT signing uchun kerak)"
    try_this_install "openssl" \
      "macOS" "brew install openssl@3" \
      "Linux" "sudo apt install openssl   # yoki: sudo dnf install openssl"
    return 1
  fi
  if ! command -v curl > /dev/null 2>&1; then
    err "curl topilmadi"
    try_this_install "curl" \
      "macOS" "brew install curl   # (macOS'da odatda allaqachon bor)" \
      "Linux" "sudo apt install curl   # yoki: sudo dnf install curl"
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
  if [ -n "$RELEASE_NOTES" ]; then
    info "Release notes: ${RELEASE_NOTES:0:60}…"
  fi
  if [ -n "$STAGED_ROLLOUT_FRACTION" ]; then
    info "Staged rollout: $(awk "BEGIN{printf \"%.0f\", $STAGED_ROLLOUT_FRACTION * 100}")% foydalanuvchiga"
  fi
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
    --connect-timeout 30 --max-time 120 \
    -d '{}' 2>&1) || {
      err "Edit yaratish xato: $edit_response"
      # 403 yoki 404 bo'lsa, eng keng tarqalgan sabablar
      if echo "$edit_response" | grep -q '"code": *403'; then
        info "Sabab: Service Account ruxsatlari yetishmaydi"
        try_this "open https://play.google.com/console/u/0/api-access   # Service Account'ga 'Releases' ruxsatlarini bering"
      elif echo "$edit_response" | grep -q '"code": *404'; then
        info "Sabab: app Play Console'da topilmadi yoki birinchi AAB qo'lda yuklanmagan"
        try_this "open 'https://play.google.com/console/u/0/developers/-/app/${package_name}/app-dashboard'"
      fi
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
  # v1.15.3: 98MB+ fayl uchun PROGRESS BAR — avval 'curl -fsS' sukut bilan
  # yuklardi (progress yo'q), sekin internetda qotgandek ko'rinardi.
  # Endi: --progress-bar terminalga, response body faylga, http_code alohida.
  info "[3/5] AAB yuklanmoqda (${size_mb} MB) — progress pastda ko'rinadi:"
  info "(katta fayl + sekin internet = bir necha daqiqa, bu normal)"
  local upload_response version_code upload_body_file upload_http upload_rc
  upload_body_file=$(mktemp 2>/dev/null || echo "/tmp/fb_play_upload.$$")
  # --progress-bar -> stderr (terminalda ko'rinadi), body -> -o fayl, kod -> -w stdout
  # --connect-timeout 30, --max-time 1800 (30 daqiqa) — cheksiz hang oldini oladi
  upload_http=$(curl -S --progress-bar -X POST \
    "${upload_base}/edits/${edit_id}/bundles?uploadType=media" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${aab}" \
    --connect-timeout 30 --max-time 1800 \
    -o "$upload_body_file" -w '%{http_code}')
  upload_rc=$?
  upload_response=$(cat "$upload_body_file" 2>/dev/null)
  rm -f "$upload_body_file"
  echo  # progress bar'dan keyin yangi qator

  # Xato: curl muvaffaqiyatsiz (network/timeout) YOKI HTTP >= 400
  if [ "$upload_rc" -ne 0 ] || { [ -n "$upload_http" ] && [ "$upload_http" -ge 400 ] 2>/dev/null; }; then
      if [ "$upload_rc" -eq 28 ]; then
        err "AAB yuklash timeout (30 daqiqa) — internet juda sekin yoki uzildi"
        info "Qayta urinib ko'ring yoki barqaror internetda sinab ko'ring"
        return 1
      fi
      err "AAB yuklash xato (HTTP ${upload_http:-?}, curl rc=${upload_rc}): $upload_response"
      echo
      # versionCode conflict — eng tez-tez uchraydi
      if echo "$upload_response" | grep -qE 'APK specifies a version code that has already been used|Version code [0-9]+ has already been used'; then
        info "Sabab: bu versionCode allaqachon Play Store'ga yuklangan"
        try_this \
          "flutter-build   # menu'da build #ga '+' bosing (avtomatik +1)" \
          "# yoki pubspec.yaml'da version: X.Y.Z+N ni N+1 ga oshiring"
        return 1
      elif echo "$upload_response" | grep -q 'APK is not signed'; then
        info "Sabab: AAB signed emas yoki noto'g'ri signing"
        try_this "flutter-build   # Production checkbox'ini yoqing va keystore sozlang"
        return 1
      elif [ "$upload_http" = "403" ] || echo "$upload_response" | grep -qE "\"code\": *403|forbidden|Forbidden"; then
        # v1.14.0: bundle upload 403 — eng tez-tez YANGI app uchun
        # Manual upload boshlansa, PLAY_MANUAL_UPLOAD_INITIATED flag o'rnatiladi.
        # Har holda return 1 (API upload tugamadi) — caller else-branch'i flag'ni
        # tekshirib to'g'ri xabar ('manual boshlandi' yoki 'xato') ko'rsatadi.
        play_handle_bundle_403 "$package_name" "$aab" "$track" || true
        return 1
      else
        info "Sabab: aniq emas — javob:"
        echo "$upload_response" | head -5 | sed 's/^/    /'
        return 1
      fi
  fi
  version_code=$(extract_json_number "$upload_response" "versionCode")
  if [ -z "$version_code" ]; then
    err "versionCode javobdan topilmadi"
    err "Javob: $upload_response"
    return 1
  fi
  ok "AAB yuklandi, versionCode=$version_code"

  # [4/5] Track'ga qo'shish (release notes + staged rollout bilan)
  info "[4/5] Track'ga qo'shilmoqda: $track..."

  # release_notes_json va status'ni qo'shamiz
  local release_notes_json="" release_status="completed" user_fraction_json=""

  # Release notes — agar belgilangan bo'lsa, en-US default tilda yuboramiz
  if [ -n "$RELEASE_NOTES" ]; then
    local escaped
    escaped=$(escape_for_json "$RELEASE_NOTES")
    release_notes_json=",\"releaseNotes\":[{\"language\":\"en-US\",\"text\":\"${escaped}\"}]"
  fi

  # Staged rollout — faqat production track uchun ma'noli
  if [ "$track" = "production" ] && [ -n "$STAGED_ROLLOUT_FRACTION" ]; then
    if [ "$STAGED_ROLLOUT_FRACTION" != "1.0" ] && [ "$STAGED_ROLLOUT_FRACTION" != "1" ]; then
      release_status="inProgress"
      user_fraction_json=",\"userFraction\":${STAGED_ROLLOUT_FRACTION}"
    fi
  fi

  local track_payload track_response
  track_payload="{\"releases\":[{\"versionCodes\":[\"${version_code}\"],\"status\":\"${release_status}\"${user_fraction_json}${release_notes_json}}]}"

  track_response=$(curl -fsS -X PUT \
    "${api_base}/edits/${edit_id}/tracks/${track}" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json" \
    --connect-timeout 30 --max-time 120 \
    -d "$track_payload" 2>&1) || {
      err "Track qo'shish xato: $track_response"
      return 1
    }
  ok "Track'ga qo'shildi: $track${user_fraction_json:+ (staged rollout)}"

  # [5/5] Commit
  info "[5/5] Edit commit qilinmoqda..."
  local commit_response
  commit_response=$(curl -fsS -X POST \
    "${api_base}/edits/${edit_id}:commit" \
    --connect-timeout 30 --max-time 120 \
    -H "Authorization: Bearer ${token}" 2>&1) || {
      err "Commit xato: $commit_response"
      echo
      # v1.13.0: HTTP code'ga ko'ra batafsil diagnostika
      # v1.13.2: 403 holatida interaktiv recovery menyusi (5 ta variant)
      if echo "$commit_response" | grep -qE "returned error: 403|HTTP/[12][^ ]* 403|\"code\": *403|forbidden|Forbidden"; then
        info "${BOLD}Sabab:${NC} Service Account 'Release Manager' ruxsatiga ega emas"
        info "(Edit yaratish va track qo'shish ishladi — demak ba'zi ruxsat'lar bor,"
        info " lekin commit qilish uchun ${BOLD}'Manage releases'${NC} ruxsati alohida kerak)"

        # Interaktiv recovery — admin retry / developer template / qo'lda upload / saqlash
        if play_handle_commit_403 "$edit_id" "$api_base" "$jwt" "$package_name" "$sa_email" "$aab" "$track"; then
          # Retry muvaffaqiyatli — `if` qonunini buzib, asosiy success'ga o'tamiz
          # Buni quyida `goto`-style qilolmaymiz, shuning uchun bevosita success qaytaramiz
          echo
          ok "Muvaffaqiyatli yuklandi! (commit retry'da ishladi)"
          info "Track:       $track"
          info "versionCode: $version_code"
          info "Play Console: https://play.google.com/console/u/0/developers/-/app/${package_name}/tracks/${track}"
          return 0
        fi
        # play_handle_commit_403 1 qaytarsa, foydalanuvchi boshqa yo'l bilan davom etgan
        # (qo'lda upload, saqlash, yoki bekor). Funksiya o'zi tushuntiradi nima qilish.
        return 1
      elif echo "$commit_response" | grep -qE "returned error: 401|HTTP/[12][^ ]* 401|\"code\": *401|[Uu]nauthorized"; then
        info "${BOLD}Sabab:${NC} Access token muddati o'tdi yoki noto'g'ri"
        info "(token 1 soat amal qiladi — bu nadir)"
        try_this "flutter-build   # qaytadan ishga tushiring (yangi token olinadi)"
      elif echo "$commit_response" | grep -qE "edit.*not found|editId|404"; then
        info "${BOLD}Sabab:${NC} Edit ID muddati o'tdi (24 soatdan ko'p ochiq turdi)"
        info "(yoki boshqa sessiya bu edit'ni allaqachon commit qilgan)"
        try_this "flutter-build   # qaytadan ishga tushiring"
      elif echo "$commit_response" | grep -qE "version code|versionCode"; then
        info "${BOLD}Sabab:${NC} versionCode konfliktida (allaqachon ishlatilgan)"
        try_this "flutter-build   # menu'da build #ga '+' bosing (+1)"
      else
        info "${BOLD}Sabab:${NC} aniq emas — javobni tekshiring"
        info "Xato: $commit_response"
      fi
      echo
      info "Edit ID: ${BOLD}$edit_id${NC}"
      info "  Qo'lda tekshirish: https://play.google.com/console/u/0/developers/-/app/${package_name}/app-dashboard"
      info "  (Pending changes' bo'limida ko'rinadi — discard yoki commit qilish mumkin)"
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

# ─── v1.13.0: Upload-only rejim (build qilmasdan, oxirgi artifact'ni yuklash) ─

# Yordamchi: faylning yaratilgan vaqtini human-readable formatda qaytaradi
# macOS va Linux uchun cross-platform.
file_mtime_human() {
  local file="$1"
  if [ "$(uname)" = "Darwin" ]; then
    stat -f '%Sm' "$file" 2>/dev/null
  else
    stat -c '%y' "$file" 2>/dev/null | cut -d'.' -f1
  fi
}

# v1.13.1: Upload natijasini hisobotga qo'shish (Ikkalasi rejimi uchun)
# rc kodlari:
#   0 — muvaffaqiyatli
#   1 — xato berdi (artifact bor edi, lekin upload qilolmadi)
#   2 — bekor qilindi (foydalanuvchi y/n da n bosdi)
#   3 — artifact topilmadi (skip)
_report_upload_result() {
  local label="$1" rc="$2"
  case "$rc" in
    0) info "  ✓ ${label}: muvaffaqiyatli yuklandi" ;;
    1) info "  ✗ ${label}: upload xato berdi" ;;
    2) info "  - ${label}: foydalanuvchi bekor qildi" ;;
    3) info "  ⊘ ${label}: artifact topilmadi (skip)" ;;
    *) info "  ? ${label}: noma'lum holat (rc=$rc)" ;;
  esac
}

# Asosiy upload-only oqimi — foydalanuvchi platforma tanlaydi, oxirgi artifact'ni
# topib, akkaunt'ni resolve qilib, yuklaydi. Build qilmaydi.
#
# Returns:
#   0 — muvaffaqiyatli (yoki foydalanuvchi orqaga qaytdi)
#   1 — xato (build artifact yo'q yoki upload xato berdi)
upload_only_flow() {
  banner "Upload (build qilmasdan)"

  # Pre-flight: Flutter loyihasi ekanini tekshirish
  if [ ! -f "pubspec.yaml" ]; then
    err "pubspec.yaml topilmadi"
    info "Flutter loyihasi ildizidan ishga tushiring (pubspec.yaml shu yerda bo'lishi kerak)"
    pause
    return 1
  fi

  echo
  info "Bu rejimda skript ${BOLD}build qilmaydi${NC} — faqat mavjud AAB/IPA fayl'ni yuklaydi"
  info "(qayta build qilmaslik = 5-15 daqiqa tejash; build allaqachon bor bo'lsa qulay)"
  echo

  # Platforma tanlash
  echo -e "  ${BOLD}╭─ Qaysi platformaga upload qilamiz? ────────────────────╮${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) 🤖 Android (oxirgi AAB → Play Store)            ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) 🍏 iOS (oxirgi IPA → App Store Connect)         ${BOLD}│${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) 🚀 Ikkalasi ham (Android keyin iOS)              ${BOLD}│${NC}"
  echo -e "  ${BOLD}├─────────────────────────────────────────────────────────${NC}"
  echo -e "  ${BOLD}│${NC}  ${CYAN}b${NC}) Orqaga (asosiy menu)                                ${BOLD}│${NC}"
  echo -e "  ${BOLD}╰─────────────────────────────────────────────────────────${NC}"
  echo

  local platform
  read -p "  Tanlang [1-3, b] [1]: " platform
  platform="${platform:-1}"

  case "$platform" in
    1) upload_android_only_flow ;;
    2) upload_ios_only_flow ;;
    3)
      # v1.13.1: "Ikkalasi" rejimi — graceful degradation
      # Har bir platforma alohida ishlatiladi. Birortasi xato bo'lsa ham, ikkinchisi davom etadi.
      # Bu user case'i uchun: "androidda build bor, iosda yo'q" — Android uploadlanadi,
      # iOS skip qilinadi, batafsil hisobot beriladi.
      local android_rc=2 ios_rc=2  # 2 = "skipped" (default — agar foydalanuvchi yo'q desa)

      info "▶ Android upload boshlanmoqda..."
      echo
      if find_latest_aab > /dev/null 2>&1; then
        upload_android_only_flow
        android_rc=$?
      else
        warn "Android AAB topilmadi — bu platforma o'tkazib yuboriladi"
        info "(qidirilgan joylar pastda upload_android_only_flow ko'rsatadi)"
        android_rc=3  # 3 = "not found, skipped"
      fi

      echo
      echo "────────────────────────────────────────"
      info "▶ iOS upload boshlanmoqda..."
      echo
      if [ "$(uname)" != "Darwin" ]; then
        warn "iOS upload faqat macOS'da ishlaydi — bu platforma o'tkazib yuboriladi"
        ios_rc=3
      elif find_latest_ipa > /dev/null 2>&1; then
        upload_ios_only_flow
        ios_rc=$?
      else
        warn "iOS IPA topilmadi — bu platforma o'tkazib yuboriladi"
        info "(qidirilgan joylar pastda upload_ios_only_flow ko'rsatadi)"
        ios_rc=3
      fi

      # Hisobot
      echo
      echo "════════════════════════════════════════"
      info "${BOLD}Yakuniy hisobot:${NC}"
      _report_upload_result "Android" "$android_rc"
      _report_upload_result "iOS    " "$ios_rc"
      echo "════════════════════════════════════════"
      echo

      # Hech bo'lmasa bittasi muvaffaqiyatli bo'lsa — return 0
      if [ $android_rc -eq 0 ] || [ $ios_rc -eq 0 ]; then
        return 0
      fi
      # Ikkalasi ham skip yoki xato bo'lsa — return 1
      return 1
      ;;
    b|B)
      return 0
      ;;
    *)
      warn "Noto'g'ri tanlov: '$platform'"
      sleep 1
      return 1
      ;;
  esac
}

# Android — oxirgi AAB'ni Play Store'ga yuklash (build qilmasdan)
upload_android_only_flow() {
  banner "Android — oxirgi AAB'ni yuklash"

  # Oxirgi AAB'ni topish (multi-location: 7 ta joydan)
  local aab
  aab=$(find_latest_aab 2>/dev/null) || {
    err "AAB topilmadi"
    echo
    info "Bizning skript quyidagi joylardan qidirdi:"
    info "  1. ${BOLD}build/app/outputs/bundle/release/${NC}        (Flutter CLI default)"
    info "  2. ${BOLD}android/app/build/outputs/bundle/release/${NC} (Android Studio Gradle)"
    info "  3. ${BOLD}android/app/release/${NC}                     (Android Studio 'Generate Signed Bundle')"
    info "  4. ${BOLD}build/app/outputs/bundle/*/${NC}              (Flutter CLI flavor'lar)"
    info "  5. ${BOLD}android/app/build/outputs/bundle/*/${NC}      (Android Studio Gradle flavor)"
    info "  6. ${BOLD}android/app/release/*/${NC}                   (Signed Bundle flavor)"
    info "  7. ${BOLD}android/${NC} va ${BOLD}build/${NC} ichida recursive (catch-all, maxdepth 6)"
    echo
    info "${BOLD}Hozir nima qilamiz?${NC}"
    echo -e "    ${CYAN}1${NC}) ${BOLD}Manual yo'l kiritish${NC} (siz AAB joyini bilasiz)"
    echo -e "    ${CYAN}2${NC}) Build qilamiz (Flutter CLI orqali — flutter build appbundle)"
    echo -e "    ${CYAN}3${NC}) Android Studio'ni ochaman (qo'lda build qilaman)"
    echo -e "    ${CYAN}4${NC}) Bekor qilish"
    echo
    local choice manual_path
    read -p "  Tanlang [1-4] [1]: " choice
    case "${choice:-1}" in
      1)
        # v1.13.3: Manual path entry — foydalanuvchi aniq joyni bilsa
        echo
        info "AAB faylga to'liq yoki nisbiy yo'lni kiriting:"
        info "  Misol: ${BOLD}android/app/release/app-release.aab${NC}"
        info "  Misol: ${BOLD}/Users/.../Desktop/.../app/release/app-release.aab${NC}"
        echo
        read -p "  AAB yo'li: " manual_path
        # Tilde expansion
        manual_path="${manual_path/#\~/$HOME}"
        if [ -z "$manual_path" ]; then
          err "Bo'sh yo'l — bekor qilindi"
          return 1
        fi
        if [ ! -f "$manual_path" ]; then
          err "Bu yo'lda fayl yo'q: $manual_path"
          info "Tekshiring: ${BOLD}ls -la \"$manual_path\"${NC}"
          pause
          return 1
        fi
        # .aab kengaytmasi tekshiruvi (skript ehtiyot bo'lib)
        case "$manual_path" in
          *.aab) ;;
          *)
            warn "Fayl .aab bilan tugamaydi — bu Android App Bundle emasligi mumkin"
            read -p "  Davom etamizmi? (y/n) [n]: " confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && return 1
            ;;
        esac
        aab="$manual_path"
        ok "Manual AAB qabul qilindi: $aab"
        ;;
      2)
        echo
        info "Build flow boshlanmoqda — keyin upload qilamiz"
        if main_build_flow; then
          return 0
        else
          warn "Build muvaffaqiyatsiz tugadi"
          return 1
        fi
        ;;
      3)
        info "Android Studio'ni oching va: Build → Generate Signed Bundle / APK → Bundle"
        try_this \
          "open -a 'Android Studio' android   # Android Studio'da android/ papka'ni ochish" \
          "# Build tugagach, shu menu'ga qayting va Upload'ni qaytadan tanlang"
        pause
        return 1
        ;;
      *)
        info "Bekor qilindi"
        return 1
        ;;
    esac
  }

  # AAB ma'lumotlari
  local size_mb mtime
  size_mb=$(du -m "$aab" | cut -f1)
  mtime=$(file_mtime_human "$aab")

  # pubspec dan version
  local pubspec_version pubspec_name pubspec_build
  pubspec_version=$(awk '/^version:/{print $2; exit}' pubspec.yaml 2>/dev/null)
  pubspec_name="${pubspec_version%%+*}"          # 1.2.3+45 → 1.2.3
  pubspec_build="${pubspec_version##*+}"          # 1.2.3+45 → 45

  # Package va akkaunt resolve
  local pkg account track
  pkg=$(detect_android_package_name)
  if [ -z "$pkg" ]; then
    err "Android applicationId aniqlanmadi (android/app/build.gradle topilmadi yoki noto'g'ri)"
    pause
    return 1
  fi

  account=$(play_project_config_get "$pkg" "account")
  if [ -z "$account" ]; then
    warn "Loyiha '${pkg}' uchun Play Store akkaunti sozlanmagan"
    info "Hozir sozlaymizmi? (akkaunt tanlash yoki yangi qo'shish)"
    if ! ensure_play_credentials; then
      pause
      return 1
    fi
    account=$(play_project_config_get "$pkg" "account")
  fi
  track=$(play_project_config_get "$pkg" "track")
  track="${track:-internal}"

  # Akkaunt JSON faylini tekshirish
  local sa_path sa_email
  sa_path=$(play_account_get "$account" "service_account_path")
  if [ -z "$sa_path" ] || [ ! -f "$sa_path" ]; then
    err "Akkaunt '${account}' uchun service account JSON topilmadi"
    info "Akkauntni qayta sozlash kerak: flutter-build --settings"
    pause
    return 1
  fi
  sa_email=$(sa_json_get_simple "$sa_path" "client_email")

  echo
  step "AAB ma'lumotlari (Play Store'ga yuklanadigan):"
  info "  ${BOLD}Fayl:${NC}        $aab"
  info "  ${BOLD}O'lchami:${NC}    ${size_mb} MB"
  info "  ${BOLD}Yaratilgan:${NC}  $mtime"
  if [ -n "$pubspec_version" ]; then
    info "  ${BOLD}pubspec ver:${NC} $pubspec_version  ${BLUE}(versionName=${pubspec_name}, versionCode=${pubspec_build})${NC}"
  fi
  echo
  step "Upload destinatsiyasi:"
  info "  ${BOLD}Package:${NC}     $pkg"
  info "  ${BOLD}Akkaunt:${NC}     $account"
  info "  ${BOLD}Service Acc:${NC} $sa_email"
  info "  ${BOLD}Track:${NC}       $track"
  echo

  # Eslatma: agar AAB versionCode allaqachon Play Store'da bor bo'lsa, upload 4xx beradi
  warn "Eslatma: agar bu versionCode (${pubspec_build}) Play Store'da allaqachon bor bo'lsa,"
  warn "upload xato beradi. Yangi build raqami uchun: flutter-build → '+' bilan +1"
  echo

  local yn
  read -p "  Davom etamizmi? (y/n) [y]: " yn
  if [[ "$yn" =~ ^[Nn]$ ]]; then
    info "Bekor qilindi"
    return 0
  fi

  # Release notes yig'ish (build flow'dagi kabi)
  RELEASE_NOTES=$(collect_release_notes "$pubspec_name" "$pubspec_build")

  # Staged rollout — faqat production track uchun
  STAGED_ROLLOUT_FRACTION=""
  if [ "$track" = "production" ]; then
    echo
    info "Production track tanlandi — staged rollout"
    echo -e "  ${BOLD}Foydalanuvchilarga foiz bilan release:${NC}"
    echo -e "    ${CYAN}1${NC}) 100%  — barchaga darrov (default)"
    echo -e "    ${CYAN}2${NC}) 50%   — yarmiga"
    echo -e "    ${CYAN}3${NC}) 10%   — sinov uchun"
    echo -e "    ${CYAN}4${NC}) 1%    — minimal sinov"
    echo
    local roll_choice
    read -p "  Tanlang [1-4] [1]: " roll_choice
    case "${roll_choice:-1}" in
      1) STAGED_ROLLOUT_FRACTION="1.0" ;;
      2) STAGED_ROLLOUT_FRACTION="0.5" ;;
      3) STAGED_ROLLOUT_FRACTION="0.1" ;;
      4) STAGED_ROLLOUT_FRACTION="0.01" ;;
      *) STAGED_ROLLOUT_FRACTION="1.0" ;;
    esac
    ok "Rollout: $(awk "BEGIN{printf \"%.0f\", $STAGED_ROLLOUT_FRACTION * 100}")%"
  fi

  # Upload — mavjud play_publish funksiyasi
  # v1.13.9: PLAY_MANUAL_UPLOAD_INITIATED flag'ini reset qilamiz
  PLAY_MANUAL_UPLOAD_INITIATED=false
  if upload_to_play_store "$aab"; then
    # Promotion taklif (faqat internal/alpha/beta uchun ma'noli)
    if [ "$track" != "production" ]; then
      play_suggest_promotion "$pkg" "$track"
    fi
    echo
    ok "Android upload muvaffaqiyatli yakunlandi"
    return 0
  else
    # v1.13.9: agar manual UI upload tanlangan bo'lsa, bu xato emas
    if [ "${PLAY_MANUAL_UPLOAD_INITIATED:-false}" = "true" ]; then
      echo
      info "📋 Manual upload Play Console'da boshlandi (API o'rniga)"
      info "Browser'da release'ni yakunlang — bu skript ishini tugatdi"
      return 0
    fi
    echo
    warn "Android upload xato berdi — AAB hali ham mavjud: $aab"
    info "Qayta urinib ko'rish uchun shu menu'ga qaytib keling"
    pause
    return 1
  fi
}

# iOS — oxirgi IPA'ni App Store Connect'ga yuklash (build qilmasdan)
upload_ios_only_flow() {
  banner "iOS — oxirgi IPA'ni yuklash"

  # macOS check (iOS upload faqat macOS'da)
  if [ "$(uname)" != "Darwin" ]; then
    err "iOS upload faqat macOS'da ishlaydi (xcrun talab qilinadi)"
    pause
    return 1
  fi

  # Oxirgi IPA (multi-location: 5 ta joydan)
  local ipa
  ipa=$(find_latest_ipa 2>/dev/null) || {
    err "IPA topilmadi"
    echo
    info "Bizning skript quyidagi joylardan qidirdi:"
    info "  1. ${BOLD}build/ios/ipa/${NC}                          (Flutter CLI default)"
    info "  2. ${BOLD}build/ios/iphoneos/${NC}                     (Flutter CLI eski versiyalar)"
    info "  3. ${BOLD}ios/build/${NC}                              (Xcode build joyi)"
    info "  4. ${BOLD}./${NC}                                      (loyiha ildizi)"
    info "  5. ${BOLD}build/${NC} va ${BOLD}ios/${NC} ichida recursive (catch-all)"
    echo
    info "${BOLD}Hozir nima qilamiz?${NC}"
    echo -e "    ${CYAN}1${NC}) ${BOLD}Manual yo'l kiritish${NC} (siz IPA joyini bilasiz)"
    echo -e "    ${CYAN}2${NC}) Build qilamiz (Flutter CLI orqali — flutter build ipa)"
    echo -e "    ${CYAN}3${NC}) Xcode'ni ochaman (qo'lda Archive → Distribute App)"
    echo -e "    ${CYAN}4${NC}) Bekor qilish"
    echo
    local choice manual_path
    read -p "  Tanlang [1-4] [1]: " choice
    case "${choice:-1}" in
      1)
        # v1.13.3: Manual path entry
        echo
        info "IPA faylga to'liq yoki nisbiy yo'lni kiriting:"
        info "  Misol: ${BOLD}build/ios/ipa/Runner.ipa${NC}"
        info "  Misol: ${BOLD}~/Desktop/MyApp.ipa${NC}"
        echo
        read -p "  IPA yo'li: " manual_path
        manual_path="${manual_path/#\~/$HOME}"
        if [ -z "$manual_path" ]; then
          err "Bo'sh yo'l — bekor qilindi"
          return 1
        fi
        if [ ! -f "$manual_path" ]; then
          err "Bu yo'lda fayl yo'q: $manual_path"
          info "Tekshiring: ${BOLD}ls -la \"$manual_path\"${NC}"
          pause
          return 1
        fi
        case "$manual_path" in
          *.ipa) ;;
          *)
            warn "Fayl .ipa bilan tugamaydi — bu iOS App Archive emasligi mumkin"
            read -p "  Davom etamizmi? (y/n) [n]: " confirm
            [[ ! "$confirm" =~ ^[Yy]$ ]] && return 1
            ;;
        esac
        ipa="$manual_path"
        ok "Manual IPA qabul qilindi: $ipa"
        ;;
      2)
        echo
        info "Build flow boshlanmoqda — keyin upload qilamiz"
        if main_build_flow; then
          return 0
        else
          warn "Build muvaffaqiyatsiz tugadi"
          return 1
        fi
        ;;
      3)
        info "Xcode'ni oching: Product → Archive, keyin Window → Organizer → Distribute App"
        try_this \
          "open ios/Runner.xcworkspace   # Xcode'da loyihani ochish" \
          "# Archive qilingach, Distribute App → App Store Connect → Export" \
          "# Export qilinganidan keyin shu menu'ga qaytib Upload'ni tanlang"
        pause
        return 1
        ;;
      *)
        info "Bekor qilindi"
        return 1
        ;;
    esac
  }

  # IPA ma'lumotlari
  local size_mb mtime
  size_mb=$(du -m "$ipa" | cut -f1)
  mtime=$(file_mtime_human "$ipa")

  local pubspec_version
  pubspec_version=$(awk '/^version:/{print $2; exit}' pubspec.yaml 2>/dev/null)

  # Bundle va akkaunt resolve
  local bundle account
  bundle=$(detect_ios_bundle_id)
  if [ -z "$bundle" ]; then
    err "iOS bundle id aniqlanmadi (ios/Runner.xcodeproj/project.pbxproj o'qib bo'lmadi)"
    pause
    return 1
  fi

  account=$(appstore_project_config_get "$bundle" "account")
  if [ -z "$account" ]; then
    warn "Bundle '${bundle}' uchun App Store akkaunti sozlanmagan"
    info "Settings → Akkauntlar orqali yangisini qo'shing: flutter-build --settings"
    pause
    return 1
  fi

  local auth_type
  auth_type=$(appstore_account_get_auth_type "$account")

  echo
  step "IPA ma'lumotlari (App Store'ga yuklanadigan):"
  info "  ${BOLD}Fayl:${NC}        $ipa"
  info "  ${BOLD}O'lchami:${NC}    ${size_mb} MB"
  info "  ${BOLD}Yaratilgan:${NC}  $mtime"
  if [ -n "$pubspec_version" ]; then
    info "  ${BOLD}pubspec ver:${NC} $pubspec_version"
  fi
  echo
  step "Upload destinatsiyasi:"
  info "  ${BOLD}Bundle ID:${NC}   $bundle"
  info "  ${BOLD}Akkaunt:${NC}     $account"
  info "  ${BOLD}Auth usuli:${NC}  $auth_type"
  echo

  warn "Eslatma: agar bu build raqami App Store'da allaqachon bor bo'lsa,"
  warn "upload 409 xato beradi. Yangi build uchun: flutter-build → '+' bilan +1"
  echo

  local yn
  read -p "  Davom etamizmi? (y/n) [y]: " yn
  if [[ "$yn" =~ ^[Nn]$ ]]; then
    info "Bekor qilindi"
    return 0
  fi

  # Upload — mavjud upload_to_appstore funksiyasi
  if upload_to_appstore "$ipa"; then
    echo
    ok "iOS upload muvaffaqiyatli yakunlandi"
    info "App Store Connect'da TestFlight bo'limini tekshiring (1-15 daqiqa kutadi)"
    return 0
  else
    echo
    warn "iOS upload xato berdi — IPA hali ham mavjud: $ipa"
    info "Qayta urinib ko'rish uchun shu menu'ga qaytib keling"
    pause
    return 1
  fi
}

# ─── v1.11.0: Bosqichma-bosqich (wizard) build pickers ─────
# Har bosqich quyidagi qaytadi:
#   0 — keyingi bosqichga o'tish
#   1 — orqaga (yoki bekor qilish)
# Bog'liq tanlovlar avtomatik kontekst asosida ko'rsatiladi.

# [1/5] Build rejimi (radio — Production / Debug)
menu_pick_build_mode() {
  echo
  step "[1/5] Build rejimi"
  echo
  echo -e "  ${BOLD}Qaysi rejim bilan build qilamiz?${NC}"
  echo -e "    ${CYAN}1${NC}) ${BOLD}🚀 Production${NC}  — release, signed (Play/App Store uchun)"
  echo -e "    ${CYAN}2${NC}) ${BOLD}🔧 Debug${NC}      — test build, signing yo'q"
  echo -e "    ${CYAN}b${NC}) Orqaga (asosiy menyu)"
  echo

  # Settings'dan default
  local default_choice="2"
  [ "$DEFAULT_PRODUCTION" = "true" ] && default_choice="1"

  read -p "  Tanlang [1-2, b] [${default_choice}]: " choice
  choice="${choice:-$default_choice}"

  case "$choice" in
    1) IS_PROD=true;  MODE_LABEL="PRODUCTION"; return 0 ;;
    2) IS_PROD=false; MODE_LABEL="DEBUG";      return 0 ;;
    b|B) return 1 ;;
    *) warn "Noto'g'ri tanlov: '$choice'"; sleep 1; return 1 ;;
  esac
}

# [2/5] Platformalar (multi-select: Android, iOS)
menu_pick_platforms() {
  echo
  step "[2/5] Platformalar"
  info "Rejim: ${BOLD}${MAGENTA}${MODE_LABEL}${NC} (oldingi bosqichdan)"

  CHECKBOX_INITIAL=("$DEFAULT_ANDROID" "$DEFAULT_IOS")
  arrow_checkbox "Qaysi platformalarni build qilamiz? (Space tanlash)" \
    "Android" \
    "iOS"

  if [ "${CHECKBOX_CANCELLED:-false}" = "true" ]; then
    return 1
  fi

  BUILD_ANDROID="${CHECKBOX_RESULT[0]}"
  BUILD_IOS="${CHECKBOX_RESULT[1]}"

  if ! $BUILD_ANDROID && ! $BUILD_IOS; then
    warn "Hech qaysi platforma tanlanmadi"
    info "Space tugmasi bilan kamida bittasini yoqing"
    pause
    return 1
  fi

  if $BUILD_IOS && [ "$(uname)" != "Darwin" ]; then
    err "iOS build faqat macOS da ishlaydi (bu tizim: $(uname))"
    info "iOS'ni o'chiring yoki macOS'da ishga tushiring"
    pause
    return 1
  fi

  return 0
}

# [3/5] Android format (faqat Android tanlanganda)
menu_pick_android_format() {
  echo
  step "[3/5] Android format"
  info "Platformalar: ${BOLD}Android${NC}$($BUILD_IOS && printf ", iOS")"

  CHECKBOX_INITIAL=("$DEFAULT_AAB" "$DEFAULT_APK")
  arrow_checkbox "Android format (AAB Play Store uchun, APK sideload uchun)" \
    "AAB" \
    "APK"

  if [ "${CHECKBOX_CANCELLED:-false}" = "true" ]; then
    return 1
  fi

  BUILD_AAB="${CHECKBOX_RESULT[0]}"
  BUILD_APK="${CHECKBOX_RESULT[1]}"

  if ! $BUILD_AAB && ! $BUILD_APK; then
    warn "Format tanlanmadi (AAB yoki APK)"
    info "Space bilan kamida bittasini yoqing"
    pause
    return 1
  fi

  return 0
}

# [4/5] Build oldidan amallar (ixtiyoriy)
menu_pick_prebuild_tasks() {
  echo
  step "[4/5] Build oldidan amallar"
  info "(Ixtiyoriy — hech qaysisi yoqilmasligi mumkin)"

  CHECKBOX_INITIAL=("$DEFAULT_FLUTTER_CLEAN" "$DEFAULT_FLUTTER_PUB_GET")
  arrow_checkbox "Tanlovlar (Space tanlash, Enter o'tish)" \
    "flutter clean   (build kesh tozalash — sekinroq, lekin toza)" \
    "flutter pub get (paketlar yangilash — tavsiya etiladi)"

  if [ "${CHECKBOX_CANCELLED:-false}" = "true" ]; then
    return 1
  fi

  DO_CLEAN="${CHECKBOX_RESULT[0]}"
  DO_PUBGET="${CHECKBOX_RESULT[1]}"
  return 0
}

# [5/5] Build'dan keyin deploy (faqat tegishli optsiyalar)
menu_pick_deploy_targets() {
  # Qaysi deploy optsiyalari mantiqiy?
  local appstore_applicable=false
  local playstore_applicable=false

  if $IS_PROD && $BUILD_IOS; then
    appstore_applicable=true
  fi
  if $IS_PROD && $BUILD_ANDROID && $BUILD_AAB; then
    playstore_applicable=true
  fi

  # Hech qaysisi mantiqiy emas — bosqichni o'tkazib yuboramiz
  if ! $appstore_applicable && ! $playstore_applicable; then
    DO_APPSTORE_UPLOAD=false
    DO_PLAYSTORE_UPLOAD=false
    if ! $IS_PROD; then
      info "Deploy bosqichi o'tkazib yuborildi (Debug rejim — Play/App Store ga yuklash mumkin emas)"
    else
      info "Deploy bosqichi o'tkazib yuborildi (Production + iOS yoki Production + Android + AAB kerak)"
    fi
    return 0
  fi

  echo
  step "[5/5] Build'dan keyin deploy"
  info "(Ixtiyoriy — faqat tegishli optsiyalar ko'rsatildi)"

  # Dinamik options list (faqat tegishlilarini)
  local options=()
  local initial=()
  if $appstore_applicable; then
    options+=("App Store Connect upload (iOS, xcrun altool)")
    initial+=("$DEFAULT_APPSTORE_UPLOAD")
  fi
  if $playstore_applicable; then
    options+=("Play Store upload (Android, AAB, Google API)")
    initial+=("$DEFAULT_PLAYSTORE_UPLOAD")
  fi

  CHECKBOX_INITIAL=("${initial[@]}")
  arrow_checkbox "Deploy (Space tanlash, Enter o'tish)" "${options[@]}"

  if [ "${CHECKBOX_CANCELLED:-false}" = "true" ]; then
    return 1
  fi

  # Natijalarni qayta sortlash (har biri faqat agar applicable bo'lsa)
  local idx=0
  if $appstore_applicable; then
    DO_APPSTORE_UPLOAD="${CHECKBOX_RESULT[$idx]}"
    idx=$((idx + 1))
  else
    DO_APPSTORE_UPLOAD=false
  fi
  if $playstore_applicable; then
    DO_PLAYSTORE_UPLOAD="${CHECKBOX_RESULT[$idx]}"
  else
    DO_PLAYSTORE_UPLOAD=false
  fi

  return 0
}

# Wizard orchestrator — 5 bosqichni state machine bilan boshqaradi
# Foydalanuvchi har bosqichdan 'b' bilan oldingi bosqichga qaytishi mumkin.
# Birinchi bosqichdan 'b' = asosiy menyu'ga qaytish.
run_build_wizard() {
  local step=1
  while true; do
    case "$step" in
      1)
        # Build mode
        if menu_pick_build_mode; then
          step=2
        else
          return 1   # Orqaga = asosiy menyu
        fi
        ;;
      2)
        # Platformalar
        if menu_pick_platforms; then
          step=3
        else
          step=1
        fi
        ;;
      3)
        # Android format (conditional)
        if $BUILD_ANDROID; then
          if menu_pick_android_format; then
            step=4
          else
            step=2
          fi
        else
          # Android tanlanmagan — formatni o'tkazib yuboramiz
          BUILD_AAB=false
          BUILD_APK=false
          step=4
        fi
        ;;
      4)
        # Pre-build tasks
        if menu_pick_prebuild_tasks; then
          step=5
        else
          # Orqaga: agar Android bo'lsa step 3 ga, aks holda step 2 ga
          if $BUILD_ANDROID; then
            step=3
          else
            step=2
          fi
        fi
        ;;
      5)
        # Deploy targets (contextual)
        if menu_pick_deploy_targets; then
          break   # Wizard tugadi
        else
          step=4
        fi
        ;;
    esac
  done
  return 0
}

# v1.14.1: ProGuard qoidalarini qo'shish (R8 Play Core missing classes fix)
# android/app/proguard-rules.pro ga keep/dontwarn qoidalarni qo'shadi va
# build.gradle/build.gradle.kts da reference borligini ta'minlaydi.
_ensure_proguard_playcore_rules() {
  local pro_file="android/app/proguard-rules.pro"
  local marker="# flutter-build-tool: Play Core deferred components fix"

  # Allaqachon qo'shilgan bo'lsa, skip
  if [ -f "$pro_file" ] && grep -qF "$marker" "$pro_file" 2>/dev/null; then
    info "ProGuard qoidalari allaqachon mavjud: $pro_file"
    return 0
  fi

  # Qoidalarni qo'shamiz (append yoki yangi fayl)
  {
    echo ""
    echo "$marker"
    echo "# Flutter embedding Play Core (deferred components) klasslarini reference qiladi,"
    echo "# lekin app ularni o'z ichiga olmaydi. R8 minify vaqtida xato bermasligi uchun:"
    echo "-dontwarn com.google.android.play.core.**"
    echo "-keep class com.google.android.play.core.** { *; }"
    echo "-keep class com.google.android.play.core.tasks.** { *; }"
  } >> "$pro_file"
  ok "ProGuard qoidalari qo'shildi: $pro_file"

  # build.gradle yoki build.gradle.kts da proguard-rules.pro reference borligini tekshirish
  local gradle_groovy="android/app/build.gradle"
  local gradle_kts="android/app/build.gradle.kts"
  local gradle_file=""
  [ -f "$gradle_groovy" ] && gradle_file="$gradle_groovy"
  [ -f "$gradle_kts" ] && gradle_file="$gradle_kts"

  if [ -z "$gradle_file" ]; then
    warn "android/app/build.gradle topilmadi — proguard reference qo'lda tekshiring"
    return 0
  fi

  if grep -q "proguard-rules.pro" "$gradle_file" 2>/dev/null; then
    info "build.gradle allaqachon proguard-rules.pro'ni reference qiladi"
  else
    info "build.gradle'da proguard-rules.pro reference yo'q"
    info "Agar build qayta xato bersa, ${BOLD}${gradle_file}${NC} release buildType'ga qo'shing:"
    if [ "$gradle_file" = "$gradle_kts" ]; then
      info '  proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'
    else
      info "  proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'"
    fi
  fi
  return 0
}

# v1.14.1: Android build muvaffaqiyatsizligini tahlil qilish va imkon bo'lsa tuzatish
# Args: build_type(appbundle/apk) exit_code log_file build_variant
# Returns:
#   0 — tuzatildi va qayta build muvaffaqiyatli (davom etish mumkin)
#   1 — tuzatib bo'lmadi yoki foydalanuvchi rad etdi
handle_android_build_failure() {
  local btype="$1" rc="$2" log_file="$3" variant="$4"

  echo
  err "Android build muvaffaqiyatsiz (exit code: $rc)"
  echo

  local log_content=""
  [ -f "$log_file" ] && log_content=$(cat "$log_file" 2>/dev/null)

  # ─── R8 Play Core missing classes (eng tez-tez) ───
  # Belgilar: "Missing class com.google.android.play.core" yoki missing_rules.txt mavjud
  if echo "$log_content" | grep -qE "Missing class com\.google\.android\.play\.core|R8: Missing class|missing_rules\.txt" \
     || [ -f "build/app/outputs/mapping/release/missing_rules.txt" ]; then
    warn "${BOLD}Sabab aniqlandi: R8 + Play Core deferred components${NC}"
    info "Flutter embedding 'com.google.android.play.core.*' klasslarini reference qiladi,"
    info "lekin app ularni o'z ichiga olmaydi. R8 (code shrinker) ularni topa olmay xato beradi."
    info "Bu ${BOLD}mashhur Flutter muammosi${NC} — ProGuard qoidalari bilan oson tuzatiladi."
    echo

    local fix_it
    read -p "  Avtomatik tuzatib, qayta build qilamizmi? (y/n) [y]: " fix_it
    if [[ "$fix_it" =~ ^[Nn]$ ]]; then
      info "Qo'lda tuzatish uchun ${BOLD}android/app/proguard-rules.pro${NC} ga qo'shing:"
      info "  -dontwarn com.google.android.play.core.**"
      info "  -keep class com.google.android.play.core.** { *; }"
      return 1
    fi

    _ensure_proguard_playcore_rules
    echo
    step "Qayta build qilinmoqda (ProGuard qoidalari bilan)..."
    info "flutter build ${btype} ${variant}"
    flutter build "${btype}" ${variant}
    local retry_rc=$?
    if [ "$retry_rc" -eq 0 ]; then
      echo
      ok "🎉 Build muvaffaqiyatli! (ProGuard qoidalari yordam berdi)"
      return 0
    fi
    echo
    err "Qayta build ham xato berdi (exit: $retry_rc)"
    info "Sabab boshqa bo'lishi mumkin — yuqoridagi xato'ni ko'ring"
    info "build.gradle'da ${BOLD}minifyEnabled${NC} va ${BOLD}proguardFiles${NC} to'g'ri sozlanganini tekshiring"
    return 1
  fi

  # ─── Out of Memory (Gradle/Java heap) ───
  if echo "$log_content" | grep -qiE "OutOfMemoryError|Java heap space|GC overhead limit|Expiring Daemon"; then
    warn "${BOLD}Sabab: Xotira yetishmadi (Gradle/Java heap)${NC}"
    info "Yechim — ${BOLD}android/gradle.properties${NC} ga qo'shing yoki oshiring:"
    info "  org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=2048m"
    echo
    local add_mem
    read -p "  Avtomatik qo'shib, qayta build qilamizmi? (y/n) [y]: " add_mem
    if [[ ! "$add_mem" =~ ^[Nn]$ ]]; then
      local gp="android/gradle.properties"
      if [ -f "$gp" ] && grep -q "org.gradle.jvmargs" "$gp"; then
        # Mavjud qatorni almashtirish
        sed -i.bak 's/^org.gradle.jvmargs=.*/org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=2048m/' "$gp"
      else
        echo "org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=2048m" >> "$gp"
      fi
      ok "gradle.properties yangilandi"
      step "Qayta build qilinmoqda..."
      flutter build "${btype}" ${variant}
      [ $? -eq 0 ] && { ok "🎉 Build muvaffaqiyatli!"; return 0; }
    fi
    return 1
  fi

  # ─── Signing xatosi ───
  if echo "$log_content" | grep -qiE "keystore|SigningConfig|Failed to read key|Keystore file .* not found"; then
    warn "${BOLD}Sabab: Signing (keystore) muammosi${NC}"
    info "android/key.properties va keystore fayl to'g'ri sozlanganini tekshiring"
    try_this "flutter-build   # Build → Production → Android → keystore qayta sozlang"
    return 1
  fi

  # ─── CocoaPods / umumiy ───
  if echo "$log_content" | grep -qiE "Could not resolve|Could not find .* in|Failed to resolve"; then
    warn "${BOLD}Sabab: Dependency resolve qilib bo'lmadi${NC}"
    info "Yechim'lar:"
    try_this \
      "flutter clean && flutter pub get   # cache tozalash" \
      "cd android && ./gradlew clean && cd ..   # Gradle cache"
    return 1
  fi

  # ─── Umumiy (aniq emas) ───
  warn "${BOLD}Sabab aniq emas${NC} — yuqoridagi to'liq xato'ni ko'ring"
  info "Tez-tez yordam beradigan qadamlar:"
  try_this \
    "flutter clean && flutter pub get" \
    "flutter doctor -v   # muhitni tekshirish" \
    "cd android && ./gradlew assembleRelease --stacktrace && cd ..   # batafsil xato"
  return 1
}

# v1.15.0: Express (Auto Deploy) rejimi konfiguratsiyasi
# Per-project config asosida barcha build flag'larni AVTOMATIK o'rnatadi —
# foydalanuvchidan hech narsa so'ramaydi. Faqat sozlanmagan loyiha bo'lsa,
# minimal sozlash so'raydi (keystore/account birinchi marta).
#
# Global flag'larni o'rnatadi: IS_PROD, MODE_LABEL, BUILD_ANDROID, BUILD_IOS,
#   BUILD_AAB, BUILD_APK, DO_CLEAN, DO_PUBGET, DO_APPSTORE_UPLOAD, DO_PLAYSTORE_UPLOAD
#
# Returns:
#   0 — konfiguratsiya tayyor, deploy qilish mumkin
#   1 — sozlanmagan yoki bekor (interaktiv rejimga qaytish kerak)
express_configure() {
  step "⚡ Express (Auto Deploy) — sozlamalar aniqlanmoqda"
  echo

  # Production rejim — deploy uchun har doim
  IS_PROD=true
  MODE_LABEL="PRODUCTION"
  BUILD_AAB=true
  BUILD_APK=false
  DO_CLEAN=false
  DO_PUBGET=false
  BUILD_ANDROID=false
  BUILD_IOS=false
  DO_PLAYSTORE_UPLOAD=false
  DO_APPSTORE_UPLOAD=false

  # ── Qaysi platformalar SOZLANGAN ekanini aniqlash (hali tanlamaymiz) ──
  local android_ok=false ios_ok=false
  local pkg android_account android_track bundle ios_account

  pkg=$(detect_android_package_name 2>/dev/null)
  if [ -n "$pkg" ]; then
    android_account=$(play_project_config_get "$pkg" "account" 2>/dev/null)
    if [ -n "$android_account" ] && play_account_exists "$android_account"; then
      android_ok=true
      android_track=$(play_project_config_get "$pkg" "track" 2>/dev/null)
      android_track="${android_track:-internal}"
    fi
  fi

  if [ "$(uname)" = "Darwin" ]; then
    bundle=$(detect_ios_bundle_id 2>/dev/null)
    if [ -n "$bundle" ]; then
      ios_account=$(appstore_project_config_get "$bundle" "account" 2>/dev/null)
      if [ -n "$ios_account" ] && appstore_account_exists "$ios_account" 2>/dev/null; then
        ios_ok=true
      fi
    fi
  fi

  # Hech bo'lmasa bitta platforma sozlangan bo'lishi kerak
  if ! $android_ok && ! $ios_ok; then
    warn "Express rejim uchun hech qaysi platforma sozlanmagan"
    info "Avval oddiy build/upload bilan akkaunt va keystore'ni sozlang:"
    info "  ${BOLD}flutter-build${NC} → 2) Build (to'liq sozlash)"
    info "Sozlangach, Express rejim ishlaydi"
    return 1
  fi

  # ── v1.15.1: Platforma checkbox — faqat sozlangan platformalar ──
  # Foydalanuvchi qaysi platformaga deploy qilishni tanlaydi (default: hammasi)
  info "Sozlangan platformalar:"
  $android_ok && info "  🤖 Android: ${BOLD}${pkg}${NC} (${android_account} | ${android_track})"
  $ios_ok     && info "  🍏 iOS: ${BOLD}${bundle}${NC} (${ios_account})"
  echo

  # Checkbox uchun faqat sozlangan platformalarni ko'rsatamiz
  local cb_labels=() cb_keys=()
  if $android_ok; then cb_labels+=("🤖 Android (Play Store)"); cb_keys+=("android"); fi
  if $ios_ok; then cb_labels+=("🍏 iOS (App Store)"); cb_keys+=("ios"); fi

  # Agar faqat 1 ta platforma sozlangan bo'lsa, checkbox shart emas — to'g'ridan-to'g'ri
  if [ "${#cb_keys[@]}" -eq 1 ]; then
    case "${cb_keys[0]}" in
      android) BUILD_ANDROID=true; DO_PLAYSTORE_UPLOAD=true ;;
      ios)     BUILD_IOS=true; DO_APPSTORE_UPLOAD=true ;;
    esac
    ok "Yagona platforma: ${cb_labels[0]}"
    return 0
  fi

  # Bir nechta sozlangan — checkbox (default: hammasi belgilangan)
  CHECKBOX_INITIAL=()
  local k
  for k in "${cb_keys[@]}"; do CHECKBOX_INITIAL+=("true"); done
  arrow_checkbox "Qaysi platformaga deploy? (Space toggle, Enter tasdiqlash)" "${cb_labels[@]}"

  if [ "${CHECKBOX_CANCELLED:-false}" = "true" ]; then
    warn "Bekor qilindi"
    return 1
  fi

  # Tanlovlarni flag'larga aylantirish
  local idx=0
  for k in "${cb_keys[@]}"; do
    if [ "${CHECKBOX_RESULT[$idx]}" = "true" ]; then
      case "$k" in
        android) BUILD_ANDROID=true; DO_PLAYSTORE_UPLOAD=true ;;
        ios)     BUILD_IOS=true; DO_APPSTORE_UPLOAD=true ;;
      esac
    fi
    idx=$((idx + 1))
  done

  # Hech narsa tanlanmagan bo'lsa
  if ! $BUILD_ANDROID && ! $BUILD_IOS; then
    warn "Hech qaysi platforma tanlanmadi — bekor qilindi"
    return 1
  fi

  echo
  $BUILD_ANDROID && ok "Android deploy tanlandi"
  $BUILD_IOS && ok "iOS deploy tanlandi"
  return 0
}

# ─── Asosiy build oqimi (v1.10.0: funksiyaga o'ralgan) ─────
# Return codes:
#   0 — build muvaffaqiyatli
#   1 — bekor qilindi yoki xato (main_menu'ga qaytadi)
# v1.15.0: EXPRESS_MODE=true bo'lsa, wizard/version/confirmation o'tkazib
#   yuboriladi — savolsiz auto deploy.
main_build_flow() {

# ─── Validatsiya ──────────────────────────────────────────
if [ ! -f "pubspec.yaml" ]; then
  err "pubspec.yaml topilmadi. Skript Flutter loyihasi ildizidan ishga tushishi kerak."
  info "Joriy papka: $(pwd)"
  try_this \
    "cd <flutter-loyiha-yo'li>" \
    "flutter-build"
  return 1
fi

if ! command -v flutter &> /dev/null; then
  err "Flutter o'rnatilmagan yoki PATH da yo'q"
  try_this_install "Flutter SDK" \
    "Hammasi" "https://docs.flutter.dev/get-started/install"
  info "Yoki agar o'rnatilgan bo'lsa, PATH ga qo'shing:"
  try_this "export PATH=\"\$PATH:\$HOME/development/flutter/bin\""
  return 1
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

# ─── 2. Build Wizard (v1.11.0: bosqichma-bosqich) ──────────
# 5 ta bosqich, har biri kichik va aniq:
#   [1/5] Build rejimi (Production/Debug)
#   [2/5] Platformalar (Android/iOS)
#   [3/5] Android format (AAB/APK) — faqat Android tanlanganda
#   [4/5] Build oldidan amallar (clean/pub get)
#   [5/5] Deploy (contextual — faqat tegishli optsiyalar)
#
# Har bosqichdan 'b' bilan oldingi bosqichga qaytish mumkin.
# Birinchi bosqichdan 'b' = asosiy menyu'ga qaytish.
#
# Wizard yakunida quyidagi global flag'lar o'rnatiladi:
#   IS_PROD, MODE_LABEL, BUILD_ANDROID, BUILD_IOS,
#   BUILD_AAB, BUILD_APK, DO_CLEAN, DO_PUBGET,
#   DO_APPSTORE_UPLOAD, DO_PLAYSTORE_UPLOAD
BUILD_AAB=false
BUILD_APK=false
DO_APPSTORE_UPLOAD=false
DO_PLAYSTORE_UPLOAD=false

# v1.15.0: Express rejim — wizard o'rniga avtomatik konfiguratsiya
if [ "${EXPRESS_MODE:-false}" = "true" ]; then
  if ! express_configure; then
    warn "Express rejim ishlamadi — oddiy rejimga o'ting"
    return 1
  fi
else
  if ! run_build_wizard; then
    warn "Build bekor qilindi — asosiy menyu'ga qaytdik"
    return 1
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
# v1.14.2 FIX: standart Flutter loyihasida Android/iOS versiyasi pubspec.yaml
# dan olinadi (Flutter reference). Avval alohida "Android versionCode" prompt
# ko'rsatardik — foydalanuvchi uni oshirardi, lekin pubspec o'zgarmagani uchun
# ta'sir qilmasdi ("versiya oshmayapti"). Endi: Flutter reference bo'lsa, faqat
# pubspec so'raladi (yagona manba). Hardcoded bo'lsagina alohida so'raladi.
# v1.15.0: Express rejim — versiyani avtomatik +1 oshiradi, savol so'ramaydi
if [ "${EXPRESS_MODE:-false}" = "true" ]; then
  new_pname="$PUBSPEC_NAME"
  # build raqamini avtomatik +1 (resolve_version_input '+' bilan)
  new_pbuild=$(resolve_version_input "+" "$PUBSPEC_BUILD")
  new_iversion="$new_pname"; new_ibuild="$new_pbuild"
  new_aversion="$new_pname"; new_abuild="$new_pbuild"
  step "⚡ Express: versiya avtomatik oshirildi"
  ok "Versiya: ${YELLOW}${PUBSPEC_NAME}+${PUBSPEC_BUILD}${NC} → ${GREEN}${new_pname}+${new_pbuild}${NC}"
  # pubspec'ni yangilaymiz (Android/iOS Flutter ref orqali avtomatik oladi)
  if [ "$new_pbuild" != "$PUBSPEC_BUILD" ]; then
    update_pubspec_version "$new_pname" "$new_pbuild"
    ok "pubspec.yaml yangilandi: ${new_pname}+${new_pbuild}"
  fi
  # Hardcoded versiya bo'lsa, ularni ham yangilaymiz
  if $BUILD_IOS && [ -f "$IOS_PROJECT" ] && ! $IOS_USES_FLUTTER_REF; then
    update_ios_version "$IOS_PROJECT" "$new_iversion" "$new_ibuild"
  fi
  if $BUILD_ANDROID && [ -n "$ANDROID_GRADLE" ] && ! $ANDROID_USES_FLUTTER_REF; then
    update_android_version "$ANDROID_GRADLE" "$new_aversion" "$new_abuild"
  fi
  # Express'da release notes avtomatik (git commit yoki default)
  RELEASE_NOTES=$(express_auto_release_notes "$new_pname")
  STAGED_ROLLOUT_FRACTION="1.0"
else  # ── Oddiy interaktiv rejim ──
step "Yangi versiyalarni kiriting"
info "Enter — hozirgi qiymatni saqlaydi  |  + — oxirgi raqamni +1 ga oshirish"

# Platformalar pubspec'ga bog'liqmi yoki hardcoded'mi — aniqlaymiz
both_use_flutter_ref=true
$BUILD_IOS && ! $IOS_USES_FLUTTER_REF && both_use_flutter_ref=false
$BUILD_ANDROID && ! $ANDROID_USES_FLUTTER_REF && both_use_flutter_ref=false

if $both_use_flutter_ref; then
  echo
  ok "Bu loyiha pubspec.yaml'ni yagona manba sifatida ishlatadi"
  info "(Android versionCode va iOS build number pubspec.yaml'dan olinadi)"
  info "${BOLD}Versiya oshirish uchun pubspec build # ni oshiring (yoki '+' bosing)${NC}"
fi
echo

read -p "    pubspec.yaml versiya (versionName)  [${PUBSPEC_NAME}]: " new_pname
read -p "    pubspec.yaml build # (versionCode)  [${PUBSPEC_BUILD}]: " new_pbuild
new_pname=$(resolve_version_input "$new_pname" "$PUBSPEC_NAME")
new_pbuild=$(resolve_version_input "$new_pbuild" "$PUBSPEC_BUILD")

# iOS: faqat HARDCODED bo'lsa alohida so'raladi
new_iversion="$new_pname"; new_ibuild="$new_pbuild"
if $BUILD_IOS && ! $IOS_USES_FLUTTER_REF; then
  echo
  info "iOS hardcoded versiya ishlatadi (pubspec'dan emas) — alohida kiriting:"
  read -p "    iOS versiya           [${IOS_VERSION}]: " new_iversion
  read -p "    iOS build number      [${IOS_BUILD}]: " new_ibuild
  new_iversion=$(resolve_version_input "$new_iversion" "$IOS_VERSION")
  new_ibuild=$(resolve_version_input "$new_ibuild" "$IOS_BUILD")
fi

# Android: faqat HARDCODED bo'lsa alohida so'raladi
new_aversion="$new_pname"; new_abuild="$new_pbuild"
if $BUILD_ANDROID && ! $ANDROID_USES_FLUTTER_REF; then
  echo
  info "Android hardcoded versiya ishlatadi (pubspec'dan emas) — alohida kiriting:"
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
# iOS qatorini ko'rsatish: Flutter ref bo'lsa "pubspec'dan", aks holda alohida qiymat
if $BUILD_IOS; then
  if $IOS_USES_FLUTTER_REF; then
    echo -e "    iOS           : ${GREEN}${new_pname} (${new_pbuild})${NC}  ${BLUE}← pubspec.yaml'dan${NC}"
  else
    echo -e "    iOS           : ${YELLOW}${IOS_VERSION} (${IOS_BUILD})${NC} → ${GREEN}${new_iversion} (${new_ibuild})${NC}"
  fi
fi
if $BUILD_ANDROID; then
  if $ANDROID_USES_FLUTTER_REF; then
    echo -e "    Android       : ${GREEN}${new_pname} (${new_pbuild})${NC}  ${BLUE}← pubspec.yaml'dan${NC}"
  else
    echo -e "    Android       : ${YELLOW}${ANDROID_VERSION} (${ANDROID_BUILD})${NC} → ${GREEN}${new_aversion} (${new_abuild})${NC}"
  fi
fi
echo

# v1.14.2: agar versiya umuman o'zgarmasa, ogohlantirish (upload conflict oldini olish)
if [ "$new_pname" = "$PUBSPEC_NAME" ] && [ "$new_pbuild" = "$PUBSPEC_BUILD" ]; then
  if $both_use_flutter_ref || { $BUILD_ANDROID && $ANDROID_USES_FLUTTER_REF; }; then
    warn "Versiya o'zgarmadi (${PUBSPEC_NAME}+${PUBSPEC_BUILD})"
    warn "Agar bu versiya allaqachon Store'ga yuklangan bo'lsa, upload xato beradi!"
    info "Yangi versiya uchun: build # ni oshiring yoki '+' bosing"
    echo
  fi
fi

read -p "  Davom etamizmi? (y/n): " confirm
[[ ! "${confirm}" =~ ^[Yy]$ ]] && { warn "Bekor qilindi — menyu'ga qaytdik"; return 1; }

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

fi  # ← v1.15.0: EXPRESS_MODE if/else oxiri (version input + confirmation + file update)

# ─── 7. Production tekshiruvi (Android signing) ───────────
if $IS_PROD && $BUILD_ANDROID; then
  setup_android_signing
fi

# ─── 7b. App Store upload pre-check (Production + iOS) ────
if $DO_APPSTORE_UPLOAD; then
  step "App Store Connect upload sozlamalarini tekshirish"
  ensure_appstore_credentials || { err "App Store Connect sozlanmadi"; return 1; }
  ensure_export_options || { err "ExportOptions.plist sozlanmadi"; return 1; }
fi

# ─── 7c. Play Store upload pre-check (Production + Android) ─
if $DO_PLAYSTORE_UPLOAD; then
  step "Play Store upload sozlamalarini tekshirish"
  ensure_play_credentials || { err "Play Store sozlanmadi"; return 1; }
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

  # v1.14.1 KRITIK FIX: avval exit code TEKSHIRILMAYDI edi — build muvaffaqiyatsiz
  # bo'lsa ham "muvaffaqiyatli" deyilardi (false positive). Endi tee + PIPESTATUS
  # bilan output'ni ushlaymiz va exit code'ni tekshiramiz. Xato bo'lsa, output'dan
  # sabab aniqlanadi (R8 Play Core, OOM, signing, va h.k.).
  android_build_rc=0
  build_variant=$($IS_PROD && echo "--release" || echo "--debug")
  build_subdir=$($IS_PROD && echo "release" || echo "debug")
  android_build_log=$(mktemp 2>/dev/null || echo "/tmp/fb_android_build.$$")

  if $BUILD_AAB; then
    info "flutter build appbundle ${build_variant}"
    flutter build appbundle ${build_variant} 2>&1 | tee "$android_build_log"
    android_build_rc=${PIPESTATUS[0]}
    if [ "$android_build_rc" -ne 0 ]; then
      handle_android_build_failure "appbundle" "$android_build_rc" "$android_build_log" "$build_variant"
      android_retry_rc=$?
      rm -f "$android_build_log"
      [ "$android_retry_rc" -eq 0 ] || { return 1 2>/dev/null || exit 1; }
    fi
    BUILD_PATHS+=("$(pwd)/build/app/outputs/bundle/${build_subdir}")
  fi

  if $BUILD_APK; then
    info "flutter build apk ${build_variant}"
    flutter build apk ${build_variant} 2>&1 | tee "$android_build_log"
    android_build_rc=${PIPESTATUS[0]}
    if [ "$android_build_rc" -ne 0 ]; then
      handle_android_build_failure "apk" "$android_build_rc" "$android_build_log" "$build_variant"
      android_retry_rc=$?
      rm -f "$android_build_log"
      [ "$android_retry_rc" -eq 0 ] || { return 1 2>/dev/null || exit 1; }
    fi
    BUILD_PATHS+=("$(pwd)/build/app/outputs/flutter-apk")
  fi

  rm -f "$android_build_log"
  ok "Android build muvaffaqiyatli (exit code 0)"
fi

if $BUILD_IOS; then
  step "iOS build (${MODE_LABEL})"
  # v1.14.1 KRITIK FIX: iOS build ham exit code tekshirmasdan "muvaffaqiyatli"
  # derdi (false positive). Endi tekshiramiz.
  ios_build_rc=0
  if $IS_PROD; then
    if $DO_APPSTORE_UPLOAD; then
      info "flutter build ipa --release --export-options-plist ios/ExportOptions.plist"
      flutter build ipa --release --export-options-plist ios/ExportOptions.plist
      ios_build_rc=$?
    else
      info "flutter build ipa --release"
      flutter build ipa --release
      ios_build_rc=$?
    fi
    BUILD_PATHS+=("$(pwd)/build/ios/ipa")
  else
    info "flutter build ios --debug --no-codesign"
    flutter build ios --debug --no-codesign
    ios_build_rc=$?
    BUILD_PATHS+=("$(pwd)/build/ios/iphoneos")
  fi
  if [ $ios_build_rc -ne 0 ]; then
    err "iOS build muvaffaqiyatsiz (exit code: $ios_build_rc)"
    info "Yuqoridagi xato xabarini ko'ring"
    info "Tez-tez uchraydigan sabablar:"
    info "  • CocoaPods muammosi: ${BOLD}cd ios && pod install && cd ..${NC}"
    info "  • Signing: Xcode'da Team/Provisioning profil sozlang"
    info "  • Clean kerak: ${BOLD}flutter clean && flutter pub get${NC}"
    return 1 2>/dev/null || exit 1
  fi
  ok "iOS build muvaffaqiyatli (exit code 0)"
fi

# ─── 9b. App Store Connect ga upload ──────────────────────
if $DO_APPSTORE_UPLOAD; then
  ipa_file=$(find_latest_ipa) || {
    err "IPA fayl topilmadi build/ios/ipa/ ichida"
    info "Build muvaffaqiyatli emas yoki ExportOptions.plist xato"
    return 1
  }
  upload_to_appstore "$ipa_file" || warn "Upload xato berdi — IPA fayl saqlangan: $ipa_file"
fi

# ─── 9c. Play Store ga upload ─────────────────────────────
if $DO_PLAYSTORE_UPLOAD; then
  aab_file=$(find_latest_aab) || {
    err "AAB fayl topilmadi build/app/outputs/bundle/release/ ichida"
    info "Build muvaffaqiyatli emas yoki AAB format yoqilmagan"
    return 1
  }

  current_pkg_for_upload=$(detect_android_package_name)
  current_track=$(play_project_config_get "$current_pkg_for_upload" "track")

  # v1.15.0: Express rejim — release notes va rollout avtomatik (so'ramaydi)
  if [ "${EXPRESS_MODE:-false}" = "true" ]; then
    # RELEASE_NOTES va STAGED_ROLLOUT_FRACTION allaqachon o'rnatilgan (express bosqichda)
    [ -z "$RELEASE_NOTES" ] && RELEASE_NOTES=$(express_auto_release_notes "$new_pname")
    [ -z "$STAGED_ROLLOUT_FRACTION" ] && STAGED_ROLLOUT_FRACTION="1.0"
    info "⚡ Express: release notes avtomatik | rollout 100%"
  else
    # Release notes yig'ish (har upload uchun yangi)
    RELEASE_NOTES=$(collect_release_notes "$new_pname" "$new_pbuild")

    # Staged rollout — agar production track tanlangan bo'lsa
    STAGED_ROLLOUT_FRACTION=""
    if [ "$current_track" = "production" ]; then
      echo
      info "Production track tanlandi — staged rollout"
      echo -e "  ${BOLD}Foydalanuvchilarga foiz bilan release:${NC}"
      echo -e "    ${CYAN}1${NC}) 100%  — barchaga darrov (default)"
      echo -e "    ${CYAN}2${NC}) 50%   — yarmiga"
      echo -e "    ${CYAN}3${NC}) 10%   — sinov uchun (keyinroq oshirish mumkin)"
      echo -e "    ${CYAN}4${NC}) 1%    — minimal sinov"
      echo -e "    ${CYAN}5${NC}) Custom %"
      echo
      read -p "  Tanlang [1-5] [1]: " roll_choice
      case "${roll_choice:-1}" in
        1) STAGED_ROLLOUT_FRACTION="1.0" ;;
        2) STAGED_ROLLOUT_FRACTION="0.5" ;;
        3) STAGED_ROLLOUT_FRACTION="0.1" ;;
        4) STAGED_ROLLOUT_FRACTION="0.01" ;;
        5)
          read -p "    Foiz (1-100): " custom_pct
          if [[ "$custom_pct" =~ ^[0-9]+$ ]] && [ "$custom_pct" -ge 1 ] && [ "$custom_pct" -le 100 ]; then
            STAGED_ROLLOUT_FRACTION=$(awk "BEGIN{printf \"%.4f\", $custom_pct / 100}")
          else
            warn "Noto'g'ri foiz, 100% ishlatamiz"
            STAGED_ROLLOUT_FRACTION="1.0"
          fi
          ;;
        *) STAGED_ROLLOUT_FRACTION="1.0" ;;
      esac
      ok "Rollout: $(awk "BEGIN{printf \"%.0f\", $STAGED_ROLLOUT_FRACTION * 100}")%"
    fi
  fi

  # v1.12.3: faqat muvaffaqiyatli upload'dan keyin promote taklif qilamiz.
  # Avval `|| warn ...` ishlatardik — bu promotion'ni hatto upload xato bo'lganda
  # ham chaqirardi va user "internal track'da release topilmadi" xatosini olardi.
  # v1.13.9: manual UI upload tanlangan bo'lsa, bu xato emas
  local play_upload_ok=true
  PLAY_MANUAL_UPLOAD_INITIATED=false
  upload_to_play_store "$aab_file" || {
    if [ "${PLAY_MANUAL_UPLOAD_INITIATED:-false}" = "true" ]; then
      info "📋 Manual upload Play Console'da boshlandi — browser'da yakunlang"
    else
      warn "Upload xato berdi — AAB fayl saqlangan: $aab_file"
      info "Promotion taklif qilinmaydi (chunki upload bo'lmadi)"
    fi
    play_upload_ok=false
  }

  if $play_upload_ok && [ "$current_track" != "production" ]; then
    play_suggest_promotion "$current_pkg_for_upload" "$current_track"
  fi
fi

# ─── 10. Build natijalarini ochish (macOS/Linux/WSL) ──────
step "Build natijalarini ochish"
for path in "${BUILD_PATHS[@]}"; do
  open_file "$path" || true
done

banner "Hammasi tayyor! Versiya: ${new_pname}+${new_pbuild}"
  return 0
}  # ← main_build_flow() oxiri

# ─── Asosiy entry point ─────────────────────────────────
# Argumentlar tahlil qilingan, special mode handler'lar yuqorida (settings,
# doctor, promote, rollout) ishlatildi va exit qilindi. Hech qaysi flag
# bo'lmasa, foydalanuvchini asosiy menyu'ga olib chiqamiz.
main_menu
