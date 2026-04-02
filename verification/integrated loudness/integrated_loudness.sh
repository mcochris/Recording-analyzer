#!/usr/bin/env bash

#
# This script compares the crest factor results for a given audio file with SoX
# This script is called by check.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by check.sh
Usage: $0 --integrated-loudness <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh

AUDIO_FILE=""
INTEGRATED_LOUDNESS=""
DEBUG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
			# shellcheck disable=SC2034
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

[[ -z "$INTEGRATED_LOUDNESS" ]] && { echo "Error: No integrated loudness specified"; exit 1; }

is_number "$INTEGRATED_LOUDNESS" || { echo "Error: integrated loudness is not a valid number"; exit 1; }

if which -s bs1770gain; then
	debug "Checking integrated loudness for $AUDIO_FILE with bs1770gain"
	TMPFILE=$(get_tempfile) || { echo "ERROR: Failed to create temporary file"; exit 1; }

	bs1770gain "$AUDIO_FILE" > "$TMPFILE" 2> /dev/null || { echo "ERROR: bs1770gain failed to analyze the audio file"; rm -f "$TMPFILE"; exit 1; }

	loudness=$(grep --ignore-case --max-count=1 "Integrated (momentary mean):" "$TMPFILE" | cut -w --fields 5)
	rm -f "$TMPFILE"

	debug "Finished checking integrated loudness for $AUDIO_FILE with bs1770gain, loudness: $loudness"

	if within_range "$loudness" "$INTEGRATED_LOUDNESS"; then
		echo "bs1770gain integrated loudness is within threshold"
	else
		echo "bs1770gain integrated loudness is not within threshold, calculated $loudness, expected $INTEGRATED_LOUDNESS, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: bs1770gain is not installed or not in PATH"
fi

if which -s loudgain; then
	debug "Checking integrated loudness for $AUDIO_FILE with loudgain"
	TMPFILE=$(get_tempfile) || { echo "ERROR: Failed to create temporary file"; exit 1; }

	loudgain "$AUDIO_FILE" > "$TMPFILE" 2> /dev/null || { echo "ERROR: loudgain failed to analyze the audio file"; rm -f "$TMPFILE"; exit 1; }

	loudness=$(grep --ignore-case --max-count=1 "loudness:" "$TMPFILE" | cut -w --fields 3)
	rm -f "$TMPFILE"

	debug "Finished checking integrated loudness for $AUDIO_FILE with loudgain, loudness: $loudness"

	if within_range "$loudness" "$INTEGRATED_LOUDNESS"; then
		echo "loudgain integrated loudness is within threshold"
	else
		echo "loudgain integrated loudness is not within threshold, calculated $loudness, expected $INTEGRATED_LOUDNESS, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: loudgain is not installed or not in PATH"
fi
