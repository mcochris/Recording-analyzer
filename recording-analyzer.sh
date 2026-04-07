#!/usr/bin/env bash

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

for cmd in ffmpeg awk seq tput; do
	command -v "$cmd" >/dev/null 2>&1 || { echo "Error: Required command not found: $cmd" >&2; exit 1; }
done

[[ $# -eq 0 ]] && { echo "Usage: $0 <audio_file>"; exit 1; }

readonly HELP="
Audio Recording Analyzer

Usage: recording-analyzer.sh <audio_file>
Example: recording-analyzer.sh recording.wav

This program is used to analyze an audio file and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.
"

readonly VERSION="1.0.0"
JSON_OUTPUT="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
		-\?|-h|--help)
			echo "$HELP"
			exit 0
			;;
		-v|--version)
			echo "recording-analyzer.sh version $VERSION"
			exit 0
			;;
        -j|--json)
            JSON_OUTPUT="true"
            shift
            ;;
        *)
			FILE="$1"
			shift
			;;
    esac
done

[[ -e "$FILE" ]] || { echo "Error: File does not exist: $FILE"; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: File is not a regular file: $FILE"; exit 1; }
[[ -r "$FILE" ]] || { echo "Error: File not readable: $FILE"; exit 1; }

RESULTS_FILE="$(mktemp)"
readonly RESULTS_FILE
readonly JSON_OUTPUT
readonly FILE

#
# Spinner function to show progress while long-running task is executing
#
function spinner() {
    local pid="$1"
    local message="$2"
	# shellcheck disable=SC1003
	local frames=('-' '\' '|' '/')
    local i=0

    # Hide cursor
    tput civis 1>&2

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%s... %s" "$message" "${frames[$i]}" 1>&2
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done

    # Clear the spinner line and restore cursor
    printf "\r\033[K" 1>&2
    tput cnorm 1>&2
}

function long_running_task() {
	# Run ffmpeg with astats filter to get per-channel statistics
	ASTATS=$(ffmpeg -hide_banner -i "$FILE" -af "astats" -f null - 2>&1)
	readonly ASTATS

	# Check ffmpeg produced expected astats output
	if ! grep -q "Channel:" <<< "$ASTATS"; then
		echo "Error: ffmpeg failed to process file."
		exit 1
	fi

	# Extract a named stat from within a specific channel block
	function get_stat() {
		local channel="$1"
		local field="$2"
			echo "$ASTATS" | awk -v ch="Channel: $channel" -v fld="$field" '
				$0 ~ ch        { in_block=1; next }
				in_block && /Channel:/ { in_block=0 }
				in_block && index($0, fld) { print $NF; exit }
			'
	}

	# Detect number of channels
	NUM_CHANNELS=$(echo "$ASTATS" | grep -c "Channel: [0-9]")
	if [[ "$NUM_CHANNELS" -ne 2 ]]; then
		echo "Error: not a stereo file."
		exit 1
	fi

	# Run loudnorm and capture JSON output
	LOUDNORM=$(ffmpeg -hide_banner -i "$FILE" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/')
	readonly LOUDNORM

	# Extract a field from the loudnorm JSON
	function get_loudnorm() {
		local field="$1"
		echo "$LOUDNORM" | grep "\"$field\"" | awk -F'"' '{print $4}'
	}

	# Print header and per-channel stats to results file
	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		TEXT="Audio Analysis: \"$FILE\""
		echo "$TEXT"
		printf '=%.0s' $(seq 1 ${#TEXT})
		echo ""
	fi

	# Per-channel stats
	left_peak=$(get_stat 1 "Peak level dB")
	left_noise=$(get_stat 1 "Noise floor dB")
	left_crest=$(get_stat 1 "Crest factor")

	left_rounded_peak=$(printf "%.2f" "$left_peak")
	left_rounded_noise=$(printf "%.2f" "$left_noise")
	left_rounded_crest=$(printf "%.2f" "$left_crest")

	right_peak=$(get_stat 2 "Peak level dB")
	right_noise=$(get_stat 2 "Noise floor dB")
	right_crest=$(get_stat 2 "Crest factor")

	right_rounded_peak=$(printf "%.2f" "$right_peak")
	right_rounded_noise=$(printf "%.2f" "$right_noise")
	right_rounded_crest=$(printf "%.2f" "$right_crest")

	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		echo "Left Channel:"
		echo "  Peak Level:     ${left_rounded_peak:-N/A} dBFS"
		echo "  Noise Floor:    ${left_rounded_noise:-N/A} dBFS"
		echo "  Crest Factor:   ${left_rounded_crest:-N/A}"
		echo ""
		echo "Right Channel:"
		echo "  Peak Level:     ${right_rounded_peak:-N/A} dBFS"
		echo "  Noise Floor:    ${right_rounded_noise:-N/A} dBFS"
		echo "  Crest Factor:   ${right_rounded_crest:-N/A}"
		echo ""
	fi

	# Stereo correlation (only meaningful for stereo files)
	average_phase=$(ffmpeg -hide_banner -i "$FILE" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2>/dev/null \
		| grep 'lavfi.aphasemeter.phase' \
		| awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.2f", sum/n; else print "N/A" }')

	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo "Stereo Correlation:"
		echo "  Average Phase:  $average_phase degrees"
	fi

	integrated_loudness=$(get_loudnorm "input_i")
	true_peak=$(get_loudnorm "input_tp")
	loudness_range=$(get_loudnorm "input_lra")

	rounded_integrated_loudness=$(printf "%.2f" "$integrated_loudness")
	rounded_true_peak=$(printf "%.2f" "$true_peak")
	rounded_loudness_range=$(printf "%.2f" "$loudness_range")

	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		echo "Loudness (EBU R128):"
		echo "  Integrated Loudness:  ${rounded_integrated_loudness:-N/A} LUFS"
		echo "  True Peak:            ${rounded_true_peak:-N/A} dBTP"
		echo "  Loudness Range:       ${rounded_loudness_range:-N/A} LU"
	else
		echo "{"
		echo "  \"file\": \"$(basename "$FILE")\","
		echo "  \"left_peak_level_db\": ${left_rounded_peak:-null},"
		echo "  \"left_noise_floor_db\": ${left_rounded_noise:-null},"
		echo "  \"left_crest_factor\": ${left_rounded_crest:-null}"
		echo "  \"right_peak_level_db\": ${right_rounded_peak:-null},"
		echo "  \"right_noise_floor_db\": ${right_rounded_noise:-null},"
		echo "  \"right_crest_factor\": ${right_rounded_crest:-null},"
		echo "  \"average_phase_degrees\": ${average_phase:-null},"
		echo "  \"integrated_loudness_lufs\": ${rounded_integrated_loudness:-null},"
		echo "  \"true_peak_db\": ${rounded_true_peak:-null},"
		echo "  \"loudness_range_lu\": ${rounded_loudness_range:-null}"
		echo "},"
	fi
} > "$RESULTS_FILE"

# Run task in background, capture PID, spin until done
long_running_task &
TASK_PID=$!
spinner $TASK_PID "Processing \"$(basename "$FILE")\""
wait $TASK_PID

echo "" >> "$RESULTS_FILE"
cat "$RESULTS_FILE"
rm -f "$RESULTS_FILE" 2> /dev/null
