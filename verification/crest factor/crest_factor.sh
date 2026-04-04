#!/usr/bin/env bash

#
# This script compares the crest factor results for a given audio file with SoX
# This script is called by check.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by verify.sh
Usage: $0 --left-crest-factor <value> --right-crest-factor <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
LEFT_CREST_FACTOR=""
RIGHT_CREST_FACTOR=""
DEBUG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
			# shellcheck disable=SC2034
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
debug "Threshold: ${THRESHOLD}%"

readonly AUDIO_FILE LEFT_CREST_FACTOR RIGHT_CREST_FACTOR THRESHOLD

check_audio_file "$AUDIO_FILE"

if [[ -n "$LEFT_CREST_FACTOR" ]]; then
	debug "Checking left crest factor for $AUDIO_FILE"
	is_number "$LEFT_CREST_FACTOR" || { echo "$0: Error: Left crest factor is not a valid number"; exit 1; }
	read -r crest_factor < <(sox "$AUDIO_FILE" -n remix 1 stats 2>&1 |
		grep --ignore-case "Crest factor" |
		sed --quiet 1p |
		awk '{print $3}')

	debug "SoX reads a Crest factor of $crest_factor for the left channel"

	if ! within_range "$crest_factor" "$LEFT_CREST_FACTOR"; then
		echo "SoX left crest factor is not within threshold, calculated $crest_factor, expected $LEFT_CREST_FACTOR, threshold ${THRESHOLD}%"
	else
		echo "SoX left crest factor is within threshold"
	fi
fi

if [[ -n "$RIGHT_CREST_FACTOR" ]]; then
	debug "Checking right crest factor for $AUDIO_FILE"
	is_number "$RIGHT_CREST_FACTOR" || { echo "$0: Error: Right crest factor is not a valid number"; exit 1; }
	read -r crest_factor < <(sox "$AUDIO_FILE" -n remix 2 stats 2>&1 |
		grep --ignore-case "Crest factor" |
		sed --quiet 1p |
		awk '{print $3}')

	debug "SoX reads a Crest factor of $crest_factor for the right channel"

	if ! within_range "$crest_factor" "$RIGHT_CREST_FACTOR"; then
		echo "SoX right crest factor is not within threshold, calculated $crest_factor, expected $RIGHT_CREST_FACTOR, threshold ${THRESHOLD}%"
	else
		echo "SoX right crest factor is within threshold"
	fi
fi