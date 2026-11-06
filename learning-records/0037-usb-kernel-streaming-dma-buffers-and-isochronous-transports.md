# High-Throughput USB & Kernel Streaming Architectures: `libusb`, Isochronous Transports, and DMA Ring Buffers

The user explored the systems architecture, protocol layers, and kernel-level streaming mechanics of USB data ingest in Software-Defined Radio (SDR), examining the bridge from physical ADC sampling across the USB bus into zero-copy native Zigler NIFs on the BEAM.

## Core Architectural Dimensions Explored

1. **USB Physical & Signaling Limits in SDR Systems:**
   - **USB 2.0 High-Speed:** Raw signaling rate of $480\ \text{Mbps}$ with NRZI line coding, bit stuffing, and $125\ \mu\text{s}$ microframes. Accounting for protocol framing (tokens, PIDs, CRC16 handshakes, inter-packet delays, host scheduling margins), practical sustained user payload throughput is constrained to $\approx 40 - 43\ \text{MB/s}$.
   - **USB 3.0 / 3.2 SuperSpeed:** Dual-simplex full-duplex differential pairs (`SSTX` / `SSRX`) operating at $5.0\ \text{Gbps}$ with $8\text{b}/10\text{b}$ encoding ($500\ \text{MB/s}$ raw symbol rate). Eliminates host polling via asynchronous endpoint-ready (`ERDY`) notifications and supports packet bursting up to 16 packets ($16\ \text{KB}$) before acknowledgment, yielding sustained throughput of $\approx 380 - 440\ \text{MB/s}$ (used in USRP B200/B210, BladeRF 2.0 micro, LimeSDR).
   - **Throughput Rate Modeling:** Payload rate calculation $R_{\text{data}} = f_s \times B_{\text{sample}}$. Evaluated bus saturation boundaries: RTL-SDR at $2.4\ \text{MSPS}$ ($4.8\ \text{MB/s}$, $12\%$ of USB 2.0) vs. HackRF at $20\ \text{MSPS}$ ($40\ \text{MB/s}$, $100\%$ bus saturation) vs. USRP B210 $2\times 2$ MIMO LTE at $30.72\ \text{MSPS}$ ($245.76\ \text{MB/s}$, $61\%$ of USB 3.0) vs. BladeRF 2.0 at $61.44\ \text{MSPS}$ MIMO ($491.52\ \text{MB/s}$, exceeding USB 3.0 bandwidth limits).

2. **Bulk Transfers vs. Isochronous Transports:**
   - **Bulk Transfers:** Non-periodic, closed-loop flow control with hardware CRC16 error checking and automatic retransmission (ACK/NAK handshake). Best-effort scheduling priority. Guarantees bit-level integrity with variable delivery latency and potential backpressure stalls.
   - **Isochronous Transfers:** Periodic, pre-reserved bandwidth per microframe (up to $3072\ \text{bytes/microframe} \approx 24.576\ \text{MB/s}$ on USB 2.0 HS). No handshake, no retransmission. Deterministic bounded latency with uncorrected packet loss upon transmission noise.
   - **Why RTL-SDR & Modern SDRs Choose Bulk:**
     - Realtek RTL2832U originated as a DVB-T television demodulator ASIC streaming MPEG-2 Transport Stream (TS) packets over USB Bulk EP1; bit errors would corrupt MPEG entropy tables, so hardware relied on Bulk retransmission.
     - DSP pipelines require continuous analytic baseband time series; Isochronous drops create unannounced variable-sized time holes that destroy carrier phase tracking and matched filtering.
     - Bulk transfers push backpressure into hardware FIFOs, cleanly demarcating overflow events and guaranteeing that every received sample block is mathematically pristine.

3. **Asynchronous `libusb` Architecture & Concurrent URB Pools:**
   - Synchronous `libusb_bulk_transfer` anti-pattern: incurs thread context switching and a "dead time gap" between transfer completion and subsequent URB submission. At $2.4\ \text{MSPS}$, the RTL2832U's small internal FIFO ($\approx 16\ \text{KB}$) drains in only $3.41\ \text{ms}$, making synchronous ingest prone to frequent FIFO overflow drops.
   - Asynchronous URB submission architecture: pre-allocates an in-flight pool of $K$ concurrent `libusb_transfer` structs (e.g. 16 transfers of 16 KB = 256 KB window).
   - Submit $\to$ complete callback lifecycle: completion callback dispatches the filled buffer to the consumer queue and immediately resubmits the URB to keep the kernel xHCI DMA queue perpetually saturated.
   - Dedicated event loop thread running `libusb_handle_events_timeout_completed` to process hardware completion interrupts without stalling compute threads.

4. **Zero-Copy Kernel Streaming (DMA, `mmap`, and `io_uring`):**
   - Host controller xHCI acts as a PCI bus master writing incoming packets directly to physical DRAM frames via Scatter-Gather DMA.
   - Cache coherency: hardware bus snooping on x86 maintains L1/L2 cache validity during DMA writes, whereas non-coherent ARM architectures require explicit kernel cache invalidation flushes.
   - Eliminating `copy_to_user` overhead via `usbfs` DMA buffer memory mapping (`mmap`).
   - Modern Linux `io_uring` integration: using Submission Queue (SQ) and Completion Queue (CQ) ring buffers shared between user and kernel space, combined with `IORING_SETUP_SQPOLL` to eliminate system call overhead (`ioctl`) in high-throughput streaming loops.

5. **RTL2832U Protocol & Packet Mechanics:**
   - Endpoint layout: EP0 control endpoint (vendor-specific requests bridge internal $I^2C$ bus to tune Rafael Micro R820T2 or Elonics E4000) and EP1 IN (`0x81` Bulk) streaming endpoint.
   - Sample format: Interleaved 8-bit unsigned integers $[I_0, Q_0, I_1, Q_1 \dots]$, with $127.5$ as DC ground. Mathematical conversions: normalized floating-point $(x_{\text{raw}} - 127.5) / 127.5$ vs. fixed-point SIMD integer scaling $(x_{\text{raw}} - 128) \ll 8$.
   - Packet alignment: strict multiples of 512 bytes (256 complex pairs per USB High-Speed packet).
   - Drop detection heuristics: RTL2832U lacks hardware sequence numbers and timestamps (unlike VITA 49 / CHDR in USRP); hardware FIFO drops must be inferred via wall-clock callback timestamp deltas ($\Delta T > T_{\text{nominal}}$) and spectral phase discontinuity detection.

6. **Zero-Copy BEAM & Zigler Integration:**
   - Erlang Port drivers incur double copying and process context switches; eliminated via Asynchronous Native Implemented Functions (NIFs).
   - Off-heap Reference-Counted Binaries (`Refc Binaries` > 64 bytes): USB buffers allocated directly as Refc binaries, allowing zero-copy pointer dispatch (`ProcBin`) across Elixir GenStage pipelines.
   - Zigler NIF kernels receive `[]const u8` slices directly in memory and execute SIMD vector transformations (`@Vector(16, u8)` to `@Vector(16, f32)`) via AVX2 / NEON without triggering BEAM garbage collection.
