#
# This script compares the peak level results for a given audio file with python's
# soundfile library to the expected values provided as arguments. It checks if the
# calculated peak levels are within a specified threshold of the expected values.
#
# Usage: peak_level.py <audio_file> <left_peak_level> <right_peak_level> <threshold> [--debug|-d]
#
# This script is normally called from check.sh
#

import soundfile as sf
import numpy as np
import sys

def main():
	audio_file = sys.argv[1]
	expected_left = float(sys.argv[2])
	expected_right = float(sys.argv[3])
	threshold = int(sys.argv[4])
	debug = len(sys.argv) > 5 and sys.argv[5] in ('--debug', '-d')

	data, samplerate = sf.read(audio_file)

	results = {}

	for i, ch in enumerate(['left', 'right']):
		peak_linear = np.max(np.abs(data[:, i]))
		peak_dbfs = 20 * np.log10(peak_linear)
		results[ch] = peak_dbfs

	expected = {'left': expected_left, 'right': expected_right}

	if debug:
		print(f"{sys.argv[0]}: [debug] expected   left={expected['left']:.4f} dBFS, right={expected['right']:.4f} dBFS")
		print(f"{sys.argv[0]}: [debug] calculated left={results['left']:.4f} dBFS, right={results['right']:.4f} dBFS")

	for ch in ['left', 'right']:
		calculated = results[ch]
		exp = expected[ch]
		diff_percent = abs(calculated - exp) / abs(exp) * 100
		if diff_percent > threshold:
			print(f"{sys.argv[0]}: Python {ch} peak level is not within threshold, calculated {calculated:.4f} dBFS, expected {exp:.4f} dBFS, difference {diff_percent:.2f}%, threshold {threshold}%")
		else:
			print(f"{sys.argv[0]}: Python {ch} peak level is within threshold ({diff_percent:.2f}% difference)")

if __name__ == '__main__':
	main()