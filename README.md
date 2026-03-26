Audio Recording Analyzer

Usage: recording-analyzer.sh <audio_file>
Example: recording-analyzer.sh recording.wav

This program is used to analyze an audio file and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.

Analyzes an audio file for:
- Peak level (dBFS)
- Noise floor (dBFS)
- Dynamic range (dB)
- Crest factor
- Stereo correlation (if stereo)
- Loudness (EBU R128: Integrated, True Peak, Loudness Range)

Requirements: mktemp ffmpeg awk grep printf seq basename cat tput

The script uses ffmpeg to analyze the audio file and extract various statistics
about the recording. The ffmpeg astats, loudnorm, aphasemeter, and ametadata
filters are used to analyze the audio file

Peak level is the maximum absolute amplitude of the audio signal, expressed in
decibels relative to full scale (dBFS). A value of 0 dBFS represents the
maximum possible digital level, while negative values indicate levels below
that. A peak level close to 0 dBFS may indicate potential clipping.

Noise floor is the level of background noise in the recording in dBFS.

Dynamic range is the difference in decibels between the peak level and the
noise floor.

Crest factor is the ratio of the peak level to the RMS (root mean square) level
of the audio signal, which can provide insight into the transient characteristics
of the recording. A higher crest factor may indicate a more dynamic recording
with more pronounced peaks.

Stereo correlation measures the similarity between the left and right channels
of a stereo recording. Values close to +1 indicate highly correlated channels
(mono-like), values close to 0 indicate uncorrelated channels (wide stereo),
and values close to -1 indicate anti-correlated channels (out of phase).

Loudness (EBU R128) is a standardized way to measure the perceived loudness of
audio. The integrated loudness represents the overall loudness of the recording,
the true peak indicates the maximum true peak level, and the loudness range
represents the variation in loudness throughout the recording.
