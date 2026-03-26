#!/usr/bin/env bash

# recording_analyzer.sh:
# Analyze peak level, noise floor, dynamic range, crest factor, stereo correlation, and loudness of an audio file.

# Usage: ./recording_analyzer.sh <audio_file>
# Example: ./recording_analyzer.sh recording.wav
# Requirements: ffmpeg, awk, grep, printf, seq, basename, cat
# Version: 1.0 (2026-03-26)

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

for cmd in ffmpeg awk grep printf seq basename cat; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "Error: Required command not found: $cmd" >&2; exit 1; }
done

[[ $# -eq 0 ]] && { echo "Usage: $0 <audio_file>"; exit 1; }

FILE="$1"
[[ -f "$FILE" ]] || { echo "Error: File not found: $FILE"; exit 1; }
[[ -r "$FILE" ]] || { echo "Error: File not readable: $FILE"; exit 1; }

# --- Run astats once and capture output ---
ASTATS=$(ffmpeg -i "$FILE" -af "astats" -f null - 2>&1)

# Check ffmpeg produced expected astats output
if ! grep -q "Channel:" <<< "$ASTATS"; then
    echo "Error: ffmpeg failed to process file."
    exit 1
fi

# --- Extract a named stat from within a specific channel block ---
get_stat() {
    local channel="$1"
    local field="$2"
    echo "$ASTATS" | awk -v ch="Channel: $channel" -v fld="$field" '
        $0 ~ ch        { in_block=1; next }
        in_block && /Channel:/ { in_block=0 }
        in_block && index($0, fld) { print $NF; exit }
    '
}

# --- Detect number of channels ---
NUM_CHANNELS=$(echo "$ASTATS" | grep -c "Channel: [0-9]")

# --- Run loudnorm and capture JSON output ---
LOUDNORM=$(ffmpeg -i "$FILE" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/')

# --- Extract a field from the loudnorm JSON ---
get_loudnorm() {
    local field="$1"
    echo "$LOUDNORM" | grep "\"$field\"" | awk -F'"' '{print $4}'
}

# --- Print header ---
echo ""
echo "Audio Analysis: $(basename "$FILE")"
echo "=================================================="

# --- Per-channel stats ---
for ch in $(seq 1 "$NUM_CHANNELS"); do
    case $ch in
        1) label="Left"  ;;
        2) label="Right" ;;
        *) label="Ch$ch" ;;
    esac

    peak=$(get_stat "$ch" "Peak level dB")
    noise=$(get_stat "$ch" "Noise floor dB")
    dynrange=$(get_stat "$ch" "Dynamic range")
    crest=$(get_stat "$ch" "Crest factor")

	echo ""
    echo "Channel $ch ($label):"
	echo "  Peak Level:     ${peak:-N/A} dB"
	echo "  Noise Floor:    ${noise:-N/A} dB"
	echo "  Dynamic Range:  ${dynrange:-N/A} dB"
	echo "  Crest Factor:   ${crest:-N/A}"
	echo "  (peak should be < 0 dB, noise floor ideally < -60 dB, dynamic range > 20 dB, crest factor > 10)"
done

# --- Stereo correlation (only meaningful for stereo files) ---
if [ "$NUM_CHANNELS" -ge 2 ]; then
    echo ""
    echo "Stereo Correlation:"

    PHASE=$(ffmpeg -i "$FILE" \
        -af "aphasemeter=video=0,ametadata=print:file=-" \
        -f null - 2>/dev/null \
        | awk -F= '/lavfi.aphasemeter.phase/ { sum+=$2; n++ }
                   END { if (n>0) printf "%.4f", sum/n; else print "N/A" }')

    printf "  Average Phase:  %8s\n" "$PHASE"
    echo "  (scale: +1.0 = identical/mono, 0.0 = uncorrelated, -1.0 = phase-inverted)"
fi

# --- Loudness (EBU R128) ---
INPUT_I=$(get_loudnorm "input_i")
INPUT_TP=$(get_loudnorm "input_tp")
INPUT_LRA=$(get_loudnorm "input_lra")

echo ""
echo "Loudness (EBU R128):"
echo "  Integrated Loudness:  ${INPUT_I:-N/A} LUFS"
echo "  True Peak:            ${INPUT_TP:-N/A} dBTP"
echo "  Loudness Range:       ${INPUT_LRA:-N/A} LU"
echo "  (targets: -23 LUFS broadcast, -14 LUFS streaming; true peak < -1 dBTP)"

echo ""
