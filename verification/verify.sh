#!/usr/bin/env bash

#
# This script calls all the check.sh scripts in all the verification subdirectories
# This script is manually run by the user.
#

#set -o xtrace

[[ $# -eq 0 ]] && { echo "Usage: $0 <audio_file>"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh" || { echo "Error: Failed to source common.sh"; exit 1; }

readonly HELP="
Audio Recording Analyzer Verification Script
Usage: verify.sh <audio_file>
Example: verify.sh recording.wav

This script runs the recording analyzer on the specified audio file and
extracts key metrics such as peak levels, noise floor, crest factor,
average phase, integrated loudness, true peak, and loudness range. It is
designed to verify that the recording analyzer is functioning correctly
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

REALPATH_AUDIO_FILE="$(realpath "$AUDIO_FILE")"
readonly AUDIO_FILE DEBUG SHOW_HELP REALPATH_AUDIO_FILE

debug "Audio file: $AUDIO_FILE"
debug "Debug mode: $DEBUG"
debug "Audio file (realpath): $REALPATH_AUDIO_FILE"

[[ -n "$SHOW_HELP" ]] && { echo "$HELP"; exit 0; }

check_audio_file "$AUDIO_FILE"

[[ -x "$SCRIPT_DIR/$RECORDING_ANALYZER_PROGRAM" ]] || { echo "Error: Main script not found or not executable: $RECORDING_ANALYZER_PROGRAM"; exit 1; }

ANALYSIS_OUTPUT="$(get_tempfile)"
readonly ANALYSIS_OUTPUT
trap 'rm -f "$ANALYSIS_OUTPUT" 2> /dev/null' EXIT

#
# Run the recording analyzer script and capture its output
#
"$SCRIPT_DIR/$RECORDING_ANALYZER_PROGRAM" "$REALPATH_AUDIO_FILE" > "$ANALYSIS_OUTPUT"

#
# Extract the analysis results
#
LEFT_PEAK_LEVEL=$(grep --ignore-case "Peak level" "$ANALYSIS_OUTPUT" | sed --quiet 1p | awk '{print $3}')
readonly LEFT_PEAK_LEVEL
debug "Left peak level: $LEFT_PEAK_LEVEL"

RIGHT_PEAK_LEVEL=$(grep --ignore-case "Peak level" "$ANALYSIS_OUTPUT" | sed --quiet 2p | awk '{print $3}')
readonly RIGHT_PEAK_LEVEL
debug "Right peak level: $RIGHT_PEAK_LEVEL"

LEFT_NOISE_FLOOR=$(grep --ignore-case "Noise floor" "$ANALYSIS_OUTPUT" | sed --quiet 1p | awk '{print $3}')
readonly LEFT_NOISE_FLOOR
debug "Left noise floor: $LEFT_NOISE_FLOOR"

RIGHT_NOISE_FLOOR=$(grep --ignore-case "Noise floor" "$ANALYSIS_OUTPUT" | sed --quiet 2p | awk '{print $3}')
readonly RIGHT_NOISE_FLOOR
debug "Right noise floor: $RIGHT_NOISE_FLOOR"

LEFT_CREST_FACTOR=$(grep --ignore-case "Crest factor" "$ANALYSIS_OUTPUT" | sed --quiet 1p | awk '{print $3}')
readonly LEFT_CREST_FACTOR
debug "Left crest factor: $LEFT_CREST_FACTOR"

RIGHT_CREST_FACTOR=$(grep --ignore-case "Crest factor" "$ANALYSIS_OUTPUT" | sed --quiet 2p | awk '{print $3}')
readonly RIGHT_CREST_FACTOR
debug "Right crest factor: $RIGHT_CREST_FACTOR"

AVERAGE_PHASE=$(grep --ignore-case "Average phase" "$ANALYSIS_OUTPUT" | awk '{print $3}')
readonly AVERAGE_PHASE
debug "Average phase: $AVERAGE_PHASE"

INTEGRATED_LOUDNESS=$(grep --ignore-case "Integrated loudness" "$ANALYSIS_OUTPUT" | awk '{print $3}')
readonly INTEGRATED_LOUDNESS
debug "Integrated loudness: $INTEGRATED_LOUDNESS"

TRUE_PEAK=$(grep --ignore-case "True peak" "$ANALYSIS_OUTPUT" | awk '{print $3}')
readonly TRUE_PEAK
debug "True peak: $TRUE_PEAK"

LOUDNESS_RANGE=$(grep --ignore-case "Loudness range" "$ANALYSIS_OUTPUT" | awk '{print $3}')
readonly LOUDNESS_RANGE
debug "Loudness range: $LOUDNESS_RANGE"

# Loop through each verification subdirectory and run its checks
# Each subdirectory should contain a script named "check.sh" that performs
# specific checks on the extracted metrics.

for dir in "peak level" "noise floor" "crest factor" "average phase" "integrated loudness" "true peak" "loudness range"; do
    debug "Checking directory: $SCRIPT_DIR/$dir"
	[[ -d "$SCRIPT_DIR/$dir" ]] || { echo "Warning: Directory not found: $SCRIPT_DIR/$dir. Skipping."; continue; }
	if [[ -x "$SCRIPT_DIR/$dir/check.sh" ]]; then
		debug "Running $SCRIPT_DIR/$dir/check.sh"
		cd "$SCRIPT_DIR/$dir" || { echo "ERROR: Failed to change directory to \"$SCRIPT_DIR/$dir\""; exit 1; }
		./check.sh "$DEBUG" --left-peak-level "$LEFT_PEAK_LEVEL" --right-peak-level "$RIGHT_PEAK_LEVEL" --left-noise-floor "$LEFT_NOISE_FLOOR" --right-noise-floor "$RIGHT_NOISE_FLOOR" --left-crest-factor "$LEFT_CREST_FACTOR" --right-crest-factor "$RIGHT_CREST_FACTOR" --average-phase "$AVERAGE_PHASE" --integrated-loudness "$INTEGRATED_LOUDNESS" --true-peak "$TRUE_PEAK" --loudness-range "$LOUDNESS_RANGE" "$REALPATH_AUDIO_FILE"
        debug "Finished running $SCRIPT_DIR/$dir/check.sh"
		cd - > /dev/null || { echo "ERROR: Failed to change directory back to parent from \"$SCRIPT_DIR/$dir\""; exit 1; }
	fi
done
