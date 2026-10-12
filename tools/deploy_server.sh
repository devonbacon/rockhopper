#!/usr/bin/env bash
# Sets up, or updates, the dedicated server on a Debian box over ssh: Godot's
# Linux build, this repo (cloned from GitHub, or pulled), and a systemd user
# service running it headless. Run it again to update to what's pushed.
#
#   tools/deploy_server.sh [user@host] [port]
set -euo pipefail
HOST=${1:-devon@192.168.1.27}
PORT=${2:-7777}
VERSION=4.7.2-stable

ssh "$HOST" bash -s -- "$VERSION" "$PORT" <<'REMOTE'
set -euo pipefail
VERSION=$1
PORT=$2
for tool in curl unzip git; do
	command -v "$tool" >/dev/null || { echo "needs $tool: sudo apt install $tool"; exit 1; }
done
mkdir -p ~/rockhopper-server
cd ~/rockhopper-server
if [ ! -x godot ]; then
	curl -fsSL -o godot.zip "https://github.com/godotengine/godot/releases/download/$VERSION/Godot_v${VERSION}_linux.x86_64.zip"
	unzip -oq godot.zip
	mv "Godot_v${VERSION}_linux.x86_64" godot
	rm godot.zip
fi
if [ -d game/.git ]; then
	git -C game pull --ff-only
else
	git clone -q https://github.com/devonbacon/rockhopper.git game
fi
./godot --headless --path game --import >/dev/null 2>&1 || true
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/rockhopper.service <<EOF
[Unit]
Description=Rockhopper dedicated server
After=network-online.target

[Service]
WorkingDirectory=%h/rockhopper-server
ExecStart=%h/rockhopper-server/godot --headless --path %h/rockhopper-server/game -- --server --port=$PORT
Restart=on-failure

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable -q rockhopper.service
systemctl --user restart rockhopper.service
loginctl enable-linger "$USER" 2>/dev/null || echo "note: run 'sudo loginctl enable-linger $USER' so it keeps running after you log out"
sleep 2
systemctl --user --no-pager status rockhopper.service | head -6
echo "listening on UDP $PORT"
REMOTE
