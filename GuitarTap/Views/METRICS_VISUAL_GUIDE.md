# FFT Metrics View - Visual Layout Guide

## Layout Variations

### macOS - Metrics Enabled

```
┌──────────────────────────────────────────────────────────────┐
│  Tap Tone Analysis              [Show Metrics] [Measurements] │
├─────────────────────────────────┬────────────────────────────┤
│                                 │                            │
│  [Start/Stop] [Save] [Reset]    │   FFT Analysis Metrics     │
│  ─────────────────────────────  │   ════════════════════     │
│                                 │                            │
│  Real-Time Frequency Response   │   ┌─ Analysis Config ────┐│
│  ┌──────────────────────────┐  │   │ Frequency Resolution  ││
│  │                          │  │   │ Bandwidth             ││
│  │    Spectrum Chart        │  │   │ Sample Length         ││
│  │                          │  │   │ Frame Rate            ││
│  └──────────────────────────┘  │   └───────────────────────┘│
│                                 │                            │
│  Tap Detection                  │   ┌─ Performance ─────────┐│
│  Peak Frequencies               │   │ Processing Time       ││
│  Mode Identification            │   │ Average Processing    ││
│  Decay Time                     │   │ CPU Usage             ││
│  Tap Tone Ratio                 │   └───────────────────────┘│
│  Peak History                   │                            │
│                                 │   ┌─ Peak Detection ──────┐│
│                                 │   │ Peak Frequency        ││
│                                 │   │ Peak Magnitude        ││
│                                 │   └───────────────────────┘│
│                                 │                            │
│                                 │   ● Analyzing              │
└─────────────────────────────────┴────────────────────────────┘
           ↕ Resizable Divider
```

### macOS - Metrics Disabled

```
┌──────────────────────────────────────────────────────────────┐
│  Tap Tone Analysis              [Hide Metrics] [Measurements] │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│  [Start/Stop] [Save] [Reset]                                │
│  ────────────────────────────────────────────────────────── │
│                                                              │
│  Real-Time Frequency Response                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │                  Spectrum Chart                        │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                              │
│  Tap Detection                                              │
│  Peak Frequencies                                           │
│  Mode Identification                                        │
│  Decay Time                                                 │
│  Tap Tone Ratio                                             │
│  Peak History                                               │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

---

### iPad (Landscape) - Metrics Enabled

```
┌─────────────────────────────────────────────────────────────┐
│ Tap Tone Analysis              [Show Metrics] [Measurements] │
├───────────────────────────────────┬─────────────────────────┤
│                                   │                         │
│  [Start] [Save] [Reset]           │  FFT Analysis Metrics   │
│                                   │  ═══════════════════    │
│  Real-Time Spectrum               │                         │
│  ┌─────────────────────────────┐ │  ┌─ Analysis Config ──┐ │
│  │                             │ │  │ Freq Resolution     │ │
│  │       Spectrum              │ │  │ Bandwidth           │ │
│  │                             │ │  │ Sample Length       │ │
│  └─────────────────────────────┘ │  │ Frame Rate          │ │
│                                   │  └─────────────────────┘ │
│  Tap Indicator                    │                         │
│  Current Peaks                    │  ┌─ Performance ──────┐ │
│  Modes                            │  │ Processing: 2.5ms   │ │
│  Decay                            │  │ Avg: 2.3ms          │ │
│  Ratio                            │  │ CPU: 15%  🟢        │ │
│                                   │  └─────────────────────┘ │
│                                   │                         │
│                                   │  ┌─ Peak Detection ───┐ │
│                                   │  │ 196.0 Hz            │ │
│                                   │  │ -42.5 dB            │ │
│                                   │  └─────────────────────┘ │
│                                   │                         │
│                                   │  ● Analyzing            │
└───────────────────────────────────┴─────────────────────────┘
              Fixed 350pt width ────┘
```

---

### iPhone (Portrait) - Metrics Enabled

```
┌────────────────────────────────────┐
│ Tap Tone      [☰] [Measurements]   │
├────────────────────────────────────┤
│  [Start] [Save] [Reset]            │
│                                    │
│  Real-Time Spectrum  ┌───────────┐ │
│  ┌─────────────────┐ │FFT Metrics│ │
│  │                 │ │●Analyzing │ │
│  │                 │ │Res:1.5 Hz │ │
│  │    Spectrum     │ │Rate:60 Hz │ │
│  │                 │ │CPU:15% 🟢 │ │
│  │                 │ └───────────┘ │
│  └─────────────────┘               │
│                                    │
│  ┌─ Tap Indicator ───────────────┐ │
│  │  ⚪ Waiting for tap...        │ │
│  └────────────────────────────────┘ │
│                                    │
│  ┌─ Current Peaks ────────────────┐│
│  │  F0: 196.0 Hz   -42.5 dB      ││
│  │  F1: 392.0 Hz   -48.2 dB      ││
│  └────────────────────────────────┘│
│                                    │
│  Mode: (0,0) - Ring Mode          │
│  Decay: 3.2 s                     │
│  Tap Tone: 0.85                   │
│                                    │
│  ┌─ Peak History ────────────────┐ │
│  │      📊 Chart                 │ │
│  └────────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘
    ↑ Compact overlay doesn't block content
```

---

### iPhone (Portrait) - Metrics Disabled

```
┌────────────────────────────────────┐
│ Tap Tone      [☰] [Measurements]   │
├────────────────────────────────────┤
│  [Start] [Save] [Reset]            │
│                                    │
│  Real-Time Spectrum                │
│  ┌───────────────────────────────┐ │
│  │                               │ │
│  │                               │ │
│  │         Spectrum              │ │
│  │                               │ │
│  │                               │ │
│  └───────────────────────────────┘ │
│                                    │
│  ┌─ Tap Indicator ───────────────┐ │
│  │  ⚪ Waiting for tap...        │ │
│  └────────────────────────────────┘ │
│                                    │
│  ┌─ Current Peaks ────────────────┐│
│  │  F0: 196.0 Hz   -42.5 dB      ││
│  │  F1: 392.0 Hz   -48.2 dB      ││
│  └────────────────────────────────┘│
│                                    │
│  Mode: (0,0) - Ring Mode          │
│  Decay: 3.2 s                     │
│  Tap Tone: 0.85                   │
│                                    │
│  ┌─ Peak History ────────────────┐ │
│  │      📊 Chart                 │ │
│  └────────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘
```

---

## Detailed Metrics Panel Content

```
╔═══════════════════════════════════════╗
║    FFT Analysis Metrics               ║
╠═══════════════════════════════════════╣
║                                       ║
║  ┌─ Analysis Configuration ─────────┐ ║
║  │                                   │ ║
║  │  Frequency Resolution             │ ║
║  │  0.73 Hz                          │ ║
║  │  Hz per bin                       │ ║
║  │  ───────────────────────────────  │ ║
║  │  Bandwidth                        │ ║
║  │  24.00 kHz                        │ ║
║  │  0 Hz to Nyquist                  │ ║
║  │  ───────────────────────────────  │ ║
║  │  Sample Length                    │ ║
║  │  1.37 s                           │ ║
║  │  Time window duration             │ ║
║  │  ───────────────────────────────  │ ║
║  │  Frame Rate                       │ ║
║  │  60.0 Hz                          │ ║
║  │  FFT calculations/sec             │ ║
║  │                                   │ ║
║  └───────────────────────────────────┘ ║
║                                       ║
║  ┌─ Performance ─────────────────────┐ ║
║  │                                   │ ║
║  │  Processing Time                  │ ║
║  │  2.456 ms             🟢          │ ║
║  │  Last frame                       │ ║
║  │  ───────────────────────────────  │ ║
║  │  Average Processing               │ ║
║  │  2.341 ms             🟢          │ ║
║  │  30-frame average                 │ ║
║  │  ───────────────────────────────  │ ║
║  │  CPU Usage                        │ ║
║  │  14.0%                🟢          │ ║
║  │  Of available frame time          │ ║
║  │                                   │ ║
║  └───────────────────────────────────┘ ║
║                                       ║
║  ┌─ Peak Detection ──────────────────┐ ║
║  │                                   │ ║
║  │  Peak Frequency                   │ ║
║  │  196.0 Hz                         │ ║
║  │  Dominant frequency               │ ║
║  │  ───────────────────────────────  │ ║
║  │  Peak Magnitude                   │ ║
║  │  -42.5 dB                         │ ║
║  │  Signal strength                  │ ║
║  │                                   │ ║
║  └───────────────────────────────────┘ ║
║                                       ║
║  ● Analyzing                          ║
║                                       ║
╚═══════════════════════════════════════╝
```

---

## Compact Overlay Detail (iPhone)

```
┌─────────────────────┐
│ ● FFT Metrics       │
│ ─────────────────── │
│ 📊 Res:  0.73 Hz    │
│ ⏱️  Time: 1366 ms   │
│ ⚡ Rate: 60.0 Hz    │
│ ─────────────────── │
│ 💻 CPU:  14.0% 🟢   │
│ ⏰ Proc: 2.34 ms    │
└─────────────────────┘
    Translucent background
    Rounded corners
    Drop shadow
```

---

## Color Coding Legend

### Performance Status Colors

- 🟢 **Green** (< 50% CPU)
  - Excellent performance
  - Plenty of headroom
  
- 🟡 **Yellow** (50-80% CPU)
  - Good performance
  - Normal operation
  
- 🟠 **Orange** (80-95% CPU)
  - High CPU usage
  - May need optimization
  
- 🔴 **Red** (> 95% CPU)
  - Critical performance
  - Likely dropping frames

### Status Indicators

- 🟢 **Green Dot** = Analyzing (running)
- ⚪ **Gray Dot** = Stopped (not running)

---

## Interaction Behaviors

### macOS
- **Split View**: Drag divider to resize panels
- **Minimum Sizes**: Main (600pt), Metrics (300pt)
- **Maximum Size**: Metrics panel (450pt)
- **Toggle**: Click toolbar button to show/hide

### iPad
- **Portrait**: Metrics disabled (not enough width)
- **Landscape**: Side-by-side layout
- **Fixed Width**: 350pt metrics panel
- **Divider**: Visual only, not draggable

### iPhone
- **Overlay Position**: Top-right corner
- **Always On Top**: Floats above content
- **Compact Size**: ~180pt wide, auto height
- **Translucent**: Doesn't fully block content
- **Toggle**: Tap toolbar to show/hide

---

## Responsive Breakpoints

| Device | Orientation | Size Class | Layout |
|--------|-------------|------------|--------|
| iPhone | Portrait | Compact | Overlay |
| iPhone | Landscape | Compact | Overlay |
| iPad Mini | Portrait | Compact | Overlay |
| iPad Mini | Landscape | Regular | Side-by-side |
| iPad | Portrait | Regular | Side-by-side |
| iPad | Landscape | Regular | Side-by-side |
| iPad Pro | Portrait | Regular | Side-by-side |
| iPad Pro | Landscape | Regular | Side-by-side |
| Mac | N/A | Regular | Split View |

---

## Space Efficiency

### Full Metrics Panel
- **Content**: ~400pt height
- **Width**: 300-450pt (configurable)
- **Items**: 11 metrics + 3 section headers
- **Scrollable**: Yes (on smaller screens)

### Compact Overlay
- **Content**: ~110pt height
- **Width**: ~180pt fixed
- **Items**: 5 key metrics + status
- **Scrollable**: No (fixed size)
- **Opacity**: 90% background blur

---

## When to Use Each Layout

### Use Full Panel When:
- Debugging performance issues
- Optimizing FFT parameters
- Monitoring long-term CPU usage
- Need all metrics visible at once
- Have screen space to spare

### Use Compact Overlay When:
- Just need quick glance at status
- Limited screen space (iPhone)
- Focus on main content
- Monitoring while working
- Want minimal distraction

### Use Hidden When:
- Demonstrating/presenting
- Maximum content space needed
- Performance is stable
- Not debugging
- Production/end-user mode
