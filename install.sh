#!/usr/bin/env bash
# Local development install. For publishing, use:
#   omarchy plugin add <git-url> --enable
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
id="io.github.antunesales-dev.translate"
dest="${HOME}/.config/omarchy/plugins/${id}"

chmod +x "$root"/bin/omarchy-translate "$root"/bin/omarchy-translate-ocr \
  "$root"/bin/omarchy-translate-paste "$root"/bin/omarchy-translate-setup-lt
mkdir -p "$(dirname "$dest")"

# Copy, never symlink: omarchy plugin validate rejects plugin folders with symlinks.
rsync -a --delete \
  --exclude '.git/' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  "$root/" "$dest/"

mkdir -p "${HOME}/.local/bin"
ln -sfn "$root/bin/omarchy-translate" "${HOME}/.local/bin/omarchy-translate"
ln -sfn "$root/bin/omarchy-translate-ocr" "${HOME}/.local/bin/omarchy-translate-ocr"
ln -sfn "$root/bin/omarchy-translate-paste" "${HOME}/.local/bin/omarchy-translate-paste"
ln -sfn "$root/bin/omarchy-translate-setup-lt" "${HOME}/.local/bin/omarchy-translate-setup-lt"

omarchy plugin validate "$dest"
omarchy plugin enable "$id" --section right
omarchy-shell shell rescanPlugins 2>/dev/null || true

echo "Installed plugin $id -> $dest"
echo "Summon: omarchy-shell shell summon $id '{}'"
echo "Keybind example: $root/extras/bindings.lua.example"
