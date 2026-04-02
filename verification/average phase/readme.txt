Stereo audio average phase, often visualized via a phase correlation meter,
measures the similarity between left and right channels, averaging from -1
(fully out-of-phase) to +1 (fully in-phase). A positive average (+0.1 to +1)
indicates good mono compatibility, while a negative average indicates potential
phase cancellation, where sounds disappear in mono.

I could not find an alternative means of measuring the average phase that
matched ffmpeg's calculation. Python's soundfile/numpy uses a different
algorithm to calculate phase.

March 2026