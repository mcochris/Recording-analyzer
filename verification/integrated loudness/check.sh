#!/usr/bin/env bash

#
# This script runs the integrated loudness analysis scripts on a given audio file
# This script is called by verify.sh
#

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --audio-file <audio_file> --integrated-loudness <value>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh

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
debug "Starting integrated loudness check for $AUDIO_FILE"
debug "Integrated loudness: $INTEGRATED_LOUDNESS"
debug "THRESHOLD: $THRESHOLD"

check_audio_file

[[ -z "$INTEGRATED_LOUDNESS" ]] && { echo "$0: Error: No integrated loudness specified"; exit 1; }

is_number "$INTEGRATED_LOUDNESS" || { echo "$0: Error: Integrated loudness is not a valid number"; exit 1; }

./integrated_loudness.sh "$DEBUG" --audio-file "$AUDIO_FILE" --integrated-loudness "$INTEGRATED_LOUDNESS"
