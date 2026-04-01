#!/usr/bin/env bash
#
# This file contains common functions and variables used by the recording analyzer tests.
#

# shellcheck disable=SC2034
readonly RECORDING_ANALYZER_PROGRAM="../recording-analyzer.sh"

debug() {
	# This function prints debug messages if the DEBUG environment variable is set.
	[[ -n "$DEBUG" ]] && echo "$0 DEBUG[${BASH_LINENO[0]}]: $*"
	return 0
}

function is_number() {
	# This function checks if the input string is a valid number (integer or floating-point).
	# It returns 0 (true) if the input is a number, or 1 (false) if it is not.
    [[ "$1" =~ ^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]
}

# Deprecated, replaced by test_threshold() which is more robust and handles edge cases better.
#function within_range() {
	# This function checks if the difference between two numbers is within a specified threshold
	# Usage: within_range <value1> <value2>
	# Returns 0 (true) if the values are within the threshold, or 1 (false) if they are not
#    local a="$1"
#    local b="$2"
#    awk "BEGIN { exit !(($a - $b)^2 <= $THRESHOLD^2) }"
#}

function get_threshold() {
	# This function reads the threshold value from threshold.txt, validates it, and returns it as a integer percentage.
	# If the file is missing, unreadable, or contains an invalid value, it defaults to 10%.
	[[ -r "threshold.txt" ]] || { echo "WARNING: threshold.txt not found or not readable, defaulting to 10%"; return 10; }
	THRESHOLD=$(sed --quiet 1p threshold.txt 2> /dev/null)
	[[ -z "$THRESHOLD" ]] && { echo "WARNING: invalid threshold.txt, defaulting to 10%"; return 10; }
	PERCENT=$(echo "$THRESHOLD" | grep --only-matching --extended-regexp "^(100|[1-9][0-9]|[0-9])%$")
	[[ -z "$PERCENT" ]] && { echo "WARNING: invalid threshold.txt , defaulting to 10%"; return 10; }
	THRESHOLD="${PERCENT//%/}"
	[[ -z "$THRESHOLD" ]] && { echo "WARNING: invalid threshold.txt, defaulting to 10%"; return 10; }
	echo "$THRESHOLD"
}

function within_range() {
	# This function compares two numeric values and checks if they are within the threshold percentage of each other.
	# Usage: within_range <value1> <value2>
	# Returns 0 (true) if the values are within the threshold, or 1 (false) if they are not.
	if [[ $# -ne 2 ]]; then
		echo "ERROR: within_range requires exactly 2 arguments, but got $#"
		return 1
	fi
	if ! is_number "$1" || ! is_number "$2"; then
		echo "ERROR: Non-numeric value provided to within_range: '$1' and '$2'"
		return 1
	fi
	THRESHOLD=$(get_threshold)
	debug "Comparing values: $1 and $2 with threshold: ${THRESHOLD}%"
	result=$(bc -l <<< "
		diff = $1 - $2
		if (diff < 0) diff = -diff
		avg = ($1 + $2) / 2
		if (avg < 0) avg = -avg
		if (avg == 0) { 0 } else { diff / avg * 100 < $THRESHOLD }
	")

	if [[ "$result" -eq 1 ]]; then
		return 0
	else
		return 1
	fi
}

function check_audio_file() {
	# This function checks if the specified audio file exists, is a regular file, and is readable.
	# It returns 0 (true) if the file is valid, or 1 (false) if it is not.
	[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
	[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
	[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
	[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }
	return 0
}
