#!/usr/bin/env bash
# Быстро поднимает общую сетевую папку (SMB/Samba) для каталога.
#
# Использование:
#   ./samba-share.sh [опции] <путь-к-папке>
#
# Опции:
#   -n, --name ИМЯ       имя ресурса в сети (по умолчанию — имя каталога)
#   -u, --user ЮЗЕР      кому дать доступ (по умолчанию — текущий пользователь)
#   -p, --password ПАРОЛЬ пароль Samba, ставится неинтерактивно (без TTY и без
#                        этой опции создание пароля пропускается, см. MANUAL_TODO)
#   -g, --guest          разрешить гостевой доступ без пароля
#   -r, --readonly       общий доступ только на чтение
#   -h, --help           эта справка
#
# Linux: ставит пакет samba, добавляет секцию в /etc/samba/smb.conf
# (с бэкапом), создаёт учётку в базе Samba (smbpasswd) и включает/
# перезапускает smbd, открывает порт в ufw/firewalld при их наличии.
#
# macOS: создаёт share point через штатную утилиту `sharing` (то же, что
# стоит за System Settings -> General -> Sharing -> File Sharing). Сам
# тумблер "File Sharing" и первичное подтверждение пароля пользователя
# для SMB Apple не даёт включить из терминала — это остаётся ручным шагом,
# скрипт выведет точную подсказку в конце.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
}

SHARE_NAME=""
SHARE_USER="${USER:-$(id -un)}"
SHARE_PASSWORD=""
GUEST_OK="no"
READ_ONLY="no"
SHARE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)     SHARE_NAME="$2"; shift 2 ;;
        -u|--user)     SHARE_USER="$2"; shift 2 ;;
        -p|--password) SHARE_PASSWORD="$2"; shift 2 ;;
        -g|--guest)    GUEST_OK="yes"; shift ;;
        -r|--readonly) READ_ONLY="yes"; shift ;;
        -h|--help)     usage; exit 0 ;;
        -*) err "Неизвестная опция: $1"; usage; exit 1 ;;
        *) SHARE_PATH="$1"; shift ;;
    esac
done

[[ -n "$SHARE_PASSWORD" ]] && warn "-p/--password: пароль будет виден в 'ps' и, возможно, в истории шелла на этой машине"

if [[ -z "$SHARE_PATH" ]]; then
    err "Укажите путь к каталогу для общего доступа"
    usage
    exit 1
fi
SHARE_PATH="$(mkdir -p "$SHARE_PATH" && cd "$SHARE_PATH" && pwd)"
[[ -n "$SHARE_NAME" ]] || SHARE_NAME="$(basename "$SHARE_PATH")"

id "$SHARE_USER" >/dev/null 2>&1 || { err "Пользователь $SHARE_USER не найден"; exit 1; }

# На Debian/Ubuntu у обычного (не root) пользователя /usr/sbin по умолчанию
# НЕ входит в PATH (в отличие от root и от secure_path sudo) — поэтому
# `command -v smbd` из-под непривилегированного пользователя не находит уже
# установленный бинарь. Проверяем PATH и типичные sbin-каталоги напрямую.
find_sbin() {
    local name="$1" p
    command -v "$name" 2>/dev/null && return 0
    for p in "/usr/sbin/$name" "/sbin/$name" "/usr/local/sbin/$name"; do
        [[ -x "$p" ]] && { echo "$p"; return 0; }
    done
    return 1
}

# В контейнерах (Docker/LXC без --privileged) systemctl может присутствовать
# как бинарь, но реально не работать: "System has not been booted with
# systemd as init system (PID 1)". systemctl тогда либо не отвечает вообще,
# либо тихо ничего не запускает — поэтому решаем не по наличию бинаря, а по
# /run/systemd/system (создаётся только настоящим systemd-инитом), и в таких
# средах поднимаем smbd/nmbd как обычные демоны напрямую.
restart_smbd_linux() {
    local conf="$1"
    if [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1; then
        $SUDO systemctl enable --now smbd 2>/dev/null || $SUDO systemctl enable --now smb 2>/dev/null || true
        if $SUDO systemctl restart smbd 2>/dev/null || $SUDO systemctl restart smb 2>/dev/null; then
            ok "smbd перезапущен (systemctl), $conf подхвачен"
            return 0
        fi
        warn "systemctl не смог перезапустить smbd/smb, пробую поднять демон напрямую"
    else
        warn "systemd недоступен как init (типично для контейнера) — поднимаю smbd напрямую, без systemctl"
    fi

    local smbd_bin nmbd_bin
    smbd_bin="$(find_sbin smbd)" || { err "Бинарь smbd не найден"; MANUAL_TODO+=("установить и запустить smbd вручную"); return 1; }
    $SUDO pkill -HUP smbd 2>/dev/null || true
    pgrep -x smbd >/dev/null 2>&1 || $SUDO "$smbd_bin" -D || true
    if nmbd_bin="$(find_sbin nmbd)" && ! pgrep -x nmbd >/dev/null 2>&1; then
        $SUDO "$nmbd_bin" -D || true
    fi

    if pgrep -x smbd >/dev/null 2>&1; then
        ok "smbd запущен напрямую (демон), $conf подхвачен"
    else
        err "Не удалось запустить smbd"
        MANUAL_TODO+=("запустить smbd вручную: sudo smbd -D (проверьте sudo journalctl / sudo smbd -i для диагностики)")
    fi
}

linux_setup() {
    info "Устанавливаю Samba..."
    # apt/zypper без предварительного обновления индекса не найдут пакет
    # даже если он есть в репозитории (типичная причина "Unable to locate
    # package" на свежих системах/контейнерах, где apt-get update ещё не
    # выполнялся).
    case "$PKG_MANAGER" in
        apt)    $SUDO apt-get update -y ;;
        zypper) $SUDO zypper --non-interactive refresh ;;
    esac
    pkg_native "" samba samba samba samba samba || { err "Не удалось установить пакет samba"; return 1; }

    local conf="/etc/samba/smb.conf"
    [[ -f "$conf" ]] || { err "Не найден $conf после установки samba"; return 1; }

    $SUDO chown "$SHARE_USER":"$(id -gn "$SHARE_USER")" "$SHARE_PATH"
    $SUDO chmod 2775 "$SHARE_PATH"

    if grep -qx "\[$SHARE_NAME\]" "$conf" 2>/dev/null; then
        warn "Секция [$SHARE_NAME] уже есть в $conf, пропускаю добавление"
    else
        local bak="${conf}.bak-$(date +%Y%m%d%H%M%S)"
        $SUDO cp "$conf" "$bak"
        info "Бэкап $conf -> $bak"
        {
            echo
            echo "[$SHARE_NAME]"
            echo "    path = $SHARE_PATH"
            echo "    browseable = yes"
            echo "    read only = $( [[ "$READ_ONLY" == "yes" ]] && echo yes || echo no )"
            echo "    guest ok = $( [[ "$GUEST_OK" == "yes" ]] && echo yes || echo no )"
            if [[ "$GUEST_OK" != "yes" ]]; then
                echo "    valid users = $SHARE_USER"
            fi
            echo "    force group = $(id -gn "$SHARE_USER")"
            echo "    create mask = 0664"
            echo "    directory mask = 2775"
        } | $SUDO tee -a "$conf" >/dev/null
        ok "Секция [$SHARE_NAME] добавлена в $conf"
    fi

    $SUDO testparm -s >/dev/null 2>&1 || warn "testparm сообщил о проблемах в конфиге — проверьте: sudo testparm"

    if [[ "$GUEST_OK" != "yes" ]]; then
        if ! $SUDO pdbedit -L 2>/dev/null | cut -d: -f1 | grep -qx "$SHARE_USER"; then
            if [[ -n "$SHARE_PASSWORD" ]]; then
                info "Задаю пароль Samba для $SHARE_USER неинтерактивно (-p/--password)"
                printf '%s\n%s\n' "$SHARE_PASSWORD" "$SHARE_PASSWORD" | $SUDO smbpasswd -s -a "$SHARE_USER"
            elif [[ -t 0 ]]; then
                info "Задайте пароль Samba для $SHARE_USER (независимый от системного логина):"
                $SUDO smbpasswd -a "$SHARE_USER"
            else
                warn "Нет TTY и не передан -p/--password — пропускаю создание пароля Samba для $SHARE_USER"
                MANUAL_TODO+=("задать пароль Samba: sudo smbpasswd -a $SHARE_USER")
            fi
        fi
        $SUDO smbpasswd -e "$SHARE_USER" >/dev/null 2>&1 || true
    fi

    restart_smbd_linux "$conf"

    if command -v ufw >/dev/null 2>&1; then
        if $SUDO ufw allow samba >/dev/null 2>&1; then
            ok "ufw: разрешён профиль Samba"
        else
            warn "ufw allow samba не сработал (профиль Samba недоступен или ufw неактивен)"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if $SUDO firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 && $SUDO firewall-cmd --reload >/dev/null 2>&1; then
            ok "firewalld: разрешён сервис samba"
        else
            warn "firewall-cmd не сработал (firewalld не запущен?)"
        fi
    fi

    local host_ip
    host_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    ok "Готово: smb://${host_ip:-$(hostname)}/$SHARE_NAME"
}

macos_setup() {
    $SUDO chown "$SHARE_USER" "$SHARE_PATH"
    chmod 775 "$SHARE_PATH"

    if [[ "$GUEST_OK" != "yes" ]]; then
        info "Добавляю $SHARE_USER в группу доступа по SMB (com.apple.access_smb)"
        $SUDO dseditgroup -o edit -a "$SHARE_USER" -t user com.apple.access_smb 2>/dev/null || true
    fi

    command -v sharing >/dev/null 2>&1 || { err "Утилита sharing не найдена, включите общий доступ вручную"; return 1; }

    if sharing -l 2>/dev/null | grep -qF "$SHARE_PATH"; then
        warn "Share point для $SHARE_PATH уже существует (sharing -l), пропускаю добавление"
    else
        local guest_flag; guest_flag=$( [[ "$GUEST_OK" == "yes" ]] && echo 001 || echo 000 )
        $SUDO sharing -a "$SHARE_PATH" -n "$SHARE_NAME" -S "$SHARE_NAME" -s 001 -g "$guest_flag"
        if [[ "$READ_ONLY" == "yes" ]]; then
            $SUDO sharing -e "$SHARE_NAME" -R 1
        fi
        ok "Share point '$SHARE_NAME' создан ($SHARE_PATH)"
    fi

    warn "На macOS остался ручной шаг (Apple не даёт включить это из терминала):"
    warn "  System Settings -> General -> Sharing -> File Sharing:"
    warn "  включите тумблер, убедитесь, что для '$SHARE_NAME' стоит SMB,"
    warn "  и отметьте $SHARE_USER в списке пользователей (потребуется ввести его пароль)."
    MANUAL_TODO+=("System Settings -> Sharing -> File Sharing: включить и добавить $SHARE_USER для '$SHARE_NAME'")

    local host
    host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"
    ok "После включения тумблера: smb://$host.local/$SHARE_NAME"
}

detect_os
case "$OS" in
    linux) linux_setup ;;
    macos) macos_setup ;;
esac

if [[ ${#MANUAL_TODO[@]} -gt 0 ]]; then
    echo
    warn "Осталось сделать вручную:"
    printf '    - %s\n' "${MANUAL_TODO[@]}"
fi
