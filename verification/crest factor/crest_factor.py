#
# This script compares the crest factor results for a given audio file with python's
# soundfile library to the expected values provided as arguments. It checks if the
# calculated crest factors are within a specified threshold of the expected values.
#
# Usage: crest_factor.py --audio-file <audio_file> --left-crest-factor <left_crest_factor> --right-crest-factor <right_crest_factor> --threshold <threshold> [--debug|-d]
#
# This script is normally called from check.sh
#

import soundfile as sf
import numpy as np
import argparse

def main():
	parser = argparse.ArgumentParser(			description="Compare crest factor results for a given audio file.")
	parser.add_argument("--audio-file",			required=True, type=str, help="Path to the audio file")
	parser.add_argument("--left-crest-factor",	required=True, type=float, help="Expected left channel crest factor")
	parser.add_argument("--right-crest-factor",	required=True, type=float, help="Expected right channel crest factor")
	parser.add_argument("--threshold", 			required=True, type=float, help="Acceptable percentage difference between calculated and expected values")

	args = parser.parse_args()

	data, sr = sf.read(args.audio_file)

	# Handle mono vs stereo
	if data.ndim == 1:
		data = data[:, np.newaxis]

	channel_names     = ["left", "right"]
	expected_values   = [args.left_crest_factor, args.right_crest_factor]

	for ch in range(data.shape[1]):
		channel  = data[:, ch]
		peak     = np.max(np.abs(channel))
		rms      = np.sqrt(np.mean(channel**2))
		crest_linear = peak / rms
		crest_db     = 20 * np.log10(crest_linear)

		name     = channel_names[ch] if ch < len(channel_names) else f"channel {ch+1}"
		expected = expected_values[ch] if ch < len(expected_values) else None

		if expected is not None:
			diff_pct = abs(crest_linear - expected) / abs(expected) * 100
			if diff_pct <= args.threshold:
				print(f"Python {name} crest factor is within threshold")
			else:
				print(
					f"Python {name} crest factor is not within threshold, "
					f"calculated {crest_linear:.6f}, "
					f"expected {expected:.6f}, "
					f"threshold {args.threshold:g}%"
				)

if __name__ == '__main__':
	main()