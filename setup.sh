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
# (+ ядро AstroNvim), htop, gitignore_global, pass, gpg, eza;
# шрифты Hack/0xProto/JetBrainsMono Nerd Font; rust, uv, omp-manager.
# zsh становится оболочкой по умолчанию (chsh).
# Публикует dotfiles в /usr/local/share/dotfiles и раскладывает симлинки в
# /etc/skel (Linux) — новые пользователи получают эти конфиги при создании;
# на macOS это штатно недоступно (SIP), см. new-user.sh.
# На Linux дополнительно ставит flatpak + репозиторий flathub, на macOS — Homebrew.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/deploy.sh"
source "$SCRIPT_DIR/lib/skel.sh"

cmd_install() {
    detect_os
    step "ensure_prereqs"          ensure_prereqs
    step "install_core_packages"   install_core_packages
    step "set_default_shell_zsh"   set_default_shell_zsh
    step "install_terminal"        install_terminal
    step "install_rust"            install_rust
    step "install_uv"              install_uv
    step "install_omp_manager"     install_omp_manager
    step "install_fonts"           install_fonts
    step "install_oh_my_zsh"       install_oh_my_zsh
    step "install_oh_my_zsh_plugins" install_oh_my_zsh_plugins
    step "install_oh_my_tmux"      install_oh_my_tmux
    step "install_astronvim_core"  install_astronvim_core
    step "install_alacritty_theme" install_alacritty_theme

    offer_restore
    deploy_configs
    step "install_skel"            install_skel

    echo
    ok "Готово."
    if [[ ${#FAILED_STEPS[@]} -gt 0 ]]; then
        warn "Эти шаги упали с ошибкой (см. вывод выше), остальное всё равно доставилось:"
        printf '    - %s\n' "${FAILED_STEPS[@]}"
    fi
    if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
        warn "Не удалось поставить автоматически, сделайте вручную:"
        local item
        for item in "${MANUAL_TODO[@]}"; do
            printf '    - %s\n' "$item"
        done
    fi
    info "Перезапустите терминал (или выполните: exec zsh), чтобы подхватить zsh/tmux."
    print_astra
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
