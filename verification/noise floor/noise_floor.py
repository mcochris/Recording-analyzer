#
# This script calculates the noise floor for a given audio file using python's
# soundfile library. It computes the minimum RMS value over a series of windows
# and converts it to dBFS.
#
# Usage: noise_floor.py <audio_file> <left_noise_floor> <right_noise_floor> <threshold_%>
#
# threshold is expressed as a percentage of the calculated noise floor (e.g. 5 = 5%)
#
# This script is normally called from check.sh
#

import soundfile as sf
import numpy as np
import sys
import os

def noise_floor(filename, expected_left, expected_right, threshold, debug, window_ms=50):
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
        tolerance_dbfs = (threshold / 100.0) * abs(calculated_dbfs)

        if debug:
            print(
                f"./{os.path.basename(sys.argv[0])}: Python {ch} debug: "
                f"calculated={calculated_dbfs:.2f} dBFS, "
                f"expected={expected_dbfs:.2f} dBFS, "
                f"threshold={threshold:.1f}% (±{tolerance_dbfs:.2f} dB)"
            )

        if abs(calculated_dbfs - expected_dbfs) <= tolerance_dbfs:
            print(f"./{os.path.basename(sys.argv[0])}: Python {ch} noise floor is within threshold")
        else:
            print(
                f"./{os.path.basename(sys.argv[0])}: Python {ch} noise floor is not within threshold, "
                f"calculated noise floor {calculated_dbfs:.2f} dBFS, "
                f"expected {expected_dbfs:.2f} dBFS, "
                f"threshold {threshold:.1f}% (±{tolerance_dbfs:.2f} dB)"
            )

audio_file = sys.argv[1]
left_noise_floor = float(sys.argv[2])
right_noise_floor = float(sys.argv[3])
threshold = float(sys.argv[4])
debug = len(sys.argv) > 5 and sys.argv[5] in ('--debug', '-d')

noise_floor(audio_file, left_noise_floor, right_noise_floor, threshold, debug)