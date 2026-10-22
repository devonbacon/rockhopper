#!/usr/bin/env bash
# Puts the dedicated server behind a shared Caddy at
# wss://NAME.play.devoncoleman.com:9443 (browsers on the HTTPS Pages site
# can't use plain ws://).
#
# One Caddy on the box serves every game: it lives in ~/caddy, runs as the
# user service play-caddy, listens on 9443 (the router forwards 9443 to the
# box) and holds a wildcard certificate for *.play.devoncoleman.com from the
# Route 53 DNS challenge, so ports 80/443 are never used and no sudo is
# needed. Each game drops a file in ~/caddy/sites/ that routes its hostname
# to its local port. AWS credentials for the challenge live only on the box,
# in ~/caddy/aws.env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION).
#
# Finally publishes the address to the Pages repo as rockhopper-server.json,
# where the web build looks for it.
#
#   tools/proxy_server.sh [user@host]            set up / update
#   tools/proxy_server.sh stop [user@host]       remove rockhopper's route
set -euo pipefail
BASE=play.devoncoleman.com
GAME=rockhopper
GAME_PORT=7777
PUBLIC=9443
if [ "${1:-}" = stop ]; then
	ssh "${2:-devon@192.168.1.27}" "rm -f ~/caddy/sites/$GAME.caddy && systemctl --user restart play-caddy.service"
	echo "$GAME route removed"
	exit 0
fi
HOST=${1:-devon@192.168.1.27}
NAME=$GAME.$BASE
PAGES=${PAGES:-$(cd "$(dirname "$0")/../.." && pwd)/game-demo-test}

ssh "$HOST" "bash -s $BASE $PUBLIC $GAME $GAME_PORT" <<'REMOTE'
set -euo pipefail
BASE=$1
PUBLIC=$2
GAME=$3
GAME_PORT=$4
mkdir -p ~/caddy/sites ~/.config/systemd/user
cd ~/caddy
if [ ! -f aws.env ]; then
	echo "missing ~/caddy/aws.env (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION)"
	exit 1
fi
chmod 600 aws.env
if [ ! -x caddy ] || ! ./caddy list-modules 2>/dev/null | grep -q dns.providers.route53; then
	curl -fsSL -o caddy "https://caddyserver.com/api/download?os=linux&arch=amd64&p=github.com/caddy-dns/route53"
	chmod +x caddy
fi
cat > Caddyfile <<EOF2
{
	http_port 9081
	https_port $PUBLIC
	auto_https disable_redirects
}

*.$BASE:$PUBLIC {
	tls {
		dns route53
		propagation_delay 45s
		propagation_timeout -1
	}
	import sites/*.caddy
	handle {
		respond "nothing here" 404
	}
}
EOF2
cat > sites/$GAME.caddy <<EOF2
@$GAME host $GAME.$BASE
handle @$GAME {
	reverse_proxy localhost:$GAME_PORT
}
EOF2
./caddy validate --config Caddyfile --adapter caddyfile >/dev/null
cat > ~/.config/systemd/user/play-caddy.service <<EOF2
[Unit]
Description=Caddy TLS proxy for *.$BASE
After=network-online.target

[Service]
WorkingDirectory=%h/caddy
EnvironmentFile=%h/caddy/aws.env
ExecStart=%h/caddy/caddy run --config Caddyfile --adapter caddyfile
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF2
systemctl --user daemon-reload
systemctl --user enable -q play-caddy.service
systemctl --user restart play-caddy.service
REMOTE

echo "waiting for the certificate..."
CODE=000
for i in $(seq 1 40); do
	CODE=$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "https://$NAME:$PUBLIC/" || true)
	[ "$CODE" != 000 ] && break
	sleep 3
done
if [ "$CODE" = 000 ]; then
	echo "https://$NAME:$PUBLIC isn't answering. Check DNS, the router forward and: ssh $HOST journalctl --user -u play-caddy -n 50"
	exit 1
fi
echo "https://$NAME:$PUBLIC is up (HTTP $CODE)"
WSS="wss://$NAME:$PUBLIC"
git -C "$PAGES" pull -q --rebase
printf '{"url": "%s", "updated": "%s"}\n' "$WSS" "$(date -u +%FT%TZ)" > "$PAGES/rockhopper-server.json"
git -C "$PAGES" add rockhopper-server.json
git -C "$PAGES" commit -q -m "Rockhopper server address" && git -C "$PAGES" push -q || echo "address unchanged"
echo "published $WSS to rockhopper-server.json"
