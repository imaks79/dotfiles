#!/usr/bin/env bash
# Настраивает УЖЕ СОЗДАННОГО пользователя: раскладывает конфиги + доклонирует
# per-user зависимости (oh-my-zsh, oh-my-tmux, AstroNvim, тему alacritty).
#
# На Linux то же самое произойдёт само по себе при первом входе пользователя,
# если /etc/skel был настроен через `setup.sh` (см. lib/skel.sh) — этот
# скрипт нужен, только если пользователь создан ДО настройки /etc/skel.
#
# На macOS /System/Library/User Template штатно недоступен для записи
# (System Integrity Protection + запечатанный системный том), поэтому здесь
# это ОСНОВНОЙ способ передать конфиги новому пользователю — запускайте
# его после создания каждой учётки.
#
# Использование: sudo ./new-user.sh <имя_пользователя>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/deploy.sh"
source "$SCRIPT_DIR/lib/skel.sh"

[[ $EUID -eq 0 ]] || { err "Запустите через sudo: sudo $0 <имя_пользователя>"; exit 1; }
target_user="${1:-}"
[[ -n "$target_user" ]] || { err "Использование: sudo $0 <имя_пользователя>"; exit 1; }

detect_os

if [[ "$OS" == "macos" ]]; then
    target_home="$(dscl . -read "/Users/$target_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
else
    target_home="$(getent passwd "$target_user" | cut -d: -f6)"
fi
[[ -n "$target_home" && -d "$target_home" ]] || { err "Не нашёл домашний каталог пользователя $target_user"; exit 1; }

sync_shared_dotfiles

info "Раскладываю конфиги и ставлю per-user зависимости для $target_user ($target_home)"
sudo -u "$target_user" HOME="$target_home" bash "$SHARED_DOTS_DIR/lib/first-login.sh"

ok "Готово: $target_user настроен"
