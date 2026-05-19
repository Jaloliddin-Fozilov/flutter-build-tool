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
SCRIPT_VERSION="1.12.1"
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
  echo
  read -p "  ${1:-Davom etish uchun Enter...}" _
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
    echo -e "  ${BOLD}│${NC}  ${CYAN}1${NC}) ${BOLD}🚀 Build${NC} (asosiy oqim)                              ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}2${NC}) ⚙️  Sozlamalar                                          ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}3${NC}) 🩺 Doctor (tizim tekshiruvi)                            ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}4${NC}) ⬆️  Android track promotion                              ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}5${NC}) 📊 Rollout foizini oshirish                              ${BOLD}│${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}6${NC}) 📋 Akkauntlar va loyihalarni ko'rish                     ${BOLD}│${NC}"
    echo -e "  ${BOLD}├─────────────────────────────────────────────────────────${NC}"
    echo -e "  ${BOLD}│${NC}  ${CYAN}q${NC}) Chiqish                                                   ${BOLD}│${NC}"
    echo -e "  ${BOLD}╰─────────────────────────────────────────────────────────${NC}"
    echo
    read -p "  Tanlang [1-6, q] [1]: " choice
    choice="${choice:-1}"

    case "$choice" in
      1)
        # Build flow — main_build_flow chaqiriladi (skript pastida aniqlangan)
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
      2)
        settings_main_menu
        ;;
      3)
        run_diagnostics
        pause
        ;;
      4)
        menu_promote_interactive
        ;;
      5)
        menu_rollout_interactive
        ;;
      6)
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
i=0
args=("$@")
while [ "$i" -lt "${#args[@]}" ]; do
  arg="${args[$i]}"
  case "$arg" in
    --no-update-check|--skip-update)
      SKIP_UPDATE=true
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
    err "Yuklash xato berdi"
    appstore_upload_recovery_hints "api_key"
    return 1
  fi
}

# Method 2: Apple ID + App-specific password orqali xcrun altool
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

  if xcrun altool --upload-app \
       --type ios \
       --file "$ipa" \
       --username "$apple_id" \
       --password "$app_pwd"; then
    echo
    ok "Muvaffaqiyatli yuklandi!"
    info "TestFlight processing 10-30 daqiqa davom etadi"
    return 0
  else
    err "Yuklash xato berdi"
    appstore_upload_recovery_hints "apple_id_altool"
    return 1
  fi
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
    read -p "  Hozir altool bilan qayta urinaylikmi? (y/n) [y]: " try_altool
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

# Track'dagi joriy release'larni olish. Natija: "versionCode versionName" qatorlar.
play_list_track_releases() {
  local token="$1" package_name="$2" track="$3"
  local response
  response=$(curl -fsS \
    "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${package_name}/tracks/${track}" \
    -H "Authorization: Bearer ${token}" 2>/dev/null)
  [ -z "$response" ] && return 1
  # Faqat versionCodes ni chiqaramiz (oddiy parsing)
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
  info "[3/5] AAB yuklanmoqda (${size_mb} MB)..."
  local upload_response version_code
  upload_response=$(curl -fsS -X POST \
    "${upload_base}/edits/${edit_id}/bundles?uploadType=media" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${aab}" 2>&1) || {
      err "AAB yuklash xato: $upload_response"
      # versionCode conflict — eng tez-tez uchraydi
      if echo "$upload_response" | grep -qE 'APK specifies a version code that has already been used|Version code [0-9]+ has already been used'; then
        info "Sabab: bu versionCode allaqachon Play Store'ga yuklangan"
        try_this \
          "flutter-build   # menu'da build #ga '+' bosing (avtomatik +1)" \
          "# yoki pubspec.yaml'da version: X.Y.Z+N ni N+1 ga oshiring"
      elif echo "$upload_response" | grep -q 'APK is not signed'; then
        info "Sabab: AAB signed emas yoki noto'g'ri signing"
        try_this "flutter-build   # Production checkbox'ini yoqing va keystore sozlang"
      fi
      return 1
    }
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

# ─── Asosiy build oqimi (v1.10.0: funksiyaga o'ralgan) ─────
# Return codes:
#   0 — build muvaffaqiyatli
#   1 — bekor qilindi yoki xato (main_menu'ga qaytadi)
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

if ! run_build_wizard; then
  warn "Build bekor qilindi — asosiy menyu'ga qaytdik"
  return 1
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

  # Release notes yig'ish (har upload uchun yangi)
  RELEASE_NOTES=$(collect_release_notes "$new_pname" "$new_pbuild")

  # Staged rollout — agar production track tanlangan bo'lsa
  STAGED_ROLLOUT_FRACTION=""
  current_pkg_for_upload=$(detect_android_package_name)
  current_track=$(play_project_config_get "$current_pkg_for_upload" "track")
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

  upload_to_play_store "$aab_file" || warn "Upload xato berdi — AAB fayl saqlangan: $aab_file"

  # Post-upload: per-project promotion_flow ga binoan keyingi qadam taklif qilish
  if [ "$current_track" != "production" ]; then
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
