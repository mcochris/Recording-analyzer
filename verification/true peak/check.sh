#!/usr/bin/env bash

#
# This script runs the true peak analysis scripts on a given audio file
# This script is called by verify.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --true-peak <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
DEBUG=""
TRUE_PEAK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        --true-peak)
            TRUE_PEAK="$2"
            shift 2
            ;;
        *)
			AUDIO_FILE="$1"
			shift
			;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting true peak check for $AUDIO_FILE"
debug "True peak: $TRUE_PEAK"
debug "Threshold: ${THRESHOLD}%"

readonly TRUE_PEAK AUDIO_FILE DEBUG THRESHOLD

print_header "Checking true peak for $(basename "$AUDIO_FILE") with threshold ${THRESHOLD}%"

check_audio_file "$AUDIO_FILE"

[[ -z "$TRUE_PEAK" ]] && { echo "$0: Error: No true peak specified"; exit 1; }

is_number "$TRUE_PEAK" || { echo "$0: Error: True peak is not a valid number"; exit 1; }

if check_dependencies "sox" "libsox-fmt-all" "ebur128" "loudgain"; then
    ./true_peak.sh "$DEBUG" --true-peak "$TRUE_PEAK" "$AUDIO_FILE"
fi