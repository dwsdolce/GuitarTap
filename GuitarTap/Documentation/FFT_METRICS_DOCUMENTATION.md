# FFT Analysis Metrics Documentation

This document explains the various metrics calculated and displayed by the `RealtimeFFTAnalyzer`.

## Analysis Configuration Metrics

### 1. Frequency Resolution
**Formula:** `sampleRate / fftSize`

**What it means:** The frequency resolution determines how precisely the analyzer can distinguish between different frequencies. Each FFT bin represents a range of frequencies equal to the frequency resolution.

**Example:**
- Sample Rate: 48000 Hz
- FFT Size: 8192
- Frequency Resolution: 48000 / 8192 = **5.86 Hz per bin**

This means the analyzer can distinguish frequencies that are 5.86 Hz apart. Two tones at 440 Hz and 445 Hz would appear in different bins, but tones at 440 Hz and 442 Hz might not be distinguishable.

**Trade-offs:**
- **Higher resolution (larger FFT):** Better frequency precision but slower time response and more computation
- **Lower resolution (smaller FFT):** Faster time response but less frequency precision

---

### 2. Bandwidth
**Formula:** `sampleRate / 2`

**What it means:** The bandwidth is the maximum frequency that can be analyzed, also known as the Nyquist frequency. According to the Nyquist-Shannon sampling theorem, you can only accurately represent frequencies up to half the sample rate.

**Example:**
- Sample Rate: 48000 Hz
- Bandwidth: 48000 / 2 = **24000 Hz**

This covers the entire audible frequency range (humans hear ~20 Hz to 20,000 Hz).

**Frequency Range:**
- DC (0 Hz) to Nyquist frequency
- Total analyzable range: 0 Hz to 24,000 Hz

---

### 3. Sample Length (Time Window)
**Formula:** `fftSize / sampleRate`

**What it means:** The sample length is the duration of audio captured in each FFT window. It represents how far "back in time" the analyzer looks for each frequency analysis.

**Example:**
- FFT Size: 8192
- Sample Rate: 48000 Hz
- Sample Length: 8192 / 48000 = **0.171 seconds** (171 ms)

Each FFT calculation analyzes 171 milliseconds of audio data.

**Implications:**
- **Longer window:** Better frequency resolution, but slower response to changes
- **Shorter window:** Faster response to transients, but lower frequency resolution
- This is a fundamental trade-off in FFT analysis (time-frequency uncertainty)

---

### 4. Frame Rate
**Formula (with 50% overlap):** `sampleRate / (fftSize / 2)`

**What it means:** The frame rate is how many times per second the FFT is calculated. With 50% overlap, each new FFT uses half new samples and half old samples.

**Example:**
- Sample Rate: 48000 Hz
- FFT Size: 8192
- Hop Size (50% overlap): 4096
- Frame Rate: 48000 / 4096 = **11.72 Hz** (or ~11.72 frames per second)

A new frequency spectrum is calculated approximately every 85 milliseconds.

**Why use overlap?**
- Smoother visualization
- Better time resolution
- Reduced artifacts from windowing
- More responsive to changes in the signal

---

## Performance Metrics

### 5. Processing Time
**Unit:** Milliseconds (ms)

**What it means:** The actual time it takes to process one frame of audio through the complete FFT pipeline, including:
- Windowing
- FFT calculation
- Magnitude computation
- dB conversion
- Peak detection

**Example:**
- Processing Time: **2.5 ms**

This means the CPU can compute an FFT frame in 2.5 milliseconds.

**Color Coding:**
- 🟢 **Green:** Fast (<50% of frame time) - plenty of headroom
- 🟡 **Yellow:** Moderate (50-80% of frame time) - acceptable
- 🟠 **Orange:** High (80-95% of frame time) - near limit
- 🔴 **Red:** Critical (>95% of frame time) - may drop frames

---

### 6. Average Processing Time
**Unit:** Milliseconds (ms)

**What it means:** A rolling average of the last 30 frames' processing times. This smooths out temporary spikes and gives a more stable performance indicator.

**Why it matters:** Individual frames might spike due to system activity, but the average shows the sustainable processing load.

---

### 7. CPU Usage Percentage
**Formula:** `(avgProcessingTime / frameTime) * 100`

**What it means:** The percentage of available time between frames that's used for FFT processing.

**Example:**
- Frame Rate: 11.72 Hz → Frame time = 85.3 ms
- Avg Processing Time: 2.5 ms
- CPU Usage: (2.5 / 85.3) * 100 = **2.9%**

This means only 2.9% of the available time is used for FFT calculations, leaving plenty of headroom for other tasks.

**Interpretation:**
- **< 50%:** Excellent - system has plenty of capacity
- **50-80%:** Good - acceptable performance
- **80-95%:** Warning - nearing capacity, may see occasional delays
- **> 95%:** Critical - system may drop frames or cause audio glitches

---

## Practical Considerations

### Choosing FFT Size

| FFT Size | Freq Resolution @ 48kHz | Sample Length | Frame Rate (50% overlap) | Use Case |
|----------|-------------------------|---------------|--------------------------|----------|
| 2048     | 23.4 Hz                | 42.7 ms       | 23.4 Hz                  | Fast response, rhythm analysis |
| 4096     | 11.7 Hz                | 85.3 ms       | 11.7 Hz                  | Balanced, general use |
| 8192     | 5.9 Hz                 | 171 ms        | 5.9 Hz                   | Good resolution, musical notes |
| 16384    | 2.9 Hz                 | 341 ms        | 2.9 Hz                   | High resolution, pitch detection |
| 32768    | 1.5 Hz                 | 683 ms        | 1.5 Hz                   | Very high resolution, slow changes |
| 65536    | 0.73 Hz                | 1.37 s        | 0.73 Hz                  | Maximum resolution, steady signals |

### Sample Rate Selection

**Common Sample Rates:**
- **44100 Hz:** CD quality, standard audio
- **48000 Hz:** Video/broadcast standard, preferred for real-time
- **88200 Hz:** High-resolution audio (2x CD)
- **96000 Hz:** Studio quality, very high bandwidth

**Trade-offs:**
- Higher sample rates increase bandwidth but require more processing power
- Higher sample rates with the same FFT size reduce frequency resolution
- Most audio applications work fine with 48000 Hz

### Performance Optimization Tips

1. **Start with smaller FFT sizes** (4096 or 8192) and increase if needed
2. **Monitor CPU usage** - keep it below 50% for smooth operation
3. **Consider device capabilities** - mobile devices have less power than desktop
4. **Balance overlap** - 50% is standard, but 0% uses less CPU (at cost of smoothness)
5. **Profile on target hardware** - performance varies significantly by device

---

## Real-World Examples

### Example 1: Musical Pitch Detection
**Goal:** Detect individual musical notes (fundamental frequency accuracy needed)

**Configuration:**
- FFT Size: 16384
- Sample Rate: 48000 Hz
- Frequency Resolution: 2.93 Hz
- Frame Rate: 2.93 Hz

**Rationale:** Musical notes are about 6% apart in frequency (semitone). At 440 Hz (A4), the next semitone (A#) is 466 Hz - a 26 Hz difference. With 2.93 Hz resolution, this is clearly distinguishable.

### Example 2: Real-Time Spectrum Visualizer
**Goal:** Smooth, responsive visualization of music or voice

**Configuration:**
- FFT Size: 8192
- Sample Rate: 48000 Hz
- Frequency Resolution: 5.86 Hz
- Frame Rate: 11.72 Hz

**Rationale:** Good balance - updates ~12 times per second for smooth animation, with sufficient frequency detail for musical content.

### Example 3: Audio Meter / Level Detection
**Goal:** Fast response to audio level changes

**Configuration:**
- FFT Size: 2048
- Sample Rate: 48000 Hz
- Frequency Resolution: 23.4 Hz
- Frame Rate: 23.4 Hz

**Rationale:** Very fast response (~23 updates/sec) suitable for VU meters or beat detection. Lower frequency resolution is acceptable since we care more about timing than precise frequency.

---

## Further Reading

- **FFT Basics:** [Accelerate vDSP Documentation](https://developer.apple.com/documentation/accelerate/vdsp)
- **Audio Processing:** [AVAudioEngine Guide](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- **Signal Processing Theory:** [The Scientist and Engineer's Guide to Digital Signal Processing](http://www.dspguide.com/)
- **Window Functions:** Understanding spectral leakage and window choice
- **Nyquist-Shannon Theorem:** Why sample rate determines maximum frequency
