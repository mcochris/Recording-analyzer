# 🔍 Recording Analyzer

![Bash](https://img.shields.io/badge/Shell-Bash-blue)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20WSL-lightgrey)
![Dependency](https://img.shields.io/badge/Dependencies-ffmpeg%2C%20jq-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

A Bash utility for analyzing objective characteristics of audio files
(.wav, .flac, .mp3, etc.) using **ffmpeg**.

Provides quick, repeatable, file-level measurements for common audio metrics.

## ❓ Why This Tool Exists

Most tools either:

- focus on **system or room measurement** (for example, REW)
- provide **raw ffmpeg output** without a concise summary
- reduce audio to a **single score** rather than showing multiple useful metrics

This tool fills that gap by providing:

- quick, objective **multi-metric summaries**
- a **scriptable** workflow for repeated analysis
- consistent results across Linux and Windows Subsystem for Linux (WSL)
- a way to download a **spreadsheet** of your music file data
- a way to create **custom playlists** of your music files based on file statistics and metadata

## 🚀 Features

- Peak level (dBFS)
- Noise floor (dBFS)
- Crest factor (dB)
- Stereo correlation (phase)
- Loudness (EBU R128: LUFS, LRA, true peak)
- Optional file metadata (genre, artist, album, track, duration, year, sample rate, average bit rate, bits per sample). recording-analyzer uses the metadata already in the file, it does not perform metadata lookups.
- File formats supported: aac, ac3, aif, aiff, amr, caf, flac, m4a, mp3, ogg, opus, pcm, wav, wma

## ✅ Requirements

The BASH shell, ffmpeg, and jq programs must be available on your computer. On Ubuntu linux, you can install them via:

```shell
sudo apt install ffmpeg jq
```

## 📦 Installation

Cut-n-paste from <https://raw.githubusercontent.com/mcochris/Recording-analyzer/refs/heads/main/recording-analyzer.sh> or

```bash
git clone https://github.com/mcochris/Recording-analyzer.git
cd Recording-analyzer
chmod +x recording-analyzer.sh
```

then copy recording-analyzer.sh to a directory in your $PATH to make the program executable from anywhere.

## ▶️ Usage

```bash
recording-analyzer.sh <audio_file>
```

## 🔁 Batch Processing Examples

Analyze every music file in the Music directory:

```bash
recording-analyzer.sh "/home/user/Music"
```

Analyze every music file in the Music directory, including all its subdirectories:

```bash
recording-analyzer.sh --recurse "/home/user/Music"
```

Analyze every music file in the Music directory and get each file's metadata:

```bash
recording-analyzer.sh --metadata "/home/user/Music"
```

Analyze every music file in the Music directory and capture the JSON results in a file. You can import the JSON file into your spreadsheet program, or upload the JSON file to <https://recording-analyzer.mcochris.com/> to see your data in spreadsheet format, download the spreadsheet of your data, and create custom playlists:

```bash
recording-analyzer.sh --metadata --json "/home/user/Music" > mydata.json
```

Command line options can be combined:

```bash
recording-analyzer.sh --metadata --json --recurse "/home/user/Music"
```

## 🖥️ Example Output

```text
chris@studio:~/audio$ recording-analyzer.sh "Computer World.flac"

Audio Analysis: "Computer World.flac"
=====================================

Left Channel:
  Peak Level:     -0.50 dBFS
  Noise Floor:    -inf dBFS
  Crest Factor:   12.30 dB

Right Channel:
  Peak Level:     -1.05 dBFS
  Noise Floor:    -inf dBFS
  Crest Factor:   10.68 dB

Stereo Correlation:
  Average Phase:  0.4893 degrees

Loudness (EBU R128):
  Integrated Loudness:  -19.37 LUFS
  True Peak:            -0.50 dBTP
  Loudness Range:       4.00 LU
```

```text
chris@studio:~/audio$ recording-analyzer.sh "The Things We Do for Love.flac"

Audio Analysis: "The Things We Do for Love.flac"
================================================

Metadata:
  Genre:           Rock
  Artist:          10cc
  Album:           The Very Best of 10cc
  Track:           11
  Duration:        213 seconds
  Year:            1997
  Sample Rate:     44100 Hz
  Avg. Bit Rate:   887750 bps
  Bits Per Sample: 16

Left Channel:
  Peak Level:     -1.76 dBFS
  Noise Floor:    -inf dBFS
  Crest Factor:   6.29°

Right Channel:
  Peak Level:     -0.55 dBFS
  Noise Floor:    -inf dBFS
  Crest Factor:   6.67°

Stereo Correlation:
  Average Phase:  0.31 degrees

Loudness (EBU R128):
  Integrated Loudness:  -13.92 LUFS
  True Peak:            -0.53 dBTP
  Loudness Range:       4.10 LU
```

## 📖 Metric Definitions

**Peak Level (dBFS)**
Audio peak level is the highest instantaneous amplitude or loudest point in an audio signal, measured in decibels relative to full scale (dBFS). Does not include intersample peaks. It represents the maximum transient peak, not the average loudness. Ensuring peaks remain below zero is crucial to prevent digital clipping (distortion).

**Noise Floor (dBFS)**
The noise floor in audio is the sum of all unwanted ambient sounds (HVAC,
traffic) and electronic hiss (preamps, interference) present in a recording
space or signal chain when no intended sound is being made. It represents
the baseline "silence" of a system; a lower noise floor allows for greater
dynamic range, while a high noise floor can make recordings sound
unprofessional. `-inf dBFS` indicates digital silence or values below numerical precision.

**Crest Factor (dB)**
Crest factor in audio is the ratio of a signal's peak amplitude to its average
(RMS) power, measuring the "peakiness" or dynamic range of a sound, typically
measured in dB. A higher crest factor indicates high dynamics (12–15+ dB, e.g.,
drums), while a lower, smaller value suggests heavy compression or a denser,
more consistent sound (6–9 dB).

**Stereo Correlation**
Stereo audio average phase, often visualized via a phase correlation meter,
measures the similarity between left and right channels, averaging from -1
(fully out-of-phase) to +1 (fully in-phase). A positive average (+0.1 to +1)
indicates good mono compatibility, while a negative average indicates potential
phase cancellation, where sounds disappear in mono.

**Integrated Loudness (LUFS)**
Audio integrated loudness is the average loudness of the audio file
in LUFS (Loudness Units Full Scale). Unlike peak meters, it calculates loudness
based on human perception to ensure consistent volume levels, often targeting
-14 LUFS for streaming services like Spotify or YouTube.

**True Peak (dBTP)**
Digital audio True Peak (measured in dBTP) is a standard measurement that
predicts the highest level an audio signal will reach after conversion
from digital to analog, accounting for peaks between samples (inter-sample
peaks). While standard digital meters (dBFS) only measure sample points,
True Peak uses oversampling to detect inter-sample peaks that can cause
distortion when converting to lossy formats like MP3 or AAC.

**Loudness Range (LRA)**
Loudness Range (LRA) measures the dynamic variation between the softest and
loudest parts of an audio program, quantified in Loudness Units (LU). While
average loudness (integrated loudness) is typically targeted at -14 to -16
LUFS for streaming, LRA ensures audio isn't too static or too erratic, with
a preferred range of 5–10 LU for consistency.

## 🔬 Validation

You can verify the recording-analyzers' output against programs other than ffmpeg for comparison. See methodology and verification details here:

<https://github.com/mcochris/Recording-analyzer/blob/main/verification/readme.md>

## 💬 Feedback

Comments, questions, and suggestions are welcome. You can open an issue here: <https://github.com/mcochris/Recording-analyzer/issues>
