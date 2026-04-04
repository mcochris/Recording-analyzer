#!/usr/bin/env bash

#
# This script runs the loudness range analysis scripts on a given audio file
# This script is called by verify.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --loudness-range <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
DEBUG=""
LOUDNESS_RANGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        --loudness-range)
            LOUDNESS_RANGE="$2"
            shift 2
            ;;
        *)
			AUDIO_FILE="$1"
			shift
			;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting loudness range check for $AUDIO_FILE"
debug "Loudness range: $LOUDNESS_RANGE"
debug "Threshold: ${THRESHOLD}%"

readonly LOUDNESS_RANGE AUDIO_FILE DEBUG THRESHOLD

print_header "Checking loudness range for $(basename "$AUDIO_FILE") with threshold ${THRESHOLD}%"

check_audio_file "$AUDIO_FILE"

[[ -z "$LOUDNESS_RANGE" ]] && { echo "$0: Error: No loudness range specified"; exit 1; }

is_number "$LOUDNESS_RANGE" || { echo "$0: Error: Loudness range is not a valid number"; exit 1; }

./loudness_range.sh "$DEBUG" --loudness-range "$LOUDNESS_RANGE" "$AUDIO_FILE"
