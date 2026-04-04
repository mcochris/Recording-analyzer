#!/usr/bin/env bash

#
# This script compares the loudness range results for a given audio file
# This script is called by check.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by check.sh
Usage: $0 --loudness-range <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh || { echo "ERROR: Failed to source common.sh"; exit 1; }

AUDIO_FILE=""
LOUDNESS_RANGE=""
DEBUG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
			# shellcheck disable=SC2034
            DEBUG="$1"
            shift
            ;;
        --loudness-range)
            LOUDNESS_RANGE="$2"
            shift 2
            ;;
        *)
            AUDIO_FILE="$1"
            shift
            ;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting loudness range check for $AUDIO_FILE"
debug "Loudness range: $LOUDNESS_RANGE"
debug "THRESHOLD: $THRESHOLD"

readonly LOUDNESS_RANGE AUDIO_FILE THRESHOLD

check_audio_file "$AUDIO_FILE"

[[ -z "$LOUDNESS_RANGE" ]] && { echo "Error: No loudness range specified"; exit 1; }

is_number "$LOUDNESS_RANGE" || { echo "Error: loudness range is not a valid number"; exit 1; }

if which -s loudgain; then
	debug "Checking loudness range for $AUDIO_FILE with loudgain"
	TMPFILE=$(get_tempfile) || { echo "ERROR: Failed to create temporary file"; exit 1; }

	loudgain "$AUDIO_FILE" > "$TMPFILE" 2> /dev/null || { echo "ERROR: loudgain failed to analyze the audio file"; rm -f "$TMPFILE"; exit 1; }

	loudness_range=$(grep --ignore-case "range:" "$TMPFILE" | awk '{print $2}' | tr -d \() || { echo "ERROR: Failed to extract loudness range from loudgain output"; rm -f "$TMPFILE"; exit 1; }
	rm -f "$TMPFILE"

	debug "Finished checking loudness range for $AUDIO_FILE with loudgain, loudness range: $loudness_range"

	if within_range "$loudness_range" "$LOUDNESS_RANGE"; then
		echo "loudgain loudness range is within threshold"
	else
		echo "loudgain loudness range is not within threshold, calculated $loudness_range, expected $LOUDNESS_RANGE, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: loudgain is not installed or not in PATH"
fi

if which -s ebur128; then
	debug "Checking loudness range for $AUDIO_FILE with ebur128"

	loudness_range=$(ebur128 "$AUDIO_FILE" | grep --ignore-case "loudness range" | awk '{print $3}') || { echo "ERROR: ebur128 failed to analyze the audio file"; exit 1; }

	debug "Finished checking loudness range for $AUDIO_FILE with ebur128, loudness range: $loudness_range"

	if within_range "$loudness_range" "$LOUDNESS_RANGE"; then
		echo "ebur128 loudness range is within threshold"
	else
		echo "ebur128 loudness range is not within threshold, calculated $loudness_range, expected $LOUDNESS_RANGE, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: ebur128 is not installed or not in PATH"
fi
