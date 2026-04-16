#!/usr/bin/env bash

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

for cmd in ffmpeg awk seq tput; do
	command -v "$cmd" &> /dev/null || { echo "Error: Required program \"$cmd\" not found" >&2; exit 1; }
done

THIS_PGM=$(basename "$0")
readonly THIS_PGM
[[ $# -eq 0 ]] && { echo "Usage: $THIS_PGM <audio_file>"; exit 1; }

readonly HELP="
╭──────────────────────────────────────────────────────────────────────────────╮
│                                                                              │
│                        Welcome to recording-analyzer!                        │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯

Usage: $THIS_PGM <audio_file>
       - or -
       $THIS_PGM <directory>

This program is used to analyze audio files and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.

JSON output format is available for easy integration with other tools or for
further processing. Metadata fields can also be included in the output for a
more comprehensive analysis. Upload the JSON output of your audio files to the
web interface at https://mcochris.com/recording-analyzer/ to view an interactive
visualization of the statistics, create playlists and spreadsheets based on the
analysis results.

Options:
  -h, --help        Show this help message and exit
  -v, --version     Show program version and exit
  -q, --quiet       Suppress progress spinner and other non-essential output
  -j, --json        Output results in JSON format (default: human-readable text)
  -m, --metadata    Include metadata fields (genre, artist, album, track,
                    duration, year, sample rate, bit rate) in output
  -r, --recurse     Recursively search directories for audio files

  Examples:
	# Analyze a single file with human-readable output
	$THIS_PGM ~/Music/track.flac

	# Analyze all music files in a directory recursively
	$THIS_PGM --recurse ~/Music

	# Analyze multiple music files with JSON output
	$THIS_PGM --json ~/Music/*.flac

	# Analyze a single file with metadata included
	$THIS_PGM --metadata ~/Music/track.flac

	# Analyze multiple music files with JSON output and metadata included
	$THIS_PGM --json --metadata ~/Music/*.flac

	# Analyze music files and redirect JSON output to a file for use with the web
	# interface at https://mcochris.com/recording-analyzer/
	$THIS_PGM --json --metadata ~/Music/*.flac > analysis_results.json

	Questions, issues, suggestions? Please open a support ticket at:
	https://github.com/mcochris/Recording-analyzer/issues
"

#readonly PROCESSING_LIMIT=100
readonly VERSION="1.0.0"
readonly DEFAULT_EXTENSIONS=("aac" "ac3" "aif" "aiff" "amr" "caf" "flac" "m4a" "mp3" "ogg" "opus" "pcm" "wav" "wma")

#
# Parse command-line options.
#
JSON_OUTPUT="false"
INCLUDE_METADATA="false"
RECURSE_FLAG=()
POSITIONAL=()
QUIET="false"

#
# Loop through arguments and handle options
#
while [[ $# -gt 0 ]]; do
    case "$1" in
		help|-h|--help)
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
                echo "Warning: ignoring unknown option '$1'" >&2
            else
                POSITIONAL+=("$1")
            fi
            shift
            ;;
	    esac
done

readonly JSON_OUTPUT
readonly INCLUDE_METADATA
readonly QUIET
set -- "${POSITIONAL[@]}"

#
# Sanitize and load one extension from a raw token
#
function parse_extension() {
    local ext
    # Lowercase, strip leading dots and any non-alphanumeric chars except hyphens
    ext=$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/^\.*//' | tr -cd '[:alnum:]-')
    echo "$ext"
}

#
# Usage: collect_audio_files [OPTIONS] -- arg1 arg2 ...
# Sets the global array AUDIO_FILES with the resolved file list.
#
function collect_audio_files() {
    AUDIO_FILES=()
    local recurse=false
    # Parse -r flag from this function's own args
    local args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r) recurse=true ;;
            --) shift; args+=("$@"); break ;;
			*)  args+=("$1") ;;
        esac
        shift
    done

    # Build a regex pattern like \.(mp3|flac|wav|...)$ for extension matching
    local ext_pattern
    ext_pattern=$(printf '%s|' "${EXTENSIONS[@]}")
    ext_pattern="\\.(${ext_pattern%|})$"

    # Helper: add a single file if it matches an audio extension
	function _add_if_audio() {
        local f="$1"
		cols=$(tput cols)
        if [[ -f "$f" ]] && [[ "${f,,}" =~ $ext_pattern ]]; then
            AUDIO_FILES+=("$f")
			msg="Scanning... found ${#AUDIO_FILES[@]} file(s): \"$(basename "$f")\""
			[[ "$QUIET" = "false" ]] && echo -e -n "\r${msg:0:$((cols))}\033[K" >&2
            #[[ "$QUIET" = "false" ]] && printf "\rScanning... found %d file(s): \"%s\"\033[K" "${#AUDIO_FILES[@]}" "$(basename "$f")" >&2
        fi
    }

    # Helper: add audio files from a directory (non-recursive)
    function _add_dir_flat() {
        local dir="$1"
        local f
        while IFS= read -r -d '' f; do
            _add_if_audio "$f"
        done < <(find "$dir" -maxdepth 1 -type f -a \( "${find_args[@]}" \) -print0)
    }

    # Helper: add audio files from a directory (recursive)
    function _add_dir_recursive() {
        local dir="$1"
        local f
        while IFS= read -r -d '' f; do
            _add_if_audio "$f"
        done < <(find "$dir" -type f -a \( "${find_args[@]}" \) -print0)
    }

    # Process each positional argument
    local arg
    for arg in "${args[@]}"; do
        # Expand ~ manually since it won't expand inside a variable
        arg="${arg/#\~/$HOME}"

        if [[ -d "$arg" ]]; then
            # Argument is a directory
            if "$recurse"; then
                _add_dir_recursive "$arg"
            else
                _add_dir_flat "$arg"
            fi

        elif [[ -f "$arg" ]]; then
            # Argument is a literal existing file
            _add_if_audio "$arg"

        else
            # Treat as a glob pattern — use eval carefully with a controlled expand
            # We use 'compgen -G' to safely expand the glob without eval
            local match
            while IFS= read -r match; do
                if [[ -d "$match" ]]; then
                    if "$recurse"; then
                        _add_dir_recursive "$match"
                    else
                        _add_dir_flat "$match"
                    fi
                else
                    _add_if_audio "$match"
                fi
            done < <(compgen -G "$arg" 2>/dev/null)

            if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
                echo "Warning: no matches found for: $arg" >&2
            fi
        fi
    done

    # Remove duplicates while preserving order
    local seen=()
    local unique=()
    local f
    for f in "${AUDIO_FILES[@]}"; do
        local real
        real=$(realpath --strip "$f" 2>/dev/null || echo "$f")
        # shellcheck disable=SC2076
        if [[ ! " ${seen[*]} " =~ " ${real} " ]]; then
            seen+=("$real")
            unique+=("$f")
        fi
    done
    AUDIO_FILES=("${unique[@]}")
}

#
# Spinner function to show progress while long-running task is executing
#
function spinner() {
    local pid="$1"
    local message="$2"
	# shellcheck disable=SC1003
	local frames=('-' '\' '|' '/')
    local i=0
	cols=$(tput cols)

    # Hide cursor
    tput civis 1>&2

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r%s... %s" "${message:0:$((cols-5))}" "${frames[$i]}" 1>&2
        i=$(( (i + 1) % ${#frames[@]} ))
        #sleep 0.1
    done

    # Clear the spinner line and restore cursor
    printf "\r\033[K" 1>&2
    tput cnorm 1>&2
}

#
# Function to log errors to a file
#
function error_log() {
	local message="$1"
	echo "ERROR: $message" >> "$ERROR_LOG"
}

#
# Functions to extract specific pieces of information from ffprobe output
#
function get_metadata() {
	local field="$1"
	echo "$FFPROBE" | grep "$field" | head --lines 1 | awk -F '"' '{print $4}' || true
}

#
# Extract duration in seconds, rounded to nearest whole number
#
function get_duration() {
	echo "$FFPROBE" | grep '"duration"' | tail --lines 1 | awk -F '"' '{printf "%.0f", $4}' || true
}

#
# Extract a named stat from within a specific channel block
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
# Extract a field from the loudnorm JSON
#
function get_loudnorm() {
	local field="$1"
	echo "$LOUDNORM" | grep "\"$field\"" | awk -F'"' '{print $4}'
}

#
#	Function to perform the long-running analysis task for a single file
#
function long_running_task() {
	# Run ffmpeg with astats filter to get per-channel statistics
	ASTATS=$(ffmpeg -hide_banner -i "$file" -af "astats" -f null - 2>&1) || { error_log "ffmpeg failed to process \"$file\""; return; }
	readonly ASTATS

	# Check if ffmpeg produced expected astats output
	echo "$ASTATS" | grep --quiet --max-count=1 "Channel:" || { error_log "ffmpeg failed to process \"$file\" correctly"; return; }

	FFPROBE=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>&1) || { error_log "ffprobe failed to process \"$file\""; return; }
	readonly FFPROBE

	# Detect number of channels
	NUM_CHANNELS=$(echo "$ASTATS" | grep -c "Channel: [0-9]")
	if [[ "$NUM_CHANNELS" -ne 2 ]]; then
		error_log "\"$file\" is not a stereo file"
		return
	fi

	# Run loudnorm and capture the JSON output
	LOUDNORM=$(ffmpeg -hide_banner -i "$file" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/') || { error_log "ffmpeg failed to run loudnorm on \"$file\""; return; }
	readonly LOUDNORM

	# Print header and per-channel stats to results file
	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		TEXT="Audio Analysis: \"$(basename "$file")\""
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
		echo "  Crest Factor:   ${left_rounded_crest:-n/a} dB"
		echo ""
		echo "Right Channel:"
		echo "  Peak Level:     ${right_rounded_peak:-n/a} dBFS"
		echo "  Noise Floor:    ${right_rounded_noise:-n/a} dBFS"
		echo "  Crest Factor:   ${right_rounded_crest:-n/a} dB"
		echo ""
	fi

	# Stereo correlation
	average_phase=$(ffmpeg -hide_banner -i "$file" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2> /dev/null \
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

#
# Create temporary files for error logging and results output, and ensure they are cleaned up on exit
#
ERROR_LOG="$(mktemp)"
readonly ERROR_LOG
RESULTS_FILE="$(mktemp)"
readonly RESULTS_FILE
trap 'rm --force "$RESULTS_FILE" 2> /dev/null; rm --force "$ERROR_LOG" 2> /dev/null' EXIT

#
# Build the active extension list
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
            echo "Warning: skipping invalid extension token: '$raw'" >&2
        fi
    done

    if [[ ${#EXTENSIONS[@]} -eq 0 ]]; then
        echo "Warning: AUDIO_EXTENSIONS contained no valid values, using defaults." >&2
        EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
    fi
else
    EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
fi

readonly EXTENSIONS

#
# Build a find command dynamically from the array
#
find_args=()
for i in "${!EXTENSIONS[@]}"; do
    [[ $i -gt 0 ]] && find_args+=(-o)
    find_args+=(-iname "*.${EXTENSIONS[$i]}")
done
readonly find_args

collect_audio_files "${RECURSE_FLAG[@]}" -- "${POSITIONAL[@]}"
[[ "$QUIET" = "false" ]] && printf "\r\033[K" >&2
#[[ ${#AUDIO_FILES[@]} -gt $PROCESSING_LIMIT ]] && echo "$THIS_PGM: WARNING: Processing will be limited to $PROCESSING_LIMIT files." >&2

row=1

#
# Loop through all the files
#
for file in "${AUDIO_FILES[@]}"; do
	[[ -e "$file" ]] || { error_log "File \"$file\" does not exist"; continue; }
	[[ -f "$file" ]] || { error_log "File \"$file\" is not a regular file"; continue; }
	[[ -r "$file" ]] || { error_log "File \"$file\" is not readable"; continue; }
	[[ -s "$file" ]] || { error_log "File \"$file\" is empty"; continue; }

	# Run task in background, capture PID, and show spinner while it runs
	long_running_task &
	TASK_PID=$!
	[[ "$QUIET" = "false" ]] && spinner $TASK_PID "Processing file $row of ${#AUDIO_FILES[@]}: \"$(basename "$file")\""
	wait $TASK_PID
	row=$((row + 1))
	#if [[ "$row" -gt $PROCESSING_LIMIT ]]; then
	#	break
	#fi
done

#
# Finalize JSON output if needed, and display results or errors
#
if [[ "$JSON_OUTPUT" = "false" ]]; then
    echo "" >> "$RESULTS_FILE"
else
    sed --in-place '$ s/,$//' "$RESULTS_FILE"
    echo "]" >> "$RESULTS_FILE"
fi

#
# Display results
#
if [[ -s "$RESULTS_FILE" ]]; then
	cat "$RESULTS_FILE"
else
	error_log "No results to display"
fi

#
# Display any warnings about processing limits and show error logs if present
#
#[[ "$row" -gt $PROCESSING_LIMIT ]] && echo "WARNING: Processing was limited to $PROCESSING_LIMIT files." >&2

[[ -s "$ERROR_LOG" ]] && cat "$ERROR_LOG" >&2

#
# Cleanup temporary files (also handled by trap on EXIT)
#
rm --force "$RESULTS_FILE" 2> /dev/null
rm --force "$ERROR_LOG" 2> /dev/null