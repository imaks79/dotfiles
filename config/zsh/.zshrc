export ZSH="$HOME/.config/.oh-my-zsh"
export PATH="/opt/homebrew/bin:$PATH"

ZSH_THEME="robbyrussell"

plugins=(
	git
	ssh-agent
	zsh-autosuggestions
	zsh-syntax-highlighting
)

zstyle :omz:plugins:ssh-agent identities adminvps github@home macos@home openwrt@home mikrotiks@work
zstyle :omz:plugins:ssh-agent ssh-add-args --apple-use-keychain

source $ZSH/oh-my-zsh.sh

if [ -x "$(command -v eza)" ]; then
	alias ll="eza --long --all --group -snew -h"
fi

alias i="brew update && brew upgrade"
alias n="nvim"
alias c="clear"
alias e="exit"
alias m="musikcube"
alias tm="termusic"
alias src="source $HOME/.zshrc"
alias ya="yazi"
alias cl="claude"
alias ff="fastfetch"
alias h="herdr"

alias t="
# Проверяем, запущен ли tmux, и не в ssh ли мы
if command -v tmux >/dev/null 2>&1 && [ -z "$TMUX" ]; then
    # Подключаемся к существующей сессии или создаем новую
    tmux attach -t main || tmux new -s main
    # exec tmux new-session -A -s main
fi"

