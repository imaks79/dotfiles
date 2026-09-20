#!/usr/bin/env bash
# Личные dotfiles: раскладка конфигов из config/ в $HOME через GNU Stow.
# Предполагается, что всё остальное (zsh, tmux, git, nvim, alacritty, mc,
# htop, stow, ...) в системе уже установлено — этот скрипт только
# раскладывает и поддерживает актуальными сами конфиги, ничего не ставит.
#
# Использование:
#   ./deploy.sh          — разложить конфиги симлинками в $HOME
#   ./deploy.sh adopt    — забрать в config/ файлы, которые приложение
#                          переписало поверх симлинка обычным файлом
#                          (stow --adopt), дальше git diff/add/commit сами

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"

C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'

info()  { printf '%s[*]%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s[+]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()   { printf '%s[x]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; }

# link_file <источник> <цель>
# Простой symlink с бэкапом существующего файла. Единственное применение —
# tmux.conf из oh-my-tmux ниже: он не входит в config/ (это не dotfile, а
# файл уже склонированного пользователем oh-my-tmux), поэтому stow тут не
# при чём.
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

# stow_packages <stow-каталог>
# Перечисляет подкаталоги первого уровня — имена stow-пакетов. Единственный
# источник истины о наборе пакетов: сама структура каталогов config/.
stow_packages() {
    local dir="$1" p
    for p in "$dir"/*/; do
        [[ -d "$p" ]] && basename "$p"
    done
}

# stow_deploy <stow-каталог> <цель> <пакет...>
# Раскладывает stow-пакеты (каждый — поддерево, зеркалящее <цель>) через
# `stow -R`. Перед вызовом stow убирает то, что помешало бы ему: существующий
# симлинк на месте цели удаляется безусловно (это же чинит миграцию со
# старых абсолютных симлинков на stow-совместимые), а существующий реальный
# ЛИСТОВОЙ файл бэкапится с суффиксом .bak-<timestamp>. Реальные каталоги на
# пути (например уже существующий ~/.config, общий для многих пакетов) не
# трогаются — в них просто спускаемся дальше, stow умеет докладывать файлы
# в уже существующий каталог.
# Все пакеты передаются в stow ОДНИМ вызовом, а не по одному — иначе на
# пустой цели stow сворачивает общий каталог вроде ~/.config в симлинк на
# первый обработанный пакет, а каждый следующий пакет в отдельном вызове
# затирает симлинк предыдущего (стоу не знает про пакеты, которые ещё не
# видел). При общем вызове stow видит все пакеты сразу и не сворачивает то,
# что делят между собой несколько из них.
stow_deploy() {
    local stow_dir="$1" target="$2"; shift 2
    local pkg entry rel dst skip bak
    local -a valid_pkgs=()
    for pkg in "$@"; do
        [[ -d "$stow_dir/$pkg" ]] || continue
        valid_pkgs+=("$pkg")
        skip=""
        while IFS= read -r entry; do
            rel="${entry#"$stow_dir/$pkg/"}"
            [[ -n "$skip" && "$rel" == "$skip"/* ]] && continue
            dst="$target/$rel"
            if [[ -L "$dst" ]]; then
                rm -f "$dst"
                skip="$rel"
            elif [[ -f "$entry" && -e "$dst" ]]; then
                bak="${dst}.bak-$(date +%Y%m%d%H%M%S)"
                warn "$dst уже существует, сохраняю как $bak"
                mv "$dst" "$bak"
            fi
        done < <(find "$stow_dir/$pkg" -mindepth 1)
    done
    [[ ${#valid_pkgs[@]} -eq 0 ]] && return 0
    mkdir -p "$target"
    stow -R -d "$stow_dir" -t "$target" "${valid_pkgs[@]}"
}

cmd_deploy() {
    command -v stow >/dev/null 2>&1 || { err "stow не найден в PATH — установите его (brew install stow / apt install stow / dnf install stow / pacman -S stow / zypper install stow / apk add stow)"; exit 1; }
    info "Раскладываю конфиги через stow"

    mkdir -p "$HOME/.config/tmux"
    if [[ -d "$HOME/.config/.oh-my-tmux" ]]; then
        link_file "$HOME/.config/.oh-my-tmux/.tmux.conf" "$HOME/.config/tmux/tmux.conf"
    fi

    chmod 600 "$CONFIG_DIR/ssh/.ssh/config" 2>/dev/null || true
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

    stow_deploy "$CONFIG_DIR" "$HOME" $(stow_packages "$CONFIG_DIR")
    ok "Конфиги разложены"
}

# Если какое-то приложение переписало путь поверх симлинка обычным файлом —
# stow --adopt затягивает этот файл обратно в config/ (заменяя там tracked
# содержимое) и на его месте снова оставляет симлинк. Дальше сам смотришь
# git diff и коммитишь, что действительно нужно.
cmd_adopt() {
    command -v stow >/dev/null 2>&1 || { err "stow не найден в PATH"; exit 1; }
    info "Забираю в config/ файлы, оказавшиеся поверх симлинков реальными (stow --adopt)"
    stow --adopt -d "$CONFIG_DIR" -t "$HOME" $(stow_packages "$CONFIG_DIR")
    warn "Проверьте git -C \"$DOTFILES_DIR\" diff — --adopt затягивает live-файл как есть, без вопросов"
    ok "Готово. Дальше обычный git add/commit/push в $DOTFILES_DIR"
}

case "${1:-deploy}" in
    deploy) cmd_deploy ;;
    adopt)  cmd_adopt ;;
    -h|--help|help)
        sed -n '2,11p' "$0"
        ;;
    *)
        err "Неизвестная команда: $1 (доступно: deploy, adopt, help)"
        exit 1
        ;;
esac
