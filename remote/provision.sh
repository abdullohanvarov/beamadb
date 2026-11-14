#!/usr/bin/env bash
# Run on the relay host as its ordinary user.
set -euo pipefail
umask 077
host=${1:?Pass the VPS hostname or IPv4 address}
port=${2:-45883}
base="$HOME/.local/share/beamadb-link"
mkdir -p "$base" "$HOME/.config/systemd/user"
cp "$(dirname "$0")/relay.py" "$base/"
if [[ ! -e "$base/key.pem" ]]; then
  openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj /CN=BeamADB -keyout "$base/key.pem" -out "$base/cert.pem"
fi
[[ -s "$base/secret" ]] || openssl rand -hex 32 > "$base/secret"
cd "$base"
python3 - "$host" "$port" <<'PY'
import hashlib,json,pathlib,ssl,sys
from relay import credential
cert=ssl.PEM_cert_to_DER_cert(pathlib.Path('cert.pem').read_text())
for role in ('desktop','phone'):
    cfg=dict(host=sys.argv[1],port=int(sys.argv[2]),pin=hashlib.sha256(cert).hexdigest(),
             token=credential(pathlib.Path('secret').read_text().strip(),role))
    pathlib.Path(role+'.json').write_text(json.dumps(cfg))
PY
cat > "$HOME/.config/systemd/user/beamadb-link-relay.service" <<EOF
[Unit]
Description=BeamADB private relay
[Service]
WorkingDirectory=%h/.local/share/beamadb-link
ExecStart=/usr/bin/python3 relay.py --cert cert.pem --key key.pem --secret secret --port $port
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now beamadb-link-relay.service
