# AudioDSP

A professional-grade real-time audio processing application for macOS. Routes audio from virtual audio devices through a customizable DSP chain with studio-quality effects.

## Features

### Audio Effects
- **5-Band Parametric EQ** - Low shelf, 3 peak bands, high shelf with interactive curve visualization
- **Compressor** - Soft-knee dynamics control with gain reduction metering
- **Limiter** - Brickwall limiter with lookahead for peak protection
- **Reverb** - Schroeder reverb with room size, damping, and width controls
- **Delay** - Stereo delay with ping-pong mode and feedback
- **Bass Enhancer** - Psychoacoustic sub-harmonic synthesis
- **Vocal Clarity** - Presence and air enhancement for vocals
- **Stereo Widener** - Mid/side processing for stereo image control
- **Output Gain** - Master level control

### Interface
- Real-time spectrum analyzer
- Input/output level metering
- A/B comparison for quick setting comparison
- Undo/redo support
- Preset system with save/load functionality
- Dark theme optimized for audio work

## Requirements

- macOS 14.0 (Sonoma) or later
- [BlackHole](https://existential.audio/blackhole/) virtual audio driver (for audio input routing)
- Audio output device (speakers or headphones)

## Building

```bash
# Clone the repository
git clone <repo-url>
cd AudioDSP

# Build with Swift Package Manager
swift build -c release

# Or generate Xcode project
xcodegen generate
open AudioDSP.xcodeproj
```

## Usage

1. Install BlackHole and configure your audio source to output to BlackHole
2. Launch AudioDSP
3. The app automatically detects BlackHole as input and your default speakers as output
4. Adjust effects using the intuitive knob and fader controls
5. Save presets for later recall

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘R` | Start audio engine |
| `⌘.` | Stop audio engine |
| `⌘B` | Toggle A/B comparison |
| `⌘S` | Save preset |
| `⌘[` | Previous preset |
| `⌘]` | Next preset |
| `⌘Z` | Undo |
| `⇧⌘Z` | Redo |

### Built-in Presets

- **Flat** - Bypass processing (limiter only for safety)
- **Bass Boost** - Enhanced low frequencies
- **Vocal Clarity** - Optimized for voice content
- **Loudness** - Maximized perceived loudness

## Architecture

```
AudioDSP/
├── App/           # Entry point and main window
├── UI/            # SwiftUI interface
│   ├── Panels/    # EQ, Dynamics, Effects, Master panels
│   ├── Components/# Knob, Fader, Meters, Spectrum
│   └── Theme/     # Design system
├── State/         # Observable state management
├── Audio/         # CoreAudio engine and ring buffer
├── DSP/           # Digital signal processing
│   ├── Core/      # Effect protocol and chain
│   ├── Effects/   # Individual effect implementations
│   ├── Filters/   # Biquad filter
│   └── Analysis/  # FFT spectrum analyzer
└── Presets/       # Preset save/load
```

### Signal Flow

```
BlackHole Input → Ring Buffer → DSP Chain → FFT Analyzer → Speaker Output
                                    │
                                    ├── Parametric EQ
                                    ├── Bass Enhancer
                                    ├── Vocal Clarity
                                    ├── Compressor
                                    ├── Reverb
                                    ├── Delay
                                    ├── Stereo Widener
                                    ├── Limiter
                                    └── Output Gain
```

## Technical Details

- Sample rate: 48 kHz
- Channels: Stereo
- Buffer size: 512 samples
- FFT size: 2048 bins
- No external audio dependencies - built entirely with Apple frameworks (CoreAudio, Accelerate, AVFoundation)

## License

MIT License - see [LICENSE](LICENSE) for details.
