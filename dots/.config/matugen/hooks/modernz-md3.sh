#!/usr/bin/env bash
# matugen post_hook: splice the generated md3_* color block into modernz.conf.
#
# modernz reads only ~/.config/mpv/script-opts/modernz.conf, so we can't point
# matugen's output there directly without clobbering the whole file. Instead the
# template writes a self-contained marker block to GENERATED, and this hook
# replaces the region between the markers inside modernz.conf (appending it if
# the markers don't exist yet).
set -euo pipefail

GENERATED="${HOME}/.config/matugen/generated/modernz-md3.conf"
CONF="${HOME}/.config/mpv/script-opts/modernz.conf"
BEGIN='# >>> matugen md3 >>>'
END='# <<< matugen md3 <<<'

[ -f "$GENERATED" ] || { echo "modernz-md3 hook: missing $GENERATED" >&2; exit 1; }
[ -f "$CONF" ] || { echo "modernz-md3 hook: missing $CONF" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if grep -qF "$BEGIN" "$CONF"; then
    # Replace existing block: print everything outside [BEGIN, END], and inject
    # the freshly generated block in place of the old one.
    awk -v begin="$BEGIN" -v end="$END" -v gen="$GENERATED" '
        $0 == begin { inblock = 1
                      while ((getline line < gen) > 0) print line
                      close(gen)
                      next }
        $0 == end   { inblock = 0; next }
        !inblock    { print }
    ' "$CONF" > "$tmp"
else
    # First run: append the generated block to the end of the conf.
    cat "$CONF" > "$tmp"
    printf '\n' >> "$tmp"
    cat "$GENERATED" >> "$tmp"
fi

cat "$tmp" > "$CONF"
echo "modernz-md3 hook: updated $CONF"
