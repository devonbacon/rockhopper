#!/usr/bin/env bash
# Sets up, or updates, the dedicated server on a Debian box over ssh: Godot's
# Linux build, this repo (cloned from GitHub, or pulled), a systemd user
# service running it headless, and a timer that checks GitHub every minute
# and, when main has moved, updates to it and restarts the server. After
# this, a push is all an update needs.
#
#   tools/deploy_server.sh [user@host] [port]
set -euo pipefail
HOST=${1:-devon@192.168.1.27}
PORT=${2:-7777}
VERSION=4.7.2-stable

# The setup runs detached on the box, logging to setup.log, so a dropped ssh
# connection can't leave it half done.
ssh "$HOST" 'mkdir -p ~/rockhopper-server && cat > ~/rockhopper-server/setup.sh' <<'REMOTE'
set -euo pipefail
trap 'echo "setup error at line $LINENO"' ERR
VERSION=$1
PORT=$2
for tool in curl unzip git; do
	command -v "$tool" >/dev/null || { echo "needs $tool: sudo apt install $tool"; exit 1; }
done
mkdir -p ~/rockhopper-server
cd ~/rockhopper-server
if [ ! -x godot ] || ! ./godot --version >/dev/null 2>&1; then
	rm -f godot godot.zip
	until curl -fsSL -C - --speed-limit 1000 --speed-time 30 -o godot.zip.part "https://github.com/godotengine/godot/releases/download/$VERSION/Godot_v${VERSION}_linux.x86_64.zip"; do
		echo "download stalled at $(stat -c %s godot.zip.part 2>/dev/null || echo 0) bytes, resuming"
		sleep 2
	done
	unzip -tq godot.zip.part
	mv godot.zip.part godot.zip
	unzip -oq godot.zip -d unpacked
	mv "unpacked/Godot_v${VERSION}_linux.x86_64" godot
	rm -rf unpacked godot.zip
fi
if [ ! -d game/.git ]; then
	git clone -q https://github.com/devonbacon/rockhopper.git game
fi
git -C game fetch -q origin main && git -C game reset -q --hard origin/main && git -C game clean -qfd -e .godot
./godot --headless --path game --import >/dev/null 2>&1 || true
cat > update.sh <<'UPDATE'
#!/usr/bin/env bash
# Run every minute by rockhopper-update.timer: updates to what's pushed, if
# anything is, and restarts the server on it.
set -euo pipefail
cd ~/rockhopper-server
git -C game fetch -q origin main
[ "$(git -C game rev-parse HEAD)" = "$(git -C game rev-parse origin/main)" ] && exit 0
git -C game reset -q --hard origin/main
git -C game clean -qfd -e .godot
./godot --headless --path game --import >/dev/null 2>&1 || true
systemctl --user restart rockhopper.service
echo "updated to $(git -C game log --oneline -1)"
UPDATE
chmod +x update.sh
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/rockhopper-update.service <<EOF
[Unit]
Description=Update the Rockhopper server to what's pushed

[Service]
Type=oneshot
ExecStart=%h/rockhopper-server/update.sh
EOF
cat > ~/.config/systemd/user/rockhopper-update.timer <<EOF
[Unit]
Description=Check for a new Rockhopper build every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF
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
systemctl --user enable -q --now rockhopper-update.timer
loginctl enable-linger "$USER" 2>/dev/null || echo "note: run 'sudo loginctl enable-linger $USER' so it keeps running after you log out"
sleep 2
systemctl --user --no-pager status rockhopper.service | head -6
echo "listening on TCP $PORT"
REMOTE
ssh "$HOST" "cd ~/rockhopper-server && rm -f setup.log && setsid nohup bash setup.sh $VERSION $PORT > setup.log 2>&1 < /dev/null &"
echo "setting up on $HOST; following ~/rockhopper-server/setup.log"
until ssh -o ConnectTimeout=8 "$HOST" 'grep -q "listening on TCP\|needs \|rror\|fatal" ~/rockhopper-server/setup.log' 2>/dev/null; do
	sleep 5
done
ssh "$HOST" 'cat ~/rockhopper-server/setup.log'
