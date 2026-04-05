#!/usr/bin/env python3
#
# This script compares the peak level results for a given audio file with python's
# soundfile library to the expected values provided as arguments. It checks if the
# calculated peak levels are within a specified threshold of the expected values.
#
# Usage: peak_level.py [--debug|-d] --left-peak-level <value> --right-peak-level <value> --threshold <value> <audio_file>
#
# This script is normally called from check.sh
#

import argparse
import soundfile as sf
import numpy as np
import sys

def main():
	parser = argparse.ArgumentParser(			description="Compare peak level results for a given audio file.")
	parser.add_argument("--debug",				action="store_true", help="Enable debug output")
	parser.add_argument("--left-peak-level",	required=True, type=float, help="Expected left channel peak level")
	parser.add_argument("--right-peak-level",	required=True, type=float, help="Expected right channel peak level")
	parser.add_argument("--threshold", 			required=True, type=float, help="Acceptable percentage difference between calculated and expected values")
	parser.add_argument("audiofile",			type=str, help="Path to the audio file")

	args = parser.parse_args()

	data, samplerate = sf.read(args.audiofile)

	results = {}

	for i, ch in enumerate(['left', 'right']):
		peak_linear = np.max(np.abs(data[:, i]))
		peak_dbfs = 20 * np.log10(peak_linear)
		results[ch] = peak_dbfs

	expected = {'left': args.left_peak_level, 'right': args.right_peak_level}
	threshold = args.threshold
	debug = args.debug

	if debug:
		print(f"{sys.argv[0]}: [debug] expected   left={expected['left']:.4f} dBFS, right={expected['right']:.4f} dBFS")
		print(f"{sys.argv[0]}: [debug] calculated left={results['left']:.4f} dBFS, right={results['right']:.4f} dBFS")

	for ch in ['left', 'right']:
		calculated = results[ch]
		exp = expected[ch]
		if exp == 0.0:
			# Percentage difference is undefined when expected is 0; use absolute difference instead
			diff = abs(calculated - exp)
			exceeded = diff > threshold
			if debug:
				print(f"{sys.argv[0]}: [debug] {ch} using absolute diff (expected=0): diff={diff:.4f} dBFS, threshold={threshold}")
		else:
			diff = abs(calculated - exp) / abs(exp) * 100
			exceeded = diff > threshold
		if exceeded:
			print(f"Python {ch} peak level is not within threshold, calculated {calculated:.4f} dBFS, expected {exp:.4f} dBFS")
		else:
			print(f"Python {ch} peak level is within threshold")

if __name__ == '__main__':
	main()