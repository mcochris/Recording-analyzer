#!/usr/bin/env bash
#
# This file contains common functions and variables used by the recording analyzer tests.
#
# This script is sourced by the test scripts in the verification directory.
# It provides common functions and variables for the tests.
#

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

# shellcheck disable=SC2034
readonly RECORDING_ANALYZER_PROGRAM="../recording-analyzer.sh"

#
# Set up a custom temporary directory for the tests to avoid conflicts with other processes.
#
function get_tempfile() {
	readonly TMPDIR_NAME="recording-analyzer"
	tmpdir_location=$(dirname "$(mktemp --quiet --dry-run)") || { echo "ERROR: Failed to get OS's temporary directory"; exit 1; }
	readonly tmpdir_location
	[[ -d "$tmpdir_location/$TMPDIR_NAME" ]] || mkdir "$tmpdir_location/$TMPDIR_NAME" || { echo "ERROR: Failed to create temporary directory in $tmpdir_location/$TMPDIR_NAME"; exit 1; }
	tmpfile=$(mktemp --tmpdir="$tmpdir_location/$TMPDIR_NAME") || { echo "ERROR: Failed to create temporary file"; exit 1; }
	readonly tmpfile
	echo "$tmpfile"
}

function debug() {
	# This function prints debug messages if the DEBUG variable is set.
	[[ -n "$DEBUG" ]] && echo "$0 DEBUG[${BASH_LINENO[0]}]: $*"
	return 0
}

function is_number() {
	# This function checks if the input string is a valid number (integer or floating-point).
	# It returns 0 (true) if the input is a number, or 1 (false) if it is not.
    [[ "$1" =~ ^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?|inf$ ]]
}

function get_threshold() {
	# This function reads the threshold value from threshold.txt, validates it, and returns it as a integer percentage.
	# If the file is missing, unreadable, or contains an invalid value, it defaults to 10%.
	[[ -r "threshold.txt" ]] || { echo "WARNING: threshold.txt not found or not readable, defaulting to 10%"; return 10; }
	threshold=$(sed --quiet 1p threshold.txt 2> /dev/null)
	[[ -z "$threshold" ]] && { echo "WARNING: invalid threshold.txt, defaulting to 10%"; return 10; }
	percent=$(echo "$threshold" | grep --only-matching --extended-regexp "^(100|[1-9][0-9]|[0-9])%$")
	[[ -z "$percent" ]] && { echo "WARNING: invalid threshold.txt, defaulting to 10%"; return 10; }
	threshold="${percent//%/}"
	[[ -z "$threshold" ]] && { echo "WARNING: invalid threshold.txt, defaulting to 10%"; return 10; }
	echo "$threshold"
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
	threshold=$(get_threshold)
	debug "Comparing values: $1 and $2 with threshold: ${threshold}%"
	result=$(bc -l <<< "
		diff = $1 - $2
		if (diff < 0) diff = -diff
		avg = ($1 + $2) / 2
		if (avg < 0) avg = -avg
		if (avg == 0) { 0 } else { diff / avg * 100 < $threshold}
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
	[[ $# -ne 1 ]] && { echo "ERROR: check_audio_file requires exactly 1 argument, but got $#"; exit 1; }
	local file="$1"
	[[ -z "$file" ]] && { echo "$0: ERROR: No audio file specified"; exit 1; }
	[[ -e "$file" ]] || { echo "$0: ERROR: Audio file does not exist: $file"; exit 1; }
	[[ -f "$file" ]] || { echo "$0: ERROR: Audio file is not a regular file: $file"; exit 1; }
	[[ -r "$file" ]] || { echo "$0: ERROR: Audio file is not readable: $file"; exit 1; }
	return 0
}

function print_header() {
	echo ""
	header="$1"
	echo "$header"
	printf '=%.0s' $(seq 1 ${#header})
	echo ""
}

function check_dependencies() {
    local missing=0

    for dep in "$@"; do
        if command -v "$dep" &>/dev/null; then
            : # found via PATH
        elif dpkg-query -W -f='${Status}' "$dep" 2>/dev/null | grep --quiet "install ok installed"; then
            : # found via dpkg
        else
            echo "ERROR: $dep is not installed or not in PATH"
            missing=1
        fi
    done

    return $missing
}

function check_python_dependencies() {
	local missing=0

	for dep in "$@"; do
		if python3 -c "import $dep" &>/dev/null; then
			: # found via Python
		else
			echo "ERROR: Python module '$dep' is not installed"
			missing=1
		fi
	done

	return $missing
}

function valid_sox_format() {
	local filename="$1"
	local format="${filename##*.}"
	case "$format" in
		"wav"|"flac"|"ogg"|"mp3")
			return 0
			;;
		*)
			echo "ERROR: Unsupported SoX audio format: $format"
			return 1
			;;
	esac
}