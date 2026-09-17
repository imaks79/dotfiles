#!/usr/bin/env bash
# Настройка автоматического подтягивания конфигов новым пользователям системы:
# публикует dotfiles в общедоступное место и раскладывает симлинки в
# /etc/skel (Linux) / User Template (macOS, если это вообще возможно — см. ниже).

SHARED_DOTS_DIR="${SHARED_DOTS_DIR:-/usr/local/share/dotfiles}"
SKEL_DIR="${SKEL_DIR:-/etc/skel}"

# Публикует текущие dotfiles в мировом доступе на чтение — это то, на что
# симлинки в /etc/skel и первый вход нового пользователя будут ссылаться.
# Запускать снова после любых изменений в config/ (setup.sh и update.sh
# делают это сами).
sync_shared_dotfiles() {
    info "Публикую dotfiles для новых пользователей в $SHARED_DOTS_DIR"
    sudo mkdir -p "$SHARED_DOTS_DIR"
    sudo rsync -a --delete --exclude '.git' --exclude 'config/*/*.bak-*' \
        "$DOTFILES_DIR/" "$SHARED_DOTS_DIR/"
    sudo chmod -R a+rX "$SHARED_DOTS_DIR"
    ok "Общая копия обновлена: $SHARED_DOTS_DIR"
}

# Пары "путь относительно $HOME" -> "путь относительно config/", одним
# источником для /etc/skel и для User Template — если добавляешь новый
# отслеживаемый файл в lib/deploy.sh, добавь его и сюда.
skel_link_map() {
    cat <<'EOF'
.zshrc|zsh/.zshrc
.config/tmux/tmux.conf.local|tmux/tmux.conf.local
.config/git/.gitconfig|git/.gitconfig
.config/git/.gitignore_global|git/.gitignore_global
.ssh/config|ssh/config
.config/alacritty/alacritty.toml|alacritty/alacritty.toml
.config/mc/ini|mc/ini
.config/mc/panels.ini|mc/panels.ini
.config/htop/htoprc|htop/htoprc
.config/nvim|nvim
EOF
}

# Раскладывает символические ссылки на $SHARED_DOTS_DIR/config/... в базовый
# каталог (skel/шаблон). oh-my-zsh/oh-my-tmux/AstroNvim у нового пользователя
# ещё не склонированы — этим занимается lib/first-login.sh при первом входе
# (см. хук в верхней части config/zsh/.zshrc).
skel_link_into() {
    local base="$1" rel cfg
    while IFS='|' read -r rel cfg; do
        [[ -n "$rel" ]] || continue
        sudo mkdir -p "$base/$(dirname "$rel")"
        sudo ln -sfn "$SHARED_DOTS_DIR/config/$cfg" "$base/$rel"
    done < <(skel_link_map)
}

install_skel_linux() {
    sync_shared_dotfiles
    info "Раскладываю симлинки в $SKEL_DIR"
    sudo mkdir -p "$SKEL_DIR"
    skel_link_into "$SKEL_DIR"
    ok "$SKEL_DIR настроен — новые пользователи, созданные через 'useradd -m', получат эти конфиги"
    info "Создавайте пользователей с zsh: sudo useradd -m -s \$(command -v zsh) <имя>"
}

# На современном macOS /System — запечатанный, доступный только для чтения том:
# запись в '/System/Library/User Template' не проходит даже под root с SIP
# (это НЕ то же самое, что просто "включить SIP" — не пытаемся его отключать,
# это небезопасно и не гарантированно поможет). Пробуем на всякий случай
# (вдруг окружение нестандартное), но полагаться на это нельзя — основной
# путь для macOS — new-user.sh после создания учётки.
install_skel_macos() {
    sync_shared_dotfiles
    local template="/System/Library/User Template/Non_localized"
    # -w как текущий пользователь ничего не доказывает (мы и так не root
    # здесь) — пробуем реальную запись под sudo, это и есть настоящий тест.
    if sudo mkdir -p "$template/.dotfiles-write-test" 2>/dev/null; then
        sudo rmdir "$template/.dotfiles-write-test" 2>/dev/null || true
        info "Раскладываю симлинки в $template"
        skel_link_into "$template"
        ok "User Template настроен"
    else
        warn "macOS: '$template' недоступен для записи (System Integrity Protection"
        warn "  + запечатанный системный том). Автоматически подготовить шаблон для"
        warn "  новых пользователей на macOS нельзя штатными средствами."
        warn "  Используйте ./new-user.sh <имя> после создания пользователя — он делает то же самое."
        MANUAL_TODO+=("новые пользователи macOS: запускайте ./new-user.sh <имя> после создания учётки")
    fi
}

install_skel() {
    if [[ "$OS" == "macos" ]]; then
        install_skel_macos
    else
        install_skel_linux
    fi
}
