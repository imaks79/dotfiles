#!/usr/bin/env bash
# Установка пакетного менеджера-прослойки и пакетов.

ensure_prereqs() {
    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            info "Homebrew не найден, устанавливаю..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"
            fi
        fi
        ok "Homebrew готов: $(brew --version | head -1)"
    else
        case "$PKG_MANAGER" in
            apt)    sudo apt-get update -y ;;
            zypper) sudo zypper --non-interactive refresh ;;
        esac
        if ! command -v flatpak >/dev/null 2>&1; then
            info "Устанавливаю flatpak..."
            case "$PKG_MANAGER" in
                apt)    sudo apt-get install -y flatpak ;;
                dnf)    sudo dnf install -y flatpak ;;
                pacman) sudo pacman -S --noconfirm flatpak ;;
                zypper) sudo zypper --non-interactive install flatpak ;;
                apk)    sudo apk add flatpak ;;
            esac
        fi
        if command -v flatpak >/dev/null 2>&1; then
            flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            ok "flatpak + репозиторий flathub готовы"
        else
            warn "flatpak установить не удалось, часть пакетов может быть недоступна"
        fi
    fi
}

# pkg_native <apt> <dnf> <pacman> <zypper> <apk>
# Устанавливает пакет через нативный менеджер macOS/Linux. Пустая строка = имя недоступно/пропустить.
pkg_native() {
    local brew_name="$1" apt_name="$2" dnf_name="$3" pacman_name="$4" zypper_name="$5" apk_name="$6"
    if [[ "$OS" == "macos" ]]; then
        [[ -n "$brew_name" ]] && brew list --formula "$brew_name" >/dev/null 2>&1 && return 0
        [[ -n "$brew_name" ]] && brew install "$brew_name"
        return $?
    fi
    case "$PKG_MANAGER" in
        apt)    [[ -n "$apt_name" ]]    && sudo apt-get install -y "$apt_name" ;;
        dnf)    [[ -n "$dnf_name" ]]    && sudo dnf install -y "$dnf_name" ;;
        pacman) [[ -n "$pacman_name" ]] && sudo pacman -S --noconfirm --needed "$pacman_name" ;;
        zypper) [[ -n "$zypper_name" ]] && sudo zypper --non-interactive install "$zypper_name" ;;
        apk)    [[ -n "$apk_name" ]]    && sudo apk add "$apk_name" ;;
        *) return 1 ;;
    esac
}

pkg_cask() {
    local cask_name="$1" flatpak_id="$2"
    if [[ "$OS" == "macos" ]]; then
        brew list --cask "$cask_name" >/dev/null 2>&1 && return 0
        brew install --cask "$cask_name"
        return $?
    fi
    if [[ -n "$flatpak_id" ]] && command -v flatpak >/dev/null 2>&1; then
        flatpak install -y --noninteractive flathub "$flatpak_id"
        return $?
    fi
    return 1
}

# install <label> -- пробует нативный пакет, потом cargo, потом записывает в MANUAL_TODO
# usage: install "yazi" native_args... [-- cargo:crate1,crate2] [-- hint:URL]
try_install() {
    local label="$1"; shift
    local -a native_args=() cargo_crates=() hint=""
    local mode="native"
    for a in "$@"; do
        case "$a" in
            --cargo) mode="cargo" ;;
            --hint)  mode="hint" ;;
            *)
                case "$mode" in
                    native) native_args+=("$a") ;;
                    cargo)  cargo_crates+=("$a") ;;
                    hint)   hint="$a" ;;
                esac
                ;;
        esac
    done

    if command -v "$label" >/dev/null 2>&1; then
        ok "$label уже установлен"
        return 0
    fi

    info "Устанавливаю $label..."
    if pkg_native "${native_args[@]}" 2>/dev/null && command -v "$label" >/dev/null 2>&1; then
        ok "$label установлен (менеджер пакетов)"
        return 0
    fi
    if [[ "$OS" == "macos" ]] && command -v "$label" >/dev/null 2>&1; then
        ok "$label установлен"
        return 0
    fi

    if [[ ${#cargo_crates[@]} -gt 0 ]]; then
        if ! command -v cargo >/dev/null 2>&1; then
            info "cargo не найден, устанавливаю rustup для сборки $label..."
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null 2>&1
            [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
        fi
        if command -v cargo >/dev/null 2>&1 && cargo install --locked "${cargo_crates[@]}" 2>/dev/null; then
            ok "$label установлен через cargo"
            return 0
        fi
    fi

    warn "$label автоматически установить не удалось"
    MANUAL_TODO+=("$label${hint:+ -> $hint}")
    return 1
}

install_core_packages() {
    info "Базовые пакеты: git, ssh, mc, htop, nvim, tmux, zsh"
    pkg_native git    git        git    git    git    git
    pkg_native ""     openssh-client openssh-clients openssh openssh openssh-client
    command -v ssh >/dev/null 2>&1 || pkg_native openssh openssh openssh openssh openssh openssh
    pkg_native mc     mc         mc     mc     mc     mc
    pkg_native htop   htop       htop   htop   htop   htop
    pkg_native neovim neovim     neovim neovim neovim neovim
    pkg_native tmux   tmux       tmux   tmux   tmux   tmux
    pkg_native zsh    zsh        zsh    zsh    zsh    zsh
}

install_editors_terminals() {
    info "zed, alacritty"
    if ! command -v zed >/dev/null 2>&1; then
        if [[ "$OS" == "macos" ]]; then
            pkg_cask zed ""
        else
            curl -f https://zed.dev/install.sh | sh
        fi
    else
        ok "zed уже установлен"
    fi

    if ! command -v alacritty >/dev/null 2>&1; then
        if [[ "$OS" == "macos" ]]; then
            pkg_cask alacritty ""
        else
            pkg_native "" alacritty alacritty alacritty alacritty alacritty || pkg_cask "" org.alacritty.Alacritty
        fi
    else
        ok "alacritty уже установлен"
    fi
}

install_7zip() {
    if command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1; then
        ok "7-zip уже установлен"
        return 0
    fi
    info "Устанавливаю 7-zip..."
    if [[ "$OS" == "macos" ]]; then
        brew install sevenzip
    else
        pkg_native "" p7zip-full p7zip p7zip p7zip p7zip
    fi
    if command -v 7zz >/dev/null 2>&1 || command -v 7z >/dev/null 2>&1; then
        ok "7-zip установлен"
    else
        warn "7-zip автоматически установить не удалось"
        MANUAL_TODO+=("7-zip -> https://7-zip.org/download.html")
    fi
}

install_extra_packages() {
    info "Дополнительные утилиты"
    #                brew      apt    dnf    pacman    zypper apk
    try_install yazi     yazi     ""    yazi   yazi      ""    yazi   --cargo yazi-fm yazi-cli --hint "https://yazi-rs.github.io/docs/installation"
    try_install chafa    chafa    chafa chafa  chafa     chafa chafa
    try_install pdftoipe pdftoipe pdftoipe ""  ""        ""    ""     --hint "https://www.ctan.org/pkg/pdftoipe (сборка из исходников)"
    install_7zip
    try_install bat      bat      bat   bat    bat       bat   bat
    # На Debian/Ubuntu пакет bat ставит бинарь как batcat (конфликт имён)
    if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        ok "bat -> симлинк на batcat в ~/.local/bin"
    fi
    try_install tree     tree     tree  tree   tree      tree  tree
    try_install duf      duf      duf   duf    duf       duf   duf    --cargo duf
    try_install tldr     tldr     tldr  tldr   tealdeer  tldr  tldr   --cargo tealdeer --hint "после cargo install tealdeer выполните: tldr --update"
    try_install termusic termusic ""    ""     ""        ""    ""     --cargo termusic termusic-server --hint "https://github.com/tsblan91/termusic"
    try_install musikcube musikcube ""  ""     ""        ""    ""     --hint "https://github.com/clangen/musikcube/releases (готовые сборки/AUR musikcube-git)"
}

install_fonts() {
    info "Nerd Fonts: Hack, 0xProto, JetBrainsMono"
    if [[ "$OS" == "macos" ]]; then
        brew install --cask font-hack-nerd-font font-0xproto-nerd-font font-jetbrains-mono-nerd-font
    else
        if ! command -v getnf >/dev/null 2>&1; then
            bash -c "$(curl -sSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh)"
            export PATH="$HOME/.local/bin:$PATH"
        fi
        if command -v getnf >/dev/null 2>&1; then
            getnf -i Hack,0xProto,JetBrainsMono
        else
            warn "getnf не установился, шрифты нужно поставить вручную: https://www.nerdfonts.com/font-downloads"
            MANUAL_TODO+=("Nerd Fonts (Hack, 0xProto, JetBrainsMono) -> https://www.nerdfonts.com/font-downloads")
        fi
        fc-cache -f >/dev/null 2>&1 || true
    fi
}

install_oh_my_zsh() {
    if [[ -d "$HOME/.config/.oh-my-zsh" ]]; then
        ok "oh-my-zsh уже установлен"
        return 0
    fi
    info "Устанавливаю oh-my-zsh в ~/.config/.oh-my-zsh"
    ZSH="$HOME/.config/.oh-my-zsh" sh -c \
        "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        "" --unattended --keep-zshrc
}

install_oh_my_tmux() {
    clone_or_update https://github.com/gpakosz/.tmux.git "$HOME/.config/.oh-my-tmux"
}

install_alacritty_theme() {
    clone_or_update https://github.com/alacritty/alacritty-theme "$HOME/.config/alacritty/themes"
}
