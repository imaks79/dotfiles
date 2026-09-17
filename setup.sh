#!/usr/bin/env bash
# Универсальный бутстрап окружения для UNIX-подобных ОС (macOS / Linux).
#
# Использование:
#   ./setup.sh              — установить пакеты, разложить конфиги, при пустом
#                              config/ предложить восстановление с прошлой системы
#   ./setup.sh seed         — только собрать текущие настройки системы в config/
#   ./setup.sh backup [файл]        — упаковать config/ + ~/.ssh в tar.gz
#   ./setup.sh restore <файл.tar.gz> — восстановить config/ (и, по желанию, ~/.ssh) из архива
#
# Устанавливает: oh-my-zsh (+ плагины zsh-autosuggestions,
# zsh-syntax-highlighting), oh-my-tmux, git, ssh, zshrc, mc, alacritty, nvim
# (+ ядро AstroNvim), htop, gitignore_global, pass, gpg;
# шрифты Hack/0xProto/JetBrainsMono Nerd Font; rust, uv, docker.
# На Linux дополнительно ставит flatpak + репозиторий flathub, на macOS — Homebrew.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/deploy.sh"

cmd_install() {
    detect_os
    ensure_prereqs
    install_core_packages
    install_terminal
    install_rust
    install_uv
    install_docker
    install_fonts
    install_oh_my_zsh
    install_oh_my_zsh_plugins
    install_oh_my_tmux
    install_astronvim_core
    install_alacritty_theme

    offer_restore
    deploy_configs

    echo
    ok "Готово."
    if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
        warn "Не удалось поставить автоматически, сделайте вручную:"
        local item
        for item in "${MANUAL_TODO[@]}"; do
            printf '    - %s\n' "$item"
        done
    fi
    info "Перезапустите терминал (или выполните: exec zsh), чтобы подхватить zsh/tmux."
}

case "${1:-install}" in
    install) cmd_install ;;
    seed) seed_configs_from_system ;;
    backup) backup_to_archive "${2:-}" ;;
    restore)
        [[ -n "${2:-}" ]] || { err "Укажите путь к архиву: setup.sh restore <файл.tar.gz>"; exit 1; }
        restore_from_archive "$2"
        deploy_configs
        ;;
    -h|--help|help)
        sed -n '2,15p' "$0"
        ;;
    *)
        err "Неизвестная команда: $1 (доступно: install, seed, backup, restore, help)"
        exit 1
        ;;
esac
