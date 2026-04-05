# 🎧 Recording Analyzer

![Bash](https://img.shields.io/badge/Shell-Bash-blue)
![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20WSL-lightgrey)
![Dependency](https://img.shields.io/badge/Dependency-ffmpeg-green)
![License](https://img.shields.io/badge/License-MIT-yellow)

A lightweight Bash utility for analyzing objective characteristics of audio files
(.wav, .flac, .mp3, etc.) using **ffmpeg**.

Provides quick, repeatable, file-level measurements for common audio metrics.

> Not intended to replace full measurement tools (e.g., REW), but useful for fast inspection and comparison.

## ❓ Why This Tool Exists

Most tools either:

- focus on **system or room measurement** (for example, REW)
- provide **raw ffmpeg output** without a concise summary
- reduce audio to a **single score** rather than showing multiple useful metrics

This tool fills that gap by providing:

- quick, objective **multi-metric summaries**
- a **scriptable** workflow for repeated analysis
- consistent results across Linux and Windows Subsystem for Linux (WSL)

It is meant for people who want fast insight into recordings without opening a GUI.

## 🚀 Features

- Peak level (dBFS)
- Noise floor (dBFS)
- Crest factor (dB)
- Stereo correlation (phase)
- Loudness (EBU R128: LUFS, LRA, true peak)

## ⚙️ How It Works

Uses ffmpeg filters on decoded PCM audio:

- `astats` → peak, RMS, crest
- `aphasemeter` → stereo correlation
- `loudnorm` → LUFS, LRA, true peak

## 📦 Installation

Cut-n-paste from <https://github.com/mcochris/Recording-analyzer/blob/main/recording-analyzer.sh>
or

```bash
git clone https://github.com/mcochris/Recording-analyzer.git
cd Recording-analyzer
chmod +x recording-analyzer.sh
```

## ▶️ Usage

```bash
recording-analyzer.sh <audio_file>
```

## 🔁 Batch Processing Example

Analyze every FLAC file in the current directory:

```bash
for f in *.flac; do
  [ -f "$f" ] || continue
  recording-analyzer.sh "$f"
done
```

Analyze all supported files recursively and save the output to a report:

```bash
find . -type f \( -iname "*.flac" -o -iname "*.wav" -o -iname "*.mp3" -o -iname "*.aac" -o -iname "*.m4a" \) -print0 |
while IFS= read -r -d '' f; do
  recording-analyzer.sh "$f"
done | tee analysis-report.txt
```

## 🖥️ Example Output (Terminal Style)

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
  Average Phase:  0.4893

Loudness (EBU R128):
  Integrated Loudness:  -19.37 LUFS
  True Peak:            -0.50 dBTP
  Loudness Range:       4.00 LU
```

## 🔍 Comparison to Other Tools

| Tool | Purpose | Strengths | Limitations |
| --- | --- | --- | --- |
| Recording Analyzer | Quick file-level metrics | Fast, scriptable, concise summary | Not a full acoustic measurement suite |
| REW | Room and system measurement | Detailed graphs and acoustic tools | Not focused on batch file analysis |
| DR Meter | Music DR scoring | Simple and familiar | Narrower scope |
| Raw ffmpeg output | Low-level analysis | Flexible and powerful | Verbose and less convenient |

## 📖 Metric Definitions

**Peak Level (dBFS)**
Audio peak level is the highest instantaneous amplitude or loudest point in an audio signal, measured in decibels relative to full scale (dBFS). Does not include intersample peaks. It represents the maximum transient peak, not the average loudness. Ensuring peaks remain below is crucial to prevent digital clipping (distortion).

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
Audio integrated loudness is the average loudness of an entire audio program,
such as a full song, podcast episode, or film, measured from beginning to end
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

## ⚠️ Common Pitfalls

- `-inf dBFS` noise floor does not mean infinite dynamic range
- Peak level is not the same as true peak
- Crest factor is not the same as perceived dynamics
- Lossy codecs can change measurements
- Short clips can skew loudness and LRA
- Silence and long fades can bias results

## 🧠 Further Reading

<https://en.wikipedia.org/wiki/DBFS>

<https://en.wikipedia.org/wiki/Loudness>

<https://en.wikipedia.org/wiki/LUFS>

<https://en.wikipedia.org/wiki/EBU_R_128>

<https://en.wikipedia.org/wiki/Crest_factor>

<https://en.wikipedia.org/wiki/Noise_floor>

## 🔬 Validation

See methodology and verification details here:

<https://github.com/mcochris/Recording-analyzer/blob/main/verification/readme.txt>

## 💬 Feedback

Comments, questions, and suggestions are welcome.
