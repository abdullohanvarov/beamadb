#!/usr/bin/env bash
set -euo pipefail
umask 077
base="$HOME/.local/share/beamadb-link"
mkdir -p "$base" "$HOME/.config/systemd/user" "${XDG_CONFIG_HOME:-$HOME/.config}/beamadb-link"
cp "$(dirname "$0")"/{agent,relay}.py "$base/"
install -m600 "${1:?Supply desktop.json from your relay}" "${XDG_CONFIG_HOME:-$HOME/.config}/beamadb-link/desktop.json"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/beamadb-link"
if [[ ! -e "$cfg/peer.key" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj /CN=BeamADB-peer -keyout "$cfg/peer.key" -out "$cfg/peer.pem"
fi
python3 - "$cfg" "${2:?Supply phone.json from your relay}" <<'PYTHON'
import hashlib,json,pathlib,secrets,ssl,sys
root=pathlib.Path(sys.argv[1])
phone=json.loads(pathlib.Path(sys.argv[2]).read_text())
desktop=json.loads((root/'desktop.json').read_text())
proof_path=root/'pair-secret'
if not proof_path.exists(): proof_path.write_text(secrets.token_hex(32))
desktop['proof']=phone['proof']=proof_path.read_text()
phone['peer']=hashlib.sha256(ssl.PEM_cert_to_DER_cert((root/'peer.pem').read_text())).hexdigest()
(root/'desktop.json').write_text(json.dumps(desktop))
(root/'invite.json').write_text(json.dumps(phone))
PYTHON
cat > "$HOME/.config/systemd/user/beamadb-link-agent.service" <<'EOF'
[Unit]
Description=BeamADB remote device connection
[Service]
ExecStart=/usr/bin/python3 %h/.local/share/beamadb-link/agent.py
Restart=always
RestartSec=5
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now beamadb-link-agent
systemctl --user restart beamadb-link-agent
