#!/usr/bin/env bash

#
# This script runs the peak level analysis scripts (peak_level.sh and peak_level.py) on a given audio file
# This script is called by verify.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --left-peak-level <value> --right-peak-level <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
DEBUG=""
LEFT_PEAK_LEVEL=""
RIGHT_PEAK_LEVEL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        --left-peak-level)
            LEFT_PEAK_LEVEL="$2"
            shift 2
            ;;
        --right-peak-level)
            RIGHT_PEAK_LEVEL="$2"
            shift 2
            ;;
        *)
			AUDIO_FILE="$1"
			shift
			;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting peak level check for $AUDIO_FILE"
debug "Left peak level: $LEFT_PEAK_LEVEL"
debug "Right peak level: $RIGHT_PEAK_LEVEL"
debug "Threshold: ${THRESHOLD}%"

readonly AUDIO_FILE DEBUG LEFT_PEAK_LEVEL RIGHT_PEAK_LEVEL THRESHOLD

print_header "Checking peak level for $(basename "$AUDIO_FILE") with threshold ${THRESHOLD}%"

check_audio_file "$AUDIO_FILE"

[[ -z "$LEFT_PEAK_LEVEL" && -z "$RIGHT_PEAK_LEVEL" ]] && { echo "$0: Error: No peak levels specified"; exit 1; }

if [[ -n "$LEFT_PEAK_LEVEL" ]]; then
    debug "Left peak level: $LEFT_PEAK_LEVEL"
	is_number "$LEFT_PEAK_LEVEL" || { echo "$0: Error: Left peak level is not a valid number"; exit 1; }
else
    debug "Left peak level not specified"
fi

if [[ -n "$RIGHT_PEAK_LEVEL" ]]; then
    debug "Right peak level: $RIGHT_PEAK_LEVEL"
	is_number "$RIGHT_PEAK_LEVEL" || { echo "$0: Error: Right peak level is not a valid number"; exit 1; }
else
    debug "Right peak level not specified"
fi

./peak_level.sh "$DEBUG" --left-peak-level "$LEFT_PEAK_LEVEL" --right-peak-level "$RIGHT_PEAK_LEVEL" "$AUDIO_FILE"

python3 ./peak_level.py --left-peak-level "$LEFT_PEAK_LEVEL" --right-peak-level "$RIGHT_PEAK_LEVEL" --threshold "$THRESHOLD" "$AUDIO_FILE"
