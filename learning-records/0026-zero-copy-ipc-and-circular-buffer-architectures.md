# Zero-Copy IPC & Circular Buffer Architectures: Page-Table Tricks vs. Erlang Refc Memory

The user explored circular buffer architectures, zero-copy IPC, and streaming memory models in Software-Defined Radio, contrasting native C++ flowgraph engines (GNU Radio) with the BEAM/Zigler hybrid architecture in SDR Scout.

## Core Architectural Dimensions Explored

1. **The Streaming DSP Buffer Dilemma:**
   - Causal FIR filtering ($y[n] = \sum_{k=0}^{M-1} h[k] x[n-k]$), matched filtering/preamble correlation ($R_{xp}[n] = \sum_{k=0}^{L-1} p[k] x[n+k]$), and overlap-save FFTs require contiguous memory slices containing historical overlap samples stitched to new incoming samples.
   - Without history contiguity, DSP kernels cannot evaluate boundary-straddling frames or compute initial filter taps without boundary glitches.

2. **Ring Buffers and SIMD Vectorization Breakage:**
   - Power-of-two modulo masking ($i \& (N - 1)$) works for scalar loops but fails for contiguous SIMD vector loads (AVX2 `_mm256_loadu_ps`, AVX-512, ARM NEON, Zig `@Vector(16, f32)`).
   - Reading 32 contiguous bytes near the ring buffer wrap boundary causes page faults (SIGSEGV) or silent buffer overrun into unrelated heap allocations.
   - Software workarounds (vector gathers, scalar fallback branches, temporary buffer copies) destroy pipelining and memory throughput.

3. **The GNU Radio `vm_circbuf` Double-mmap Trick:**
   - Uses OS virtual memory page tables to offload circular wrapping to the hardware Memory Management Unit (MMU).
   - Allocates an anonymous shared memory object (`memfd_create` or POSIX `shm_open`) of size $B$ (page-aligned multiple of 4096 bytes).
   - Reserves a $2B$ virtual address space (`mmap(PROT_NONE)`), then maps the same physical backing store twice contiguously with `MAP_FIXED | MAP_SHARED`.
   - Virtual pages $[A, A+B)$ and $[A+B, A+2B)$ point to the identical Physical Frame Numbers (PFNs). A vector instruction reading across boundary $A+B$ seamlessly wraps to physical offset 0 at zero CPU overhead.

4. **The Architectural Conflict on the BEAM:**
   - Why double-`mmap` cannot be applied directly to Erlang process heaps or off-heap Refc binaries:
     - ERTS multi-carrier slab allocators (`erts_alloc`, `sys_alloc`) sub-allocate binaries inside supercarriers without guaranteed 4KB page alignment or page sizing.
     - `MAP_FIXED` over BEAM heap pointers clobbers memory tags and corrupts generational copying GC pointers.
     - Double-`mmap` creates aliased mutable memory, violating the BEAM's core invariants of immutability and actor isolation.
     - OS virtual memory area limits (`vm.max_map_count`) restrict scalability when managing thousands of actor processes.

5. **The SdrScout Tail-Buffer Hybrid Architecture:**
   - Ingests radio streams as 64 KB off-heap Refc binaries, passed zero-copy across GenStage stages and into Zig NIFs as a raw slice pointer (`[]const u8`).
   - A persistent native `beam.Resource` (`DspContext`) maintains a 480-byte (240 complex sample) overlap tail buffer.
   - In Zig, incoming chunks are stitched into a contiguous working buffer ($480 + 65,536$ bytes), allowing uninterrupted `@Vector(16, f32)` execution.
   - The trailing 480 bytes are copied into `ctx.overlap_buf` for the subsequent chunk. Copying 480 bytes represents only $0.73\%$ overhead ($\approx 15\ \text{ns}$, 8 cache lines), avoiding the microsecond-level syscall overhead and TLB shootdown penalties of `mmap`.

6. **Hardware Cache Line and DMA Realities:**
   - 64-byte cache line granularity: avoiding split-cache-line access penalties on SIMD vector loads.
   - False sharing in SPSC ring buffers: when `head` (producer) and `tail` (consumer) share a single 64-byte line, inter-core MESI cache line bouncing degrades throughput by up to $90\%$. Solved via explicit 64-byte padding (`align(64)`).
   - Cache-coherent DMA: aligning SDR DMA ring buffers to 4KB page and 64-byte cache boundaries avoids cache line tearing when hardware DMA engines write directly into host RAM.
