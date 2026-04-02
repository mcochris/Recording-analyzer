#!/usr/bin/env bash

#
# This script calls all the check.sh scripts in all the verification subdirectories
# This script is manually run by the user.
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Usage: $0 <audio_file>"; exit 1; }

source ./common.sh

readonly HELP="
Audio Recording Analyzer Verification Script
Usage: verify.sh <audio_file>
Example: verify.sh recording.wav

This script runs the recording analyzer on the specified audio file and
extracts key metrics such as peak levels, noise floor, dynamic range, crest
factor, average phase, integrated loudness, true peak, and loudness range.
It is designed to verify that the recording analyzer is functioning correctly
and producing expected results.

Optional flags:
  -d, --debug       Enable debug output
  -h, --help        Show this help message and exit
"

# -----------------------------
# Parse optional flags
# -----------------------------
AUDIO_FILE=""
DEBUG=""
SHOW_HELP=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        -h|--help)
            SHOW_HELP="true"
            shift
            ;;
        *)
			AUDIO_FILE="$1"
            shift
            ;;
    esac
done

readonly AUDIO_FILE DEBUG SHOW_HELP

[[ -n "$SHOW_HELP" ]] && { echo "$HELP"; exit 0; }

check_audio_file "$AUDIO_FILE"

[[ -x "$RECORDING_ANALYZER_PROGRAM" ]] || { echo "Error: Main script not found or not executable: $RECORDING_ANALYZER_PROGRAM"; exit 1; }

ANALYSIS_OUTPUT="$(get_tempfile)"
readonly ANALYSIS_OUTPUT
trap 'rm -f "$ANALYSIS_OUTPUT" 2> /dev/null' EXIT

#
# Run the recording analyzer script and capture its output
#
"$RECORDING_ANALYZER_PROGRAM" "$AUDIO_FILE" > "$ANALYSIS_OUTPUT"

#
# Extract the analysis results
#
LEFT_PEAK_LEVEL=$(grep --ignore-case "Peak level" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_PEAK_LEVEL
debug "Left peak level: $LEFT_PEAK_LEVEL"

RIGHT_PEAK_LEVEL=$(grep --ignore-case "Peak level" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_PEAK_LEVEL
debug "Right peak level: $RIGHT_PEAK_LEVEL"

LEFT_NOISE_FLOOR=$(grep --ignore-case "Noise floor" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_NOISE_FLOOR
debug "Left noise floor: $LEFT_NOISE_FLOOR"

RIGHT_NOISE_FLOOR=$(grep --ignore-case "Noise floor" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_NOISE_FLOOR
debug "Right noise floor: $RIGHT_NOISE_FLOOR"

LEFT_DYNAMIC_RANGE=$(grep --ignore-case "Dynamic range" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_DYNAMIC_RANGE
debug "Left dynamic range: $LEFT_DYNAMIC_RANGE"

RIGHT_DYNAMIC_RANGE=$(grep --ignore-case "Dynamic range" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_DYNAMIC_RANGE
debug "Right dynamic range: $RIGHT_DYNAMIC_RANGE"

LEFT_CREST_FACTOR=$(grep --ignore-case "Crest factor" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_CREST_FACTOR
debug "Left crest factor: $LEFT_CREST_FACTOR"

RIGHT_CREST_FACTOR=$(grep --ignore-case "Crest factor" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_CREST_FACTOR
debug "Right crest factor: $RIGHT_CREST_FACTOR"

AVERAGE_PHASE=$(grep --ignore-case "Average phase" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly AVERAGE_PHASE
debug "Average phase: $AVERAGE_PHASE"

INTEGRATED_LOUDNESS=$(grep --ignore-case "Integrated loudness" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly INTEGRATED_LOUDNESS
debug "Integrated loudness: $INTEGRATED_LOUDNESS"

TRUE_PEAK=$(grep --ignore-case "True peak" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly TRUE_PEAK
debug "True peak: $TRUE_PEAK"

LOUDNESS_RANGE=$(grep --ignore-case "Loudness range" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly LOUDNESS_RANGE
debug "Loudness range: $LOUDNESS_RANGE"

# Loop through each verification subdirectory and run its checks
# Each subdirectory should contain a script named "check.sh" that performs
# specific checks on the extracted metrics.

for dir in "peak level" "noise floor" "dynamic range" "crest factor" "average_phase" "integrated loudness" "true peak" "loudness range"; do
	if [[ -x "$dir/check.sh" ]]; then
		debug "Running $dir/check.sh"
		cd "$dir" || { echo "ERROR: Failed to change directory to \"$dir\""; exit 1; }
		./check.sh "$DEBUG" --left-peak-level "$LEFT_PEAK_LEVEL" --right-peak-level "$RIGHT_PEAK_LEVEL" --left-noise-floor "$LEFT_NOISE_FLOOR" --right-noise-floor "$RIGHT_NOISE_FLOOR" --left-dynamic-range "$LEFT_DYNAMIC_RANGE" --right-dynamic-range "$RIGHT_DYNAMIC_RANGE" --left-crest-factor "$LEFT_CREST_FACTOR" --right-crest-factor "$RIGHT_CREST_FACTOR" --average-phase "$AVERAGE_PHASE" --integrated-loudness "$INTEGRATED_LOUDNESS" --true-peak "$TRUE_PEAK" --loudness-range "$LOUDNESS_RANGE" "$AUDIO_FILE"
		cd .. || { echo "ERROR: Failed to change directory back to parent from \"$dir\""; exit 1; }
	else
		echo "Warning: No executable \"$dir/check.sh\", skipping checks for this directory"
	fi
done
