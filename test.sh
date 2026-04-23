#!/usr/bin/env bash

readonly DEFAULT_EXTENSIONS="aac ac3 aif aiff amr caf flac m4a mp3 ogg opus pcm wav wma"

readonly options << EOF

Possible starting points find cmd:
.
/
/dir
/dir/*
/dir/dir...
~
~/
~/dir
~/dir/*
~/dir/dir...

Possible file patterns:
file
file.ext
*.ext
file.*

Options:
- recurse
- extensions

EOF
$options

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

RECURSE=false
POSITIONAL=()
EXTENSIONS="$DEFAULT_EXTENSIONS"

while [[ $# -gt 0 ]]; do
	case "$1" in
		-r|--recurse)
			RECURSE=true
			shift
			;;
		-e|--extensions)
			if [[ -n "$2" ]]; then
				EXTENSIONS="$2"
				shift 2
			else
				error_log "Error: --extensions option requires an argument"
				exit 1
			fi
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

set -- "${POSITIONAL[@]}"

# don't allow wildcards in extensions

echo "extensions: $EXTENSIONS"

for arg in "${POSITIONAL[@]}"; do
	# determine if arg is a directory, file, or glob pattern
	if [[ -d "$arg" ]]; then
		echo "arg is a directory"
		dir="$arg"
	elif [[ -f "$arg" ]]; then
		echo "arg is a file"
	else
		echo "arg is a glob pattern"
	fi

	# if file is empty, find all files with the specified extensions
	if [[ -n "$dir" ]]; then
		echo "building regex for extensions: $EXTENSIONS"
		find_args=""
		for ext in $EXTENSIONS; do
			find_args+="${ext} "
		done
		find_args=${find_args% }
		find_args=${find_args// /\\\|}
		find_args="-iregex .*\.\($find_args\)$"
	fi

	if [[ $RECURSE = false ]]; then
		recurse="-maxdepth 1"
	else
		recurse=""
	fi

	if [[ -z "$dir" ]]; then
		echo "listing files: \"$arg\""
		ls "$arg"
	else
		echo "find args: \"$find_args\""
		find "$dir" $recurse -type f -a $find_args -print0 | while IFS= read -r -d '' file; do
			echo "found file: \"$file\""
		done
	fi
done