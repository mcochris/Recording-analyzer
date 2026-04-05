#!/usr/bin/env bash

#
# This script runs the crest factor analysis scripts (crest_factor.sh and crest_factor.py) on a given audio file
# This script is called by verify.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --audio-file <audio_file> --left-crest-factor <value> --right-crest-factor <value>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
DEBUG=""
LEFT_CREST_FACTOR=""
RIGHT_CREST_FACTOR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        --left-crest-factor)
            LEFT_CREST_FACTOR="$2"
            shift 2
            ;;
        --right-crest-factor)
            RIGHT_CREST_FACTOR="$2"
            shift 2
            ;;
		*)
			AUDIO_FILE="$1"
			shift
			;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting crest factor check for $AUDIO_FILE"
debug "Left crest factor: $LEFT_CREST_FACTOR"
debug "Right crest factor: $RIGHT_CREST_FACTOR"
debug "THRESHOLD: $THRESHOLD"

readonly LEFT_CREST_FACTOR RIGHT_CREST_FACTOR AUDIO_FILE DEBUG THRESHOLD

print_header "Checking crest factor for $(basename "$AUDIO_FILE") with threshold ${THRESHOLD}%"

check_audio_file "$AUDIO_FILE"

[[ -z "$LEFT_CREST_FACTOR" && -z "$RIGHT_CREST_FACTOR" ]] && { echo "$0: Error: No crest factors specified"; exit 1; }

if [[ -n "$LEFT_CREST_FACTOR" ]]; then
	is_number "$LEFT_CREST_FACTOR" || { echo "$0: Error: Left crest factor is not a valid number"; exit 1; }
else
    debug "Left crest factor not specified"
fi

if [[ -n "$RIGHT_CREST_FACTOR" ]]; then
	is_number "$RIGHT_CREST_FACTOR" || { echo "$0: Error: Right crest factor is not a valid number"; exit 1; }
else
    debug "Right crest factor not specified"
fi

if check_dependencies "sox" "libsox-fmt-all"; then
    ./crest_factor.sh "$DEBUG" --left-crest-factor "$LEFT_CREST_FACTOR" --right-crest-factor "$RIGHT_CREST_FACTOR" "$AUDIO_FILE"
fi

if check_python_dependencies "soundfile" "numpy"; then
	if valid_python_format "$AUDIO_FILE"; then
		python3 ./crest_factor.py --left-crest-factor "$LEFT_CREST_FACTOR" --right-crest-factor "$RIGHT_CREST_FACTOR" --threshold "$THRESHOLD" "$AUDIO_FILE"
	fi
fi