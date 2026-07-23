#!/usr/bin/env bash
#
# redact_sensitive.sh
#
# Scans a directory for IPv4, IPv6, and MAC addresses and replaces them with
# placeholder tags (<ip_addr>, <ip6_addr>, <mac_addr>) before a git push.
#
# Usage:
#   ./redact_sensitive.sh [options] <directory>
#
# Options:
#   -n, --dry-run       Report matches without modifying any files
#   -b, --backup        Keep a .bak copy of every modified file
#   -e, --ext EXT       Only process files with this extension (repeatable)
#                        e.g. -e log -e txt
#   -x, --exclude GLOB  Skip files/dirs matching glob (repeatable)
#   -v, --verbose       Print each file as it's processed
#   -h, --help          Show this help
#
# Exit codes:
#   0 = success
#   1 = bad usage
#   2 = target directory not found
#
set -euo pipefail

# ---------- defaults ----------
DRY_RUN=0
BACKUP=0
VERBOSE=0
declare -a EXTS=()
declare -a EXCLUDES=()
TARGET_DIR=""

# ---------- placeholders ----------
IP_PLACEHOLDER="<ip_addr>"
IP6_PLACEHOLDER="<ip6_addr>"
MAC_PLACEHOLDER="<mac_addr>"

# ---------- regex patterns ----------
# Strict IPv4: each octet 0-255, word-boundary guarded so we don't chew into
# version strings like "10.0.0.68123" or match inside longer numbers.
IPV4_OCTET='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
IPV4_REGEX="\\b(${IPV4_OCTET}\\.){3}${IPV4_OCTET}\\b"

# MAC address: six colon- or hyphen-separated hex pairs.
MAC_REGEX='\b([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b'

# IPv6: covers full and common compressed "::" forms. Not a fully exhaustive
# RFC 4291 validator, but catches the vast majority of real-world addresses
# without false-positive matching on things like timestamps.
IPV6_REGEX='\b((([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){1,7}:)|(([0-9A-Fa-f]{1,4}:){1,6}:[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){1,5}(:[0-9A-Fa-f]{1,4}){1,2})|(([0-9A-Fa-f]{1,4}:){1,4}(:[0-9A-Fa-f]{1,4}){1,3})|(([0-9A-Fa-f]{1,4}:){1,3}(:[0-9A-Fa-f]{1,4}){1,4})|(([0-9A-Fa-f]{1,4}:){1,2}(:[0-9A-Fa-f]{1,4}){1,5})|([0-9A-Fa-f]{1,4}:((:[0-9A-Fa-f]{1,4}){1,6}))|(:((:[0-9A-Fa-f]{1,4}){1,7}|:)))\b'

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

log() {
  [[ "$VERBOSE" -eq 1 ]] && echo "$@" >&2 || true
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    -b|--backup) BACKUP=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -e|--ext) EXTS+=("$2"); shift 2 ;;
    -x|--exclude) EXCLUDES+=("$2"); shift 2 ;;
    -h|--help) usage 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
      else
        echo "Unexpected extra argument: $1" >&2
        usage 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: no target directory given." >&2
  usage 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: '$TARGET_DIR' is not a directory." >&2
  exit 2
fi

# ---------- build find command ----------
find_args=("$TARGET_DIR" -type f)

# Never touch git internals
find_args+=(-not -path '*/.git/*')

if [[ ${#EXCLUDES[@]} -gt 0 ]]; then
  for pattern in "${EXCLUDES[@]}"; do
    find_args+=(-not -path "$pattern")
  done
fi

if [[ ${#EXTS[@]} -gt 0 ]]; then
  find_args+=('(')
  first=1
  for ext in "${EXTS[@]}"; do
    [[ $first -eq 0 ]] && find_args+=(-o)
    find_args+=(-iname "*.${ext}")
    first=0
  done
  find_args+=(')')
fi

# ---------- stats ----------
total_files=0
modified_files=0
total_ip_hits=0
total_ip6_hits=0
total_mac_hits=0

# ---------- helper: is this a text file? ----------
is_text_file() {
  local f="$1"
  file --mime-encoding -b "$f" 2>/dev/null | grep -qv 'binary'
}

process_file() {
  local f="$1"

  if ! is_text_file "$f"; then
    log "skip (binary): $f"
    return
  fi

  total_files=$((total_files + 1))

  local ip_hits mac_hits ip6_hits
  ip_hits=$(grep -oE "$IPV4_REGEX" "$f" 2>/dev/null | wc -l | tr -d ' ')
  mac_hits=$(grep -oE "$MAC_REGEX" "$f" 2>/dev/null | wc -l | tr -d ' ')
  ip6_hits=$(grep -oiE "$IPV6_REGEX" "$f" 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$ip_hits" -eq 0 && "$mac_hits" -eq 0 && "$ip6_hits" -eq 0 ]]; then
    log "clean: $f"
    return
  fi

  echo "MATCH  $f  (ipv4=$ip_hits mac=$mac_hits ipv6=$ip6_hits)"
  total_ip_hits=$((total_ip_hits + ip_hits))
  total_mac_hits=$((total_mac_hits + mac_hits))
  total_ip6_hits=$((total_ip6_hits + ip6_hits))

  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi

  if [[ "$BACKUP" -eq 1 ]]; then
    cp -p -- "$f" "$f.bak"
  fi

  # Order matters: MAC and IPv6 first (more specific), IPv4 last, so we don't
  # let an IPv4-inside-IPv6 substring get consumed prematurely.
  sed -i -E \
    -e "s/${MAC_REGEX}/${MAC_PLACEHOLDER}/g" \
    "$f"
  sed -i -E \
    -e "s/${IPV6_REGEX}/${IP6_PLACEHOLDER}/gI" \
    "$f" 2>/dev/null || \
  sed -i -E \
    -e "s/${IPV6_REGEX}/${IP6_PLACEHOLDER}/g" \
    "$f"
  sed -i -E \
    -e "s/${IPV4_REGEX}/${IP_PLACEHOLDER}/g" \
    "$f"

  modified_files=$((modified_files + 1))
}

echo "Scanning '$TARGET_DIR' ..."
[[ "$DRY_RUN" -eq 1 ]] && echo "(dry run — no files will be modified)"
echo

while IFS= read -r -d '' file; do
  process_file "$file"
done < <(find "${find_args[@]}" -print0)

echo
echo "----------------------------------------"
echo "Files scanned:     $total_files"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Files with hits:   (see MATCH lines above)"
else
  echo "Files modified:    $modified_files"
fi
echo "IPv4 matches:       $total_ip_hits"
echo "IPv6 matches:       $total_ip6_hits"
echo "MAC matches:        $total_mac_hits"
echo "----------------------------------------"

if [[ "$DRY_RUN" -eq 1 && $((total_ip_hits + total_ip6_hits + total_mac_hits)) -gt 0 ]]; then
  echo "Run again without --dry-run to apply redaction."
fi
