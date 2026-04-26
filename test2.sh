#!/usr/bin/env bash

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

#
# The global variables and constants.
#
readonly DEFAULT_EXTENSIONS=(aac ac3 aif aiff amr caf dsf dff flac m4a mp3 ogg opus pcm wav wma)
EXTENSIONS=("${DEFAULT_EXTENSIONS[@]}")
ERROR_LOG=""
REPORT=""
DEBUG=false
RECURSE=false
JSON_OUTPUT=false
INCLUDE_METADATA=false
QUIET=false
LIMIT=0

#
# Cleanup function to remove temporary files and restore terminal state on exit.
#
function cleanup() {
	echo -e "$REPORT"
	echo -e "$ERROR_LOG"
}

trap 'echo "Aborted."; exit 130' SIGINT
trap 'echo "Terminated."; exit 143' SIGTERM
trap cleanup EXIT

usage() {
cat <<'EOF'
Usage:
  ./test.sh [options] PATH_OR_PATTERN [...]

Examples:
  ./test.sh ~/Music
  ./test.sh -r ~/Music
  ./test.sh -r -e "wav flac" ~/Music
  ./test.sh -r '~/Music/*.wav'
  ./test.sh ~/Music/song.wav

Options:
  -r, --recurse                 Recurse into subdirectories
  -e, --extensions "ext ..."   Space-separated extension list for directory searches
  -h, --help                   Show this help
  -l, --limit N                   Limit the number of results (not implemented yet)
  -j, --json                    Output results in JSON format (not implemented yet)
  -m, --metadata                 Include metadata in output (not implemented yet)
  -q, --quiet                    Suppress non-error output (not implemented yet)
  -v, --version				  Show version information (not implemented yet)
  -d, --debug                    Enable debug output (not implemented yet)
EOF
}

#
# Function to log errors to the ERROR_LOG string.
#
function error_log() {
	ERROR_LOG+="$1\n"
}

function in_array() {
	local needle="$1"; shift
	local item
	for item in "$@"; do
		[[ "$item" == "$needle" ]] && return 0
	done
	return 1
}

function is_extension_valid() {
	local ext="$1"
	[[ -z "$ext" ]] && return 1
	in_array "$ext" "${DEFAULT_EXTENSIONS[@]}" && return 0
	return 1
}

function validate_extensions() {
	local ext
	for ext in "${EXTENSIONS[@]}"; do
		if ! is_extension_valid "$ext"; then
			error_log "Error: unrecognized extension: $ext"
			exit $LINENO
		fi
	done
}

function build_extension_list() {
	local ext
	for ext in "${EXTENSIONS[@]}"; do
		list+="$ext\|"
	done
	echo "${list%\\|}"  # strip trailing \|
}

function debug() {
	# don't make this a one-liner
    if [[ "${DEBUG:-false}" == true ]]; then
		echo "DEBUG [${BASH_LINENO[0]}]: $*" >&2
    fi
}

function get_command_line_args() {
	POSITIONAL=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-d|--debug)
				DEBUG=true
				shift
				;;
			-e|--extensions)
				if (($# < 2)) || [[ -z ${2:-} ]]; then
				error_log "Error: --extensions requires an argument"
				exit $LINENO
				fi
				read -r -a EXTENSIONS <<< "$2"
				validate_extensions
				shift 2
				;;
			-h|--help)
				usage
				exit 0
				;;
			-j|--json)
				JSON_OUTPUT=true
				shift
				;;
			-l|--limit)
				if (($# < 2)) || ! [[ "$2" =~ ^[0-9]+$ ]]; then
					error_log "Error: --limit requires a numeric argument"
					exit $LINENO
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
				echo "Recording Analyzer version 1.0.0"
				exit 0
				;;
			--)
				shift
				POSITIONAL+=("$@")
				break
				;;
			-*)
				error_log "Error: unknown option: $1"
				usage >&2
				exit $LINENO
				;;
			*)
				POSITIONAL+=("$1")
				shift
				;;
		esac
	done

	if ((${#POSITIONAL[@]} == 0)); then
		usage >&2
		exit $LINENO
	fi
}

#
#	Convert a value to an integer if it's a valid number, otherwise return empty string.
#
function integerize() {
    local value="$1"
    if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%.0f" "$value"
    else
        echo ""
    fi
}

#
# Extract duration in seconds, rounded to nearest whole number.
#
function get_duration() {
	echo "$FFPROBE" | jq -r '.format.duration // empty' | awk '{printf "%.0f", $1}'
}

#
# Extract channel statistics from ffmpeg astats filter output.
#
function get_channel_stats() {
	local file="$1"
	local -n _channel_stats="$2"
	local -n _num_channels="$3"

	[[ -z "$file" ]] && { error_log "ERROR: get_channel_stats requires a file and two output variables"; exit $LINENO; }

	function failed() {
		local channel
		for channel in 1 2; do
			_channel_stats["$channel:Peak level dB"]="n/a"
			_channel_stats["$channel:Noise floor dB"]="n/a"
			_channel_stats["$channel:Crest factor"]="n/a"
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

	debug "Detected $_num_channels channels in \"$file\""

	_num_channels=$(integerize "$_num_channels")
	[[ -z "$_num_channels" || "$_num_channels" -le 0 ]] \
		&& { error_log "ERROR: invalid number of channels detected in \"$file\""; failed; return 1; }

	local channel
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
				_channel_stats["$channel:$field"]="n/a"
			fi

			debug "Channel $channel $field for \"$file\": ${_channel_stats["$channel:$field"]}"
		done
	done
}

#
# Extract a field from the loudnorm JSON.
#
function get_loudness() {
	local file="$1"
	local loudness integrated_loudness true_peak loudness_range

	[[ -z "$file" ]] && { error_log "ERROR: get_loudness requires a file"; return 1; }

	loudness=$(ffmpeg -hide_banner -i "$file" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/') \
		|| { error_log "ERROR: ffmpeg failed to run loudnorm on \"$file\""; return 1; }

	integrated_loudness=$(echo "$loudness" | grep "input_i" | cut -d: -f2 | tr -d '":, ')
	true_peak=$(echo "$loudness" | grep "input_tp" | cut -d: -f2 | tr -d '":, ')
	loudness_range=$(echo "$loudness" | grep "input_lra" | cut -d: -f2 | tr -d '":, ')

	loudness_stats=(
		"Integrated loudness (LUFS)=$integrated_loudness"
		"True peak (dBTP)=$true_peak"
		"Loudness range (LU)=$loudness_range"
	)

	debug "Loudness stats for $file: ${loudness_stats[*]}"

	echo "${loudness_stats[@]}"
}

#
# Get stereo correlation by averaging the output of the aphasemeter filter.
#
function get_average_phase() {
	local file="$1"
	local average_phase

	[[ -z "$file" ]] && { error_log "ERROR: get_average_phase requires a file"; return 1; }

	average_phase=$(ffmpeg -hide_banner -i "$file" -af "aphasemeter=video=0,ametadata=print:file=-" -f null - 2> /dev/null \
		| grep 'lavfi.aphasemeter.phase' \
		| awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.2f", sum/n; else print "n/a" }')

	debug "Average phase for $file: $average_phase"

	echo "$average_phase"
}

#
# Extract metadata tags from ffprobe output.
#
function get_metadata() {
	local file="$1"
	local -n _metadata="$2"

	[[ -z "$file" ]] && { error_log "ERROR: get_metadata requires a filename"; return 1; }

	local FFPROBE
	FFPROBE=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>&1) \
		|| { error_log "ERROR: ffprobe failed to process \"$file\""; return 1; }
	readonly FFPROBE

	for field in "GENRE" "ARTIST" "ALBUM" "track" "DATE"; do
		_metadata["$field"]=$(jq -r --arg field "$field" '.format.tags[$field] // empty' <<< "$FFPROBE")
		[[ -z "${_metadata["$field"]}" ]] && _metadata["$field"]="n/a"
	done

	[[ "${_metadata["track"]}" != "n/a" ]] && integerize _metadata["track"]

	for field in "sample_rate" "bit_rate" "bits_per_raw_sample"; do
		_metadata["$field"]=$(jq -r --arg f "$field" '.streams[0][$f] // .format[$f] // empty' <<< "$FFPROBE")
		[[ -z "${_metadata["$field"]}" ]] && _metadata["$field"]="n/a"
		[[ "${_metadata["$field"]}" != "n/a" ]] && integerize _metadata["$field"]
	done

	_metadata["duration"]=$(jq -r '.format.duration // empty' <<< "$FFPROBE" | awk '{printf "%.0f", $1}')
	[[ -z "${_metadata["duration"]}" ]] && _metadata["duration"]="n/a"
	[[ "${_metadata["duration"]}" != "n/a" ]] && integerize _metadata["duration"]
}

function create_find_parameters() {
		debug "create_find_parameters called with argument: $1"
		local arg="$1"
		local dir
		dir=$(dirname "${arg}")
		local base
		base=$(basename "${arg}")

		dir=${dir/#~/$HOME}
		dir=${dir/#./$PWD}

		[[ "$base" == "~" || "$base" == "." || "$base" == "*" ]] && base=""

		if [[ -d "$dir/$base" ]]; then
			dir="$dir/$base"
			base=""
		fi

		if [[ -f "$dir/$base" ]]; then
			debug "no search needed for: $dir/$base"
			exit 0
		elif [[ -z "$base" ]]; then
			debug "search for audio files in directory: $dir"
		else
			local base_ext="${base##*.}"
			if ! is_extension_valid "$base_ext"; then
				echo "Error: unrecognized extension in filename: $base" >&2
				exit $LINENO
			fi
			debug "search for $base audio files in directory: $dir"
		fi

		local return
		return=("$dir" "$base")
		printf '%s\n' "${return[@]}"
}

function run_find() {
	debug "run_find called with arguments: $*"
	local dir="$1"
	local base="$2"

	local cmd
	cmd=("find" "$dir")
	[[ "${RECURSE:-false}" == false ]] && cmd+=("-maxdepth" "1")
	cmd+=("-type" "f")
	if [[ -n "$base" ]]; then
		cmd+=("-a" "-name" "$base")
	else
		cmd+=("-a" "-iregex" "^.*\\.\\($(build_extension_list)\\)\$")
	fi
	cmd+=("-print")

	debug "Running command: ${cmd[*]}"
	local files
	readarray -t files < <("${cmd[@]}")
	debug "Found ${#files[@]} files: $(printf '\n%s' "${files[@]}")"

	if [[ "${LIMIT:-0}" -gt 0 && "$LIMIT" -lt ${#files[@]} ]]; then
		files=("${files[@]:0:$LIMIT}")
		debug "Limited files to ${#files[@]} files: $(printf '\n%s' "${files[@]}")"
	fi

	printf '%s\n' "${files[@]}"
}

function generate_report() {
	local file="$1"
	readonly file
	declare -A channel_stats metadata
	declare num_channels
	local channel_stats num_channels average_phase genre artist album track duration date sample_rate \
		bit_rate bits_per_raw_sample

	debug "Generating report for file: $file"

	[[ -f "$file" && -r "$file" && -s "$file" ]] || { error_log "ERROR: file not found, not readable, or empty: \"$file\""; return 1; }

	get_channel_stats "$file" channel_stats num_channels || { error_log "ERROR: failed to get astats for \"$file\""; return 1; }

	# Just two channels for now.
	[[ "$num_channels" -gt 2 ]] && error_log "WARNING: more than 2 channels detected in \"$file\"; only processing first 2 channels"

	#local left_peak="${channel_stats["1:Peak level dB"]}"
	#local left_noise="${channel_stats["1:Noise floor dB"]}"
	#local left_crest="${channel_stats["1:Crest factor"]}"
	#local right_peak="${channel_stats["2:Peak level dB"]}"
	#local right_noise="${channel_stats["2:Noise floor dB"]}"
	#local right_crest="${channel_stats["2:Crest factor"]}"

	average_phase=$(get_average_phase "$file") || { error_log "ERROR: failed to get stereo phase for \"$file\""; return 1; }

	loudness=$(get_loudness "$file") || { error_log "ERROR: failed to get loudness for \"$file\""; return 1; }

	get_metadata "$file" metadata || { error_log "ERROR: failed to get metadata for \"$file\""; return 1; }

	#debug "Metadata for $file: GENRE=${metadata["GENRE"]}, ARTIST=${metadata["ARTIST"]}, ALBUM=${metadata["ALBUM"]}, track=${metadata["track"]}, DATE=${metadata["DATE"]}, sample_rate=${metadata["sample_rate"]}, bit_rate=${metadata["bit_rate"]}, bits_per_raw_sample=${metadata["bits_per_raw_sample"]}, duration=${metadata["duration"]}"

	#genre="${metadata["GENRE"]}"
	#artist="${metadata["ARTIST"]}"
	#album="${metadata["ALBUM"]}"
	#track="${metadata["track"]}"
	#date="${metadata["DATE"]}"
	#sample_rate="${metadata["sample_rate"]}"
	#bit_rate="${metadata["bit_rate"]}"
	#bits_per_raw_sample="${metadata["bits_per_raw_sample"]}"
	#duration="${metadata["duration"]}"

	# Print header and per-channel stats to results file.
	if [[ "$JSON_OUTPUT" = "false" ]]; then
		echo ""
		TEXT="Audio Analysis: \"$(basename "$file")\""
		echo "$TEXT"
		printf '=%.0s' $(seq 1 ${#TEXT})
		echo ""

		if [[ "$INCLUDE_METADATA" == true ]]; then
			echo "Metadata:"
			for key in "GENRE" "ARTIST" "ALBUM" "track" "DATE" "sample_rate" "bit_rate" "bits_per_raw_sample" "duration"; do
				printf "  %s: %s\n" "$key" "${metadata["$key"]}"
			done
			echo ""
		fi

		echo "Metadata:"
	fi


}

#
# Main script logic
#
get_command_line_args "$@"
for positional in "${POSITIONAL[@]}"; do
	debug "Positional argument: $positional"
	readarray -t find_parameters < <(create_find_parameters "$positional")
	debug "Find parameters: ${find_parameters[*]}"
	readarray -t FILES < <(run_find "${find_parameters[@]}")
	debug "${#FILES[@]} files found for $positional: $(printf '\n%s' "${FILES[@]}")"
	i=1
	for file in "${FILES[@]}"; do
		generate_report "$file"
		((i++))
	done
done
