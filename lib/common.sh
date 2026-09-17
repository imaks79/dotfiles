#!/usr/bin/env bash
# Общие хелперы: логирование, определение ОС/пакетного менеджера, симлинки.

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'

info()  { printf '%s[*]%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s[+]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf '%s[x]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANUAL_TODO=()
FAILED_STEPS=()

# Запускает один шаг установки так, чтобы его провал (недостающий пакет,
# скрипт-установщик отказался ставиться и т.п.) не обрывал set -e весь
# остальной setup.sh — сообщаем и идём дальше.
step() {
    local name="$1"; shift
    if ! "$@"; then
        warn "Шаг '$name' завершился с ошибкой, продолжаю дальше"
        FAILED_STEPS+=("$name")
    fi
}

detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *) err "Неподдерживаемая ОС: $(uname -s). Скрипт рассчитан на macOS и Linux."; exit 1 ;;
    esac

    PKG_MANAGER=""
    if [[ "$OS" == "linux" ]]; then
        if   command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"
        elif command -v dnf     >/dev/null 2>&1; then PKG_MANAGER="dnf"
        elif command -v pacman  >/dev/null 2>&1; then PKG_MANAGER="pacman"
        elif command -v zypper  >/dev/null 2>&1; then PKG_MANAGER="zypper"
        elif command -v apk     >/dev/null 2>&1; then PKG_MANAGER="apk"
        else err "Не удалось определить пакетный менеджер Linux."; exit 1
        fi
    fi
    info "Обнаружена система: $OS${PKG_MANAGER:+ ($PKG_MANAGER)}"
}

# link_file <источник в dotfiles> <цель в системе>
# Существующий файл/симлинк в цели бэкапится с суффиксом .bak-<timestamp>.
link_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [[ -L "$dst" ]]; then
        [[ "$(readlink "$dst")" == "$src" ]] && return 0
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        local bak="${dst}.bak-$(date +%Y%m%d%H%M%S)"
        warn "$dst уже существует, сохраняю как $bak"
        mv "$dst" "$bak"
    fi
    ln -s "$src" "$dst"
    ok "Симлинк: $dst -> $src"
}

# clone_or_update <repo-url> <целевая директория>
clone_or_update() {
    local repo="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        info "Обновляю $dir"
        git -C "$dir" pull --ff-only --quiet || warn "Не удалось обновить $dir, оставляю как есть"
    else
        info "Клонирую $repo -> $dir"
        git clone --quiet --depth 1 "$repo" "$dir"
    fi
}
