#!/usr/bin/env bash

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

[[ $# -eq 0 ]] && { echo "Usage: $0 <audio_file>"; exit 1; }

readonly VERSION="1.0.0 (2026-03-27)"
readonly HELP="Audio Recording Analyzer Verification Script
Usage: verify.sh <audio_file>
Example: verify.sh recording.wav"

readonly FILE="$1"
[[ "$FILE" == "-?" || "$FILE" == "-h" || "$FILE" == "--help" ]] && { echo "$HELP"; echo ""; exit 0; }
[[ "$FILE" == "-v" || "$FILE" == "--version" ]] && { echo "recording-analyzer.sh version $VERSION"; exit 0; }
[[ -e "$FILE" ]] || { echo "Error: File does not exist: $FILE"; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: File is not a regular file: $FILE"; exit 1; }
[[ -r "$FILE" ]] || { echo "Error: File not readable: $FILE"; exit 1; }

readonly MAIN_SCRIPT="../recording-analyzer.sh"

[[ -x "$MAIN_SCRIPT" ]] || { echo "Error: Main script not found or not executable: $MAIN_SCRIPT"; exit 1; }

ANALYSIS_OUTPUT="$(mktemp)"
readonly ANALYSIS_OUTPUT

#
# Run the recording analyzer script and capture its output
#
"$MAIN_SCRIPT" "$FILE" > "$ANALYSIS_OUTPUT"

#
# Extract and display the analysis results
#
LEFT_PEAK_LEVEL=$(grep --ignore-case "Peak level" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_PEAK_LEVEL
echo "Left peak level: $LEFT_PEAK_LEVEL"

RIGHT_PEAK_LEVEL=$(grep --ignore-case "Peak level" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_PEAK_LEVEL
echo "Right peak level: $RIGHT_PEAK_LEVEL"

LEFT_NOISE_FLOOR=$(grep --ignore-case "Noise floor" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_NOISE_FLOOR
echo "Left noise floor: $LEFT_NOISE_FLOOR"

RIGHT_NOISE_FLOOR=$(grep --ignore-case "Noise floor" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_NOISE_FLOOR
echo "Right noise floor: $RIGHT_NOISE_FLOOR"

LEFT_DYNAMIC_RANGE=$(grep --ignore-case "Dynamic range" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_DYNAMIC_RANGE
echo "Left dynamic range: $LEFT_DYNAMIC_RANGE"

RIGHT_DYNAMIC_RANGE=$(grep --ignore-case "Dynamic range" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_DYNAMIC_RANGE
echo "Right dynamic range: $RIGHT_DYNAMIC_RANGE"

LEFT_CREST_FACTOR=$(grep --ignore-case "Crest factor" "$ANALYSIS_OUTPUT" | sed --quiet 1p | cut -w --fields 4)
readonly LEFT_CREST_FACTOR
echo "Left crest factor: $LEFT_CREST_FACTOR"

RIGHT_CREST_FACTOR=$(grep --ignore-case "Crest factor" "$ANALYSIS_OUTPUT" | sed --quiet 2p | cut -w --fields 4)
readonly RIGHT_CREST_FACTOR
echo "Right crest factor: $RIGHT_CREST_FACTOR"

AVERAGE_PHASE=$(grep --ignore-case "Average phase" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly AVERAGE_PHASE
echo "Average phase: $AVERAGE_PHASE"

INTEGRATED_LOUDNESS=$(grep --ignore-case "Integrated loudness" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly INTEGRATED_LOUDNESS
echo "Integrated loudness: $INTEGRATED_LOUDNESS"

TRUE_PEAK=$(grep --ignore-case "True peak" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly TRUE_PEAK
echo "True peak: $TRUE_PEAK"

LOUDNESS_RANGE=$(grep --ignore-case "Loudness range" "$ANALYSIS_OUTPUT" | cut -w --fields 4)
readonly LOUDNESS_RANGE
echo "Loudness range: $LOUDNESS_RANGE"
