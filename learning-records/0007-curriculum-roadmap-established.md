# Curriculum Roadmap Established: Clock Recovery, Filterbanks, and Protocol Framing

The user expressed strong interest across all three suggested tracks: Symbol Timing Recovery, Polyphase Channelization, and Protocol Framing / Code Inspection.

## Sequencing Decision
1. **Lesson 0007 (Clock Recovery & Symbol Timing):** Close the physical layer loop. Show how an SDR samples at the optimal eye-opening instant without an external clock line, using the Gardner Timing Error Detector and fractional delay interpolation.
2. **Lesson 0008 (Wideband Channelization & Polyphase Filterbanks):** Tackle multi-channel SDR. Explain how a single Polyphase Filterbank (PFB) + FFT decomposes a 2.4 MHz spectrum into dozens of discrete HAM audio channels at line rate.
3. **Lesson 0009 (Protocol Framing & Live Codebase Tour):** Dissect AX.25 / Mode-S bitstream framing (NRZI, bit stuffing, CRC verification) and tour the real Zig NIF and Elixir GenStage pipeline in this repository.
