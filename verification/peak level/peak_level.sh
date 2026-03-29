#!/usr/bin/env bash

#
# This script compares the peak level results for a given audio file with SoX
# This script is called by check.sh
#

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

[[ $# -eq 0 ]] && { echo "Normally, this script is called by check.sh
Usage: $0 --left-peak-level <value> --right-peak-level <value> <audio_file>
Optional: --debug"; exit 1; }

source ../common.sh

THRESHOLD=$(cat threshold.txt)
readonly THRESHOLD

AUDIO_FILE=""
LEFT_PEAK_LEVEL=""
RIGHT_PEAK_LEVEL=""
DEBUG=""
EXIT_CODE=0

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

debug "Starting peak level check for $AUDIO_FILE"
debug "Left peak level: $LEFT_PEAK_LEVEL"
debug "Right peak level: $RIGHT_PEAK_LEVEL"

[[ -z "$THRESHOLD" ]] && { echo "$0: Error: THRESHOLD variable is not set"; exit 1; }
is_number "$THRESHOLD" || { echo "$0: Error: THRESHOLD variable is not a valid number"; exit 1; }
debug "THRESHOLD: $THRESHOLD"

[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }

[[ -z "$LEFT_PEAK_LEVEL" && -z "$RIGHT_PEAK_LEVEL" ]] && { echo "$0: Error: No peak levels specified"; exit 1; }

is_number "$LEFT_PEAK_LEVEL" || { echo "$0: Error: Left peak level is not a valid number"; exit 1; }
is_number "$RIGHT_PEAK_LEVEL" || { echo "$0: Error: Right peak level is not a valid number"; exit 1; }

if [[ -n "$LEFT_PEAK_LEVEL" ]]; then
	debug "Checking left peak level for $AUDIO_FILE"
	read -r max_amplitude < <(sox "$AUDIO_FILE" -n remix 1 stat 2>&1 |
		grep --ignore-case "Maximum amplitude" |
		sed --quiet 1p |
		cut -w --fields 3)

	debug "SoX reads a Max amplitude of $max_amplitude for the left channel"

	dBFS=$(echo "20 * l($max_amplitude) / l(10)" | bc -l)

	debug "Calculated dBFS for the left channel: $dBFS"

	if ! within_range "$dBFS" "$LEFT_PEAK_LEVEL"; then
		echo "$0: SoX left peak level is not within threshold, calculated $dBFS dBFS, expected $LEFT_PEAK_LEVEL dBFS, threshold $THRESHOLD dB"
	else
		echo "$0: SoX left peak level is within threshold"
	fi
fi

if [[ -n "$RIGHT_PEAK_LEVEL" ]]; then
	debug "Checking right peak level for $AUDIO_FILE"
	read -r max_amplitude < <(sox "$AUDIO_FILE" -n remix 2 stat 2>&1|
		grep --ignore-case "Maximum amplitude" |
		sed --quiet 1p |
		cut -w --fields 3)

	debug "SoX reads a Max amplitude of $max_amplitude for the right channel"

	dBFS=$(echo "20 * l($max_amplitude) / l(10)" | bc -l)

	debug "Calculated dBFS for the right channel: $dBFS"

	if ! within_range "$dBFS" "$RIGHT_PEAK_LEVEL"; then
		echo "$0: SoX right peak level is not within threshold, calculated $dBFS dBFS, expected $RIGHT_PEAK_LEVEL dBFS, threshold $THRESHOLD dB"
	else
		echo "$0: SoX right peak level is within threshold"
	fi
fi