#!/usr/bin/env bash

#
# This script runs the noise floor analysis script noise_floor.py on a given audio file
# This script is called by verify.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --left-noise-floor <value> --right-noise-floor <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

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
		*)
			AUDIO_FILE="$1"
			shift
			;;
    esac
done

THRESHOLD="$(get_threshold)"
debug "Starting noise floor check for $AUDIO_FILE"
debug "Left noise floor: $LEFT_NOISE_FLOOR"
debug "Right noise floor: $RIGHT_NOISE_FLOOR"
debug "Threshold: ${THRESHOLD}%"

readonly AUDIO_FILE THRESHOLD

print_header "Checking noise floor for $(basename "$AUDIO_FILE") with threshold ${THRESHOLD}%"

check_audio_file "$AUDIO_FILE"

[[ -z "$LEFT_NOISE_FLOOR" && -z "$RIGHT_NOISE_FLOOR" ]] && { echo "$0: Error: No noise floor levels specified"; exit 1; }

if [[ -n "$LEFT_NOISE_FLOOR" ]]; then
	is_number "$LEFT_NOISE_FLOOR" || { echo "$0: Error: Left noise floor is not a valid number"; exit 1; }
else
    debug "Left noise floor not specified"
fi

if [[ -n "$RIGHT_NOISE_FLOOR" ]]; then
	is_number "$RIGHT_NOISE_FLOOR" || { echo "$0: Error: Right noise floor is not a valid number"; exit 1; }
else
    debug "Right noise floor not specified"
fi

if [[ "$LEFT_NOISE_FLOOR" == "-inf" ]]; then
    LEFT_NOISE_FLOOR=-99.99
fi

if [[ "$RIGHT_NOISE_FLOOR" == "-inf" ]]; then
    RIGHT_NOISE_FLOOR=-99.99
fi

if check_python_dependencies "soundfile" "numpy"; then
	python3 ./noise_floor.py --left-noise-floor "$LEFT_NOISE_FLOOR" --right-noise-floor "$RIGHT_NOISE_FLOOR" --threshold "$THRESHOLD" "$AUDIO_FILE"
fi
