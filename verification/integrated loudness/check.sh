#!/usr/bin/env bash

#
# This script runs the integrated loudness analysis scripts on a given audio file
# This script is called by verify.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --integrated-loudness <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
DEBUG=""
INTEGRATED_LOUDNESS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        --integrated-loudness)
            INTEGRATED_LOUDNESS="$2"
            shift 2
            ;;
        *)
			AUDIO_FILE="$1"
			shift
			;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting integrated loudness check for $AUDIO_FILE"
debug "Integrated loudness: $INTEGRATED_LOUDNESS"
debug "Threshold: ${THRESHOLD}%"

readonly INTEGRATED_LOUDNESS AUDIO_FILE DEBUG THRESHOLD

print_header "Checking integrated loudness for $(basename "$AUDIO_FILE") with threshold ${THRESHOLD}%"

check_audio_file "$AUDIO_FILE"

[[ -z "$INTEGRATED_LOUDNESS" ]] && { echo "$0: Error: No integrated loudness specified"; exit 1; }

is_number "$INTEGRATED_LOUDNESS" || { echo "$0: Error: Integrated loudness is not a valid number"; exit 1; }

if check_dependencies "bs1770gain" "loudgain"; then
    ./integrated_loudness.sh "$DEBUG" --integrated-loudness "$INTEGRATED_LOUDNESS" "$AUDIO_FILE"
fi