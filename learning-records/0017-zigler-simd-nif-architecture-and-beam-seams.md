# Zigler SIMD NIF Architecture, Resource Lifecycle, and BEAM Seams

The user requested a thorough technical breakdown of Zigler in the context of the SDR Scout architecture, specifically following the benchmark scaling and CPU utilization analysis.

## Core Architecture Insights

1. **Compilation Mechanics**: Zigler uses the `~Z` sigil to parse native Zig code, synthesize the Erlang C NIF boilerplate (`module.zig`), build the shared object with `zig build`, and inject corresponding Elixir stubs that load the `.so`.
2. **Zero-Copy Boundary**: Slices of refc binaries (>64 bytes) in the BEAM are passed directly as `[]const u8` pointers into Zig without heap copying or serialization.
3. **`beam.Resource` Safety**: Persistent state (`DspContext`) holds the 480-byte overlap tail buffer and counters across chunks. Allocations are tracked by ERTS and automatically freed by the BEAM garbage collector when the owning process dies.
4. **SIMD Vectorization**: `@Vector(16, f32)` allows target-independent LLVM vectorization (AVX2 on x86, NEON on ARM), calculating parallel envelope magnitudes ($\sqrt{I^2 + Q^2}$) in 1 instruction cycle per 16 samples.
5. **In-NIF Syndrome Recovery**: Discarding 99.9% of invalid noise pulses in Zig and performing single-bit polynomial error correction before term creation protects Elixir from heap thrashing and GC pauses.
