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

This program is used to analyze an audio file and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.

JSON output format is available for easy integration with other tools or for
further processing. Metadata fields can also be included in the output for a
more comprehensive analysis. Upload your audio files to the web interface at
https://mcochris.com/index.html/ to view interactive visualizations of these
statistics.

Options:
  -h, --help        Show this help message and exit
  -v, --version     Show program version and exit
  -j, --json        Output results in JSON format (default: human-readable text)
  -m, --metadata    Include metadata fields (genre, artist, album, track,
                    duration, year, sample rate, bit rate) in output

  Examples:
	# Analyze a single file with human-readable output
	recording-analyzer.sh ~/Music/track.flac

	# Analyze multiple files with JSON output
	recording-analyzer.sh -j ~/Music/*.flac

	# Analyze a single file with metadata included
	recording-analyzer.sh -m ~/Music/track.flac

	# Analyze multiple files with JSON output and metadata included
	recording-analyzer.sh -j -m ~/Music/*.flac

	Additional help at: https://mcochris/cli-help.html

	Questions, issues, or suggestions? Please open a support ticket at:
	https://github.com/mcochris/Recording-analyzer/issues
"

readonly VERSION="1.0.0"
RESULTS_FILE="$(mktemp)"
readonly RESULTS_FILE

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

JSON_OUTPUT="false"
INCLUDE_METADATA="false"
POSITIONAL=()

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
        -m|--metadata)
            INCLUDE_METADATA="true"
            shift
            ;;
        *)
			POSITIONAL+=("$1")
			shift
			;;
    esac
done

readonly JSON_OUTPUT
readonly INCLUDE_METADATA

set -- "${POSITIONAL[@]}"

# If multiple args received, shell already expanded the glob
if [[ $# -gt 1 ]]; then
    files=("$@")
elif [[ $# -eq 1 ]]; then
    # Single arg — treat as a pattern to expand ourselves
    pattern="$1"
    expanded="${pattern/#\~/$HOME}"
    dir=$(dirname "$expanded")
    glob=$(basename "$expanded")

    readarray -d '' files < <(find "$dir" -maxdepth 1 -name "$glob" -print0 | sort -z)
else
    echo "Usage: $0 <pattern>  (e.g. \"~/Music/*.flac\")" >&2
    exit 1
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No files found" >&2
    exit 1
fi

row=1

for file in "${files[@]}"; do
	[[ -e "$file" ]] || { echo "Error: File does not exist: $file"; exit 1; }
	[[ -f "$file" ]] || { echo "Error: File is not a regular file: $file"; exit 1; }
	[[ -r "$file" ]] || { echo "Error: File not readable: $file"; exit 1; }

	function long_running_task() {
		# Run ffmpeg with astats filter to get per-channel statistics
		ASTATS=$(ffmpeg -hide_banner -i "$file" -af "astats" -f null - 2>&1)
		readonly ASTATS

		FFPROBE=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2> /dev/null)
		readonly FFPROBE

		# Check ffmpeg produced expected astats output
		if ! grep -q "Channel:" <<< "$ASTATS"; then
			echo "Error: ffmpeg failed to process file."
			exit 1
		fi

		function get_metadata() {
			local field="$1"
			echo "$FFPROBE" | grep "$field" | head -n 1 | awk -F '"' '{print $4}' || true
		}

		function get_duration() {
			echo "$FFPROBE" | grep '"duration"' | tail -n 1 | awk -F '"' '{printf "%.0f", $4}' || true
		}

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
		LOUDNORM=$(ffmpeg -hide_banner -i "$file" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/')
		readonly LOUDNORM

		# Extract a field from the loudnorm JSON
		function get_loudnorm() {
			local field="$1"
			echo "$LOUDNORM" | grep "\"$field\"" | awk -F'"' '{print $4}'
		}

		# Print header and per-channel stats to results file
		if [[ "$JSON_OUTPUT" = "false" ]]; then
			echo ""
			TEXT="Audio Analysis: \"$file\""
			echo "$TEXT"
			printf '=%.0s' $(seq 1 ${#TEXT})
			echo ""
		fi

		if [[ "$INCLUDE_METADATA" = "true" ]]; then
			genre=$(get_metadata "genre")
			artist=$(get_metadata "artist")
			album=$(get_metadata "album")
			track=$(get_metadata "track")
			duration=$(get_duration)
			year=$(get_metadata "date")
			sample_rate=$(get_metadata "sample_rate")
			bit_rate=$(get_metadata "bit_rate")
			bits_per_raw_sample=$(get_metadata "bits_per_raw_sample")

			if [[ "$JSON_OUTPUT" = "false" ]]; then
				echo ""
				echo "Metadata:"
				echo "  Genre:           ${genre:-n/a}"
				echo "  Artist:          ${artist:-n/a}"
				echo "  Album:           ${album:-n/a}"
				echo "  Track:           ${track:-n/a}"
				echo "  Duration:        ${duration:-n/a} seconds"
				echo "  Year:            ${year:-n/a}"
				echo "  Sample Rate:     ${sample_rate:-n/a} Hz"
				echo "  Avg. Bit Rate:   ${bit_rate:-n/a} bps"
				echo "  Bits Per Sample: ${bits_per_raw_sample:-n/a}"
			fi
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
			echo "  Peak Level:     ${left_rounded_peak:-n/a} dBFS"
			echo "  Noise Floor:    ${left_rounded_noise:-n/a} dBFS"
			echo "  Crest Factor:   ${left_rounded_crest:-n/a}°"
			echo ""
			echo "Right Channel:"
			echo "  Peak Level:     ${right_rounded_peak:-n/a} dBFS"
			echo "  Noise Floor:    ${right_rounded_noise:-n/a} dBFS"
			echo "  Crest Factor:   ${right_rounded_crest:-n/a}°"
			echo ""
		fi

		# Stereo correlation (only meaningful for stereo files)
		average_phase=$(ffmpeg -hide_banner -i "$file" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2>/dev/null \
			| grep 'lavfi.aphasemeter.phase' \
			| awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.2f", sum/n; else print "n/a" }')

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
			echo "  Integrated Loudness:  ${rounded_integrated_loudness:-n/a} LUFS"
			echo "  True Peak:            ${rounded_true_peak:-n/a} dBTP"
			echo "  Loudness Range:       ${rounded_loudness_range:-n/a} LU"
		else
			[[ "$row" -eq 1 ]] && echo "[" > "$RESULTS_FILE"
			echo "{"
			echo "  \"id\": $row,"
			[[ "$INCLUDE_METADATA" = "true" ]] && echo "  \"path\": \"$(dirname "$file")\","
			echo "  \"file\": \"$(basename "$file")\","
			if [[ "$INCLUDE_METADATA" = "true" ]]; then
				echo "  \"genre\": \"${genre:-n/a}\","
				echo "  \"artist\": \"${artist:-n/a}\","
				echo "  \"album\": \"${album:-n/a}\","
				echo "  \"track\": ${track:-\"n/a\"},"
				echo "  \"duration\": ${duration:-\"n/a\"},"
				echo "  \"year\": ${year:-\"n/a\"},"
				echo "  \"sample_rate\": ${sample_rate:-\"n/a\"},"
				echo "  \"bit_rate\": ${bit_rate:-\"n/a\"},"
				echo "  \"bits_per_sample\": ${bits_per_raw_sample:-\"n/a\"},"
			fi
			echo "  \"left_peak_level_db\": ${left_rounded_peak:-\"n/a\"},"

			if [[ "$left_rounded_noise" = "-inf" ]]; then
				echo "  \"left_noise_floor_db\": \"-inf\","
			else
				echo "  \"left_noise_floor_db\": ${left_rounded_noise:-\"n/a\"},"
			fi

			echo "  \"left_crest_factor\": ${left_rounded_crest:-\"n/a\"},"
			echo "  \"right_peak_level_db\": ${right_rounded_peak:-\"n/a\"},"

			if [[ "$right_rounded_noise" = "-inf" ]]; then
				echo "  \"right_noise_floor_db\": \"-inf\","
			else
				echo "  \"right_noise_floor_db\": ${right_rounded_noise:-\"n/a\"},"
			fi

			echo "  \"right_crest_factor\": ${right_rounded_crest:-\"n/a\"},"
			echo "  \"average_phase_degrees\": ${average_phase:-\"n/a\"},"
			echo "  \"integrated_loudness_lufs\": ${rounded_integrated_loudness:-\"n/a\"},"
			echo "  \"true_peak_db\": ${rounded_true_peak:-\"n/a\"},"
			echo "  \"loudness_range_lu\": ${rounded_loudness_range:-\"n/a\"}"
			echo "},"
		fi
	} >> "$RESULTS_FILE"

	# Run task in background, capture PID, spin until done
	long_running_task &
	TASK_PID=$!
	spinner $TASK_PID "Processing \"$(basename "$file")\""
	wait $TASK_PID
	row=$((row + 1))
done

if [[ "$JSON_OUTPUT" = "false" ]]; then
    echo "" >> "$RESULTS_FILE"
else
    sed --in-place '$ s/,$//' "$RESULTS_FILE"
    echo "]" >> "$RESULTS_FILE"
fi

cat "$RESULTS_FILE"
rm -f "$RESULTS_FILE" 2> /dev/null
