#!/usr/bin/env bash

set -Eeuo pipefail

ORIGINAL_ARGS=("$@")

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOMELAB_USER="${HOMELAB_USER:-eldayia}"
HOMELAB_ROOT="${HOMELAB_ROOT:-/srv/docker}"
ACTIVATE_FIREWALL=0
ENABLE_BACKUP=0

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/install-host.sh [options]

Options:
  --activate-firewall  Active immédiatement le pare-feu nftables.
  --enable-backup      Active le timer Restic (secrets et montage requis).
  -h, --help           Affiche cette aide.
EOF
}

while (($#)); do
  case "$1" in
    --activate-firewall) ACTIVATE_FIREWALL=1 ;;
    --enable-backup) ENABLE_BACKUP=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Option inconnue: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if ((EUID != 0)); then
  exec sudo -E bash "$0" "${ORIGINAL_ARGS[@]}"
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Impossible d'identifier le système." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
ARCH="$(dpkg --print-architecture)"

if [[ "$ID" != "debian" || "${VERSION_ID%%.*}" != "13" || "$ARCH" != "arm64" ]]; then
  echo "Hôte attendu: Debian 13 arm64; détecté: $PRETTY_NAME ($ARCH)." >&2
  echo "Définir ALLOW_UNSUPPORTED=1 uniquement après vérification manuelle." >&2
  [[ "${ALLOW_UNSUPPORTED:-0}" == "1" ]] || exit 1
fi

if ! id "$HOMELAB_USER" >/dev/null 2>&1; then
  echo "Utilisateur introuvable: $HOMELAB_USER" >&2
  exit 1
fi

mapfile -t APT_PACKAGES < <(
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$REPO_ROOT/inventory/apt-packages.txt"
)

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"

if ! command -v docker >/dev/null 2>&1; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

usermod -aG docker "$HOMELAB_USER"
chsh -s /usr/bin/zsh "$HOMELAB_USER"

USER_HOME="$(getent passwd "$HOMELAB_USER" | cut -d: -f6)"
install -d -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0755 \
  "$USER_HOME/.config/nvim" "$USER_HOME/.config/labwc" "$USER_HOME/.local/bin"

install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0644 \
  "$REPO_ROOT/dotfiles/.zshrc" "$USER_HOME/.zshrc"
install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0644 \
  "$REPO_ROOT/dotfiles/.bashrc" "$USER_HOME/.bashrc"
install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0644 \
  "$REPO_ROOT/dotfiles/.profile" "$USER_HOME/.profile"
install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0644 \
  "$REPO_ROOT/dotfiles/.gitconfig" "$USER_HOME/.gitconfig"
install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0644 \
  "$REPO_ROOT/dotfiles/.config/nvim/init.lua" "$USER_HOME/.config/nvim/init.lua"
install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0644 \
  "$REPO_ROOT/dotfiles/.config/labwc/environment" "$USER_HOME/.config/labwc/environment"
install -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0700 \
  "$REPO_ROOT/dotfiles/.local/bin/ssh-dashboard" "$USER_HOME/.local/bin/ssh-dashboard"

if [[ ! -d "$USER_HOME/.oh-my-zsh/.git" ]]; then
  sudo -u "$HOMELAB_USER" git clone --depth=1 \
    https://github.com/ohmyzsh/ohmyzsh.git "$USER_HOME/.oh-my-zsh"
fi

ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions/.git" ]]; then
  sudo -u "$HOMELAB_USER" git clone --depth=1 \
    https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting/.git" ]]; then
  sudo -u "$HOMELAB_USER" git clone --depth=1 \
    https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

install -d -m 0755 /etc/nftables.d /etc/ssh/sshd_config.d /etc/systemd/system
install -m 0644 "$REPO_ROOT/config/nftables/rpi-guard.nft" \
  /etc/nftables.d/rpi-guard.nft
install -m 0644 "$REPO_ROOT/config/ssh/10-key-auth.conf" \
  /etc/ssh/sshd_config.d/10-key-auth.conf
install -m 0644 "$REPO_ROOT/config/ssh/99-hardening.conf" \
  /etc/ssh/sshd_config.d/99-hardening.conf
install -m 0644 "$REPO_ROOT/config/systemd/rpi-firewall.service" \
  /etc/systemd/system/rpi-firewall.service
install -m 0644 "$REPO_ROOT/config/systemd/docker-restic-backup.service" \
  /etc/systemd/system/docker-restic-backup.service
install -m 0644 "$REPO_ROOT/config/systemd/docker-restic-backup.timer" \
  /etc/systemd/system/docker-restic-backup.timer

install -d -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0755 "$HOMELAB_ROOT"
install -d -m 0700 "$HOMELAB_ROOT/backup"
install -m 0700 "$REPO_ROOT/scripts/backup.sh" "$HOMELAB_ROOT/backup/backup.sh"

install -d -o "$HOMELAB_USER" -g "$HOMELAB_USER" -m 0700 "$USER_HOME/.ssh"
touch "$USER_HOME/.ssh/authorized_keys"
chown "$HOMELAB_USER:$HOMELAB_USER" "$USER_HOME/.ssh/authorized_keys"
chmod 0600 "$USER_HOME/.ssh/authorized_keys"
while IFS= read -r public_key; do
  [[ -n "$public_key" ]] || continue
  grep -qxF "$public_key" "$USER_HOME/.ssh/authorized_keys" || \
    printf '%s\n' "$public_key" >>"$USER_HOME/.ssh/authorized_keys"
done <"$REPO_ROOT/config/ssh/authorized_keys"

nft -c -f /etc/nftables.d/rpi-guard.nft
sshd -t
systemctl daemon-reload
systemctl enable --now docker.service ssh.service cockpit.socket
systemctl reload ssh.service

docker network inspect proxy >/dev/null 2>&1 || docker network create proxy >/dev/null

if ((ACTIVATE_FIREWALL)); then
  systemctl enable --now rpi-firewall.service
else
  echo "Pare-feu installé mais non activé; utiliser --activate-firewall après un test SSH parallèle."
fi

if ((ENABLE_BACKUP)); then
  [[ -s /root/.config/restic/rpi-password ]] || {
    echo "Mot de passe Restic absent; exécuter configure-backup.sh." >&2
    exit 1
  }
  mountpoint -q /mnt/qnap-backups || {
    echo "Montage QNAP absent; exécuter configure-backup.sh." >&2
    exit 1
  }
  systemctl enable --now docker-restic-backup.timer
fi

echo "Installation hôte terminée. Reconnecte-toi pour appliquer le groupe docker et le shell zsh."
