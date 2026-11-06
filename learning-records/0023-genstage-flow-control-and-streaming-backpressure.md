# GenStage Flow Control & Streaming Backpressure in SDR Pipelines

Authored Lesson 19 covering reactive streaming backpressure, actor demand contracts, zero-copy off-heap message passing, and deterministic pipeline drain synchronization for the computational engineering / systems-focused learner.

## Core Architectural & Mathematical Insights

1. **The Inexorable Physical Clock ($f_s$):**
   - Radio ADCs stream samples driven by quartz crystal oscillators (e.g. 2.0 MSPS = 4.0 MB/s). Unlike TCP sockets or file descriptors, antennas cannot be paused or flow-controlled via OS blocking syscalls.
   - If downstream DSP service rate lags arrival ($\lambda > \mu$), queuing growth is strictly monotonic ($\frac{dQ}{dt} = \lambda - \mu$), converting even a 1% processing deficit into rapid Erlang heap exhaustion and Linux kernel OOM termination.
   - Naive chunk-dropping corrupts framing boundaries (such as 120 µs ADS-B Mode-S squitters) and introduces severe phase discontinuities that disrupt symbol timing recovery.

2. **GenStage Pull-Based Demand Contract:**
   - Inverts control flow: `Producer` tracks positive demand (`state.demand > 0`) and never emits unsolicited events.
   - Downstream `Consumer` dictates processing pace via explicit demand tokens, enforcing bounded mailbox queues under variable CPU loads.

3. **Window Mechanics (`max_demand: 4, min_demand: 1`):**
   - **Bounded Memory:** Caps maximum in-flight unconsumed data to $M_{\text{inflight}} = 4 \times 64\text{ KB} = 256\text{ KiB}$, ensuring the working set resides entirely within the CPU L2/L3 cache hierarchy.
   - **Starvation Elimination:** When $\Delta D = \text{max\_demand} - \text{min\_demand} = 3$ chunks are processed, GenStage automatically requests 3 more upstream while the 4th chunk is actively being crunched, overlapping SIMD DSP execution with actor IPC and eliminating pipeline idle bubbles.

4. **Zero-Copy Refc Binary IPC:**
   - Chunks of size 65,536 bytes exceed the BEAM's 64-byte threshold and are allocated as global off-heap reference-counted binaries (`refc`).
   - Inter-process message passing between `Producer` and `DetectorConsumer` copies only a 24-byte `ProcBin` pointer descriptor into the recipient heap.
   - Zigler NIF receives the raw slice (`[]const u8`) pointing directly into the off-heap buffer with zero heap allocations or `memcpy` calls.

5. **Deterministic Benchmarking (`Pipeline.drain/2`):**
   - Implements a two-phase barrier synchronization without `Process.sleep`:
     - Phase 1: `Producer.drain/2` suspends until `state.chunks == []`.
     - Phase 2: `DetectorConsumer.sync/2` leverages FIFO mailbox ordering to guarantee that all preceding SIMD chunk processing has finished before returning.

6. **GNU Radio `vm_circbuf` vs. GenStage Actors:**
   - GNU Radio uses POSIX threads and circular buffers with double virtual memory mappings (`mmap`/`shm_open`), blocking threads on POSIX condition variables and incurring OS kernel context switch penalties.
   - <code>SdrScout</code> utilizes Erlang user-space reduction scheduling (sub-microsecond context switches) with asynchronous demand tokens and fault-isolated supervision boundaries.
