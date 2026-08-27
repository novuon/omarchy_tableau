#!/usr/bin/env bash
set -euo pipefail

plugin_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$plugin_dir"

python3 -m json.tool manifest.json >/dev/null
omarchy plugin validate "$plugin_dir"
python3 -m py_compile bin/omarchy-tableau
rm -rf bin/__pycache__
python3 test/test_save_state.py
python3 test/test_state_safety.py

# The generated starter config must remain usable on a fresh Omarchy install.
# Keep this guard close to the source template so optional developer tools do
# not quietly return to the public example.
if rg -n 'term = "(codex|claude)"|app = "kdenlive"' bin/omarchy-tableau; then
  echo "starter template contains non-default applications" >&2
  exit 1
fi

qmllint_bin="$(command -v qmllint || true)"
if [[ -z "$qmllint_bin" && -x /usr/lib/qt6/bin/qmllint ]]; then
  qmllint_bin=/usr/lib/qt6/bin/qmllint
fi

if [[ -n "$qmllint_bin" ]]; then
  "$qmllint_bin" -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
    LayoutPreview.qml MenuRow.qml Panel.qml SetupCard.qml SetupsStore.qml
else
  echo "qmllint not found; skipping QML lint" >&2
fi

# Saving must persist the new setup as the active selection, and the QML store
# must not let a stale Empty poll overwrite that selection while saving.
rg -q 'save_state\(setup=name, phase="idle"' bin/omarchy-tableau
rg -q 'root\.actionBusy && reportedCurrent === "Empty"' SetupsStore.qml

echo "Tableau validation passed"
