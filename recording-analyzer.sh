#!/usr/bin/env bash
#
# ╭──────────────────────────────────────────────────────────────────────────────╮
# │                                                                              │
# │                        Welcome to recording-analyzer!                        │
# │                                                                              │
# │                  Analyze audio files and extract statistics                  │
# │                                                                              │
# │             For more details, please visit the GitHub repository:            │
# │	               https://github.com/mcochris/Recording-analyzer                │
# │                                                                              │
# │        Questions, issues, suggestions? Please open a support ticket at:      │
# │             https://github.com/mcochris/Recording-analyzer/issues            │
# │                                                                              │
# ╰──────────────────────────────────────────────────────────────────────────────╯

#
# Sanity checks and strict mode settings.
#
#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

#
# Program version is automatically updated by GitHub Actions on new releases.
#
readonly VERSION="1.0.0"

#
# Create temporary files for error logging and results output.
#
ERROR_LOG="$(mktemp)"
readonly ERROR_LOG
RESULTS_FILE="$(mktemp)"
readonly RESULTS_FILE

#
# Cleanup function to remove temporary files and restore terminal state on exit.
#
function cleanup() {
	[[ -n "${RESULTS_FILE:-}" ]] && rm --force "$RESULTS_FILE" 2> /dev/null
	[[ -n "${ERROR_LOG:-}" ]] && rm --force "$ERROR_LOG" 2> /dev/null
	tput cnorm 1>&2
}

#
# Function to log errors to a file.
#
function error_log() {
	echo "$1" >> "$ERROR_LOG"
}

#
# Set traps for signals to ensure cleanup is performed.
#
trap 'echo "Aborted."; tput cnorm 1>&2; exit 130' SIGINT
trap 'echo "Terminated."; tput cnorm 1>&2; exit 143' SIGTERM
trap cleanup EXIT

#
# Check for required external programs.
#
for cmd in ffmpeg ffprobe jq; do
	command -v "$cmd" &> /dev/null || { echo "Error: Required program \"$cmd\" not found" >&2; exit 1; }
done

#
# Get the program name for usage messages and other references.
#
THIS_PGM=$(basename "$0")
readonly THIS_PGM
# Check if at least one argument is provided, otherwise show usage and exit.
[[ $# -eq 0 ]] && { echo "Usage: $THIS_PGM <audio_file>"; exit 1; }

readonly HELP="
╭──────────────────────────────────────────────────────────────────────────────╮
│                                                                              │
│                        Welcome to recording-analyzer!                        │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

Usage:
	$THIS_PGM <audio_file> ...
	- or -
	$THIS_PGM <directory> ...

This program is used to analyze audio files and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.

JSON output format is available for easy integration with other tools or for
further processing. Metadata fields can also be included in the output for a
more comprehensive analysis. Upload the JSON output of your audio files to
https://recording-analyzer.mcochris.com/ to view an interactive visualization
of the statistics, create playlists and spreadsheets based on the analysis
results.

Options:
  -h, --help        Show this help message and exit
  -v, --version     Show program version and exit
  -q, --quiet       Suppress progress spinner and other non-essential output
  -j, --json        Output results in JSON format (default: human-readable text)
  -m, --metadata    Include metadata fields (genre, artist, album, track,
                    duration, date, sample rate, bit rate) in output
  -r, --recurse     Recursively search directories for audio files

  Examples:
	# Analyze a single file with human-readable output
	$THIS_PGM ~/Music/track.flac

	# Analyze all music files in a directory recursively
	$THIS_PGM --recurse ~/Music

	# Analyze files and directories with metadata included
	$THIS_PGM --metadata ~/Music/track.flac ../song.mp3 /mnt/nas/audio/album/

	# Analyze music files and redirect JSON output to a file for use with the web
	# page at https://recording-analyzer.mcochris.com/
	$THIS_PGM --json --metadata ~/Music/*.flac > analysis_results.json

	For more details, please visit the GitHub repository:
	https://github.com/mcochris/Recording-analyzer

	Questions, issues, suggestions? Please open a support ticket at:
	https://github.com/mcochris/Recording-analyzer/issues
"

#
# Optional processing limit to prevent overloading the system with too many files.
# Can be set via PROCESSING_LIMIT environment variable, default is 0 for no limit.
#
readonly DEFAULT_PROCESSING_LIMIT=0

#
# Default audio file extensions to look for (can be overridden by AUDIO_EXTENSIONS env var).
#
readonly DEFAULT_EXTENSIONS=("aac" "ac3" "aif" "aiff" "amr" "caf" "flac" "m4a" "mp3" "ogg" "opus" "pcm" "wav" "wma")

#
# Get terminal width for dynamic output formatting (e.g., spinner messages).
#
COLS=$(tput cols)
readonly COLS

#
# Default command-line options.
#
JSON_OUTPUT="false"
INCLUDE_METADATA="false"
RECURSE_FLAG=()
POSITIONAL=()
QUIET="false"

#
# Loop through options and arguments, handling known flags and collecting positional arguments for file processing.
#
while [[ $# -gt 0 ]]; do
	case "$1" in
		help|-h|--help|-\?)
			echo "$HELP"
			exit 0
			;;
		-v|--version)
			echo "$THIS_PGM version $VERSION"
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
		-q|--quiet)
			QUIET="true"
			shift
			;;
		-r|--recurse)
			RECURSE_FLAG=("-r")
			shift
			;;
		*)
			if [[ "$1" == -* ]]; then
				error_log "Warning: ignoring unknown option '$1'"
			else
				POSITIONAL+=("$1")
			fi
			shift
			;;
		esac
done

#
# Make the parsed options read-only and set the positional parameters to the collected file arguments.
#
readonly JSON_OUTPUT
readonly INCLUDE_METADATA
readonly QUIET
set -- "${POSITIONAL[@]}"

#
# Sanitize and load one extension from a raw token.
#
function parse_extension() {
	local ext
	# Lowercase, strip leading dots and any non-alphanumeric chars except hyphens
	ext=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^\.*//' | tr -cd '[:alnum:]-')
	echo "$ext"
}

#
# Check for updates by fetching the latest version string from the GitHub repository.
#
check_for_update() {
	if [[ "$QUIET" = "false" ]]; then
		tput civis 1>&2
		printf "\rChecking for updates..." 1>&2
	fi

	local remote

	remote=$(curl --silent --fail --max-time 3 \
		"https://api.github.com/repos/mcochris/Recording-analyzer/releases/latest" \
		| grep '"tag_name":' | head -1 | cut -d'"' -f4) || \
		{	if [[ "$QUIET" = "false" ]]; then
				printf "\r%s\033[K\n" "Checking for updates failed" 1>&2
				tput cnorm 1>&2
			fi
			return 1
		}

	if [[ -z "$remote" ]]; then
		if [[ "$QUIET" = "false" ]]; then
			printf "\r%s\033[K\n" "Checking for updates failed" 1>&2
			tput cnorm 1>&2
		fi
		return 2
	fi

	if [[ "$remote" != "$VERSION" ]]; then
		if [[ "$QUIET" = "false" ]]; then
			printf "\r%s\033[K\n" "Update available: v$remote (you have v$VERSION)" 1>&2
			echo "Update: curl --remote-name https://raw.githubusercontent.com/mcochris/Recording-analyzer/main/recording-analyzer.sh" 1>&2
		fi
		return 3
  	fi

	tput cnorm 1>&2
	return 0
}

#
# Helper: add a single file if it matches an audio extension.
#
function add_if_audio() {
	local f="$1"
	if [[ -f "$f" ]] && [[ "${f,,}" =~ $ext_pattern ]]; then
		AUDIO_FILES+=("$f")
		msg="Scanning... found ${#AUDIO_FILES[@]} file(s)"
		if [[ "$QUIET" = "false" ]]; then
			printf "\r%s\033[K" "${msg:0:$COLS}" 1>&2
		fi
	fi
}

#
# Helper: add audio files from a directory (non-recursive).
#
function add_dir_flat() {
	local dir="$1"
	local f
	while IFS= read -r -d '' f; do
		add_if_audio "$f"
	done < <(find "$dir" -maxdepth 1 -type f -a \( "${find_args[@]}" \) -print0)
}

#
# Helper: add audio files from a directory (recursive).
#
function add_dir_recursive() {
	local dir="$1"
	local f
	while IFS= read -r -d '' f; do
		add_if_audio "$f"
	done < <(find "$dir" -type f -a \( "${find_args[@]}" \) -print0)
}

#
# Sets the global array AUDIO_FILES with the resolved file list.
#
function collect_audio_files() {
	AUDIO_FILES=()
	local recurse=false
	local args=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-r) recurse=true ;;
			--) shift; args+=("$@"); break ;;
			*)  args+=("$1") ;;
		esac
		shift
	done

	# Build a regex pattern like \.(mp3|flac|wav|...)$ for extension matching.
	local ext_pattern
	ext_pattern=$(printf '%s|' "${EXTENSIONS[@]}")
	ext_pattern="\\.(${ext_pattern%|})$"

	# Process each positional argument
	local arg
	for arg in "${args[@]}"; do
		# Expand ~ manually since it won't expand inside a variable.
		arg="${arg/#\~/$HOME}"

		if [[ -d "$arg" ]]; then
			# Argument is a directory.
			if "$recurse"; then
				add_dir_recursive "$arg"
			else
				add_dir_flat "$arg"
			fi

		elif [[ -f "$arg" ]]; then
			# Argument is a literal existing file.
			add_if_audio "$arg"

		else
			# Got a glob pattern?
			local match
			local match_count=0
			while IFS= read -r match; do
				match_count=$((match_count + 1))
				if [[ -d "$match" ]]; then
					if "$recurse"; then
						add_dir_recursive "$match"
					else
						add_dir_flat "$match"
					fi
				else
					add_if_audio "$match"
				fi
			done < <(compgen -G "$arg" 2>/dev/null)

			if [[ $match_count -eq 0 ]]; then
				error_log "Warning: no matches found for: $arg"
			fi
		fi
	done

	# Remove duplicates while preserving order.
	local unique=()
	local f
	# shellcheck disable=SC1003
	local frames=('-' '\' '|' '/')
	local i=0
	local j=1
	tput civis 1>&2

	# Use realpath to resolve symlinks and get a canonical path for each file, then use an associative array to track seen paths.
	# This way we can avoid processing the same file multiple times if it appears in multiple locations.
	for f in "${AUDIO_FILES[@]}"; do
		local real
		real=$(realpath --no-symlinks "$f" 2>/dev/null || echo "$f")
		declare -A seen_map
		if [[ -z "${seen_map[$real]+_}" ]]; then
			seen_map[$real]=1
			unique+=("$f")
		fi
		if [[ "$QUIET" = "false" ]]; then
			printf "\r\033[KFound %d files, preparing file %d... %s" "${#AUDIO_FILES[@]}" "$j" "${frames[$i]}" 1>&2
			i=$(( (i + 1) % ${#frames[@]} ))
			j=$((j + 1))
		fi
	done

	# Clear the spinner line and restore cursor.
	printf "\r\033[K" 1>&2
	tput cnorm 1>&2

	AUDIO_FILES=("${unique[@]}")
}

#
# Spinner function to show progress while long-running task is executing.
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
		printf "\r%s... %s" "${message:0:$((COLS-5))}" "${frames[$i]}" 1>&2
		i=$(( (i + 1) % ${#frames[@]} ))
		sleep 0.1
	done

	# Clear the spinner line and restore cursor
	printf "\r\033[K" 1>&2
	tput cnorm 1>&2
}

#
# Functions to extract specific pieces of information from ffprobe output.
#
function get_metadata() {
	echo "$FFPROBE" | jq -r --arg f "$1" '.streams[0][$f] // .format[$f] // empty'
}

#
# Extract duration in seconds, rounded to nearest whole number.
#
function get_duration() {
	echo "$FFPROBE" | jq -r '.format.duration // empty' | awk '{printf "%.0f", $1}'
}

#
# Extract a named stat from within a specific channel block.
#
function get_stat() {
	local channel="$1"
	local field="$2"
	echo "$ASTATS" | awk -v ch="Channel: $channel" -v fld="$field" '
		$0 ~ ch        { in_block=1; next }
		in_block && /Channel:/ { in_block=0 }
		in_block && index($0, fld) { print $NF; exit }
	'
}

#
# Extract a field from the loudnorm JSON.
#
function get_loudnorm() {
	echo "$LOUDNORM" | jq -r --arg f "$1" '.[$f] // empty'
}

#
# Extract metadata tags from ffprobe output.
#
function get_metadata_tags() {
	local field="$1"
	echo "$FFPROBE" | jq -r --arg field "$field" '.format.tags[$field] // empty'
}

#
#	Helper function to convert a value to an integer if it's a valid number, otherwise return empty string.
#
function integerize() {
	local value="$1"
	if [[ "$value" =~ ^[0-9]+$ ]]; then
		echo $((10#$value))  # 10# forces base-10, stripping leading zeros
	else
		echo ""
	fi
}

#
# Function to perform the long-running analysis task for a single file.
# All the heavy lifting is done here, and the results are printed in the appropriate format (human-readable or JSON).
# This function is run in the background for each file, allowing the main loop to show a spinner while it runs.
# All output from this function is captured to RESULTS_FILE for later display.
#
function long_running_task() {
	# Run ffmpeg with astats filter to get per-channel statistics.
	ASTATS=$(ffmpeg -hide_banner -i "$file" -af "astats" -f null - 2>&1) || { error_log "ERROR: ffmpeg failed to process \"$file\""; return; }
	readonly ASTATS

	# Check if ffmpeg produced expected astats output.
	echo "$ASTATS" | grep --quiet --max-count=1 "Channel:" || { error_log "ERROR: ffmpeg failed to process \"$file\" correctly"; return; }

	FFPROBE=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>&1) || { error_log "ERROR: ffprobe failed to process \"$file\""; return; }
	readonly FFPROBE

	# Detect number of channels.
	NUM_CHANNELS=$(echo "$ASTATS" | grep -c "Channel: [0-9]")
	if [[ "$NUM_CHANNELS" -ne 2 ]]; then
		error_log "ERROR: \"$file\" is not a stereo file"
		return
	fi

	# Run loudnorm and capture the JSON output.
	LOUDNORM=$(ffmpeg -hide_banner -i "$file" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/') || { error_log "ERROR: ffmpeg failed to run loudnorm on \"$file\""; return; }
	readonly LOUDNORM

	# Print header and per-channel stats to results file.
	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		TEXT="Audio Analysis: \"$(basename "$file")\""
		echo "$TEXT"
		printf '=%.0s' $(seq 1 ${#TEXT})
		echo ""
	fi

	# Extract metadata if requested and print it in the appropriate format.
	if [[ "$INCLUDE_METADATA" = "true" ]]; then
		genre=$(get_metadata_tags "GENRE")
		artist=$(get_metadata_tags "ARTIST")
		album=$(get_metadata_tags "ALBUM")
		track=$(integerize "$(get_metadata_tags "track")")
		duration=$(integerize "$(get_duration)")
		date=$(get_metadata_tags "DATE")
		sample_rate=$(integerize "$(get_metadata "sample_rate")")
		bit_rate=$(integerize "$(get_metadata "bit_rate")")
		bits_per_raw_sample=$(integerize "$(get_metadata "bits_per_raw_sample")")

		# For human-readable output, print the metadata in a nice format. For JSON output,
		# the metadata will be included in the structured output below.
		if [[ "$JSON_OUTPUT" = "false" ]]; then
			echo ""
			echo "Metadata:"
			echo "  Genre:           ${genre:-n/a}"
			echo "  Artist:          ${artist:-n/a}"
			echo "  Album:           ${album:-n/a}"
			echo "  Track:           ${track:-n/a}"
			echo "  Duration:        ${duration:-n/a} seconds"
			echo "  Date:            ${date:-n/a}"
			echo "  Sample Rate:     ${sample_rate:-n/a} Hz"
			echo "  Avg. Bit Rate:   ${bit_rate:-n/a} bps"
			echo "  Bits Per Sample: ${bits_per_raw_sample:-n/a}"
		fi
	fi

	# Gather per-channel stats.
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

	# Print per-channel stats in the appropriate format.
	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		echo "Left Channel:"
		echo "  Peak Level:     ${left_rounded_peak:-n/a} dBFS"
		echo "  Noise Floor:    ${left_rounded_noise:-n/a} dBFS"
		echo "  Crest Factor:   ${left_rounded_crest:-n/a} dB"
		echo ""
		echo "Right Channel:"
		echo "  Peak Level:     ${right_rounded_peak:-n/a} dBFS"
		echo "  Noise Floor:    ${right_rounded_noise:-n/a} dBFS"
		echo "  Crest Factor:   ${right_rounded_crest:-n/a} dB"
		echo ""
	fi

	# Stereo correlation. The aphasemeter filter outputs a line for each frame with the current phase value,
	#so we can average those values to get an overall average phase for the file.
	average_phase=$(ffmpeg -hide_banner -i "$file" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2> /dev/null \
		| grep 'lavfi.aphasemeter.phase' \
		| awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.2f", sum/n; else print "n/a" }')

	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo "Stereo Correlation:"
		echo "  Average Phase:  $average_phase"
	fi

	# Gather loudness stats.
	integrated_loudness=$(get_loudnorm "input_i")
	true_peak=$(get_loudnorm "input_tp")
	loudness_range=$(get_loudnorm "input_lra")

	rounded_integrated_loudness=$(printf "%.2f" "$integrated_loudness")
	rounded_true_peak=$(printf "%.2f" "$true_peak")
	rounded_loudness_range=$(printf "%.2f" "$loudness_range")

	# Print loudness stats in the appropriate format.
	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		echo "Loudness (EBU R128):"
		echo "  Integrated Loudness:  ${rounded_integrated_loudness:-n/a} LUFS"
		echo "  True Peak:            ${rounded_true_peak:-n/a} dBTP"
		echo "  Loudness Range:       ${rounded_loudness_range:-n/a} LU"
	else
		# For JSON output, print all the collected data in a structured format. The metadata fields will be included if requested.
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
			echo "  \"date\": \"${date:-n/a}\","
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
		echo "  \"average_phase\": ${average_phase:-\"n/a\"},"
		echo "  \"integrated_loudness_lufs\": ${rounded_integrated_loudness:-\"n/a\"},"
		echo "  \"true_peak_db\": ${rounded_true_peak:-\"n/a\"},"
		echo "  \"loudness_range_lu\": ${rounded_loudness_range:-\"n/a\"}"
		echo "},"
	fi
} >> "$RESULTS_FILE"

#
# Validate the PROCESSING_LIMIT environment variable if set, otherwise use the default.
#
PROCESSING_LIMIT="${PROCESSING_LIMIT:-$DEFAULT_PROCESSING_LIMIT}"
if [[ "$PROCESSING_LIMIT" != "0" ]]; then
	if ! [[ "$PROCESSING_LIMIT" =~ ^[1-9][0-9]*$ ]]; then
		error_log "Warning: Invalid PROCESSING_LIMIT value '$PROCESSING_LIMIT', using default of $DEFAULT_PROCESSING_LIMIT"
		PROCESSING_LIMIT=$DEFAULT_PROCESSING_LIMIT
	fi
fi
readonly PROCESSING_LIMIT

#
# Build the active extension list from the default list and the AUDIO_EXTENSIONS environment variable, if set.
#
declare -a EXTENSIONS
AUDIO_EXTENSIONS="${AUDIO_EXTENSIONS:-}"
if [[ -n "$AUDIO_EXTENSIONS" ]]; then
	# Read the env var into an array (word-splitting on spaces/tabs is intentional here)
	read -r -a raw_exts <<< "$AUDIO_EXTENSIONS"

	for raw in "${raw_exts[@]}"; do
		cleaned=$(parse_extension "$raw")
		if [[ -n "$cleaned" ]]; then
			EXTENSIONS+=("$cleaned")
		else
			error_log "Warning: skipping invalid extension token: '$raw'"
		fi
	done

	if [[ ${#EXTENSIONS[@]} -eq 0 ]]; then
		error_log "Warning: AUDIO_EXTENSIONS contained no valid values, using defaults."
		EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
	fi
else
	EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
fi

readonly EXTENSIONS

#
# Build a find command that includes all the specified extensions. This will be used to efficiently find audio files in directories.
#
find_args=()
for i in "${!EXTENSIONS[@]}"; do
	[[ $i -gt 0 ]] && find_args+=(-o)
	find_args+=(-iname "*.${EXTENSIONS[$i]}")
done
readonly find_args

#
# Collect the list of audio files to process. This will populate the AUDIO_FILES array with the
# resolved file paths based on the provided arguments and options.
#
collect_audio_files "${RECURSE_FLAG[@]}" -- "${POSITIONAL[@]}"
[[ "$QUIET" = "false" ]] && printf "\r\033[K" 1>&2

#
# Warn user if there are more files than the processing limit (if a limit is set).
#
[[ "$QUIET" = "false" && "$PROCESSING_LIMIT" -gt 0 && ${#AUDIO_FILES[@]} -gt $PROCESSING_LIMIT ]] && echo "Warning: Processing will be limited to $PROCESSING_LIMIT files." >&2

#
# The main file loop: process each file, run the analysis in the background, and show a spinner while it runs.
#
row=1
if [[ $PROCESSING_LIMIT -gt 0 && ${#AUDIO_FILES[@]} -gt $PROCESSING_LIMIT ]]; then
	limit=$PROCESSING_LIMIT
else
	limit=${#AUDIO_FILES[@]}
fi

for file in "${AUDIO_FILES[@]}"; do
	[[ -e "$file" ]] || { error_log "ERROR: File \"$file\" does not exist"; continue; }
	[[ -f "$file" ]] || { error_log "ERROR: File \"$file\" is not a regular file"; continue; }
	[[ -r "$file" ]] || { error_log "ERROR: File \"$file\" is not readable"; continue; }
	[[ -s "$file" ]] || { error_log "ERROR: File \"$file\" is empty"; continue; }

	# Run task in background, capture PID, and show spinner while it runs
	long_running_task &
	TASK_PID=$!
	[[ "$QUIET" = "false" ]] && spinner $TASK_PID "Processing file $row of $limit: \"$(basename "$file")\""
	wait $TASK_PID
	row=$((row + 1))
	if [[ "$PROCESSING_LIMIT" -gt 0 && "$row" -gt $PROCESSING_LIMIT ]]; then
		break
	fi
done

#
# Finalize JSON output by removing trailing comma and closing the array.
#
if [[ "$JSON_OUTPUT" = "false" ]]; then
	echo "" >> "$RESULTS_FILE"
else
	sed --in-place '$ s/,$//' "$RESULTS_FILE"
	echo "]" >> "$RESULTS_FILE"
fi

#
# Display results.
#
if [[ -s "$RESULTS_FILE" ]]; then
	cat "$RESULTS_FILE"
else
	error_log "ERROR: No results to display"
fi

#
# Display any warnings about processing limits and show error log if present.
#
[[ $PROCESSING_LIMIT -gt 0 && "$row" -gt $PROCESSING_LIMIT ]] && error_log "Warning: Processing was limited to $PROCESSING_LIMIT files."

#
# If there were any errors logged, display the unique set of error messages to stderr.
#
[[ -s "$ERROR_LOG" ]] && sort --unique "$ERROR_LOG" >&2

#
# Cleanup temporary files (also handled by trap on EXIT)
#
rm --force "$RESULTS_FILE" 2> /dev/null
rm --force "$ERROR_LOG" 2> /dev/null

#
# Check for updates if not in quiet mode.
#
check_for_update