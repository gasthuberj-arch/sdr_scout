# Polyphase Filterbanks: Channelization Mechanics, Commutators, and Multirate DSP

The user explored the mathematical foundations, multirate DSP theorems, and low-level systems architecture of Polyphase Filterbanks (PFBs) for wideband channelization.

## Core Architectural & DSP Insights

1. **The Wideband Channelization Problem:** Slicing a wideband RF capture (e.g., 10 MHz amateur spectrum on 10m/2m) into 100 contiguous 100 kHz channels via naive per-channel Digital Down Converters (DDCs) requires 800 Giga-MACs/sec ($M \times L \times f_s$) and discards 99% of computed samples during decimation.
2. **Failure of Naive Windowed FFTs:** An $M$-point FFT channelizer is fundamentally locked to filter length $L = M$. Rectangular windows exhibit $-13.3\text{ dB}$ first sidelobes with slow $1/f$ roll-off that allows strong adjacent carriers to drown weak signals. Tapering windows (Hann, Blackman) reduce sidelobes at the cost of doubling or tripling the mainlobe width, inducing severe passband droop and inter-channel crosstalk.
3. **The First Noble Identity:** In multirate theory, filtering by an upsampled impulse response $G(z^M)$ followed by downsampling by $M$ is algebraically identical to downsampling by $M$ first and filtering with $G(z)$ at the lower rate $f_s / M$.
4. **Polyphase Decomposition:** Partitioning a prototype FIR filter $H(z)$ into $M$ interleaved sub-filters $E_k(z) = \sum_{r=0}^{K-1} h[rM + k] z^{-r}$ of length $K = L/M$ allows the filter bank to operate strictly at the decimated rate.
5. **Commutator and IFFT Synthesis:** An input commutator delay line distributes incoming samples to the $M$ sub-filters, whose outputs are synthesized into $M$ baseband channels simultaneously using a single $M$-point Inverse FFT in $\mathcal{O}(M \log M)$ time, yielding an algorithmic speedup of over $100\times$ compared to $\mathcal{O}(K M^2)$ naive mixing.
6. **Systems Architecture & SIMD Memory Layout:** Storing prototype taps linearly results in an $M$-element stride that causes cache thrashing. Transposing coefficients into a contiguous $[K][M]$ matrix allows SIMD FMA vectorization (AVX-512 / AVX2 / ARM NEON) across 8–16 channels per instruction cycle, while virtual memory mirroring (`mmap` double-mapping) eliminates commutator pointer wrapping branches.
