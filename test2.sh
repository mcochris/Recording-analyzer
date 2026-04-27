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
DEBUG=false
RECURSE=false
JSON_OUTPUT=false
INCLUDE_METADATA=false
QUIET=false
LIMIT=0
i=0

#
# Cleanup function to display error log on exit.
#
function cleanup() {
	echo -e "$ERROR_LOG"
}

trap 'echo "Aborted."; cleanup; exit 130' SIGINT
trap 'echo "Terminated."; cleanup; exit 143' SIGTERM
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
    if [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%.0f" "$1"
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
				_channel_stats["$channel:$field"]=""
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
	local -n _loudness_stats="$2"
	local loudness integrated_loudness true_peak loudness_range

	[[ -z "$file" ]] && { error_log "ERROR: get_loudness requires a file"; return 1; }

	loudness=$(ffmpeg -hide_banner -i "$file" -af loudnorm=print_format=json -f null - 2>&1 | awk '/^{/,/^}/') \
		|| { error_log "ERROR: ffmpeg failed to run loudnorm on \"$file\""; return 1; }

	integrated_loudness=$(echo "$loudness" | grep "input_i" | cut -d: -f2 | tr -d '":, ')
	true_peak=$(echo "$loudness" | grep "input_tp" | cut -d: -f2 | tr -d '":, ')
	loudness_range=$(echo "$loudness" | grep "input_lra" | cut -d: -f2 | tr -d '":, ')

	_loudness_stats=([0]="$integrated_loudness" [1]="$true_peak" [2]="$loudness_range")

	debug "Loudness stats for $file: ${_loudness_stats[*]}"
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
		| awk -F '=' '{ sum+=$2; n++ } END { if (n>0) printf "%.2f", sum/n; else print "" }')

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
		[[ -z "${_metadata["$field"]}" ]] && _metadata["$field"]=""
	done

	#[[ "${_metadata["track"]}" != "n/a" ]] && _metadata["track"]=$(integerize "${_metadata["track"]}")

	for field in "sample_rate" "bit_rate" "bits_per_raw_sample"; do
		_metadata["$field"]=$(jq -r --arg f "$field" '.streams[0][$f] // .format[$f] // empty' <<< "$FFPROBE")
		#[[ -z "${_metadata["$field"]}" ]] && _metadata["$field"]="n/a"
		#[[ "${_metadata["$field"]}" != "n/a" ]] && _metadata["$field"]=$(integerize "${_metadata["$field"]}")
	done

	_metadata["duration"]=$(jq -r '.format.duration // empty' <<< "$FFPROBE" | awk '{printf "%.0f", $1}')
	#[[ -z "${_metadata["duration"]}" ]] && _metadata["duration"]="n/a"
	#[[ "${_metadata["duration"]}" != "n/a" ]] && _metadata["duration"]=$(integerize "${_metadata["duration"]}")
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

function find_files() {
	debug "find_files called with arguments: $*"
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
	local file="$1" json_object1 json_object2 json_object3
	readonly file
	declare -A channel_stats metadata loudness_stats
	declare num_channels
	local channel_stats num_channels average_phase track duration sample_rate \
		bit_rate bits_per_raw_sample text

	debug "Generating report for file: $file"

	[[ -f "$file" && -r "$file" && -s "$file" ]] || { error_log "ERROR: file not found, not readable, or empty: \"$file\""; return 1; }

	get_channel_stats "$file" channel_stats num_channels || { error_log "ERROR: failed to get astats for \"$file\""; return 1; }

	[[ "$num_channels" -gt 2 ]] && error_log "WARNING: more than 2 channels detected in \"$file\"; only processing first 2 channels"

	average_phase=$(get_average_phase "$file") || { error_log "ERROR: failed to get stereo phase for \"$file\""; return 1; }

	get_loudness "$file" loudness_stats || { error_log "ERROR: failed to get loudness for \"$file\""; return 1; }

	if [[ "$INCLUDE_METADATA" == true ]]; then
		get_metadata "$file" metadata || { error_log "ERROR: failed to get metadata for \"$file\""; return 1; }
	fi

	if [[ "$JSON_OUTPUT" == "false" ]]; then
		echo ""
		text="Audio Analysis: \"$(basename "$file")\""
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
	fi

	#JSON_REPORT=$(if [[ "$JSON_OUTPUT" = "true" ]]; then
	if [[ "$JSON_OUTPUT" == "true" ]]; then
		echo "Generating JSON report for \"$file\""
		#echo "  {"
		#echo "    \"id\": $i,"
		#echo "    \"path\": \"$(dirname "$(realpath "$file")")\","
		#echo "    \"file\": \"$(basename "$file")\","
		#if [[ "$INCLUDE_METADATA" == true ]]; then
		#	echo "    \"genre\": \"${metadata["GENRE"]}\","
		#	echo "    \"artist\": \"${metadata["ARTIST"]}\","
		#	echo "    \"album\": \"${metadata["ALBUM"]}\","
		#	echo "    \"track\": \"${metadata["track"]}\","
		#	echo "    \"duration\": \"${metadata["duration"]}\","
		#	echo "    \"year\": \"${metadata["DATE"]}\","
		#	echo "    \"sample_rate\": \"${metadata["sample_rate"]}\","
		#	echo "    \"bit_rate\": \"${metadata["bit_rate"]}\","
		#	echo "    \"bits_per_sample\": \"${metadata["bits_per_raw_sample"]}\","
		#fi
		#echo "    \"left_peak_level_dB\": \"${channel_stats["1:Peak level dB"]}\","
		#echo "    \"left_noise_floor_dB\": \"${channel_stats["1:Noise floor dB"]}\","
		#echo "    \"left_crest_factor_dB\": \"${channel_stats["1:Crest factor"]}\","
		#echo "    \"right_peak_level_dB\": \"${channel_stats["2:Peak level dB"]}\","
		#echo "    \"right_noise_floor_dB\": \"${channel_stats["2:Noise floor dB"]}\","
		#echo "    \"right_crest_factor_dB\": \"${channel_stats["2:Crest factor"]}\","
		#echo "    \"average_phase\": \"$average_phase\","
		#echo "    \"integrated_loudness_LUFS\": \"${loudness_stats[0]}\","
		#echo "    \"true_peak_dBTP\": \"${loudness_stats[1]}\","
		#echo "    \"loudness_range_LU\": \"${loudness_stats[2]}\""
		#echo "  },"

	    json_object1=$(jq -n \
			--argjson 	id					"$i"									\
			--arg		path				"$(dirname "$(realpath "$file")")"		\
			--arg		file				"$(basename "$file")"					\
			--argjson	left_peak_dB		"${channel_stats["1:Peak level dB"]}"	\
			--argjson	left_noise_dB		"${channel_stats["1:Noise floor dB"]}"	\
			--argjson	left_crest_dB		"${channel_stats["1:Crest factor"]}"	\
			--argjson	right_peak_dB		"${channel_stats["2:Peak level dB"]}"	\
			--argjson	right_noise_dB		"${channel_stats["2:Noise floor dB"]}"	\
			--argjson	right_crest_dB		"${channel_stats["2:Crest factor"]}"	\
			--argjson	average_phase		"$average_phase"						\
			--argjson	integrated_loudness	"${loudness_stats[0]}"					\
			--argjson 	true_peak_dBTP		"${loudness_stats[1]}"					\
			--argjson	loudness_range_LU	"${loudness_stats[2]}"					\
			'{id: $id, path: $path, file: $file, left_peak_dB: $left_peak_dB, left_noise_dB: $left_noise_dB, left_crest_dB: $left_crest_dB, right_peak_dB: $right_peak_dB, right_noise_dB: $right_noise_dB, right_crest_dB: $right_crest_dB, average_phase: $average_phase, integrated_loudness_LUFS: $integrated_loudness, true_peak_dBTP: $true_peak_dBTP, loudness_range_LU: $loudness_range_LU}')

		if [[ "$INCLUDE_METADATA" == true ]]; then
			json_object2=$(jq -n \
				--arg		genre			"${metadata["GENRE"]:-}"		\
				--arg		artist			"${metadata["ARTIST"]:-}"		\
				--arg		album			"${metadata["ALBUM"]:-}"		\
				--arg	track			"${metadata["track"]:-}"		\
				--arg	duration		"${metadata["duration"]:-}"		\
				--arg	year			"${metadata["DATE"]:-}"			\
				--arg	sample_rate		"${metadata["sample_rate"]:-}"	\
				--arg	bit_rate		"${metadata["bit_rate"]:-}"		\
				--arg	bits_per_sample	"${metadata["bits_per_raw_sample"]:-}"	\
				'{genre: $genre, artist: $artist, album: $album, track: $track, duration: $duration, year: $year, sample_rate: $sample_rate, bit_rate: $bit_rate, bits_per_sample: $bits_per_sample} | with_entries(select(.value != ""))')

				json_object3=$(jq -n --argjson base "$json_object1" --argjson metadata "$json_object2" '$base * $metadata')
				printf '%s\n' "${json_object3[@]}" | jq -s '.'
		else
			printf '%s\n' "${json_object1[@]}" | jq -s '.'
		fi
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
	if [[ ${#find_parameters[@]} -ne 2 ]]; then
		FILES=("$positional")
	else
		readarray -t FILES < <(find_files "${find_parameters[@]}")
		debug "${#FILES[@]} files found for $positional: $(printf '\n%s' "${FILES[@]}")"
	fi
	i=1
	#[[ "$JSON_OUTPUT" == "true" ]] && JSON_REPORT="["
	for file in "${FILES[@]}"; do
		generate_report "$file"
		((i++))
	done
	#if [[ "$JSON_OUTPUT" == "true" ]]; then
	#	echo "$JSON_REPORT" | sed '$ s/,$/]/' | jq "."
	#fi
done
