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

## Дополнительные утилиты

Проверяются через `command -v`, ставятся нативным пакетным менеджером,
при неудаче — фоллбэк на `cargo install`, если он есть.

| Пакет | brew | apt | dnf | pacman | zypper | apk | cargo-фоллбэк |
|---|---|---|---|---|---|---|---|
| yazi | yazi | — | yazi | yazi | — | yazi | yazi-fm, yazi-cli |
| chafa | chafa | chafa | chafa | chafa | chafa | chafa | — |
| pdftoipe | pdftoipe | pdftoipe | — | — | — | — | — (нужна сборка вручную) |
| 7-zip | sevenzip (`7zz`) | p7zip-full (`7z`) | p7zip | p7zip | p7zip | p7zip | — |
| bat | bat | bat | bat | bat | bat | bat | — (на Debian/Ubuntu симлинк `batcat` → `bat`) |
| tree | tree | tree | tree | tree | tree | tree | — |
| duf | duf | duf | duf | duf | duf | duf | duf |
| tldr | tldr | tldr | tldr | tealdeer | tldr | tldr | tealdeer |
| termusic | termusic | — | — | — | — | — | termusic, termusic-server |
| musikcube | musikcube | — | — | — | — | — | — (см. GitHub releases/AUR) |

То, что не удалось поставить ни одним из способов, попадает в список
"сделать вручную", который печатается в конце работы скрипта.

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
