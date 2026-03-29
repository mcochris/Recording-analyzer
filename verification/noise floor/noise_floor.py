#
# This script calculates the noise floor for a given audio file using python's
# soundfile library. It computes the minimum RMS value over a series of windows
# and converts it to dBFS.
#
# Usage: noise_floor.py <audio_file> <left_noise_floor> <right_noise_floor>
#
# This script is normally called from check.sh
#

import soundfile as sf
import numpy as np
import sys
import os

def read_threshold(threshold_file='threshold.txt'):
    with open(threshold_file, 'r') as f:
        return float(f.read().strip())

def noise_floor(filename, expected_left, expected_right, window_ms=50):
    threshold = read_threshold()
    data, samplerate = sf.read(filename)
    window_samples = int(samplerate * window_ms / 1000)

    expected = [expected_left, expected_right]

    for i, ch in enumerate(['left', 'right']):
        channel = data[:, i]

        # Calculate RMS for each window
        num_windows = len(channel) // window_samples
        rms_values = []
        for w in range(num_windows):
            window = channel[w * window_samples:(w + 1) * window_samples]
            rms = np.sqrt(np.mean(window ** 2))
            if rms > 0:  # avoid log(0)
                rms_values.append(rms)

        min_rms = np.min(rms_values)
        calculated_dbfs = 20 * np.log10(min_rms)
        expected_dbfs = expected[i]

        if abs(calculated_dbfs - expected_dbfs) <= threshold:
            print(f"./{os.path.basename(sys.argv[0])}: Python {ch} noise floor is within threshold")
        else:
            print(
                f"./{os.path.basename(sys.argv[0])}: Python {ch} noise floor is not within threshold, "
                f"calculated noise floor {calculated_dbfs:.2f} dBFS, "
                f"expected {expected_dbfs:.2f} dBFS, "
                f"threshold {threshold:.2f} dBFS"
            )

if len(sys.argv) != 4:
    print(f"Usage: {os.path.basename(sys.argv[0])} <audio_file> <left_noise_floor> <right_noise_floor>")
    sys.exit(1)

audio_file = sys.argv[1]
left_noise_floor = float(sys.argv[2])
right_noise_floor = float(sys.argv[3])

noise_floor(audio_file, left_noise_floor, right_noise_floor)