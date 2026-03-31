#!/usr/bin/env bash

#
# This script runs the crest factor analysis scripts (crest_factor.sh and crest_factor.py) on a given audio file
# This script is called by verify.sh
#

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --audio-file <audio_file> --left-crest-factor <value> --right-crest-factor <value>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh

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
        --audio-file)
			AUDIO_FILE="$2"
			shift 2
			;;
		*)
			shift
			;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting crest factor check for $AUDIO_FILE"
debug "Left crest factor: $LEFT_CREST_FACTOR"
debug "Right crest factor: $RIGHT_CREST_FACTOR"
debug "THRESHOLD: $THRESHOLD"

[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }

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

./crest_factor.sh "$DEBUG" --audio-file "$AUDIO_FILE" --left-crest-factor "$LEFT_CREST_FACTOR" --right-crest-factor "$RIGHT_CREST_FACTOR"

python3 ./crest_factor.py --audio-file "$AUDIO_FILE" --left-crest-factor "$LEFT_CREST_FACTOR" --right-crest-factor "$RIGHT_CREST_FACTOR" --threshold "$THRESHOLD"
