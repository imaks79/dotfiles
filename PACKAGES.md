# Что устанавливает setup.sh

Список того, что ставится (или проверяется на наличие) командой `./setup.sh`,
и как именно — по каждому пакетному менеджеру.

## Прослойка пакетного менеджера

| ОС | Что ставится |
|---|---|
| macOS | Homebrew (если ещё не установлен) |
| Linux | flatpak + репозиторий flathub |

## Базовые пакеты

| Пакет | brew | apt | dnf | pacman | zypper | apk |
|---|---|---|---|---|---|---|
| git | git | git | git | git | git | git |
| ssh | (системный) | openssh-client | openssh-clients | openssh | openssh | openssh-client |
| mc | mc | mc | mc | mc | mc | mc |
| htop | htop | htop | htop | htop | htop | htop |
| nvim | neovim | neovim | neovim | neovim | neovim | neovim |
| tmux | tmux | tmux | tmux | tmux | tmux | tmux |
| zsh | zsh | zsh | zsh | zsh | zsh | zsh |
| pass | pass | pass | pass | pass | pass | pass |
| gpg | gnupg | gnupg | gnupg2 | gnupg | gpg2 | gnupg |
| eza | eza | eza | eza | eza | eza | eza |

После установки zsh скрипт также делает его оболочкой по умолчанию
(`chsh`, функция `set_default_shell_zsh()`) — путь к бинарю при необходимости
дописывается в `/etc/shells`. Если `chsh` не проходит автоматически (нет прав,
недоступен интерактивно), команда попадает в список "сделать вручную".

## Терминал

| Пакет | macOS | Linux |
|---|---|---|
| alacritty | brew cask | нативный пакет, иначе flatpak `org.alacritty.Alacritty` |

## Языки и инструменты разработки

| Пакет | Способ установки |
|---|---|
| rust | `rustup` (официальный установщик, обе ОС); перед сборкой на Linux ставится тулчейн — компилятор, `pkg-config`, заголовки openssl |
| uv | brew (macOS) / официальный скрипт `astral.sh/uv/install.sh` (Linux) |
| docker | brew cask "Docker" — Docker Desktop (macOS) / `get.docker.com` — Docker Engine + добавление пользователя в группу `docker` (Linux) |

## Шрифты (Nerd Fonts)

- Hack
- 0xProto
- JetBrainsMono

macOS — brew cask; Linux — через [`getnf`](https://github.com/getnf/getnf).

## Клонируемые git-репозитории

| Что | Куда |
|---|---|
| oh-my-zsh | `~/.config/.oh-my-zsh` |
| zsh-autosuggestions | `~/.config/.oh-my-zsh/custom/plugins/zsh-autosuggestions` |
| zsh-syntax-highlighting | `~/.config/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting` |
| oh-my-tmux | `~/.config/.oh-my-tmux` |
| AstroNvim (ядро) | `~/.local/share/nvim/lazy/AstroNvim` |
| alacritty-theme | `~/.config/alacritty/themes` |

## Новые пользователи системы

`setup.sh` также настраивает автоматическую раздачу этих же конфигов
пользователям, которых создадут после этого на этой машине:

1. `sync_shared_dotfiles()` (`lib/skel.sh`) публикует `config/` в
   `/usr/local/share/dotfiles` — общедоступную для чтения копию. `setup.sh` и
   `update.sh` обновляют её каждый раз сами.
2. **Linux**: `install_skel_linux()` раскладывает в `/etc/skel` символические
   ссылки на файлы из этой общей копии. Всё, что создаётся дальше через
   `useradd -m`, получает те же конфиги.
3. **macOS**: `/System/Library/User Template` на современных версиях
   недоступен для записи даже под root (System Integrity Protection +
   запечатанный системный том) — `install_skel_macos()` честно проверяет это
   и, если не вышло, добавляет напоминание запускать `new-user.sh` вручную.
4. oh-my-zsh, oh-my-tmux, ядро AstroNvim и тема alacritty — git-клоны в
   `$HOME`, которых у только что созданного пользователя ещё нет. За это
   отвечает `lib/first-login.sh`: хук в самом верху `config/zsh/.zshrc`
   запускает его при первом входе (один раз, помечает себя маркером в
   `~/.cache/.dotfiles-bootstrapped`), он доклонирует зависимости и
   перекладывает симлинки, которые skel не мог создать заранее (например
   `tmux.conf`, ссылающийся на ещё не склонированный `oh-my-tmux`).
5. `./new-user.sh <имя>` — то же самое для уже существующего пользователя
   (создан до настройки `/etc/skel`, либо это macOS, где шаг 3 не сработал).
   Запускается от root: `sudo ./new-user.sh <имя>`.

## Явно исключено

- **Zed** — убран из установки по запросу.
- **musikcube** — убран из установки по запросу.
- **Доп. утилиты** (yazi, chafa, pdftoipe, 7-zip, bat, tree, duf, tldr, termusic) — установка полностью убрана по запросу.

Всё, что не удалось поставить автоматически, попадает в список
"сделать вручную", который печатается в конце работы скрипта.

## Как добавить или убрать свой пакет

Вся установка живёт в `lib/packages.sh`, вызовы функций — в `setup.sh` внутри
`cmd_install()`. Раскладка/сбор конфигов — отдельно, в `lib/deploy.sh`.

**Обычный пакет через системный менеджер** — правь `install_core_packages()`
или `install_terminal()` в `lib/packages.sh`. Формат вызова:

```bash
pkg_native <brew> <apt> <dnf> <pacman> <zypper> <apk>
```

Пустая строка `""` в любой позиции = "в этом менеджере пакета нет, пропустить".
Чтобы добавить пакет — допиши строку с его именами для каждого менеджера.
Чтобы убрать — удали строку (или закомментируй `#`).

**Пакет со своим способом установки** (официальный curl-скрипт, cask,
flatpak и т.п.) — по образцу `install_rust()`, `install_uv()`,
`install_docker()` в `lib/packages.sh`: своя функция с проверкой
`command -v <бинарь>` в начале (чтобы не ставить повторно), и вызов этой
функции из `cmd_install()` в `setup.sh`.

**Клонируемый git-репозиторий** (плагин, тема, чей-то дотфайл-репозиторий) —
по образцу `install_oh_my_tmux()` / `install_astronvim_core()` /
`install_alacritty_theme()`: одна строка с `clone_or_update <url> <путь>`
(она сама решает clone или pull). Не забудь добавить вызов в `cmd_install()`.

**Шрифт** — допиши имя в `install_fonts()`: для brew — в список
`brew install --cask font-...`, для Linux — в список имён у `getnf -i`.

**Отслеживаемый конфиг-файл** (симлинк из `config/` в систему) — три места
в `lib/deploy.sh`:
- `deploy_configs()` — добавить `link_file "$CONFIG_DIR/..." "$HOME/..."`
- `seed_configs_from_system()` — добавить `sync_from_live "$HOME/..." "$CONFIG_DIR/..."`,
  чтобы `setup.sh seed` и `update.sh` подхватывали изменения этого файла
- сам файл положить в `config/<приложение>/...`

После любых правок: `bash -n setup.sh lib/*.sh` — быстрая проверка синтаксиса
без реального запуска.
