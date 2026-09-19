#!/usr/bin/env bash
# Установка "дополнительных" TUI/CLI-инструментов (tools-extra.sh) — список
# специально сделан таблицей одной функции (install_tool) + case в tool_desc,
# чтобы дописать новый инструмент было одной строкой в каждой из них, без
# ассоциативных массивов (их нет в bash 3.2 — системном /bin/bash на macOS).

# pkg_or_cargo <cli-бинарь> <cargo-крейт> <brew> <apt> <dnf> <pacman> <zypper> <apk>
# Сначала пробует нативный пакетный менеджер (pkg_native), при неудаче —
# `cargo install <крейт>` (rust уже стоит после setup.sh, см. install_rust()).
# Пустой crate = фолбэка нет, промах пакетного менеджера идёт в MANUAL_TODO.
pkg_or_cargo() {
    local bin="$1" crate="$2" brew_name="$3" apt_name="$4" dnf_name="$5" pacman_name="$6" zypper_name="$7" apk_name="$8"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    if pkg_native "$brew_name" "$apt_name" "$dnf_name" "$pacman_name" "$zypper_name" "$apk_name"; then
        ok "$bin: пакет поставлен через пакетный менеджер"
        return 0
    fi
    if [[ -z "$crate" ]]; then
        warn "$bin недоступен через пакетный менеджер на этой системе"
        MANUAL_TODO+=("$bin -> нет пакета в этом пакетном менеджере, ставьте вручную")
        return 1
    fi
    if ! command -v cargo >/dev/null 2>&1; then
        warn "$bin недоступен через пакетный менеджер, а cargo не найден"
        MANUAL_TODO+=("$bin -> нет пакета в этом пакетном менеджере; поставьте rust (cargo install $crate)")
        return 1
    fi
    info "$bin недоступен через пакетный менеджер, ставлю: cargo install $crate"
    ensure_build_toolchain
    # shellcheck disable=SC2086 # $crate иногда содержит несколько имён крейтов (yazi-fm yazi-cli)
    if cargo install $crate; then
        ok "$bin установлен через cargo"
    else
        warn "cargo install $crate не удался"
        MANUAL_TODO+=("$bin -> cargo install $crate")
        return 1
    fi
}

# install_gh_release_bin <owner/repo> <бинарь> <имя-архива-без-расширения> <ext>
# Общий загрузчик для проектов на Go/C без покрытия во всех пакетных
# менеджерах: качает .tar.gz (или .deb) с GitHub Releases, по возможности
# проверяет sha256 по файлу контрольных сумм на той же странице релиза.
# checksums_name пустой = проверка пропускается (не у всех проектов есть файл).
install_gh_release_tar() {
    local repo="$1" bin="$2" asset="$3" checksums_name="$4" bin_path_in_tar="${5:-}"
    [[ -n "$bin_path_in_tar" ]] || bin_path_in_tar="$bin"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    info "$bin недоступен через пакетный менеджер, ставлю бинарь с GitHub Releases ($repo)"
    local tag
    tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        warn "$bin: не удалось узнать версию последнего релиза"
        MANUAL_TODO+=("$bin -> https://github.com/$repo/releases")
        return 1
    fi
    local base_url="https://github.com/$repo/releases/download/$tag"
    local tmp; tmp="$(mktemp -d)"

    if ! curl -fsSL -o "$tmp/$asset" "$base_url/$asset"; then
        warn "$bin: не удалось скачать $asset (версия $tag)"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $base_url"); return 1
    fi
    if [[ -n "$checksums_name" ]]; then
        if curl -fsSL -o "$tmp/$checksums_name" "$base_url/$checksums_name" 2>/dev/null; then
            if ! (cd "$tmp" && awk -v f="$asset" '$2 == f' "$checksums_name" | sha256sum -c - >/dev/null 2>&1); then
                warn "$bin: контрольная сумма не совпала, НЕ устанавливаю"
                rm -rf "$tmp"; MANUAL_TODO+=("$bin: проверьте вручную -> $base_url"); return 1
            fi
        else
            warn "$bin: файл контрольных сумм не скачался, ставлю без проверки"
        fi
    fi

    tar -xzf "$tmp/$asset" -C "$tmp" "$bin_path_in_tar" 2>/dev/null || tar -xzf "$tmp/$asset" -C "$tmp"
    $SUDO install -m0755 "$tmp/$bin_path_in_tar" "/usr/local/bin/$bin"
    rm -rf "$tmp"

    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin установлен ($tag)"
    else
        MANUAL_TODO+=("$bin -> $base_url")
        return 1
    fi
}

# install_gh_release_deb <owner/repo> <бинарь> <имя-.deb>
# Для проектов, публикующих .deb прямо в релизе — ставим через dpkg, чтобы
# попасть в базу пакетов apt, а не просто разложить файл в /usr/local/bin.
install_gh_release_deb() {
    local repo="$1" bin="$2" asset="$3"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin уже установлен"
        return 0
    fi
    info "$bin недоступен через apt, ставлю .deb с GitHub Releases ($repo)"
    local tag
    tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
    if [[ -z "$tag" ]]; then
        warn "$bin: не удалось узнать версию последнего релиза"
        MANUAL_TODO+=("$bin -> https://github.com/$repo/releases")
        return 1
    fi
    local url="https://github.com/$repo/releases/download/$tag/$asset"
    local tmp; tmp="$(mktemp -d)"
    if ! curl -fsSL -o "$tmp/$asset" "$url"; then
        warn "$bin: не удалось скачать $asset"
        rm -rf "$tmp"; MANUAL_TODO+=("$bin -> $url"); return 1
    fi
    $SUDO dpkg -i "$tmp/$asset" >/dev/null 2>&1 || $SUDO apt-get install -y -qq "$tmp/$asset" >/dev/null 2>&1
    rm -rf "$tmp"
    if command -v "$bin" >/dev/null 2>&1; then
        ok "$bin установлен ($tag)"
    else
        MANUAL_TODO+=("$bin -> $url")
        return 1
    fi
}

install_lazygit() {
    command -v lazygit >/dev/null 2>&1 && { ok "lazygit уже установлен"; return 0; }
    if pkg_native lazygit "" "" lazygit lazygit lazygit && command -v lazygit >/dev/null 2>&1; then
        ok "lazygit установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("lazygit -> https://github.com/jesseduffield/lazygit#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=x86_64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("lazygit -> https://github.com/jesseduffield/lazygit/releases"); return 1 ;;
    esac
    local tag; tag="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1)"
    [[ -n "$tag" ]] || { MANUAL_TODO+=("lazygit -> https://github.com/jesseduffield/lazygit/releases"); return 1; }
    install_gh_release_tar "jesseduffield/lazygit" "lazygit" "lazygit_${tag}_linux_${arch}.tar.gz" "checksums.txt"
}

install_lazydocker() {
    command -v lazydocker >/dev/null 2>&1 && { ok "lazydocker уже установлен"; return 0; }
    if pkg_native lazydocker "" "" lazydocker "" lazydocker && command -v lazydocker >/dev/null 2>&1; then
        ok "lazydocker установлен"; return 0
    fi
    [[ "$OS" == "linux" ]] || { MANUAL_TODO+=("lazydocker -> https://github.com/jesseduffield/lazydocker#installation"); return 1; }
    info "lazydocker недоступен через пакетный менеджер, ставлю официальным install-скриптом"
    if DIR=/usr/local/bin $SUDO bash -c "$(curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh)"; then
        command -v lazydocker >/dev/null 2>&1 && ok "lazydocker установлен" || MANUAL_TODO+=("lazydocker -> https://github.com/jesseduffield/lazydocker#installation")
    else
        MANUAL_TODO+=("lazydocker -> https://github.com/jesseduffield/lazydocker#installation")
        return 1
    fi
}

install_k9s() {
    command -v k9s >/dev/null 2>&1 && { ok "k9s уже установлен"; return 0; }
    if pkg_native k9s "" k9s k9s k9s k9s && command -v k9s >/dev/null 2>&1; then
        ok "k9s установлен"; return 0
    fi
    [[ "$OS" == "linux" && "$PKG_MANAGER" == "apt" ]] || { MANUAL_TODO+=("k9s -> https://github.com/derailed/k9s#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) MANUAL_TODO+=("k9s -> https://github.com/derailed/k9s/releases"); return 1 ;;
    esac
    install_gh_release_deb "derailed/k9s" "k9s" "k9s_linux_${arch}.deb"
}

install_7zip() {
    if command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; then
        ok "7-zip уже установлен"
        return 0
    fi
    pkg_native sevenzip p7zip-full 7zip 7zip 7zip p7zip
    if command -v 7z >/dev/null 2>&1 || command -v 7zz >/dev/null 2>&1; then
        ok "7-zip установлен"
    else
        warn "7-zip не установился через пакетный менеджер"
        MANUAL_TODO+=("7zip -> https://7-zip.org (или p7zip для вашего дистрибутива)")
        return 1
    fi
}

install_fastfetch() {
    command -v fastfetch >/dev/null 2>&1 && { ok "fastfetch уже установлен"; return 0; }
    if pkg_native fastfetch "" fastfetch fastfetch fastfetch fastfetch && command -v fastfetch >/dev/null 2>&1; then
        ok "fastfetch установлен"; return 0
    fi
    [[ "$OS" == "linux" && "$PKG_MANAGER" == "apt" ]] || { MANUAL_TODO+=("fastfetch -> https://github.com/fastfetch-cli/fastfetch#installation"); return 1; }
    local arch; case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=aarch64 ;;
        *) MANUAL_TODO+=("fastfetch -> https://github.com/fastfetch-cli/fastfetch/releases"); return 1 ;;
    esac
    install_gh_release_deb "fastfetch-cli/fastfetch" "fastfetch" "fastfetch-linux-${arch}.deb"
}

TOOLS_EXTRA_NAMES=(tldr duf gpg-tui termusic vortix wlctl lazygit lazydocker k9s termscp lnav dust yazi fastfetch bottom gping trippy bandwhich bat chafa pdftoipe 7zip slumber)

tool_desc() {
    case "$1" in
        tldr)     echo "Короткие практические примеры для команд вместо полного man" ;;
        duf)      echo "Диски и точки монтирования — наглядная замена df" ;;
        gpg-tui)  echo "Управление ключами GnuPG" ;;
        termusic) echo "Терминальный музыкальный плеер" ;;
        vortix)   echo "TUI для WireGuard/OpenVPN: телеметрия, kill switch, утечки DNS/IPv6" ;;
        wlctl)    echo "TUI для wifi/ethernet/vpn через NetworkManager (только Linux)" ;;
        lazygit)  echo "TUI для git" ;;
        lazydocker) echo "TUI для docker и docker-compose" ;;
        k9s)      echo "TUI для Kubernetes-кластера" ;;
        termscp)  echo "Терминальный SCP/SFTP/FTP/S3-клиент" ;;
        lnav)     echo "Просмотр и анализ логов с подсветкой и SQL-запросами" ;;
        dust)     echo "Наглядная замена du — что занимает место на диске" ;;
        yazi)     echo "Быстрый терминальный файловый менеджер" ;;
        fastfetch) echo "Информация о системе при старте терминала (замена neofetch)" ;;
        bottom)   echo "Монитор процессов/ресурсов (замена top/htop), бинарь btm" ;;
        gping)    echo "ping с графиком задержки в реальном времени" ;;
        trippy)   echo "traceroute + ping в одном TUI, бинарь trip" ;;
        bandwhich) echo "Кто из процессов сколько сетевого трафика потребляет" ;;
        bat)      echo "cat с подсветкой синтаксиса и git-диффом (на Debian/Ubuntu бинарь batcat)" ;;
        chafa)    echo "Показ картинок прямо в терминале" ;;
        pdftoipe) echo "Конвертация PDF в XML для редактора Ipe" ;;
        7zip)     echo "Архиватор 7-Zip" ;;
        slumber)  echo "Терминальный REST/gRPC-клиент (замена Postman/Insomnia в TUI)" ;;
        *) return 1 ;;
    esac
}

# install_tool <имя> — диспетчер: часть инструментов ставится дженериком
# pkg_or_cargo, часть (lazygit/lazydocker/k9s/fastfetch) — через свою функцию
# из-за пробелов в apt/dnf у соответствующих проектов на конец 2026.
install_tool() {
    local name="$1"
    case "$name" in
        tldr)      pkg_or_cargo tldr     tealdeer  tldr   tldr tldr tldr tealdeer "" ;;
        duf)       pkg_or_cargo duf      ""        duf    duf  duf  duf  duf      "" ;;
        gpg-tui)   pkg_or_cargo gpg-tui  gpg-tui   gpg-tui "" "" gpg-tui gpg-tui gpg-tui ;;
        termusic)  pkg_or_cargo termusic termusic  termusic "" "" termusic "" "" ;;
        vortix)    pkg_or_cargo vortix vortix vortix "" "" vortix "" "" ;;
        wlctl)
            if [[ "$OS" == "linux" ]]; then
                pkg_or_cargo wlctl wlctl "" "" "" "" "" ""
            else
                info "wlctl использует NetworkManager, есть только на Linux — пропускаю на macOS"
            fi ;;
        lazygit)   install_lazygit ;;
        lazydocker) install_lazydocker ;;
        k9s)       install_k9s ;;
        termscp)   pkg_or_cargo termscp termscp termscp "" "" termscp termscp "" ;;
        lnav)      pkg_or_cargo lnav     ""      lnav   lnav lnav lnav lnav lnav ;;
        dust)      pkg_or_cargo dust     du-dust dust   ""   du-dust dust dust dust ;;
        yazi)      pkg_or_cargo yazi     "yazi-fm yazi-cli" yazi "" "" yazi yazi yazi ;;
        fastfetch) install_fastfetch ;;
        bottom)    pkg_or_cargo btm      bottom  bottom ""   ""   bottom bottom bottom ;;
        gping)     pkg_or_cargo gping    gping   gping  gping ""  gping gping gping ;;
        trippy)    pkg_or_cargo trip     trippy  trippy ""   ""   trippy trippy "" ;;
        bandwhich) pkg_or_cargo bandwhich bandwhich bandwhich "" "" bandwhich "" bandwhich ;;
        bat)       pkg_or_cargo bat      ""      bat    bat  bat  bat  bat  bat ;;
        chafa)     pkg_or_cargo chafa    ""      chafa  chafa chafa chafa chafa chafa ;;
        pdftoipe)  pkg_or_cargo pdftoipe ""      pdftoipe pdftoipe "" "" "" "" ;;
        7zip)      install_7zip ;;
        slumber)   pkg_or_cargo slumber  slumber slumber "" "" slumber "" "" ;;
        *) err "Неизвестный инструмент: $name"; return 1 ;;
    esac
}
