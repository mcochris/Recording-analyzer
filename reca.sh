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
# │       Questions, issues, suggestions? Please open a support ticket at:       │
# │            https://github.com/mcochris/Recording-analyzer/issues             │
# │                                                                              │
# ╰──────────────────────────────────────────────────────────────────────────────╯

# ╭──────────────────────────────────────────────────────────────────────────────╮
# │                                                                              │
# │          Define all functions first, main logic will be at the end           │
# │          of the script. This allows for better organization and              │
# │          readability, as well as ensuring that all functions are             │
# │          available when called in the main logic.                            │
# │                                                                              │
# ╰──────────────────────────────────────────────────────────────────────────────╯

#
# Build a regex pattern for find command based on the list of extensions.
#
function build_extension_list() {
	local ext list=""
	for ext in "${EXTENSIONS[@]}"; do
		list+="$ext\|"
	done
	echo "${list%\\|}"  # strip trailing \|
}

#
# Check for updates by fetching the latest version string from the GitHub repository.
#
function check_for_update() {
    local latest_version

    if [[ -f "$CACHE_FILE" ]]; then
        local last_check
        last_check=$(stat -c %Y "$CACHE_FILE")
        local now
        now=$(date +%s)
        if (( now - last_check < CACHE_TTL )); then
            return   # Cache is fresh — skip everything
        fi
    fi

    # Cache is stale or missing — fetch and notify
    latest_version=$(curl --fail --silent --show-error --location \
        "https://api.github.com/repos/mcochris/Recording-analyzer/releases/latest" \
        | grep '"tag_name"' \
        | sed 's/.*"tag_name": *"\(.*\)".*/\1/')

    if [[ -n "$latest_version" ]]; then
        mkdir -p "$(dirname "$CACHE_FILE")"
        echo "$latest_version" > "$CACHE_FILE"
        compare_versions "$latest_version"
    else
        touch "$CACHE_FILE"  # suppress retries on failure
    fi
}

#
# Cleanup function to display errors and remove temporary files on exit.
#
function cleanup() {
	tput cnorm 1>&2
	if [[ -e "$ERROR_LOG" && $(wc -l < "$ERROR_LOG") -gt 0 ]]; then
		echo "Errors encountered during processing:" >&2
		cat "$ERROR_LOG" >&2
	fi
	rm --force "$ERROR_LOG" 2> /dev/null
	rm --force "$RESULTS_FILE" 2> /dev/null
}

#
# Compare the latest version with the current version and notify the user if an update is available.
#
function compare_versions() {
    local latest="$1"
    if [[ "$latest" != "$CURRENT_VERSION" ]]; then
        echo "Update available: $latest (you have $CURRENT_VERSION)"
        echo "https://github.com/mcochris/Recording-analyzer/releases/latest"
    fi
}

#
# Create the parameters for the find command based on the provided arguments, handling directories, files, and patterns.
#
function create_find_parameters() {
		debug "create_find_parameters(): called with argument: $1"
		local arg="$1" dir base
		dir=$(dirname "${arg}")
		base=$(basename "${arg}")

		debug "create_find_parameters(): step 1 - dir set to: \"$dir\", base set to: \"$base\""

		dir=${dir/#~/$HOME}
		dir=${dir/#./$PWD}

		[[ "$base" == "~" || "$base" == "." || "$base" == "*" ]] && base=""

		debug "create_find_parameters(): step 2 - dir set to: \"$dir\", base set to: \"$base\""

		if [[ -d "$dir/$base" ]]; then
			debug "create_find_parameters(): \"$dir/$base\" is a directory, treating as search path"
			dir="$dir/$base"
			base=""
		else
			debug "create_find_parameters(): \"$dir/$base\" is not a directory, treating as file or pattern"
		fi

		if [[ -f "$dir/$base" ]]; then
			debug "create_find_parameters(): no search needed for: $dir/$base"
		elif [[ -z "$base" ]]; then
			debug "create_find_parameters(): search for audio files in directory: $dir"
		else
			local base_ext="${base##*.}"
			if ! is_extension_valid "$base_ext"; then
				debug "create_find_parameters(): unrecognized or no extension in filename: \"$dir/$base\", returning exit code 1"
				error_log "ERROR: unrecognized or no extension in filename: \"$dir/$base\""
				return 1
			fi
		fi

		debug "create_find_parameters(): returning: dir='$dir', base='$base'"

		local return
		return=("$dir" "$base")
		printf '%s\n' "${return[@]}"
}

#
# Debug function to print messages when DEBUG mode is enabled.
#
function debug() {
	# don't make this a one-liner
    if [[ "$DEBUG" == true ]]; then
		echo "DEBUG [${BASH_LINENO[0]}]: $*" >&2
    fi
}

#
# Function to log errors to the ERROR_LOG file.
#
function error_log() {
	echo "$1" >> "$ERROR_LOG"
}

#
# Find files matching the criteria using the find command, with options for recursion and extension filtering.
#
function find_files() {
	debug "find_files(): called with arguments: $*"
	local dir="$1" base="$2" cmd=() files=()

	cmd=("find" "$dir")
	[[ "${RECURSE:-false}" == false ]] && cmd+=("-maxdepth" "1")
	cmd+=("-type" "f")
	if [[ -n "$base" ]]; then
		cmd+=("-a" "-name" "$base")
	else
		cmd+=("-a" "-iregex" "^.*\\.\\($(build_extension_list)\\)\$")
	fi
	cmd+=("-print")

	debug "find_files(): Running command: ${cmd[*]}"
	readarray -t files < <("${cmd[@]}")
	debug "find_files(): Found ${#files[@]} files"

	if [[ "${LIMIT:-0}" -gt 0 && "$LIMIT" -lt ${#files[@]} ]]; then
		files=("${files[@]:0:$LIMIT}")
		debug "find_files(): Limited files to ${#files[@]} files based on user-specified limit of $LIMIT"
	fi

	if [[ ${#files[@]} -eq 0 ]]; then
		debug "find_files(): No files found matching criteria in \"$dir\" with base \"$base\""
		return
	else
		debug "find_files(): Files found matching criteria in \"$dir\" with base \"$base\": $(printf '\n%s' "${files[@]}")"
		printf '%s\n' "${files[@]}"
	fi
}

#
# Generate the report for a single file, extracting all relevant statistics and formatting the output based on user preferences.
#
function generate_report() {
	local file="$1" i="$2" channel_stats num_channels average_phase track duration sample_rate bit_rate \
		bits_per_raw_sample text json_object=""
	readonly file
	declare -A channel_stats metadata loudness_stats

	debug "generate_report(): Generating report for file: $file"

	if [[ -r "$file" && -s "$file" ]]; then
		debug "generate_report(): File \"$file\" is readable and not empty"
	else
		error_log "ERROR: file not readable, or is empty: \"$file\""
		return
	fi

	if get_channel_stats "$file" channel_stats num_channels; then
		debug "generate_report(): Successfully retrieved channel stats for \"$file\", num_channels: $num_channels, channel_stats: ${channel_stats[*]}"
	else
		error_log "ERROR: failed to get channel stats for \"$file\""
		return
	fi

	[[ "$num_channels" -gt 2 ]] && error_log "WARNING: more than 2 channels detected in \"$file\"; only processing first 2 channels"

	if average_phase=$(get_average_phase "$file"); then
		debug "generate_report(): Successfully retrieved average phase for \"$file\", average_phase: $average_phase"
	else
		error_log "ERROR: failed to get stereo phase for \"$file\""
		return
	fi

	if get_loudness "$file" loudness_stats; then
		debug "generate_report(): Successfully retrieved loudness stats for \"$file\", loudness_stats: ${loudness_stats[*]}"
	else
		error_log "ERROR: failed to get loudness for \"$file\""
		return
	fi

	if [[ "$INCLUDE_METADATA" == true ]]; then
		debug "generate_report(): User requested metadata inclusion for \"$file\""
		if get_metadata "$file" metadata; then
			debug "generate_report(): Successfully retrieved metadata for \"$file\", metadata: ${metadata[*]}"
		else
			error_log "ERROR: failed to get metadata for \"$file\""
			return
		fi
	else
		debug "generate_report(): User did not request metadata inclusion for \"$file\"; skipping metadata extraction"
	fi

	debug "generate_report(): Channel stats for \"$file\": ${channel_stats[*]}"
	debug "generate_report(): Average phase for \"$file\": $average_phase"
	debug "generate_report(): Loudness stats for \"$file\": ${loudness_stats[*]}"

	[[ "$INCLUDE_METADATA" == true ]] && debug "generate_report(): Metadata for \"$file\": ${metadata[*]}"
	[[ "$JSON_OUTPUT" == "true" ]] && debug "generate_report(): JSON_OUTPUT: $JSON_OUTPUT"

	if [[ "$JSON_OUTPUT" == "false" ]]; then
		debug "generate_report(): Generating human-readable report for \"$file\""
		echo ""
		text="Recording Analysis: \"$(basename "$file")\""
		echo "$text"
		printf '🭶%.0s' $(seq 1 ${#text})
		echo ""

		if [[ "$INCLUDE_METADATA" == true ]]; then
			echo "Metadata:"
			echo "  Genre:           ${metadata["GENRE"]}"
			echo "  Artist:          ${metadata["ARTIST"]}"
			echo "  Album:           ${metadata["ALBUM"]}"
			echo "  Track:           ${metadata["track"]}"
			echo "  Duration:        ${metadata["duration"]}"
			echo "  Year:            ${metadata["DATE"]}"
			echo "  Sample Rate:     ${metadata["sample_rate"]}"
			echo "  Avg. Bit Rate:   ${metadata["bit_rate"]}"
			echo "  Bits per sample: ${metadata["bits_per_raw_sample"]}"
			echo ""
		fi

		echo "Left Channel:"
		echo "  Peak level:      ${channel_stats["1:Peak level dB"]} dBFS"
		echo "  Noise floor:     ${channel_stats["1:Noise floor dB"]} dBFS"
		echo "  Crest factor:    ${channel_stats["1:Crest factor"]} dB"
		echo ""
		echo "Right Channel:"
		echo "  Peak level:      ${channel_stats["2:Peak level dB"]} dBFS"
		echo "  Noise floor:     ${channel_stats["2:Noise floor dB"]} dBFS"
		echo "  Crest factor:    ${channel_stats["2:Crest factor"]} dB"
		echo ""
		echo "Average phase:     $average_phase"
		echo ""
		echo "Loudness:"
		echo "  Integrated loudness:  ${loudness_stats[0]} LUFS"
		echo "  True peak:            ${loudness_stats[1]} dBTP"
		echo "  Loudness range:       ${loudness_stats[2]} LU"
		debug "generate_report(): Finished generating human-readable report for file: $file"
	fi

	if [[ "$JSON_OUTPUT" == "true" ]]; then
		debug "generate_report(): Generating JSON report for \"$file\""
		[[ "${channel_stats["1:Noise floor dB"]}" == "-inf" ]] && channel_stats["1:Noise floor dB"]=-999
		[[ "${channel_stats["2:Noise floor dB"]}" == "-inf" ]] && channel_stats["2:Noise floor dB"]=-999
		json_object="$(jq -n \
			--argjson 	id					"$i"											\
			--arg		path				"$(dirname "$(realpath "$file")")"				\
			--arg		file				"$(basename "$file")"							\
			--argjson	left_peak_dB		"${channel_stats["1:Peak level dB"]:-null}"		\
			--argjson	left_noise_dB		"${channel_stats["1:Noise floor dB"]:-null}"	\
			--argjson	left_crest_dB		"${channel_stats["1:Crest factor"]:-null}"		\
			--argjson	right_peak_dB		"${channel_stats["2:Peak level dB"]:-null}"		\
			--argjson	right_noise_dB		"${channel_stats["2:Noise floor dB"]:-null}"	\
			--argjson	right_crest_dB		"${channel_stats["2:Crest factor"]:-null}"		\
			--argjson	average_phase		"${average_phase:-null}"						\
			--argjson	integrated_loudness	"${loudness_stats[0]:-null}"					\
			--argjson 	true_peak_dBTP		"${loudness_stats[1]:-null}"					\
			--argjson	loudness_range_LU	"${loudness_stats[2]:-null}"					\
			--arg		genre				"${metadata["GENRE"]:-}"						\
			--arg		artist				"${metadata["ARTIST"]:-}"						\
			--arg		album				"${metadata["ALBUM"]:-}"						\
			--arg		track				"${metadata["track"]:-}"						\
			--argjson	duration			"${metadata["duration"]:-null}"					\
			--arg		year				"${metadata["DATE"]:-}"							\
			--argjson	sample_rate			"${metadata["sample_rate"]:-null}"				\
			--argjson	bit_rate			"${metadata["bit_rate"]:-null}"					\
			--argjson	bits_per_sample		"${metadata["bits_per_raw_sample"]:-null}"		\
			'{id: $id, path: $path, file: $file, left_peak_dB: $left_peak_dB, left_noise_dB: $left_noise_dB, left_crest_dB: $left_crest_dB, right_peak_dB: $right_peak_dB, right_noise_dB: $right_noise_dB, right_crest_dB: $right_crest_dB, average_phase: $average_phase, integrated_loudness_LUFS: $integrated_loudness, true_peak_dBTP: $true_peak_dBTP, loudness_range_LU: $loudness_range_LU, genre: $genre, artist: $artist, album: $album, track: $track, duration: $duration, year: $year, sample_rate: $sample_rate, bit_rate: $bit_rate, bits_per_sample: $bits_per_sample} | with_entries(select(.value != "" and .value != null))')"

		debug "generate_report(): Finished generating JSON report for file: \"$file\", JSON object: $json_object"
		printf '%s\n' "$json_object"
	fi
}

#
# Get stereo correlation by averaging the output of the aphasemeter filter.
#
function get_average_phase() {
	local file="$1" average_phase

	[[ -z "$file" ]] && { error_log "ERROR: get_average_phase() requires a file"; return 1; }

	average_phase=$(ffmpeg -hide_banner -i "$file" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2> /dev/null \
		| grep 'lavfi.aphasemeter.phase' \
		| awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.2f", sum/n; else print "" }')

	debug "Average phase for $file: $average_phase"

	echo "$average_phase"
}

#
# Extract channel statistics from ffmpeg astats filter output.
#
function get_channel_stats() {
	local file="$1" channel stat field
	local -n _channel_stats="$2" _num_channels="$3"

	if [[ -z "$file" ]]; then
		error_log "ERROR: get_channel_stats() requires a file and two output variables"
		return 1
	fi

	function failed() {
		local channel
		for channel in 1 2; do
			_channel_stats["$channel:Peak level dB"]=""
			_channel_stats["$channel:Noise floor dB"]=""
			_channel_stats["$channel:Crest factor"]=""
		done
		_num_channels=0
	}

	local ASTATS
	ASTATS=$(ffmpeg -hide_banner -i "$file" -af "astats" -f null - 2>&1) \
		|| { error_log "ERROR: ffmpeg failed to process \"$file\""; failed; return 1;}
	readonly ASTATS

	# Detect number of channels.
	_num_channels=$(grep --count "Channel: [0-9]" <<< "$ASTATS") \
		|| { error_log "ERROR: failed to detect number of channels in \"$file\""; failed; return 1;}

	debug "get_channel_stats(): Detected $_num_channels channels in \"$file\""

	_num_channels=$(integerize "$_num_channels")
	[[ -z "$_num_channels" || "$_num_channels" -le 0 ]] \
		&& { error_log "ERROR: invalid number of channels detected in \"$file\""; failed; return 1; }

	for channel in 1 2; do
		for field in "Peak level dB" "Noise floor dB" "Crest factor"; do
			stat=$(awk -v ch="Channel: $channel" -v fld="$field" '
				$0 ~ ch { in_block=1; next }
				in_block && /Channel:/ { in_block=0 }
				in_block && index($0, fld) { print $NF; exit }' <<< "$ASTATS")
		    # shellcheck disable=SC2034
		    if [[ -n "$stat" ]]; then
				_channel_stats["$channel:$field"]=$(printf "%.2f" "$stat")
			else
				_channel_stats["$channel:$field"]=""
			fi

			debug "get_channel_stats(): Channel $channel $field for \"$file\": ${_channel_stats["$channel:$field"]}"
		done
	done
}

#
# Extract metadata duration in seconds, rounded to nearest whole number.
#
function get_duration() {
	echo "$FFPROBE" | jq -r '.format.duration // empty' | awk '{printf "%.0f", $1}'
}

#
# Extract the loudness statistics from the ffmpeg loudnorm option.
#
function get_loudness() {
	local file="$1" loudness integrated_loudness true_peak loudness_range
	local -n _loudness_stats="$2"

	[[ -z "$file" ]] && { error_log "ERROR: get_loudness() requires a file"; return 1; }

	loudness=$(ffmpeg -hide_banner -i "$file" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/') \
		|| { error_log "ERROR: ffmpeg failed to run loudnorm on \"$file\""; return 1; }

	integrated_loudness=$(echo "$loudness" | grep "input_i" | cut -d: -f2 | tr -d '":, ')
	true_peak=$(echo "$loudness" | grep "input_tp" | cut -d: -f2 | tr -d '":, ')
	loudness_range=$(echo "$loudness" | grep "input_lra" | cut -d: -f2 | tr -d '":, ')

	_loudness_stats=([0]="$integrated_loudness" [1]="$true_peak" [2]="$loudness_range")

	debug "Loudness stats for $file: ${_loudness_stats[*]}"
}

#
# Extract metadata tags from ffprobe output.
#
function get_metadata() {
	local file="$1" field="" FFPROBE=""
	local -n _metadata="$2"

	[[ -z "$file" ]] && { error_log "ERROR: get_metadata() requires a filename"; return 1; }

	FFPROBE=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>&1) \
		|| { error_log "ERROR: ffprobe failed to process \"$file\""; return 1; }
	readonly FFPROBE

	for field in "GENRE" "ARTIST" "ALBUM" "track" "DATE"; do
		_metadata["$field"]=$(jq -r --arg field "$field" '.format.tags[$field] // empty' <<< "$FFPROBE")
		[[ -z "${_metadata["$field"]}" ]] && _metadata["$field"]=""
		debug "Metadata $field for \"$file\": ${_metadata["$field"]}"
	done

	for field in "sample_rate" "bit_rate" "bits_per_raw_sample"; do
		_metadata["$field"]=$(jq -r --arg f "$field" '.streams[0][$f] // .format[$f] // empty' <<< "$FFPROBE")
		debug "Metadata $field for \"$file\": ${_metadata["$field"]}"
	done

	_metadata["duration"]=$(jq -r '.format.duration // empty' <<< "$FFPROBE" | awk '{printf "%.0f", $1}')
	debug "Metadata duration for \"$file\": ${_metadata["duration"]}"
}

#
# Utility function to check if a value is in an array.
#
function in_array() {
	local needle="$1" item="$2"
	shift 1
	for item in "$@"; do
		[[ "$item" == "$needle" ]] && return 0
	done
	return 1
}

#
#	Convert a value to an integer if it's a valid number, otherwise return empty string.
#
function integerize() {
    if [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%.0f" "$1"
    else
        echo ""
    fi
}

#
# Validate that the provided extension is in the list of supported audio formats.
#
function is_extension_valid() {
	local ext="$1"
	[[ -z "$ext" ]] && return 1
	in_array "$ext" "${DEFAULT_EXTENSIONS[@]}" && return 0
	return 1
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

	while kill -0 "$pid" 2> /dev/null; do
		printf "\r%s... %s" "${message:0:$((COLS-5))}" "${frames[$i]}" 1>&2
		i=$(( (i + 1) % ${#frames[@]} ))
		sleep 0.1
	done

	# Clear the spinner line and restore cursor
	printf "\r\033[K" 1>&2
	tput cnorm 1>&2
}

#
# Validate all extensions in the users --extensions option.
#
function validate_extensions() {
	local ext
	for ext in "${EXTENSIONS[@]}"; do
		if ! is_extension_valid "$ext"; then
			error_log "ERROR: unrecognized extension: $ext"
		fi
	done
}

#
# Show usage/help text.
#
function help() {
	echo -e "\e[38;5;214m
╭──────────────────────────────────────────────────────────────────────────────╮
│                                                                              │
│                        Welcome to Recording Analyzer!                        │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
\e[0m
Usage:
	$THIS_PGM \"<audio_file>\" ...
	- or -
	$THIS_PGM \"<directory>\" ...

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
  -d, --debug       Enable debug mode to show detailed processing information
  -e, --extensions  Specify a custom list of audio file extensions to analyze
  -h, --help        Show this help message and exit
  -j, --json        Output results in JSON format (default: human-readable text)
  -l, --limit N     Limit processing to the first N audio files found
                    (default: no limit)
  -m, --metadata    Include metadata fields in output
  -q, --quiet       Suppress progress spinner and other non-essential output
  -r, --recurse     Recursively search directories for audio files
  -v, --version     Show program version and exit

  Examples:
	# Analyze a single file with human-readable output
	$THIS_PGM \"~/Music/track.flac\"

	# Analyze all music files in a directory recursively
	$THIS_PGM --recurse \"~/Music\"

	# Analyze files and directories with metadata included
	$THIS_PGM --metadata \"~/Music/track.flac\" \"../song.mp3\"

	# Analyze music files and redirect JSON output to a file for use with
	#  the web page at https://recording-analyzer.mcochris.com/
	$THIS_PGM --json --metadata \"~/Music/*.flac\" > analysis_results.json

	For more details, please visit the GitHub repository:
	https://github.com/mcochris/Recording-analyzer

	Questions, issues, suggestions? Please open a support ticket at:
	https://github.com/mcochris/Recording-analyzer/issues
"
}

# ╭──────────────────────────────────────────────────────────────────────────────╮
# │                                                                              │
# │             End of function definitions, main logic starts here.             │
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
# Get the program name for usage messages and other references.
#
THIS_PGM=$(basename "$0")
readonly THIS_PGM

#
# Check for minimum Bash version (4.3 or greater) since we rely on associative arrays and other features not available in older versions.
#
if [ -z "$BASH_VERSION" ]; then
    echo 'Cannot detect Bash version. Are you running this with Bash?' >&2
    exit 1
fi
if [ "${BASH_VERSINFO[0]}" -lt 4 ] || [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 3 ]; then
    echo 'Bash version 4.3 or greater is required for this script.' >&2
    echo "You appear to be running version $BASH_VERSION." >&2
    exit 1
fi

#
# Check for required external programs.
#
for cmd in ffmpeg ffprobe jq; do
	command -v "$cmd" &> /dev/null || { echo "Error: Required program \"$cmd\" not found" >&2; exit 1; }
done

#
# The global variables and constants.
#
CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/$THIS_PGM/version_check"
CACHE_TTL=86400
readonly CURRENT_VERSION="v2.0.1"
readonly CACHE_FILE CACHE_TTL DEFAULT_EXTENSIONS=(aac ac3 aif aiff amr caf flac m4a mp3 ogg opus pcm wav wma)
EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
DEBUG=false
RECURSE=false
JSON_OUTPUT=false
INCLUDE_METADATA=false
QUIET=false
LIMIT=0
declare -a JSON_REPORT=()
TEXT_REPORT=""

#
# Create temporary files for error logging and results.
#
ERROR_LOG="$(mktemp)"
readonly ERROR_LOG
RESULTS_FILE="$(mktemp)"
readonly RESULTS_FILE

#
# Get terminal width for dynamic output formatting (e.g., spinner messages).
#
COLS=$(tput cols)
readonly COLS

#
# Set traps for signals to ensure cleanup is performed.
#
trap 'echo "Aborted."; cleanup; exit 130' SIGINT
trap 'echo "Terminated."; cleanup; exit 143' SIGTERM
trap cleanup EXIT

#
# Check if at least one argument is provided, otherwise show usage and exit.
#
[[ $# -eq 0 ]] && { help; exit 1; }

#
# Loop through options and arguments, handling known flags and collecting positional arguments for file processing.
#
POSITIONAL=()
ARGUMENTS=("$@")
while [[ $# -gt 0 ]]; do
	case "$1" in
		-d|--debug)
			DEBUG=true
			shift
			;;
		-e|--extensions)
			if (($# < 2)) || [[ -z ${2:-} ]]; then
				error_log "Error: --extensions requires an argument"
				exit 1
			fi
			read -r -a EXTENSIONS <<< "$2"
			validate_extensions
			shift 2
			;;
		-h|--help|-\?)
			help
			exit 0
			;;
		-j|--json)
			JSON_OUTPUT=true
			shift
			;;
		-l|--limit)
			if (($# < 2)) || ! [[ "$2" =~ ^[0-9]+$ ]]; then
				error_log "Error: --limit requires a numeric argument"
				exit 1
			fi
			LIMIT="$2"
			shift 2
			;;
		-m|--metadata)
			INCLUDE_METADATA=true
			shift
			;;
		-q|--quiet)
			QUIET=true
			shift
			;;
		-r|--recurse)
			RECURSE=true
			shift
			;;
		-v|--version)
			echo "$THIS_PGM $CURRENT_VERSION"
			exit 0
			;;
		--)
			shift
			POSITIONAL+=("$@")
			break
			;;
		-*)
			error_log "Error: unknown option: $1"
			help >&2
			exit 1
			;;
		*)
			POSITIONAL+=("$1")
			shift
			;;
	esac
done

#
# If no positional arguments were collected, show usage and exit.
#
if ((${#POSITIONAL[@]} == 0)); then
	help >&2
	exit 1
fi

#
# May help remote debugging efforts.
#
debug "Bash version: $BASH_VERSION"
debug "Machine type: $MACHTYPE"
debug "Program version: $CURRENT_VERSION"
debug "Program args: ${ARGUMENTS[*]}"

#
# Main script logic
#
for positional in "${POSITIONAL[@]}"; do
	debug "main(): Positional argument: $positional"

	readarray -t find_parameters < <(create_find_parameters "$positional")
	if [[ ! ${find_parameters[*]} ]]; then
		debug "main(): No find parameters generated for $positional, skipping."
		continue
	fi

	debug "main(): Find parameters: ${find_parameters[*]}"
	if [[ ${#find_parameters[@]} -ne 2 ]]; then
		FILES=("$positional")
	else
		FOUND_FILES=$(mktemp)
		find_files "${find_parameters[@]}" > "$FOUND_FILES" 2>> "$ERROR_LOG" &
		TASK_PID=$!
		[[ "$QUIET" == "false" ]] && spinner $TASK_PID "Looking for files on \"$positional\""
		wait $TASK_PID
		readarray -t FILES < "$FOUND_FILES"
		rm -f "$FOUND_FILES" 2> /dev/null

		debug "main(): ${#FILES[@]} files found for $positional: $(printf '\n%s' "${FILES[@]}")"
		if [[ ${#FILES[@]} -eq 0 ]]; then
			debug "main(): No files found for $positional, skipping."
			error_log "ERROR: No files found for \"$positional\""
			continue
		fi
	fi

	i=1
	TEXT_REPORT=""
	JSON_REPORT=()
	for file in "${FILES[@]}"; do
		debug "main(): Processing file $i of ${#FILES[@]}: \"$file\""

		# Prepend a metadata=true record to the JSON_REPORT for later use on the web site
		if [[ "$JSON_OUTPUT" == true && "$INCLUDE_METADATA" == true && $i -eq 1 ]]; then
			echo "{\"metadata\": true}" > "$RESULTS_FILE" 2>> "$ERROR_LOG"
			debug "main(): Prepending metadata=true record to JSON_REPORT for later use on the web site"
			JSON_REPORT+=("$(cat "$RESULTS_FILE")")
		fi

		generate_report "$file" "$i" > "$RESULTS_FILE" 2>> "$ERROR_LOG" &
		TASK_PID=$!
		[[ "$QUIET" == "false" ]] && spinner $TASK_PID "Processing file $i of ${#FILES[@]}: \"$(basename "$file")\""
		wait $TASK_PID

		if [[ "$JSON_OUTPUT" == "true" ]]; then
			JSON_REPORT+=("$(cat "$RESULTS_FILE")")
		else
			TEXT_REPORT+="$(cat "$RESULTS_FILE")"$'\n'
		fi

		debug "main(): Finished processing file $i: \"$file\"."

		((i++))
	done

	if [[ "$JSON_OUTPUT" == true ]]; then
		printf '%s\n' "${JSON_REPORT[@]}" | jq -s '.'
	else
		echo "$TEXT_REPORT"
	fi
done

#
# Check for program updates.
#
[[ "$QUIET" == "false" ]] && check_for_update