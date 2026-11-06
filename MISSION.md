# Mission: SDR Systems Architecture & DSP for Amateur Radio

## Why
Master Software-Defined Radio (SDR) architectures from continuous RF physics down to discrete complex baseband DSP and higher-layer protocol framing. Understand systems-level trade-offs (cache locality, SIMD vectorization, zero-copy IPC, concurrency models, scheduler jitter) across SDR engines so you can design, analyze, and build high-performance HAM radio systems and digital mode pipelines.

## Success looks like
- Rigorously evaluate SDR architectures (Elixir/OTP + Zig NIFs, GNU Radio C++/Python, pure C/Rust pipelines) across memory throughput, SIMD cache efficiency, latency jitter, and fault tolerance.
- Explain and manipulate complex baseband I/Q representations, downconversion mixing, Nyquist-Shannon bandwidth limits, and matched filtering.
- Design robust streaming pipelines that handle DSP math at line rate without triggering scheduler stalls or buffer overflows.
- Confidently reason about HAM digital modes (AFSK, FSK/MFSK in FT8, PSK, QAM) and choose the right architectural pattern for each.

## Constraints
- Leverages user's Computational Engineering BSc & CS MSc background (C/Rust/systems architecture).
- Focus on general SDR and amateur radio signal processing; Mode-S / ADS-B serves as the concrete reference implementation.

## Out of scope
- Niche aviation-only business rules (e.g., Gillham altitude decoding, CPR spherical coordinate formulas) except where illustrating protocol framing and error syndromes.
