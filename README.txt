Audio Recording Analyzer
========================

Usage: recording-analyzer.sh <audio_file>

Example: recording-analyzer.sh recording.wav

Example output:

	Audio Analysis: "Computer World.flac"
	=====================================

	Left Channel:
	Peak Level:     -0.496082 dBFS
	Noise Floor:    -inf dBFS
	Crest Factor:   12.296386

	Right Channel:
	Peak Level:     -1.051494 dBFS
	Noise Floor:    -inf dBFS
	Crest Factor:   10.675954

	Stereo Correlation:
	Average Phase:  0.4893

	Loudness (EBU R128):
	Integrated Loudness:  -19.37 LUFS
	True Peak:            -0.50 dBTP
	Loudness Range:       4.00 LU

This program is used to analyze an audio file and extract various statistics.
The script provides insights into the quality and characteristics of the
recording, which can be useful for audio engineers, musicians, and anyone
interested in understanding the technical aspects of their audio files.

Analyzes an audio file for:
- Peak level (dBFS)
- Noise floor (dBFS)
- Crest factor
- Stereo correlation (if stereo)
- Loudness (Integrated, True Peak, Loudness Range)

Requirements: unix-like OS (including Windows subsystem for Linux, cygwin),
ffmpeg, and the BASH shell. Optional: Git version control software

The script uses ffmpeg to analyze the audio file and extract various statistics
about the recording. Other analysis programs and test files are used in the
verification directory of the Git repository.

Audio peak level is the highest instantaneous amplitude or loudest point in an
audio signal, measured in decibels relative to full scale (dBFS). It represents
the maximum transient peak, not the average loudness. Ensuring peaks remain below
is crucial to prevent digital clipping (distortion).
https://en.wikipedia.org/wiki/DBFS

The noise floor in audio is the sum of all unwanted ambient sounds (HVAC,
traffic) and electronic hiss (preamps, interference) present in a recording
space or signal chain when no intended sound is being made. It represents
the baseline "silence" of a system; a lower noise floor allows for greater
dynamic range, while a high noise floor can make recordings sound
unprofessional. https://en.wikipedia.org/wiki/Noise_floor

Crest factor in audio is the ratio of a signal's peak amplitude to its average
(RMS) power, measuring the "peakiness" or dynamic range of a sound, typically
measured in dB. A higher crest factor indicates high dynamics (12–15+ dB, e.g.,
drums), while a lower, smaller value suggests heavy compression or a denser,
more consistent sound (6–9 dB). https://en.wikipedia.org/wiki/Crest_factor

Stereo audio average phase, often visualized via a phase correlation meter,
measures the similarity between left and right channels, averaging from -1
(fully out-of-phase) to +1 (fully in-phase). A positive average (+0.1 to +1)
indicates good mono compatibility, while a negative average indicates potential
phase cancellation, where sounds disappear in mono.

Loudness (EBU R128) is a standardized way to measure the perceived loudness of
audio. The integrated loudness represents the overall loudness of the recording,
the true peak indicates the maximum inter-sample peak level, and the loudness
range represents the variation in loudness throughout the recording.
https://en.wikipedia.org/wiki/EBU_R_128

Verification of the statistics is also available via Git, see the readme in the
verification directory for details.