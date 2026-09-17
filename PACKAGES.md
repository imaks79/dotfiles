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
| musikcube | musikcube | — | — | — | — | — |

На Linux нативного пакета для musikcube чаще всего нет — если `pkg_native`
не находит его, ставится пометка "сделать вручную" со ссылкой на
[GitHub releases/AUR](https://github.com/clangen/musikcube/releases).

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

## Явно исключено

- **Zed** — убран из установки по запросу.
- **Доп. утилиты** (yazi, chafa, pdftoipe, 7-zip, bat, tree, duf, tldr, termusic) — установка полностью убрана по запросу.

Всё, что не удалось поставить автоматически (например, musikcube без
подходящего пакета в репозитории дистрибутива), попадает в список
"сделать вручную", который печатается в конце работы скрипта.
