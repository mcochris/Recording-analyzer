#!/usr/bin/env bash

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

for cmd in mktemp ffmpeg awk grep printf seq basename cat tput; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "Error: Required command not found: $cmd" >&2; exit 1; }
done

[[ $# -eq 0 ]] && { echo "Usage: $0 <audio_file>"; exit 1; }

HELP="
Audio Recording Analyzer

Usage: recording-analyzer.sh <audio_file>
Example: recording-analyzer.sh recording.wav

This program is used to analyze an audio file and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.

Analyzes an audio file for:
	- Peak level (dBFS)
	- Noise floor (dBFS)
	- Crest factor
	- Stereo correlation (if stereo)
	- Loudness (EBU R128: Integrated, True Peak, Loudness Range)

Requirements: ffmpeg and awk must be available in the system. These are
usually automatically included in most Unix-like systems.

The script uses ffmpeg to analyze the audio file and extract various statistics
about the recording. The ffmpeg astats, loudnorm, aphasemeter, and ametadata
filters are used to analyze the audio file.

Peak level is the maximum absolute amplitude of the audio signal, expressed in
decibels relative to full scale (dBFS). A value of 0 dBFS represents the
maximum possible digital level, while negative values indicate levels below
that. A peak level close to 0 dBFS may indicate potential clipping.

Noise floor is the level of background noise in the recording in dBFS.

Crest factor is the ratio of the peak level to the RMS (root mean square) level
of the audio signal, which can provide insight into the transient characteristics
of the recording. A higher crest factor may indicate a more dynamic recording
with more pronounced peaks.

Stereo correlation measures the similarity between the left and right channels
of a stereo recording. Values close to +1 indicate highly correlated channels
(mono-like), values close to 0 indicate uncorrelated channels (wide stereo),
and values close to -1 indicate anti-correlated channels (out of phase).

Loudness (EBU R128) is a standardized way to measure the perceived loudness of
audio. The integrated loudness represents the overall loudness of the recording,
the true peak indicates the maximum true peak level, and the loudness range
represents the variation in loudness throughout the recording.

Verification of the script's functionality can be done by running it against
known audio files or using other audio analysis tools for cross-validation.
See the verification directory in the GitHub repository for more details.

https://github.com/mcochris/Recording-analyzer
"

FILE="$1"
[[ "$FILE" == "-?" || "$FILE" == "-h" || "$FILE" == "--help" ]] && { echo "$HELP"; exit 0; }
[[ "$FILE" == "-v" || "$FILE" == "--version" ]] && { echo "recording-analyzer.sh version $VERSION"; exit 0; }
[[ -e "$FILE" ]] || { echo "Error: File does not exist: $FILE"; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: File is not a regular file: $FILE"; exit 1; }
[[ -r "$FILE" ]] || { echo "Error: File not readable: $FILE"; exit 1; }

RESULTS_FILE="$(mktemp)"

# --- Spinner ---
spinner() {
    local pid=$1
    local message=${2:-"Working"}
	local frames=('-' '\' '|' '/')
    local i=0

    # Hide cursor
    tput civis

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%s... %s" "$message" "${frames[$i]}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done

    # Clear the spinner line and restore cursor
    printf "\r\033[K"
    tput cnorm
}

long_running_task() {
	# --- Run astats once and capture output ---
	ASTATS=$(ffmpeg -hide_banner -i "$FILE" -af "astats" -f null - 2>&1)

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
	LOUDNORM=$(ffmpeg -hide_banner -i "$FILE" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/')

	# --- Extract a field from the loudnorm JSON ---
	get_loudnorm() {
		local field="$1"
		echo "$LOUDNORM" | grep "\"$field\"" | awk -F'"' '{print $4}'
	}

	# --- Print header ---
	echo ""
	TEXT="Audio Analysis: \"$FILE\""
	echo "$TEXT"
	printf '=%.0s' $(seq 1 ${#TEXT})
	echo ""

	# --- Per-channel stats ---
	for ch in $(seq 1 "$NUM_CHANNELS"); do
		case $ch in
			1) label="Left"  ;;
			2) label="Right" ;;
			*) label="Ch $ch";;
		esac

		peak=$(get_stat "$ch" "Peak level dB")
		noise=$(get_stat "$ch" "Noise floor dB")
#		dynrange=$(get_stat "$ch" "Dynamic range")
		crest=$(get_stat "$ch" "Crest factor")

		echo ""
		echo "Channel $ch ($label):"
		echo "  Peak Level:     ${peak:-N/A} dBFS"
		echo "  Noise Floor:    ${noise:-N/A} dBFS"
#		echo "  Dynamic Range:  ${dynrange:-N/A} dB"
		echo "  Crest Factor:   ${crest:-N/A}"
	done

	# --- Stereo correlation (only meaningful for stereo files) ---
	if [ "$NUM_CHANNELS" -ge 2 ]; then
		echo ""
		echo "Stereo Correlation:"

		PHASE=$(ffmpeg -hide_banner -i "$FILE" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2>/dev/null \
			| awk -F= '/lavfi.aphasemeter.phase/ { sum+=$2; n++ } END { if (n>0) printf "%.4f", sum/n; else print "N/A" }')

		echo "  Average Phase:  ${PHASE:-N/A}"
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
} > "$RESULTS_FILE"

# Run task in background, capture PID, spin until done
long_running_task &
TASK_PID=$!
spinner $TASK_PID "Working"
wait $TASK_PID

cat "$RESULTS_FILE"
rm -f "$RESULTS_FILE" 2>/dev/null
echo ""
