#!/usr/bin/env bash
# Copies the dedicated server's playtest logs into sessions/ (gitignored).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sessions
scp -q 'devon@192.168.1.27:.local/share/godot/app_userdata/Rockhopper/sessions/*.jsonl' sessions/
ls -1t sessions | head -5
