#!/usr/bin/env bash
# Раскладка конфигов из dotfiles/config в систему + сид/восстановление.

CONFIG_DIR="$DOTFILES_DIR/config"

deploy_configs() {
    info "Раскладываю конфиги симлинками"

    link_file "$CONFIG_DIR/zsh/.zshrc"            "$HOME/.zshrc"

    mkdir -p "$HOME/.config/tmux"
    if [[ -d "$HOME/.config/.oh-my-tmux" ]]; then
        link_file "$HOME/.config/.oh-my-tmux/.tmux.conf" "$HOME/.config/tmux/tmux.conf"
    fi
    link_file "$CONFIG_DIR/tmux/tmux.conf.local"   "$HOME/.config/tmux/tmux.conf.local"

    link_file "$CONFIG_DIR/git/.gitconfig"         "$HOME/.config/git/.gitconfig"
    link_file "$CONFIG_DIR/git/.gitignore_global"  "$HOME/.config/git/.gitignore_global"

    chmod 600 "$CONFIG_DIR/ssh/config" 2>/dev/null || true
    mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
    link_file "$CONFIG_DIR/ssh/config"             "$HOME/.ssh/config"

    link_file "$CONFIG_DIR/alacritty/alacritty.toml" "$HOME/.config/alacritty/alacritty.toml"
    link_file "$CONFIG_DIR/zed/settings.json"      "$HOME/.config/zed/settings.json"

    if [[ -d "$CONFIG_DIR/nvim" ]]; then
        link_file "$CONFIG_DIR/nvim"                "$HOME/.config/nvim"
    fi

    link_file "$CONFIG_DIR/mc/ini"                 "$HOME/.config/mc/ini"
    link_file "$CONFIG_DIR/mc/panels.ini"           "$HOME/.config/mc/panels.ini"

    link_file "$CONFIG_DIR/htop/htoprc"            "$HOME/.config/htop/htoprc"

    if [[ -d "$CONFIG_DIR/musikcube" ]]; then
        local f
        for f in "$CONFIG_DIR"/musikcube/*.json; do
            [[ -e "$f" ]] || continue
            link_file "$f" "$HOME/.config/musikcube/$(basename "$f")"
        done
    fi

    ok "Конфиги разложены"
}

# Заполняет config/ из ТЕКУЩЕЙ живой системы — используется, когда это "родная"
# машина и восстанавливать не с чего (запускается вручную через: setup.sh seed)
seed_configs_from_system() {
    info "Собираю текущие конфиги системы в $CONFIG_DIR"
    mkdir -p "$CONFIG_DIR"/{zsh,tmux,git,ssh,alacritty,zed,mc,htop,musikcube}

    [[ -f "$HOME/.zshrc" ]]                          && cp "$HOME/.zshrc" "$CONFIG_DIR/zsh/.zshrc"
    [[ -f "$HOME/.config/tmux/tmux.conf.local" ]]    && cp "$HOME/.config/tmux/tmux.conf.local" "$CONFIG_DIR/tmux/tmux.conf.local"
    [[ -f "$HOME/.config/git/.gitconfig" ]]          && cp "$HOME/.config/git/.gitconfig" "$CONFIG_DIR/git/.gitconfig"
    [[ -f "$HOME/.config/git/.gitignore_global" ]]   && cp "$HOME/.config/git/.gitignore_global" "$CONFIG_DIR/git/.gitignore_global"
    [[ -f "$HOME/.ssh/config" ]]                     && cp "$HOME/.ssh/config" "$CONFIG_DIR/ssh/config"
    [[ -f "$HOME/.config/alacritty/alacritty.toml" ]] && cp "$HOME/.config/alacritty/alacritty.toml" "$CONFIG_DIR/alacritty/alacritty.toml"
    [[ -f "$HOME/.config/zed/settings.json" ]]       && cp "$HOME/.config/zed/settings.json" "$CONFIG_DIR/zed/settings.json"
    [[ -d "$HOME/.config/nvim" ]]                    && rsync -a --exclude '.git' "$HOME/.config/nvim/" "$CONFIG_DIR/nvim/"
    [[ -f "$HOME/.config/mc/ini" ]]                  && cp "$HOME/.config/mc/ini" "$CONFIG_DIR/mc/ini"
    [[ -f "$HOME/.config/mc/panels.ini" ]]           && cp "$HOME/.config/mc/panels.ini" "$CONFIG_DIR/mc/panels.ini"
    [[ -f "$HOME/.config/htop/htoprc" ]]             && cp "$HOME/.config/htop/htoprc" "$CONFIG_DIR/htop/htoprc"
    if [[ -d "$HOME/.config/musikcube" ]]; then
        cp "$HOME"/.config/musikcube/settings.json   "$CONFIG_DIR/musikcube/" 2>/dev/null || true
        cp "$HOME"/.config/musikcube/hotkeys.json    "$CONFIG_DIR/musikcube/" 2>/dev/null || true
        cp "$HOME"/.config/musikcube/libraries.json  "$CONFIG_DIR/musikcube/" 2>/dev/null || true
        cp "$HOME"/.config/musikcube/playback.json   "$CONFIG_DIR/musikcube/" 2>/dev/null || true
        cp "$HOME"/.config/musikcube/plugin_*.json   "$CONFIG_DIR/musikcube/" 2>/dev/null || true
    fi

    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        git -C "$DOTFILES_DIR" init -q
        git -C "$DOTFILES_DIR" add -A
        git -C "$DOTFILES_DIR" commit -q -m "Initial dotfiles snapshot" || true
        warn "Репозиторий $DOTFILES_DIR проинициализирован локально."
        warn "Добавьте приватный remote и запушьте, чтобы восстанавливаться через git на других машинах:"
        warn "  git -C $DOTFILES_DIR remote add origin <url> && git -C $DOTFILES_DIR push -u origin main"
    fi
    ok "Текущие настройки сохранены в $CONFIG_DIR"
}

config_is_empty() {
    [[ ! -d "$CONFIG_DIR" ]] || [[ -z "$(find "$CONFIG_DIR" -type f -print -quit 2>/dev/null)" ]]
}

restore_from_git() {
    local repo_url="$1"
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        info "В $DOTFILES_DIR уже есть git-репозиторий, просто обновляю"
        git -C "$DOTFILES_DIR" pull --ff-only
    else
        info "Клонирую $repo_url во временный каталог и переношу в $DOTFILES_DIR"
        local tmp; tmp="$(mktemp -d)"
        git clone --depth 1 "$repo_url" "$tmp"
        rsync -a "$tmp/" "$DOTFILES_DIR/"
        rm -rf "$tmp"
    fi
    ok "Настройки получены из git-репозитория"
}

# Архив: config/ (без секретов) + опционально полный ~/.ssh с приватными ключами.
# Архив с ключами передавайте только доверенным каналом (scp, флешка), никогда не через git/облако публично.
backup_to_archive() {
    local dest="${1:-$HOME/dotfiles-backup-$(hostname -s 2>/dev/null || echo host)-$(date +%Y%m%d).tar.gz}"
    local work; work="$(mktemp -d)"
    mkdir -p "$work/config"
    rsync -a "$CONFIG_DIR/" "$work/config/"
    if [[ -d "$HOME/.ssh" ]]; then
        warn "В архив добавляется ПОЛНЫЙ ~/.ssh, включая приватные ключи."
        warn "Передавайте файл только по доверенному каналу и не публикуйте его."
        mkdir -p "$work/ssh-full"
        rsync -a "$HOME/.ssh/" "$work/ssh-full/"
    fi
    tar -czf "$dest" -C "$work" .
    rm -rf "$work"
    ok "Архив создан: $dest"
}

restore_from_archive() {
    local archive="$1"
    [[ -f "$archive" ]] || { err "Файл не найден: $archive"; exit 1; }
    local work; work="$(mktemp -d)"
    tar -xzf "$archive" -C "$work"

    if [[ -d "$work/config" ]]; then
        mkdir -p "$CONFIG_DIR"
        rsync -a "$work/config/" "$CONFIG_DIR/"
        ok "Конфиги восстановлены из архива"
    fi

    if [[ -d "$work/ssh-full" ]]; then
        warn "В архиве найден полный ~/.ssh (с приватными ключами)."
        read -r -p "Восстановить его поверх текущего ~/.ssh? [y/N] " reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            mkdir -p "$HOME/.ssh"
            rsync -a "$work/ssh-full/" "$HOME/.ssh/"
            chmod 700 "$HOME/.ssh"
            find "$HOME/.ssh" -type f -name '*.pub' -prune -o -type f -print | xargs -I{} chmod 600 {} 2>/dev/null || true
            chmod 644 "$HOME"/.ssh/*.pub 2>/dev/null || true
            ok "~/.ssh восстановлен из архива"
        else
            info "Пропускаю восстановление ~/.ssh"
        fi
    fi
    rm -rf "$work"
}

offer_restore() {
    if ! config_is_empty; then
        info "Найдены уже сохранённые конфиги в $CONFIG_DIR, использую их"
        return 0
    fi

    echo
    warn "В $CONFIG_DIR пока нет сохранённых настроек."
    read -r -p "Восстановить настройки с предыдущей системы? [y/N] " reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        seed_configs_from_system
        return 0
    fi

    local method
    read -r -p "Откуда восстанавливать? [g]it-репозиторий / [a]рхив (tar.gz): " method
    case "$method" in
        g|G)
            local url
            read -r -p "URL git-репозитория с dotfiles: " url
            restore_from_git "$url"
            ;;
        a|A)
            local path
            read -r -p "Путь к архиву (.tar.gz): " path
            restore_from_archive "$path"
            ;;
        *)
            warn "Не понял выбор, беру текущие настройки системы как основу"
            seed_configs_from_system
            ;;
    esac
}
