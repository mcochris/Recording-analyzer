#!/usr/bin/env bash

file=$1
readonly file

function error_log() {
	echo "Error: $1" >&2
}

FFPROBE=$(ffprobe -v quiet -print_format json -show_format -show_streams "$file" 2>&1) || { error_log "ffprobe failed to process \"$file\""; return; }
readonly FFPROBE

function get_metadata_tags() {
	local field="$1"
	echo "$FFPROBE" | jq -r --arg field "$field" '.format.tags[$field] // empty'
}

function get_metadata_stream() {
	local field="$1"
	echo "$FFPROBE" | jq -r --arg field "$field" '.streams[0].tags[$field] // empty'
}

function integerize() {
	local value="$1"
	if [[ "$value" =~ ^[0-9]+$ ]]; then
		echo $((10#$value))  # 10# forces base-10, stripping leading zeros
	else
		echo ""
	fi
}

date="$(get_metadata_tags "DATE")"
#track=$(integer "$track")
#echo "track = \"$track\""
echo "date = \"$date\""