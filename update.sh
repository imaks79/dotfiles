#!/usr/bin/env bash
# Бэкап + синхронизация конфигов dotfiles с этой машиной (без установки пакетов).
#
# Что делает:
#   1. Делает архив текущих конфигов + ~/.ssh в ~/dotfiles-backup-<host>-<дата>.tar.gz
#   2. Подтягивает актуальное содержимое отслеживаемых файлов из системы в config/
#      (на случай, если приложение перезаписало файл поверх симлинка обычным файлом)
#   3. Чинит симлинки (deploy_configs), если что-то из п.2 их разорвало
#   4. Если есть изменения — коммитит их в dotfiles
#
# Использование:
#   ./update.sh          — бэкап + обновление + локальный коммит
#   ./update.sh --push   — то же самое, и сразу пушит в origin
#   ./update.sh --no-backup   — пропустить архив (быстрее, но без сети безопасности)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/deploy.sh"

DO_PUSH=0
DO_BACKUP=1
for a in "$@"; do
    case "$a" in
        --push) DO_PUSH=1 ;;
        --no-backup) DO_BACKUP=0 ;;
        *) err "Неизвестный флаг: $a (доступно: --push, --no-backup)"; exit 1 ;;
    esac
done

if [[ "$DO_BACKUP" == "1" ]]; then
    info "Делаю резервный архив перед обновлением"
    backup_to_archive
else
    info "Пропускаю резервный архив (--no-backup)"
fi

seed_configs_from_system
deploy_configs

cd "$DOTFILES_DIR"
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git status --porcelain)" ]]; then
    ok "config/ уже соответствует текущей системе, обновлять нечего"
    exit 0
fi

echo
info "Изменения в dotfiles:"
git status --short

git add -A
git commit -q -m "Sync configs from $(hostname -s 2>/dev/null || echo host) on $(date +%Y-%m-%d)"
ok "Изменения закоммичены локально"

if [[ "$DO_PUSH" == "1" ]]; then
    git push
    ok "Запушено в origin"
else
    info "Пуш пропущен, запусти вручную: git -C $DOTFILES_DIR push  (или ./update.sh --push)"
fi
