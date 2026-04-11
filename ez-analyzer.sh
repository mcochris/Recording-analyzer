#!/usr/bin/env bash

#
# This script provides a user-friendly interface for selecting a directory of
# audio files to analyze with recording-analyzer.sh. It uses the gum tool to
# create interactive prompts for the user to choose which file types to include
# in the analysis and which options to enable. The script validates the user's
# input and generates a list of files to be processed by recording-analyzer.sh
# based on the selected criteria.
#

#set -o xtrace
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
trap 'echo "ERROR: line $LINENO command \"$BASH_COMMAND\" exited with status $?" >&2' ERR

readonly HELP="
EZ Analyzer

Usage: ez-analyzer.sh

This script will guide you through selecting a directory of audio files to
analyze with recording-analyzer.sh. You will be prompted to choose which file
types to include in the analysis and which options to enable. The script will
validate your input and generate a list of files based on your selected
criteria. These files will then be processed by recording-analyzer.sh.

If you only want to analyze a specific set of files and not a directory of
files, please use recording-analyzer.sh directly with the appropriate
options and file paths. For example:

  # Analyze a single file with human-readable output
	recording-analyzer.sh ~/Music/track.flac

ez-analyzer options:
  -h, --help        Show this help message and exit
  -v, --version     Show program version and exit

Questions, issues, or suggestions? Please open a support ticket at:
https://github.com/mcochris/Recording-analyzer/issues
"

readonly VERSION="1.0.0"
POSITIONAL=()

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
		help|-h|--help)
			echo "$HELP"
			exit 0
			;;
		-v|--version)
			echo "ez-analyzer.sh version $VERSION"
			exit 0
			;;
        *)
			POSITIONAL+=("$1")
			shift
			;;
    esac
done

# Positional arguments are not allowed for this script, so if any are present
# after parsing options, exit with an error
set -- "${POSITIONAL[@]}"
[[ $# -gt 0 ]] && echo "Too many arguments provided. Please provide only the options specified in the help message. Exiting." && exit 1

# Define supported audio file extensions. The formats must be supported by ffmpeg
# to be analyzed successfully.
readonly extensions="aac wav mp3 flac m4a ogg caf aiff aif pcm wma opus ac3 amr"

# Check if gum is installed
if ! command -v gum &> /dev/null; then
	echo "gum is not installed. Please install gum to use this script."
	exit 1
fi

# Check if recording-analyzer.sh is installed
if ! command -v recording-analyzer.sh &> /dev/null; then
	echo "recording-analyzer.sh is not installed or not in your PATH. Please install recording-analyzer.sh to use this script."
	exit 1
fi

# Display welcome message and instructions
echo ""
gum style --border rounded --align center --width 80 --padding "1 1" 'Welcome to recording-analyzer!'

echo "
This script will help you analyze your music collection using
recording-analyzer.sh. It will guide you through selecting a directory,
choosing which file types to analyze, and which options to include in the
analysis. Press the spacebar to select an item/s in lists.
"

# Prompt user for directory to scan
search_dir=$(gum input --prompt="What directory do you want to scan for music files: ")

# Validate directory input
[[ -z "$search_dir" ]] && echo "No directory entered. Exiting." && exit 1
resolved_dir=$(realpath "${search_dir/#\~/$HOME}")
[[ ! -d "$resolved_dir" ]] && echo "Directory \"$resolved_dir\" does not exist. Exiting." && exit 1
[[ ! -r "$resolved_dir" ]] && echo "Directory \"$resolved_dir\" is not readable. Exiting." && exit 1
echo "  You entered \"$resolved_dir\"
"

# Prompt user for whether to include subdirectories in the search
echo "Do you want to include subdirectories in the search?"
scan_subdirs=$(gum choose --limit 1 Yes No)

# Validate subdirectory choice
find_opts=""
[[ -z "$scan_subdirs" ]] && echo "No choice made. Exiting." && exit 1
[[ "$scan_subdirs" != "Yes" && "$scan_subdirs" != "No" ]] && echo "Invalid choice. Exiting." && exit 1
[[ "$scan_subdirs" = "No" ]] && find_opts="-maxdepth 1"
echo "
  You entered \"$scan_subdirs\"
"

# Search for audio files in the specified directory with the chosen options
echo "Searching for audio files in $resolved_dir..."
# shellcheck disable=SC2086
# shellcheck disable=SC2001
found=$(find "$resolved_dir" -type f $find_opts -regextype posix-extended -iregex ".*\.($(echo $extensions | sed 's/ /|/g'))$" 2> /dev/null)

# Check if any audio files were found
[[ -z "$found" ]] && echo "No audio files found in $resolved_dir. Exiting." && exit 1

# Display found file types and prompt user to select which ones to analyze
echo "Found $(echo "$found" | wc -l) audio files in $resolved_dir. Chose which file types you want to analyze: "
extensions_found=$(echo "$found" | sed --regexp-extended 's/.*\.([a-zA-Z0-9]+)$/\1/' | tr '[:upper:]' '[:lower:]' | sort | uniq --count | sort --numeric-sort --reverse | awk '{print $2 " (" $1 " files)"}')

# Add "All" option to the list of extensions
extensions_found="All"$'\n'"$extensions_found"

# Prompt user to select which extensions to include in the analysis
extensions_selected=$(echo "$extensions_found" | gum choose --no-limit)

# Validate extension selection
[[ -z "$extensions_selected" ]] && echo "No choice made. Exiting." && exit 1
echo "
  You entered: $extensions_selected
"

# Generate list of files to analyze based on selected extensions
if echo "$extensions_selected" | grep --quiet --word-regexp "All"; then
	selected_files="$found"
elif [[ "$extensions_selected" = "None" ]]; then
	echo "No file types selected. Exiting."
	exit 1
else
	selected_exts=$(echo "$extensions_selected" | sed --regexp-extended 's/ \([0-9]+ files\)$//')
	selected_files=$(echo "$found" | grep --extended-regexp "\.($(echo "$selected_exts" | tr '\n' '|' | sed 's/ /|/g; s/|$//'))$" 2> /dev/null)
fi

# Check if any files were selected for analysis
[[ -z "$selected_files" ]] && echo "No files found for the selected extensions. Exiting." && exit 1
mapfile -t selected_files_array <<< "$selected_files"

# Prompt user to select which options to include in the analysis
echo "What options do you want?"
options=$(gum choose --no-limit "Include metadata" "Output JSON" "Quiet mode" "None")
echo "
  You entered: $options
"

# Validate options selection
[[ -z "$options" ]] && echo "No choice made. Exiting." && exit 1

# Check if "None" is selected along with other options, which is not allowed
echo "$options" | grep --quiet --word-regexp "None" && none_selected=true || none_selected=false
if [[ "$none_selected" = true && $(echo "$options" | wc -l) -gt 1 ]]; then
	echo "You cannot select 'None' with other options. Please select either 'None' or the other options. Exiting."
	exit 1
fi

# Set flags based on selected options
command_line_options=()
echo "$options" | grep --quiet --word-regexp "Include metadata" && command_line_options+=("--metadata")
echo "$options" | grep --quiet --word-regexp "Output JSON" && command_line_options+=("--json")
echo "$options" | grep --quiet --word-regexp "Quiet mode" && command_line_options+=("--quiet")

echo "Ready to analyze ${#selected_files_array[@]} files. Continue?"
confirm=$(gum choose --limit 1 Yes No)
[[ "$confirm" != "Yes" ]] && echo "Aborted." && exit 0

recording-analyzer.sh ${command_line_options[@]+"${command_line_options[@]}"} "${selected_files_array[@]}"