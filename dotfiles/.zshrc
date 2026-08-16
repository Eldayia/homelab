# ─────────────────────────────────────────────────────────────
# Oh My Zsh
# ─────────────────────────────────────────────────────────────

export ZSH="$HOME/.oh-my-zsh"

# Thème lisible et léger, sans dépendance à une police spéciale.
ZSH_THEME="robbyrussell"

# Mise à jour automatique d'Oh My Zsh.
zstyle ':omz:update' mode auto
zstyle ':omz:update' frequency 14

# Sensibilité à la casse pour la complétion.
CASE_SENSITIVE="false"
HYPHEN_INSENSITIVE="true"

# Ne pas afficher le nom d'utilisateur si l'on est connecté
# avec l'utilisateur normal de la machine.
DEFAULT_USER="$USER"

# Correction interactive des petites fautes.
ENABLE_CORRECTION="true"

# Évite de marquer les fichiers collés depuis le terminal.
DISABLE_MAGIC_FUNCTIONS="true"

plugins=(
  git
  sudo
  docker
  docker-compose
  systemd
  ssh
  rsync
  extract
  command-not-found
  colored-man-pages
  history
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

# ─────────────────────────────────────────────────────────────
# Historique
# ─────────────────────────────────────────────────────────────

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_SAVE_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt HIST_VERIFY
setopt EXTENDED_HISTORY

# Recherche dans l'historique avec les flèches haut/bas
# en fonction du texte déjà saisi.
autoload -Uz up-line-or-beginning-search
autoload -Uz down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

# Accepter une autosuggestion avec Ctrl+E ou flèche droite.
bindkey '^E' autosuggest-accept
bindkey '^[[C' forward-char

ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# ─────────────────────────────────────────────────────────────
# Comportement général
# ─────────────────────────────────────────────────────────────

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP

# Édition de la ligne de commande façon Emacs :
# Ctrl+A début, Ctrl+E fin, Ctrl+R historique.
bindkey -e

# Ctrl+R avec fzf si disponible.
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh 2>/dev/null) || true
fi

# ─────────────────────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────────────────────

export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less"
export LESS="-R"

# ─────────────────────────────────────────────────────────────
# Alias généraux
# ─────────────────────────────────────────────────────────────

alias ls='ls --color=auto'
alias ll='ls -alFh'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias c='clear'
alias cls='clear'
alias grep='grep --color=auto'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ports='sudo ss -tulpn'
alias ipinfo='ip -br address'
alias myip='hostname -I'
alias reload='source ~/.zshrc'
alias zshrc='nvim ~/.zshrc'
alias nvimrc='nvim ~/.config/nvim/init.lua'

# Noms Debian/Raspberry Pi OS.
command -v batcat >/dev/null 2>&1 && alias bat='batcat'
command -v fdfind >/dev/null 2>&1 && alias fd='fdfind'

# ─────────────────────────────────────────────────────────────
# Git
# ─────────────────────────────────────────────────────────────

alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias glog='git log --graph --decorate --oneline --all'

# ─────────────────────────────────────────────────────────────
# Docker
# ─────────────────────────────────────────────────────────────

alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias di='docker images'
alias dv='docker volume ls'
alias dn='docker network ls'
alias dlogs='docker logs --tail=100 -f'
alias dcup='docker compose up -d'
alias dcdown='docker compose down'
alias dcpull='docker compose pull'
alias dcps='docker compose ps'
alias dcconfig='docker compose config'

# ─────────────────────────────────────────────────────────────
# Système
# ─────────────────────────────────────────────────────────────

alias update='sudo apt update && sudo apt full-upgrade'
alias services='systemctl --type=service --state=running'
alias failed='systemctl --failed'
alias jctl='journalctl -xe'
alias temperature='vcgencmd measure_temp 2>/dev/null || true'

# Crée un dossier puis entre dedans.
mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

# Affiche les derniers logs d'un service.
slogs() {
  if [[ -z "$1" ]]; then
    echo "Usage : slogs nom-du-service"
    return 1
  fi

  sudo journalctl -u "$1" -n 100 -f
}

# Tableau de bord lors d'une nouvelle connexion SSH interactive.
if [[ -n "$SSH_CONNECTION" && -o interactive && "$SHLVL" -le 1 ]]; then
  "$HOME/.local/bin/ssh-dashboard"
fi
