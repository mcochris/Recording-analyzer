Digital audio True Peak (measured in dBTP) is a standard measurement that
predicts the highest level an audio signal will reach after conversion
from digital to analog, accounting for peaks between samples (inter-sample
peaks). While standard digital meters (dBFS) only measure sample points,
True Peak uses oversampling to detect inter-sample peaks that can cause
distortion when converting to lossy formats like MP3 or AAC.

True peak statistics are available from the ffmpeg, SoX, ebur128, and
loudgain programs.

https://en.wikipedia.org/wiki/EBU_R_128

https://www.ffmpeg.org/

https://en.wikipedia.org/wiki/SoX

https://r128gain.sourceforge.net/

https://github.com/Moonbase59/loudgain
