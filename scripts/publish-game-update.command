#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly SPARKLE_ROOT="$("$PROJECT_DIR/scripts/prepare-sparkle.command")"
readonly SIGN_UPDATE="$SPARKLE_ROOT/bin/sign_update"
readonly APK_DIR="${MACTICIAN_GAME_APK_DIR:-${TFT_GAME_APK_DIR:-}}"
readonly VERSION="${MACTICIAN_GAME_VERSION:-}"
readonly VERSION_CODE="${MACTICIAN_GAME_VERSION_CODE:-}"
readonly PACKAGE="${MACTICIAN_GAME_PACKAGE:-com.riotgames.league.teamfighttactics}"
readonly SIGNING_ACCOUNT="${MACTICIAN_GAME_SIGNING_ACCOUNT:-mactician-game-updates}"
readonly SIGNING_KEY_FILE="${MACTICIAN_GAME_SIGNING_KEY_FILE:-}"
readonly UPDATE_BASE_URL="${MACTICIAN_UPDATE_BASE_URL:-https://sergeinaumov.dev/mactician/updates}"
readonly SSH_TARGET="${MACTICIAN_UPDATE_SSH_TARGET:-}"
readonly SSH_PORT="${MACTICIAN_UPDATE_SSH_PORT:-22}"
readonly REMOTE_ROOT="${MACTICIAN_UPDATE_REMOTE_ROOT:-}"
readonly OUTPUT_ROOT="${MACTICIAN_GAME_UPDATE_WORKDIR:-$PROJECT_DIR/dist/mactician-game-update}"
typeset -i PREPARE_ONLY=0

usage() {
    print -u2 "Usage: ${0:t} [--prepare-only]"
}

for argument in "$@"; do
    case "$argument" in
        --prepare-only)
            (( PREPARE_ONLY == 0 )) || { usage; exit 2; }
            PREPARE_ONLY=1
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

[[ -d "$APK_DIR" ]] || { print -u2 "MACTICIAN_GAME_APK_DIR must contain the official split APK files."; exit 2; }
[[ -n "$VERSION" ]] || { print -u2 "MACTICIAN_GAME_VERSION is required."; exit 2; }
[[ "$VERSION_CODE" == <1-> ]] || { print -u2 "MACTICIAN_GAME_VERSION_CODE must be a positive integer."; exit 2; }
case "$PACKAGE" in
    com.riotgames.league.teamfighttactics|com.riotgames.league.teamfighttacticsvn) ;;
    *) print -u2 "MACTICIAN_GAME_PACKAGE must select the global or Vietnam TFT package."; exit 2 ;;
esac
[[ -n "$SIGNING_ACCOUNT" ]] || { print -u2 "MACTICIAN_GAME_SIGNING_ACCOUNT is required to sign the game feed."; exit 2; }
command -v jq >/dev/null || { print -u2 "jq is required."; exit 1; }
command -v openssl >/dev/null || { print -u2 "openssl is required."; exit 1; }

typeset -a APK_FILES
typeset apk name size sha256 url apk_json='[]'
APK_FILES=("$APK_DIR/base.apk")
for apk in "$APK_DIR"/*.apk(N); do
    [[ "${apk:t}" == "base.apk" ]] || APK_FILES+=("$apk")
done
(( ${#APK_FILES[@]} >= 1 && ${#APK_FILES[@]} <= 32 )) || {
    print -u2 "The game release must contain between 1 and 32 split APK files."
    exit 1
}

for apk in "${APK_FILES[@]}"; do
    [[ -f "$apk" ]] || { print -u2 "APK not found: $apk"; exit 1; }
    name="${apk:t}"
    [[ "$name" =~ '^[A-Za-z0-9._-]+[.]apk$' ]] || { print -u2 "Unsafe APK filename: $name"; exit 1; }
    size="$(stat -f '%z' "$apk")"
    sha256="$(shasum -a 256 "$apk" | awk '{print $1}')"
    [[ "$sha256" =~ '^[0-9a-f]{64}$' ]] || {
        print -u2 "Could not hash $name"
        exit 1
    }
    if [[ "$name" == "base.apk" ]]; then
        readonly BASE_SHA256="$sha256"
    fi
    url="$UPDATE_BASE_URL/game/releases/$BASE_SHA256/$name"
    apk_json="$(jq -c \
        --arg name "$name" \
        --arg url "$url" \
        --arg sha256 "$sha256" \
        --argjson size "$size" \
        '. + [{name: $name, size: $size, sha256: $sha256, url: $url}]' \
        <<<"$apk_json")"
done

readonly RELEASE_ROOT="$OUTPUT_ROOT/releases/$BASE_SHA256"
readonly PAYLOAD="$OUTPUT_ROOT/payload.json"
readonly MANIFEST="$OUTPUT_ROOT/manifest.json"
case "$OUTPUT_ROOT" in
    "/"|"/Users"|"$HOME"|"$PROJECT_DIR")
        print -u2 "Refusing unsafe local output root: $OUTPUT_ROOT"
        exit 2
        ;;
esac
rm -rf "$OUTPUT_ROOT"
mkdir -p "$RELEASE_ROOT"
for apk in "${APK_FILES[@]}"; do
    ditto "$apk" "$RELEASE_ROOT/${apk:t}"
done

jq -n \
    --arg publishedAt "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg packageName "$PACKAGE" \
    --arg version "$VERSION" \
    --argjson versionCode "$VERSION_CODE" \
    --arg baseSHA256 "$BASE_SHA256" \
    --argjson apks "$apk_json" \
    '{
        schemaVersion: 1,
        publishedAt: $publishedAt,
        release: {
            packageName: $packageName,
            version: $version,
            versionCode: $versionCode,
            baseSHA256: $baseSHA256,
            apks: $apks
        }
    }' >"$PAYLOAD"

if [[ -n "$SIGNING_KEY_FILE" ]]; then
    [[ -f "$SIGNING_KEY_FILE" ]] || { print -u2 "MACTICIAN_GAME_SIGNING_KEY_FILE was not found."; exit 2; }
    readonly SIGNATURE="$("$SIGN_UPDATE" --ed-key-file "$SIGNING_KEY_FILE" -p "$PAYLOAD")"
else
    readonly SIGNATURE="$("$SIGN_UPDATE" --account "$SIGNING_ACCOUNT" -p "$PAYLOAD")"
fi
[[ "$SIGNATURE" =~ '^[A-Za-z0-9+/=]+$' ]] || { print -u2 "Sparkle returned an invalid feed signature."; exit 1; }
readonly PAYLOAD_BASE64="$(openssl base64 -A -in "$PAYLOAD")"
jq -n \
    --arg payload "$PAYLOAD_BASE64" \
    --arg signature "$SIGNATURE" \
    '{schemaVersion: 1, payload: $payload, signature: $signature}' >"$MANIFEST"

if (( PREPARE_ONLY == 1 )); then
    print "Prepared signed TFT $VERSION feed: $MANIFEST"
    exit 0
fi

[[ -n "$SSH_TARGET" && -n "$REMOTE_ROOT" ]] || {
    print -u2 "Publishing requires MACTICIAN_UPDATE_SSH_TARGET and MACTICIAN_UPDATE_REMOTE_ROOT."
    exit 2
}
[[ "$SSH_PORT" == <1-> ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || {
    print -u2 "MACTICIAN_UPDATE_SSH_PORT must be a TCP port from 1 through 65535."
    exit 2
}
case "$REMOTE_ROOT" in
    "/"|"/var"|"/var/www"|"/usr"|"/etc"|"/home"|"/tmp")
        print -u2 "Refusing unsafe remote update root: $REMOTE_ROOT"
        exit 2
        ;;
esac

remote_quote() {
    print -r -- "'${1//\'/\'\\\'\'}'"
}

readonly REMOTE_RELEASE="$REMOTE_ROOT/game/releases/$BASE_SHA256"
readonly REMOTE_STAGING="$REMOTE_ROOT/game/.release-$BASE_SHA256-$$"
readonly REMOTE_MANIFEST_NEXT="$REMOTE_ROOT/game/.manifest-$$.json"
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
    "mkdir -p -- $(remote_quote "$REMOTE_STAGING") $(remote_quote "$REMOTE_ROOT/game/releases")"
scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    "$RELEASE_ROOT"/*.apk \
    "$SSH_TARGET:$REMOTE_STAGING/"
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
    "mkdir -p -- $(remote_quote "$REMOTE_RELEASE") && chmod 644 -- $(remote_quote "$REMOTE_STAGING")/*.apk && mv -f -- $(remote_quote "$REMOTE_STAGING")/*.apk $(remote_quote "$REMOTE_RELEASE")/ && rmdir -- $(remote_quote "$REMOTE_STAGING")"
scp -P "$SSH_PORT" -o StrictHostKeyChecking=accept-new \
    "$MANIFEST" \
    "$SSH_TARGET:$REMOTE_MANIFEST_NEXT"
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
    "chmod 644 -- $(remote_quote "$REMOTE_MANIFEST_NEXT") && mv -f -- $(remote_quote "$REMOTE_MANIFEST_NEXT") $(remote_quote "$REMOTE_ROOT/game/manifest.json")"

print "Published TFT $VERSION to $UPDATE_BASE_URL/game/manifest.json"
