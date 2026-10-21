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
omabox -b "$BOX" up --plugin "$HERE" --ro-bind "$CLI" --ro-bind /opt/google >/dev/null
# A fixed theme, so the assets do not follow whatever the author runs.
omabox -b "$BOX" run -- omarchy-theme-set "${OMAEGO_THEME:-tokyo-night}" >/dev/null 2>&1

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

echo "==> web apps, with their real icons"
omabox -b "$BOX" run -- bash -c "export PATH=$CLI/bin:\$PATH
  omaego app add work outlook teams
  omaego app add personal gmail
  omaego app add acme figma slack" >/dev/null 2>&1

echo "==> egos kept in a (local, bare) repo, in sync"
# Slack Acme stays declared in the repo but uninstalled here, so the card shows
# a blurred app that installs on first click.
omabox -b "$BOX" run -- bash -c "export PATH=$CLI/bin:\$PATH
  git init -q --bare -b main ~/remote.git
  git config --global user.name Demo; git config --global user.email demo@example.com
  omaego sync --remote ~/remote.git
  cd ~/.config/omaego && git add -A && git commit -qm 'Egos, apps and rules' && git push -qu origin main
  rm ~/.local/share/applications/'Slack Acme.desktop'
  omarchy-notification-dismiss omaego" >/dev/null 2>&1 || true

echo "==> a window carrying an ego's class, so one ego is 'here'"
omabox -b "$BOX" run -d --wait -- foot --app-id=chrome-work >/dev/null 2>&1 || true
omabox -b "$BOX" restart-shell >/dev/null

echo "==> frames"
CROP=${CROP:-880x450}
# closed, then open: two states are enough to show what the widget does
omabox -b "$BOX" shot -g "0,0 $CROP" -o "$FRAMES/01-closed.png" >/dev/null
omabox -b "$BOX" run -- omarchy-shell shell summon io.github.lcorneliussen.omaego >/dev/null
omabox -b "$BOX" wait still --timeout 8 >/dev/null 2>&1 || true
omabox -b "$BOX" shot -g "0,0 $CROP" -o "$FRAMES/02-open.png" >/dev/null

cp "$FRAMES/02-open.png" "$HERE/preview.png"
magick -delay 180 "$FRAMES/01-closed.png" -delay 320 "$FRAMES/02-open.png" \
       -loop 0 -layers optimize "$HERE/demo.gif"

echo "==> wrote $HERE/preview.png and $HERE/demo.gif"
magick identify -format '    preview %wx%h %b\n' "$HERE/preview.png"
magick identify -format '    gif     %wx%h %b\n' "$HERE/demo.gif[0]"
