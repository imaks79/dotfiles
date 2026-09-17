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
    pkg_native pass   pass       pass   pass   pass   pass
    pkg_native gnupg  gnupg      gnupg2 gnupg  gpg2   gnupg
}

install_terminal() {
    info "alacritty"
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

install_musikcube() {
    if command -v musikcube >/dev/null 2>&1; then
        ok "musikcube уже установлен"
        return 0
    fi
    info "Устанавливаю musikcube..."
    pkg_native musikcube "" "" "" "" ""
    if command -v musikcube >/dev/null 2>&1; then
        ok "musikcube установлен"
    else
        warn "musikcube автоматически установить не удалось"
        MANUAL_TODO+=("musikcube -> https://github.com/clangen/musikcube/releases (готовые сборки/AUR musikcube-git)")
    fi
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

install_oh_my_zsh_plugins() {
    local custom="${ZSH_CUSTOM:-$HOME/.config/.oh-my-zsh/custom}"
    clone_or_update https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"
    clone_or_update https://github.com/zsh-users/zsh-autosuggestions.git     "$custom/plugins/zsh-autosuggestions"
}

install_oh_my_tmux() {
    clone_or_update https://github.com/gpakosz/.tmux.git "$HOME/.config/.oh-my-tmux"
}

install_alacritty_theme() {
    clone_or_update https://github.com/alacritty/alacritty-theme "$HOME/.config/alacritty/themes"
}

# Ядро AstroNvim заранее кладём в кэш lazy.nvim, чтобы nvim не тянул его
# из интернета при первом запуске (пользовательский конфиг лежит в config/nvim).
install_astronvim_core() {
    clone_or_update https://github.com/AstroNvim/AstroNvim "$HOME/.local/share/nvim/lazy/AstroNvim"
}

# cargo/rustup не может собирать пакеты без компилятора и линковщика (cc) —
# на минимальных установках (Parrot OS, серверные образы и т.п.) их обычно нет.
BUILD_TOOLCHAIN_READY=0
ensure_build_toolchain() {
    [[ "$BUILD_TOOLCHAIN_READY" == "1" ]] && return 0
    [[ "$OS" == "macos" ]] && { BUILD_TOOLCHAIN_READY=1; return 0; }
    command -v cc >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1 && { BUILD_TOOLCHAIN_READY=1; return 0; }

    info "Ставлю инструменты сборки (компилятор, pkg-config, заголовки openssl)..."
    case "$PKG_MANAGER" in
        apt)    sudo apt-get install -y build-essential pkg-config libssl-dev ;;
        dnf)    sudo dnf groupinstall -y "Development Tools"; sudo dnf install -y pkg-config openssl-devel ;;
        pacman) sudo pacman -S --noconfirm --needed base-devel openssl ;;
        zypper) sudo zypper --non-interactive install -t pattern devel_basis; sudo zypper --non-interactive install pkg-config libopenssl-devel ;;
        apk)    sudo apk add build-base pkgconfig openssl-dev ;;
    esac
    BUILD_TOOLCHAIN_READY=1
}

install_rust() {
    if command -v rustc >/dev/null 2>&1; then
        ok "rust уже установлен"
        return 0
    fi
    info "Устанавливаю rust (rustup)..."
    ensure_build_toolchain
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile default
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    command -v rustc >/dev/null 2>&1 && ok "rust установлен" || MANUAL_TODO+=("rust -> https://rustup.rs")
}

install_uv() {
    if command -v uv >/dev/null 2>&1; then
        ok "uv уже установлен"
        return 0
    fi
    info "Устанавливаю uv..."
    if [[ "$OS" == "macos" ]]; then
        brew install uv
    else
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    command -v uv >/dev/null 2>&1 && ok "uv установлен" || MANUAL_TODO+=("uv -> https://docs.astral.sh/uv/getting-started/installation/")
}

install_docker() {
    if command -v docker >/dev/null 2>&1; then
        ok "docker уже установлен"
        return 0
    fi
    info "Устанавливаю docker..."
    if [[ "$OS" == "macos" ]]; then
        pkg_cask docker ""
        MANUAL_TODO+=("Docker Desktop поставлен как приложение — запустите его вручную один раз из /Applications")
    else
        curl -fsSL https://get.docker.com | sudo sh
        if command -v docker >/dev/null 2>&1; then
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            MANUAL_TODO+=("docker: перелогиньтесь (или выполните 'newgrp docker'), чтобы работать без sudo")
        fi
    fi
    command -v docker >/dev/null 2>&1 || MANUAL_TODO+=("docker -> https://docs.docker.com/engine/install/")
}
