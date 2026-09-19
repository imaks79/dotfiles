#!/usr/bin/env bash
# Общие хелперы: логирование, определение ОС/пакетного менеджера, симлинки.

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_MAGENTA=$'\033[35m'

info()  { printf '%s[*]%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s[+]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf '%s[x]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANUAL_TODO=()
FAILED_STEPS=()

# retry <попыток> <команда...>
# Повторяет команду при неудаче с паузой между попытками (3с, 6с, 9с...).
# Нужно для шагов, которые тянут что-то по сети (git clone, curl-установщики) —
# на свежей машине (только что поднятый VM/контейнер) сеть иногда не готова
# ещё пару секунд, DNS не разрешается с первого раза и т.п. — временный сбой,
# не ошибка конфигурации.
retry() {
    local attempts="$1"; shift
    local i=1
    while true; do
        if "$@"; then return 0; fi
        if [[ "$i" -ge "$attempts" ]]; then return 1; fi
        warn "Попытка $i/$attempts не удалась, повтор через $((i * 3))с..."
        sleep "$((i * 3))"
        i=$((i + 1))
    done
}

# Префикс для привилегированных команд. Если мы уже root (частый случай в
# минимальных Docker-образах, где sudo вообще не установлен) или sudo нет
# в PATH — выполняем команды напрямую, без него.
if [[ "$(id -u)" -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    warn "sudo не найден и вы не root — привилегированные шаги ниже могут не сработать"
    SUDO=""
fi

# В некоторых окружениях (минимальные Docker-образы, su без -l) переменная
# $USER не экспортирована, хотя мы прекрасно знаем, кто мы — id -un.
USER="${USER:-$(id -un)}"

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

print_astra() {
    printf '%s' "$C_MAGENTA"
    cat <<'EOF'

           *    \   |   /    *
             *   \  |  /   *
               *  \ | /  *
          * * *  \\\|///  * * *
                 ( ( o ) )
          * * *  ///|\\\  * * *
               *  / | \  *
             *   /  |  \   *
           *    /   |   \    *

EOF
    printf '%s' "$C_GREEN"
    cat <<'EOF'
                     |
                     |
                    /|\
                   / | \
                     |
                    / \
EOF
    printf '%s\n' "$C_RESET"
}

# clone_or_update <repo-url> <целевая директория>
clone_or_update() {
    local repo="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        info "Обновляю $dir"
        git -C "$dir" pull --ff-only --quiet || warn "Не удалось обновить $dir, оставляю как есть"
    else
        info "Клонирую $repo -> $dir"
        # На неудачной попытке git обычно сам подчищает частично склонированный
        # каталог, но не гарантированно (прервали процесс, кончилось место) —
        # перед повтором подчищаем сами, иначе git откажется клонировать в
        # непустой каталог.
        retry 3 bash -c '[[ -d "$1" && ! -d "$1/.git" ]] && rm -rf "$1"; git clone --quiet --depth 1 "$2" "$1"' _ "$dir" "$repo"
    fi
}
