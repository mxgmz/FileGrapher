#!/usr/bin/env bash
# Cartographer gardening loop — wire a headless Claude agent to the running app's in-app MCP server and
# run one custodian pass: canvas_health → tidy LAYOUT → canvas_screenshot → repeat (see garden-prompt.md).
#
# The app must already be RUNNING on the target vault (the MCP server lives inside the app and writes
# <vault>/.graphingapp/mcp.json on open). Usage:
#     tools/garden/run-garden.sh <vault-path>
#
# Safety: the agent is whitelisted to LAYOUT-ONLY tools — no create/move/link — so it can reorganize the
# canvas (board.json) but provably cannot touch note contents or vault structure. Verify with a file hash
# before/after (it must be identical).
set -euo pipefail

VAULT="${1:?usage: run-garden.sh <vault-path>}"
INFO="$VAULT/.graphingapp/mcp.json"
[ -f "$INFO" ] || { echo "No $INFO — is the app running on this vault?"; exit 1; }

PORT=$(python3 -c "import json;print(json.load(open('$INFO'))['port'])")
TOKEN=$(python3 -c "import json;print(json.load(open('$INFO'))['token'])")

CFG=$(mktemp -t garden-mcp-XXXX.json)
trap 'rm -f "$CFG"' EXIT
cat > "$CFG" <<JSON
{"mcpServers":{"graphing-canvas":{"type":"http","url":"http://127.0.0.1:$PORT/mcp","headers":{"Authorization":"Bearer $TOKEN"}}}}
JSON

# Layout-only allow-list (board.json writes); deliberately omits create_note/create_folder/move/link.
P="mcp__graphing-canvas__"
ALLOW="${P}canvas_get,${P}canvas_health,${P}canvas_arrange,${P}canvas_collapse,${P}canvas_expand,${P}canvas_color,${P}canvas_resize,${P}canvas_screenshot"

claude -p "$(cat "$(dirname "$0")/garden-prompt.md")" \
  --mcp-config "$CFG" --strict-mcp-config \
  --allowedTools "$ALLOW" \
  --dangerously-skip-permissions
