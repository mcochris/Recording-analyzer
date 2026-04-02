#!/usr/bin/env bash

#
# This script compares the true peak results for a given audio file
# This script is called by check.sh
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Normally, this script is called by check.sh
Usage: $0 --true-peak <value> <audio_file>
Optional: --debug"; exit 1; }

# shellcheck disable=SC1091
source ../common.sh

AUDIO_FILE=""
TRUE_PEAK=""
DEBUG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
			# shellcheck disable=SC2034
            DEBUG="$1"
            shift
            ;;
        --true-peak)
            TRUE_PEAK="$2"
            shift 2
            ;;
        *)
            AUDIO_FILE="$1"
            shift
            ;;
    esac
done

THRESHOLD=$(get_threshold)
debug "Starting true peak check for $AUDIO_FILE"
debug "True peak: $TRUE_PEAK"
debug "THRESHOLD: $THRESHOLD"

readonly TRUE_PEAK AUDIO_FILE THRESHOLD

check_audio_file

[[ -z "$TRUE_PEAK" ]] && { echo "Error: No true peak specified"; exit 1; }

is_number "$TRUE_PEAK" || { echo "Error: true peak is not a valid number"; exit 1; }

if which -s sox; then
	debug "Checking true peak for $AUDIO_FILE with sox"

	true_peak=$(sox "$AUDIO_FILE" --null stats 2>&1 | grep --ignore-case "pk lev db" | cut -w --fields 4) || { echo "ERROR: sox failed to analyze the audio file"; exit 1; }

	debug "Finished checking true peak for $AUDIO_FILE with sox, true peak: $true_peak"

	if within_range "$true_peak" "$TRUE_PEAK"; then
		echo "sox true peak is within threshold"
	else
		echo "sox true peak is not within threshold, calculated $true_peak, expected $TRUE_PEAK, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: sox is not installed or not in PATH"
fi

if which -s loudgain; then
	debug "Checking true peak for $AUDIO_FILE with loudgain"
	TMPFILE=$(get_tempfile) || { echo "ERROR: Failed to create temporary file"; exit 1; }

	loudgain "$AUDIO_FILE" > "$TMPFILE" 2> /dev/null || { echo "ERROR: loudgain failed to analyze the audio file"; rm -f "$TMPFILE"; exit 1; }

	true_peak=$(grep --ignore-case "peak:" "$TMPFILE" | cut -w --fields 4 | tr -d \() || { echo "ERROR: Failed to extract true peak from loudgain output"; rm -f "$TMPFILE"; exit 1; }
	rm -f "$TMPFILE"

	debug "Finished checking true peak for $AUDIO_FILE with loudgain, true peak: $true_peak"

	if within_range "$true_peak" "$TRUE_PEAK"; then
		echo "loudgain true peak is within threshold"
	else
		echo "loudgain true peak is not within threshold, calculated $true_peak, expected $TRUE_PEAK, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: loudgain is not installed or not in PATH"
fi

if which -s ebur128; then
	debug "Checking true peak for $AUDIO_FILE with ebur128"

	true_peak=$(ebur128 "$AUDIO_FILE" | grep --ignore-case "peak level" | cut -w --fields 3) || { echo "ERROR: ebur128 failed to analyze the audio file"; exit 1; }

	debug "Finished checking true peak for $AUDIO_FILE with ebur128, true peak: $true_peak"

	if within_range "$true_peak" "$TRUE_PEAK"; then
		echo "ebur128 true peak is within threshold"
	else
		echo "ebur128 true peak is not within threshold, calculated $true_peak, expected $TRUE_PEAK, threshold ${THRESHOLD}%"
	fi
else
    echo "ERROR: ebur128 is not installed or not in PATH"
fi
