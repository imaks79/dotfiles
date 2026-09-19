# Что ставит tools-extra.sh

Дополнительные TUI/CLI-инструменты, не входящие в базовый набор `setup.sh`.
Ставятся отдельно, потому что не всем нужны — `./tools-extra.sh --list`
показывает этот же список в терминале, `./tools-extra.sh <имя> ...` ставит
только выбранные.

Для каждого инструмента скрипт сначала пробует нативный пакетный менеджер
(brew/apt/dnf/pacman/zypper/apk), и только если пакета там нет — переходит к
фолбэку (`cargo install`, официальный install-скрипт или бинарь с GitHub
Releases). `cargo` должен быть уже установлен — его ставит основной
`setup.sh` (`install_rust()`), поэтому `tools-extra.sh` имеет смысл запускать
после него.

| Инструмент | Что делает | Fallback, если нет в пакетном менеджере |
|---|---|---|
| **tldr** | Короткие практические примеры для команд вместо полного `man` | `cargo install tealdeer` (на zypper пакет уже называется `tealdeer`) |
| **duf** | Диски и точки монтирования — наглядная замена `df` | нет (Go-проект, не публикуется на crates.io); на apk ставьте вручную |
| **gpg-tui** | Управление ключами GnuPG в TUI | `cargo install gpg-tui` |
| **termusic** | Терминальный музыкальный плеер | `cargo install termusic` |
| **vortix** | TUI для WireGuard/OpenVPN: живая телеметрия, kill switch, детект утечек DNS/IPv6 | `cargo install vortix` |
| **wlctl** | TUI для wifi/ethernet/vpn через NetworkManager | `cargo install wlctl`; **только Linux** — на macOS нет NetworkManager, скрипт пропускает |
| **lazygit** | TUI для git | бинарь с GitHub Releases (tar.gz + проверка sha256 по `checksums.txt`) |
| **lazydocker** | TUI для docker/docker-compose | официальный `install_update_linux.sh` с GitHub |
| **k9s** | TUI для Kubernetes-кластера | `.deb` с GitHub Releases (только там, где есть apt) |
| **termscp** | Терминальный SCP/SFTP/FTP/S3-клиент | `cargo install termscp` |
| **lnav** | Просмотр и анализ логов: подсветка, SQL-запросы к логам | — (есть везде) |
| **dust** | Наглядная замена `du` — что занимает место на диске | `cargo install du-dust` (бинарь всё равно называется `dust`) |
| **yazi** | Быстрый терминальный файловый менеджер | `cargo install yazi-fm yazi-cli` |
| **fastfetch** | Информация о системе при старте терминала (замена neofetch) | `.deb` с GitHub Releases (только там, где есть apt) |
| **bottom** | Монитор процессов и ресурсов (замена top/htop), бинарь `btm` | `cargo install bottom` |
| **gping** | `ping` с графиком задержки в реальном времени | `cargo install gping` |
| **trippy** | `traceroute` + `ping` в одном TUI, бинарь `trip` | `cargo install trippy` |
| **bandwhich** | Какой процесс сколько сетевого трафика потребляет | `cargo install bandwhich` |
| **bat** | `cat` с подсветкой синтаксиса и git-диффом | — (есть везде; на Debian/Ubuntu бинарь называется `batcat`, не `bat`) |
| **chafa** | Показ картинок прямо в терминале | — (есть везде) |
| **pdftoipe** | Конвертация PDF в XML для редактора Ipe | нет; есть только в brew и apt, на dnf/pacman/zypper/apk ставьте из исходников |
| **7zip** | Архиватор 7-Zip | — (есть везде под разными именами: `sevenzip`/`p7zip-full`/`7zip`/`p7zip`) |
| **slumber** | Терминальный REST/gRPC-клиент (TUI-замена Postman/Insomnia) | `cargo install slumber` |

## Требует системных библиотек для сборки из исходников

Некоторые cargo-фолбэки тянут системные зависимости помимо компилятора
(который и так ставит `ensure_build_toolchain()` в `lib/packages.sh`):

- **gpg-tui** — `gpgme`, `libgpg-error`, (опционально `libxcb` для буфера обмена)
- **termusic** — аудио-библиотеки (ALSA на Linux)

Если сборка упадёт из-за отсутствующего `-dev`/`-devel` пакета, ошибка
попадёт в `MANUAL_TODO` в конце вывода скрипта — доустановите нужный
`-dev`-пакет вручную и повторите `./tools-extra.sh <имя>`.

## Как добавить новый инструмент

Список специально сделан таблицей одной функции, а не набором отдельных
шагов, — чтобы дописывать было легко:

1. Имя — в массив `TOOLS_EXTRA_NAMES` (`lib/tools_extra.sh`).
2. Описание — строка в `case` внутри `tool_desc()`.
3. Установка — строка в `case` внутри `install_tool()`:
   - если пакет есть хоть где-то нативно (или можно собрать `cargo install`) —
     `pkg_or_cargo <бинарь> <cargo-крейт> <brew> <apt> <dnf> <pacman> <zypper> <apk>`
     (пустая строка = "пакета здесь нет");
   - если у проекта свой официальный install-скрипт или релизы без cargo —
     отдельная функция по образцу `install_lazygit`/`install_k9s` в том же файле.
