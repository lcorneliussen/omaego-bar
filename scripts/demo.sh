#!/usr/bin/env bash
# Produce the marketing assets - preview.png and demo.gif - from a scripted run
# in a contained Omarchy desktop (omabox), never from the author's own session.
#
# The box is seeded with invented egos, so nothing real appears in a published
# asset. Rerun it after a UI change and the assets regenerate identically.
#
#   scripts/demo.sh [--keep]     --keep leaves the box up for poking at
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI=${OMAEGO_SRC:-$HOME/Work/omaego}
BOX=omaego-demo
FRAMES=$(mktemp -d)
trap '[ "${1:-}" = "--keep" ] || omabox -b "$BOX" down >/dev/null 2>&1 || true; rm -rf "$FRAMES"' EXIT

command -v omabox >/dev/null || { echo "omabox is required" >&2; exit 1; }
[ -x "$CLI/bin/omaego" ] || { echo "set OMAEGO_SRC to the omaego checkout" >&2; exit 1; }

echo "==> box"
omabox -b "$BOX" down >/dev/null 2>&1 || true
omabox -b "$BOX" up --plugin "$HERE" --ro-bind "$CLI" >/dev/null

H=$(omabox -b "$BOX" path)/home
mkdir -p "$H/.local/share/chrome-profiles"/{work,personal,acme} \
         "$H/.config/omaego" "$H/.local/share/applications"
printf 'Work\n'     > "$H/.local/share/chrome-profiles/work/.profile-name"
printf 'Personal\n' > "$H/.local/share/chrome-profiles/personal/.profile-name"
printf 'Acme\n'     > "$H/.local/share/chrome-profiles/acme/.profile-name"
printf 'work\n'     > "$H/.local/share/chrome-profiles/.default"
cat > "$H/.config/omaego/rules.toml" <<'RULES'
[[rule]]
url = "https://git.example.com/acme/*"
profile = "Acme"
[[rule]]
url = "https://acme.atlassian.net/*"
profile = "Acme"
[[rule]]
url = "https://github.com/your-handle/*"
profile = "Personal"
[[rule]]
url = "https://*zoom.us/j/*"
app = true
RULES
while IFS='|' read -r n e u; do
  [ -n "$n" ] || continue
  printf '[Desktop Entry]\nVersion=1.0\nName=%s\nExec=%s/bin/omaego-webapp --ego=%s --app=%s\nTerminal=false\nType=Application\nIcon=google-chrome\n' \
    "$n" "$CLI" "$e" "$u" > "$H/.local/share/applications/$n.desktop"
done <<'APPS'
Teams Work|work|https://teams.microsoft.com/
Outlook Work|work|https://outlook.office.com/mail/
Gmail Personal|personal|https://mail.google.com/
Jira Acme|acme|https://acme.atlassian.net/
APPS

python3 - "$H" "$CLI" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])/".config/omarchy/shell.json"
d = json.loads(p.read_text())
for sec in d["bar"]["layout"].values():
    for e in sec:
        if isinstance(e, dict) and e.get("id", "").endswith("omaego"):
            e["command"] = f"{sys.argv[2]}/bin/omaego"
p.write_text(json.dumps(d, indent=2))
PY

echo "==> a window carrying an ego's class, so one ego is 'here'"
omabox -b "$BOX" run -d --wait -- foot --app-id=chrome-work >/dev/null 2>&1 || true
omabox -b "$BOX" restart-shell >/dev/null

echo "==> frames"
# closed, then open: two states are enough to show what the widget does
omabox -b "$BOX" shot -g "0,0 880x350" -o "$FRAMES/01-closed.png" >/dev/null
omabox -b "$BOX" run -- omarchy-shell shell summon io.github.lcorneliussen.omaego >/dev/null
omabox -b "$BOX" wait still --timeout 8 >/dev/null 2>&1 || true
omabox -b "$BOX" shot -g "0,0 880x350" -o "$FRAMES/02-open.png" >/dev/null

cp "$FRAMES/02-open.png" "$HERE/preview.png"
magick -delay 180 "$FRAMES/01-closed.png" -delay 320 "$FRAMES/02-open.png" \
       -loop 0 -layers optimize "$HERE/demo.gif"

echo "==> wrote $HERE/preview.png and $HERE/demo.gif"
magick identify -format '    preview %wx%h %b\n' "$HERE/preview.png"
magick identify -format '    gif     %wx%h %b\n' "$HERE/demo.gif[0]"
