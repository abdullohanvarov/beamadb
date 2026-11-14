#!/usr/bin/env bash
# Run on Ubuntu with access to the VPS. No sudo or firewall changes.
set -euo pipefail
umask 077
cd "$(dirname "$0")"
key=${1:?Supply the SSH private key path}
target=${2:-ubuntu@130.61.119.34}
host=${target#*@}
[[ "$host" =~ ^[a-zA-Z0-9.-]+$ ]] || exit 2
options=(-F /dev/null -i "$key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=ask)
ssh "${options[@]}" "$target" 'set -eu
if ss -Hltn "sport = :45883" | grep -q . && ! systemctl --user is-active --quiet beamadb-link-relay.service; then
  echo "Port 45883 already belongs to another listener. Stopping." >&2; exit 1
fi
install -d -m700 ~/.local/share/beamadb-link/deploy'
scp "${options[@]}" relay.py provision.sh "$target:.local/share/beamadb-link/deploy/"
ssh "${options[@]}" "$target" "bash ~/.local/share/beamadb-link/deploy/provision.sh $host && systemctl --user is-active beamadb-link-relay.service"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/beamadb-link/profiles"
mkdir -p "$dest"
for role in desktop phone; do
 scp "${options[@]}" "$target:.local/share/beamadb-link/$role.json" "$dest/$role.json"
 chmod 600 "$dest/$role.json"
done
printf 'Relay profiles are in %s\n' "$dest"
ssh "${options[@]}" "$target" 'loginctl show-user "$USER" -p Linger'
