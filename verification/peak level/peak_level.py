#
# This script compares the peak level results for a given audio file with python's
# soundfile library to the expected values provided as arguments. It checks if the
# calculated peak levels are within a specified threshold of the expected values.
#
# Usage: peak_level.py <audio_file> <left_peak_level> <right_peak_level>
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

def main():
    audio_file = sys.argv[1]
    expected_left = float(sys.argv[2])
    expected_right = float(sys.argv[3])

    threshold = read_threshold()

    data, samplerate = sf.read(audio_file)

    results = {}
    within_threshold = True

    for i, ch in enumerate(['left', 'right']):
        peak_linear = np.max(np.abs(data[:, i]))
        peak_dbfs = 20 * np.log10(peak_linear)
        results[ch] = peak_dbfs

    expected = {'left': expected_left, 'right': expected_right}

    for ch in ['left', 'right']:
        calculated = results[ch]
        exp = expected[ch]
        diff = abs(calculated - exp)
        status = "OK" if diff <= threshold else "FAIL"
        if diff > threshold:
            print(f"{sys.argv[0]}: Python {ch} peak level is not within threshold, calculated {calculated} dBFS, expected {exp} dBFS, threshold {threshold} dB")
        else:
            print(f"{sys.argv[0]}: Python {ch} peak level is within threshold")

if __name__ == '__main__':
    main()