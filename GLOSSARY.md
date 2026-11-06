# SDR & DSP Architecture Glossary

Canonical definitions for SDR signal processing and systems architecture used throughout this workspace.

## Signal Processing & DSP

**Complex Baseband (I/Q)**:
A two-dimensional representation of an RF band centered at zero frequency, consisting of In-Phase ($I$) and Quadrature ($Q$, 90° phase shifted) components, capturing both amplitude and phase without redundant symmetric negative-frequency data.
_Avoid_: Dual-channel audio, stereophonic radio signal

**Analytic Signal**:
A continuous or discrete complex signal with no negative frequency components, represented mathematically as $s_a(t) = s(t) + j\hat{s}(t)$, where $\hat{s}(t)$ is the Hilbert transform of real signal $s(t)$.
_Avoid_: Complexified wave, imaginary voltage

**Matched Filter**:
The optimal linear filter for maximizing the signal-to-noise ratio (SNR) in the presence of additive white Gaussian noise, obtained by cross-correlating the received signal with a time-reversed, conjugated template of the known transmitted pulse.
_Avoid_: Template matcher, signal cleaner

**CFAR (Constant False Alarm Rate)**:
An adaptive detection algorithm that dynamically scales the detection threshold based on surrounding reference noise cells, preventing thermal noise fluctuations from swamping the receiver with false positives.
_Avoid_: Dynamic squelch, auto-threshold

**Syndrome Vector**:
In linear block error-detecting codes over $\text{GF}(2)$, the non-zero remainder resulting from polynomial division of a corrupted codeword, which uniquely identifies the error polynomial for single-bit faults.
_Avoid_: CRC hash error, parity checksum remainder

**Soft-Decision Slicing**:
Preserving continuous reliability metrics (such as signal magnitude deltas or log-likelihood ratios) alongside raw binary decisions, enabling downstream error decoders to repair weak or ambiguous bits.
_Avoid_: Fuzzy bit reading, threshold quantization

**Symbol Timing Recovery**:
The discrete signal processing loop that estimates and tracks the transmitter's symbol clock phase and frequency from received data, determining the exact sample instant where the eye diagram is widest.
_Avoid_: Clock sync, baud timer

**Eye Diagram**:
An oscilloscope display formed by overlaying repeating symbol intervals, whose open central aperture indicates high signal-to-noise ratio and low intersymbol interference (ISI).
_Avoid_: Jitter plot, scope wave

**Gardner Timing Error Detector**:
A non-data-aided timing recovery algorithm requiring only two samples per symbol (the on-time sample and mid-point sample) to compute clock drift: $e[k] = x[k - 1/2] \cdot (x[k] - x[k-1])$.
_Avoid_: Bit sync formula, phase comparator

**Polyphase Filterbank (PFB)**:
A computationally optimal multirate filter architecture that decomposes a prototype low-pass FIR filter into $M$ parallel sub-filters coupled to an inverse FFT, channelizing wideband spectrum into $M$ narrowband sub-bands in $O(M \log M)$ time.
_Avoid_: Multi-tuner bank, channel splitter

**Noble Identities**:
Mathematical commutation rules in multirate digital signal processing that permit swapping downsamplers/decimators before filtering operations, ensuring arithmetic is executed at the lowest sample rate.
_Avoid_: DSP shortcut rules, filter swap property

**Decimation**:
The combined process of low-pass anti-aliasing filtering followed by downsampling by an integer factor $M$, reducing the sample rate to match the smaller bandwidth of an extracted sub-channel.
_Avoid_: Sample dropping, down-sampling without filter

**TDOA (Time Difference of Arrival)**:
A multilateration technique that determines the location of an RF emitter by measuring the difference in arrival times of the exact same signal across spatially separated receiver nodes, defining hyperbolic position curves ($c \approx 300\text{ m}/\mu\text{s}$).
_Avoid_: Triangulation, signal bearing finder

**Cross-Correlation (Signals)**:
A measure of similarity of two waveforms as a function of the displacement of one relative to the other, computed efficiently in the frequency domain as $R_{xy}(\tau) = \mathcal{F}^{-1}\{X(f) \cdot Y^*(f)\}$.
_Avoid_: Stream comparison, mutual overlap score

**GCC-PHAT (Generalized Cross-Correlation with Phase Transform)**:
A cross-correlation algorithm that whitens the cross-power spectrum by dividing out the magnitude ($R = \mathcal{F}^{-1}\{(X Y^*) / |X Y^*|\}$), producing razor-sharp delta peaks that resist multipath interference and frequency distortion.
_Avoid_: Whitened correlation, normalized delay finder

**Parabolic Sub-Sample Interpolation**:
A mathematical technique that fits a 3-point quadratic polynomial around a discrete correlation peak ($y_{-1}, y_0, y_{+1}$) to estimate true continuous peak delay with fractional-sample accuracy ($\delta = \frac{y_{-1} - y_{+1}}{2(y_{-1} - 2y_0 + y_{+1})}$).
_Avoid_: Sub-bin guess, peak smoother

**Distributed Erlang Cluster**:
A mesh of independent BEAM virtual machine nodes communicating transparently via TCP sockets, providing location-agnostic actor messaging and distributed process groups (`:pg`) with zero external middleware.
_Avoid_: Microservice cluster, REST gateway network

**Airspace Tracking**:
The stateful process of ingesting decoded Mode-S Extended Squitter frames, calculating aircraft kinematics (latitude/longitude from even/odd CPR pairs, barometric/geometric altitude, ground speed, heading, callsign), and evicting stale flight contacts after a timeout threshold.
_Avoid_: Radar database, flight store

**Downconversion / Mixing**:
Multiplying a high-frequency bandpass RF signal by a local oscillator tone ($e^{-j 2\pi f_c t}$) to translate the center frequency from carrier frequency $f_c$ down to $0\text{ Hz}$ (baseband).
_Avoid_: Heterodyning down to zero, RF demodulation

## Systems & Concurrency Architecture

**Refc Binary**:
A BEAM (Erlang/Elixir) heap binary exceeding 64 bytes that is allocated on a global ref-counted heap outside process heaps, enabling zero-copy sharing across processes and NIF boundaries.
_Avoid_: Global shared pointer, heap blob

**NIF (Native Implemented Function)**:
A native C, C++, or Zig shared library function called directly by a BEAM Erlang process on a scheduler thread, running synchronously without inter-process communication overhead.
_Avoid_: FFI subprocess, native plugin

**GenStage Demand Backpressure**:
A producer-consumer pattern where downstream processing stages explicitly request a discrete batch count ($N$ events) from upstream producers, preventing buffer ballooning during CPU-bound workloads.
_Avoid_: Pull streaming, reactive throttling
