#!/usr/bin/env bash
# Бутстрап при первом входе пользователя, который получил конфиги через
# /etc/skel или User Template. Запускается самим пользователем (без sudo) —
# хук на это стоит в самом верху config/zsh/.zshrc.
#
# skel мог разложить только симлинки на статичные файлы; oh-my-zsh,
# oh-my-tmux, ядро AstroNvim и тема alacritty — это git-клоны в $HOME,
# которых на момент создания учётки ещё не существовало. Этот скрипт
# доклонирует их и чинит зависящие от них симлинки (например tmux.conf).
#
# Перезапустить вручную: bash /usr/local/share/dotfiles/lib/first-login.sh
set -euo pipefail

SHARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SHARE_DIR/lib/common.sh"
source "$SHARE_DIR/lib/packages.sh"
source "$SHARE_DIR/lib/deploy.sh"

detect_os >/dev/null

install_oh_my_zsh
install_oh_my_zsh_plugins
install_oh_my_tmux
install_astronvim_core
install_alacritty_theme
deploy_configs

if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
    warn "Не всё установилось автоматически:"
    printf '    - %s\n' "${MANUAL_TODO[@]}"
fi
ok "Первичная настройка окружения завершена"
