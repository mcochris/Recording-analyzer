#!/usr/bin/env bash

source ./threshold.sh
AUDIO_FILE=""
LEFT_PEAK_LEVEL=""
RIGHT_PEAK_LEVEL=""
DEBUG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)
            DEBUG="$1"
            shift
            ;;
        --left-peak-level)
            LEFT_PEAK_LEVEL="$2"
            shift 2
            ;;
        --right-peak-level)
            RIGHT_PEAK_LEVEL="$2"
            shift 2
            ;;
        *)
			AUDIO_FILE="$1"
            shift
            ;;
    esac
done

debug() {
	[[ -n "$DEBUG" ]] && echo "$0: DEBUG[${BASH_LINENO[0]}]: $*"
	return 0
}

debug "THRESHOLD: $THRESHOLD"

[[ -z "$AUDIO_FILE" ]] && { echo "$0: Error: No audio file specified"; exit 1; }
[[ -e "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file does not exist: $AUDIO_FILE"; exit 1; }
[[ -f "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not a regular file: $AUDIO_FILE"; exit 1; }
[[ -r "$AUDIO_FILE" ]] || { echo "$0: Error: Audio file is not readable: $AUDIO_FILE"; exit 1; }

[[ -z "$LEFT_PEAK_LEVEL" ]] && { echo "$0: Error: Left peak level not specified"; exit 1; }
[[ -z "$RIGHT_PEAK_LEVEL" ]] && { echo "$0: Error: Right peak level not specified"; exit 1; }

[[ -n "$LEFT_PEAK_LEVEL" ]] && remix=1
[[ -n "$RIGHT_PEAK_LEVEL" ]] && remix=2

read -r max_amplitude < <(sox "$AUDIO_FILE" -n remix "$remix" stat 2>&1 |
    grep --ignore-case "Maximum amplitude" |
    sed --quiet 1p |
    cut -w --fields 3)

debug "SoX reads a Max amplitude of $max_amplitude for the left channel"

dBFS=$(echo "20 * l($max_amplitude) / l(10)" | bc -l)

debug "Calculated dBFS for the left channel: $dBFS"

if ! echo "if (a($dBFS - $LEFT_PEAK_LEVEL) < $THRESHOLD) 1 else 0" | bc -l | grep --quiet --line-regexp "1"; then
    echo "$0: Error: Left peak level is not within threshold"
    exit 1
fi

read -r max_amplitude < <(sox "$AUDIO_FILE" -n remix "$remix" stat 2>&1|
    grep --ignore-case "Maximum amplitude" |
    sed --quiet 1p |
    cut -w --fields 3)

debug "SoX reads a Max amplitude of $max_amplitude for the right channel"

dBFS=$(echo "20 * l($max_amplitude) / l(10)" | bc -l)

debug "Calculated dBFS for the right channel: $dBFS"

if ! echo "if (a($dBFS - $RIGHT_PEAK_LEVEL) < $THRESHOLD) 1 else 0" | bc -l | grep --quiet --line-regexp "1"; then
    echo "$0: Error: Right peak level is not within threshold"
    exit 1
fi
