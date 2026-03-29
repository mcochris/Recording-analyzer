#!/usr/bin/env bash

#
# This script runs the peak level analysis scripts (peak_level.sh and peak_level.py) on a given audio file
# This script is called by verify.sh
#

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --left-peak-level <value> --right-peak-level <value> <audio_file>
Optional: --debug"; exit 1; }

source ../common.sh

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
        --audio-file)
			AUDIO_FILE="$2"
			shift 2
			;;
		*)
			shift
			;;
    esac
done

debug "Starting peak level check for $AUDIO_FILE"

[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }
debug "Audio file: $AUDIO_FILE"

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

./peak_level.sh "$DEBUG" "$AUDIO_FILE" --left-peak-level "$LEFT_PEAK_LEVEL" --right-peak-level "$RIGHT_PEAK_LEVEL"

python3 ./peak_level.py "$AUDIO_FILE" "$LEFT_PEAK_LEVEL" "$RIGHT_PEAK_LEVEL" "$DEBUG"
