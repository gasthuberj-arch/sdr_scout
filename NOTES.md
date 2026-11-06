# Teaching Notes & User Preferences

## Learner Profile
- **Formal Education:** Computational Engineering BSc + Computer Science Master.
- **Languages:** Well-versed with C and Rust (solid systems foundations, pointers, memory models, cache locality, SIMD).
- **Day Job:** Cloud, security, and systems architecture.
- **Domain Interest:** Radio nerd aiming to advance in Amateur (HAM) radio and deepen exposure to Digital Signal Processing (DSP).
- **Stated Goals:**
  - Understand the deep architectural and systems tradeoffs across SDR designs (throughput, memory safety, latency, BEAM vs. C++/Rust vs. flowgraph engines).
  - Gain rigorous exposure to DSP (discrete signals, complex baseband, filtering, modulation/demodulation, correlation).
  - ADS-B is treated as a stepping-stone reference pipeline, not the destination.

## Pedagogical Guidelines
- Do not dilute the math or systems concepts. Lean into their background in computational engineering and CS.
- Emphasize memory layouts (cache lines, zero-copy, SIMD vector registers, page-table circular buffers like GNU Radio's `vm_circbuf`).
- Ground DSP theory (analytic signals, Hilbert transform, I/Q mixing, matched filters) in both physical RF intuition and concrete SIMD implementations.
