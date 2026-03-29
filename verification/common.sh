#!/usr/bin/env bash

# shellcheck disable=SC2034
readonly RECORDING_ANALYZER_SCRIPT="../recording-analyzer.sh"

debug() {
	[[ -n "$DEBUG" ]] && echo "$0 DEBUG[${BASH_LINENO[0]}]: $*"
	return 0
}

function is_number() {
    [[ "$1" =~ ^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$ ]]
}

function within_range() {
	# This function checks if the difference between two numbers is within a specified threshold
	# Usage: within_range <value1> <value2>
	# Returns 0 (true) if the values are within the threshold, or 1 (false) if they are not
    local a="$1"
    local b="$2"
    awk "BEGIN { exit !(($a - $b)^2 <= $THRESHOLD^2) }"
}
