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

HELP="
Audio Recording Analyzer

Usage: recording-analyzer.sh <audio_file>
Example: recording-analyzer.sh recording.wav

This program is used to analyze an audio file and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.
"

readonly FILE="$1"
[[ "$FILE" == "-?" || "$FILE" == "-h" || "$FILE" == "--help" ]] && { echo "$HELP"; exit 0; }
[[ "$FILE" == "-v" || "$FILE" == "--version" ]] && { echo "recording-analyzer.sh version $VERSION"; exit 0; }
[[ -e "$FILE" ]] || { echo "Error: File does not exist: $FILE"; exit 1; }
[[ -f "$FILE" ]] || { echo "Error: File is not a regular file: $FILE"; exit 1; }
[[ -r "$FILE" ]] || { echo "Error: File not readable: $FILE"; exit 1; }

RESULTS_FILE="$(mktemp)"
readonly RESULTS_FILE

#
# Spinner function to show progress while long-running task is executing
#
function spinner() {
    local pid=$1
    local message=${2:-"Working"}
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
	readonly NUM_CHANNELS

	# Run loudnorm and capture JSON output
	LOUDNORM=$(ffmpeg -hide_banner -i "$FILE" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/')
	readonly LOUDNORM

	# Extract a field from the loudnorm JSON
	function get_loudnorm() {
		local field="$1"
		echo "$LOUDNORM" | grep "\"$field\"" | awk -F'"' '{print $4}'
	}

	# Print header and per-channel stats to results file
	echo ""
	TEXT="Audio Analysis: \"$FILE\""
	echo "$TEXT"
	printf '=%.0s' $(seq 1 ${#TEXT})
	echo ""

	# Per-channel stats
	for ch in $(seq 1 "$NUM_CHANNELS"); do
		case $ch in
			1) label="Left"  ;;
			2) label="Right" ;;
			*) label="Ch $ch";;
		esac

		peak=$(get_stat "$ch" "Peak level dB")
		noise=$(get_stat "$ch" "Noise floor dB")
		crest=$(get_stat "$ch" "Crest factor")

		echo ""
		echo "$label Channel:"
		echo "  Peak Level:     ${peak:-N/A} dBFS"
		echo "  Noise Floor:    ${noise:-N/A} dBFS"
		echo "  Crest Factor:   ${crest:-N/A}"
	done

	# Stereo correlation (only meaningful for stereo files)
	if [ "$NUM_CHANNELS" -ge 2 ]; then
		echo ""
		echo "Stereo Correlation:"

		PHASE=$(ffmpeg -hide_banner -i "$FILE" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2>/dev/null \
			  | grep 'lavfi.aphasemeter.phase' \
			  | awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.4f", sum/n; else print "N/A" }')

		echo "  Average Phase:  ${PHASE:-N/A}"
	fi

	# Loudness (EBU R128)
	INPUT_I=$(get_loudnorm "input_i")
	INPUT_TP=$(get_loudnorm "input_tp")
	INPUT_LRA=$(get_loudnorm "input_lra")

	echo ""
	echo "Loudness (EBU R128):"
	echo "  Integrated Loudness:  ${INPUT_I:-N/A} LUFS"
	echo "  True Peak:            ${INPUT_TP:-N/A} dBTP"
	echo "  Loudness Range:       ${INPUT_LRA:-N/A} LU"
} > "$RESULTS_FILE" 2> /dev/null

# Run task in background, capture PID, spin until done
long_running_task &
TASK_PID=$!
spinner $TASK_PID "Working"
wait $TASK_PID

# Display results and clean up
cat "$RESULTS_FILE"
rm -f "$RESULTS_FILE" 2>/dev/null
echo ""
