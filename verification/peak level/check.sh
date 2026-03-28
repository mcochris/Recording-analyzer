#!/usr/bin/env bash

#
# This script runs the peak level analysis scripts (peak_level.sh and peak_level.py) on a given audio file
# This script is called by verify.sh
#

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

debug() {
	[[ -n "$DEBUG" ]] && echo "$0: DEBUG[${BASH_LINENO[0]}]: $*"
	return 0
}

debug "Audio file: $AUDIO_FILE"
debug "Left peak level: $LEFT_PEAK_LEVEL"
debug "Right peak level: $RIGHT_PEAK_LEVEL"

[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }

[[ -z "$LEFT_PEAK_LEVEL" ]] && { echo "$0: Error: Left peak level not specified"; exit 1; }
[[ -z "$RIGHT_PEAK_LEVEL" ]] && { echo "$0: Error: Right peak level not specified"; exit 1; }

[[ "$LEFT_PEAK_LEVEL" -eq "$LEFT_PEAK_LEVEL" ]] 2> /dev/null || { echo "$0: Error: Left peak level is not a valid number"; exit 1; }
[[ "$RIGHT_PEAK_LEVEL" -eq "$RIGHT_PEAK_LEVEL" ]] 2> /dev/null || { echo "$0: Error: Right peak level is not a valid number"; exit 1; }

if ! peak_level.sh "$DEBUG" "$AUDIO_FILE" --left-peak-level "$LEFT_PEAK_LEVEL"; then
    echo "$0: Error: peak_level.sh failed for left peak level"
    exit 1
fi

if ! peak_level.sh "$DEBUG" "$AUDIO_FILE" --right-peak-level "$RIGHT_PEAK_LEVEL"; then
    echo "$0: Error: peak_level.sh failed for right peak level"
    exit 1
fi

if ! python3 peak_level.py "$AUDIO_FILE" --left-peak-level "$LEFT_PEAK_LEVEL"; then
    echo "$0: Error: peak_level.py failed for left peak level"
    exit 1
fi

if ! python3 peak_level.py "$AUDIO_FILE" --right-peak-level "$RIGHT_PEAK_LEVEL"; then
    echo "$0: Error: peak_level.py failed for right peak level"
    exit 1
fi