import soundfile as sf
import numpy as np

data, samplerate = sf.read('input.wav')

for i, ch in enumerate(['Left', 'Right']):
    peak_linear = np.max(np.abs(data[:, i]))
    peak_dbfs = 20 * np.log10(peak_linear)
    print(f"{ch}: {peak_dbfs:.2f} dBFS")