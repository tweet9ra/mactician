#!/system/bin/sh
# Run before TFT starts: changing Android resources can restart a running app.
set -eu

package=${1:-}
case "$package" in
    com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn|com.riotgames.league.teamfighttacticstw) ;;
    *) echo 'Unsupported game-focus package.' >&2; exit 2 ;;
esac

if pidof "$package" >/dev/null 2>&1; then
    echo 'Game-focus protection must be prepared while TFT is stopped.' >&2
    exit 1
fi

# A hardware key can focus GameActivity's full-screen Android content view.
# Its AppCompat ripple paints a white scrim over the separate Unreal surface.
# Override only TFT's native ripple color; WebView and Unreal draw their own UI.
resource="$package:color/ripple_material_dark"
name="MacticianGameFocus_${package##*.}"
overlay="com.android.shell:$name"
color=$(cmd overlay lookup --user 0 "$package" "$resource")
case "$color" in
    '#33ffffff'|'#33FFFFFF'|'#0'|'#00000000') ;;
    *) echo "Unsupported TFT native focus color: $color" >&2; exit 1 ;;
esac

cmd overlay fabricate --target "$package" --name "$name" "$resource" 0x1c 0x00000000
cmd overlay enable --user 0 "$overlay"
color=$(cmd overlay lookup --user 0 "$package" "$resource") || color=unavailable
case "$color" in
    '#0'|'#00000000') echo 'TFT native focus scrim is disabled.' ;;
    *)
        cmd overlay disable --user 0 "$overlay"
        echo 'Could not verify TFT native focus protection.' >&2
        exit 1
        ;;
esac
