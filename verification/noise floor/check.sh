#!/usr/bin/env bash

#
# This script runs the noise floor analysis script noise_floor.py on a given audio file
# This script is called by verify.sh
#

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --left-peak-level <value> --right-peak-level <value> --audio-file <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh

AUDIO_FILE=""
DEBUG=""
LEFT_NOISE_FLOOR=""
RIGHT_NOISE_FLOOR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
			# shellcheck disable=SC2034
            DEBUG="$1"
            shift
            ;;
        --left-noise-floor)
            LEFT_NOISE_FLOOR="$2"
            shift 2
            ;;
        --right-noise-floor)
            RIGHT_NOISE_FLOOR="$2"
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

debug "Starting noise floor check for $AUDIO_FILE"

[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }
debug "Audio file: $AUDIO_FILE"

[[ -z "$LEFT_NOISE_FLOOR" && -z "$RIGHT_NOISE_FLOOR" ]] && { echo "$0: Error: No noise floor levels specified"; exit 1; }

if [[ -n "$LEFT_NOISE_FLOOR" ]]; then
    debug "Left noise floor: $LEFT_NOISE_FLOOR"
	is_number "$LEFT_NOISE_FLOOR" || { echo "$0: Error: Left noise floor is not a valid number"; exit 1; }
else
    debug "Left noise floor not specified"
fi

if [[ -n "$RIGHT_NOISE_FLOOR" ]]; then
    debug "Right noise floor: $RIGHT_NOISE_FLOOR"
	is_number "$RIGHT_NOISE_FLOOR" || { echo "$0: Error: Right noise floor is not a valid number"; exit 1; }
else
    debug "Right noise floor not specified"
fi

python3 ./noise_floor.py "$AUDIO_FILE" "$LEFT_NOISE_FLOOR" "$RIGHT_NOISE_FLOOR"
