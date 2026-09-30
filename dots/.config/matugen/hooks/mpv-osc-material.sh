#!/usr/bin/env bash
# matugen post_hook:
# splice the generated Material OSC color block into material-osc.conf.
#
# material-osc reads ~/.config/mpv/script-opts/material-osc.conf.
# We don't let matugen generate that whole file because it would overwrite
# manually configured OSC options.
#
# Instead matugen generates only a small marked color block into GENERATED,
# and this hook replaces that block inside material-osc.conf.

set -euo pipefail

GENERATED="${HOME}/.config/matugen/generated/mpv-osc-material-color.conf"
CONF="${HOME}/.config/mpv/script-opts/material-osc.conf"

BEGIN='# >>> matugen material-osc >>>'
END='# <<< matugen material-osc <<<'

[ -f "$GENERATED" ] || {
    echo "material-osc hook: missing $GENERATED" >&2
    exit 1
}

[ -f "$CONF" ] || {
    echo "material-osc hook: missing $CONF" >&2
    exit 1
}

# Protect against a broken/incomplete marker block.
has_begin=0
has_end=0

grep -qF "$BEGIN" "$CONF" && has_begin=1
grep -qF "$END" "$CONF" && has_end=1

if [[ "$has_begin" != "$has_end" ]]; then
    echo "material-osc hook: broken marker block in $CONF" >&2
    echo "Both markers must either exist or be absent." >&2
    exit 1
fi

tmp="$(mktemp "${CONF}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

if [[ "$has_begin" -eq 1 ]]; then
    # Replace the existing generated block.
    awk \
        -v begin="$BEGIN" \
        -v end="$END" \
        -v gen="$GENERATED" '
        $0 == begin {
            inblock = 1

            while ((getline line < gen) > 0)
                print line

            close(gen)
            next
        }

        $0 == end {
            inblock = 0
            next
        }

        !inblock {
            print
        }
    ' "$CONF" > "$tmp"
else
    # First run: append generated block to the end.
    cat "$CONF" > "$tmp"

    # Ensure there is a blank line before the generated section.
    printf '\n' >> "$tmp"
    cat "$GENERATED" >> "$tmp"
fi

# Preserve original permissions.
chmod --reference="$CONF" "$tmp"

mv "$tmp" "$CONF"
trap - EXIT

echo "material-osc hook: updated $CONF"
