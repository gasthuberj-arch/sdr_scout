# FFT Butterfly Mechanics & Spectral Windowing Physics: Discrete Fourier Math, SIMD Vectorization, and Leakage Dynamics

Authored Lesson 25 focusing on the Fast Fourier Transform (FFT), Radix-2 Cooley-Tukey butterfly mechanics, CPU cache line striding, Stockham autosort autovectorization, and the physics of spectral windowing in Software-Defined Radio.

## Core Architecture & DSP Insights

1. **From DFT to Cooley-Tukey Radix-2 Decomposition**:
   - Discrete Fourier Transform definition: $X[k] = \sum_{n=0}^{N-1} x[n] W_N^{kn}$ ($O(N^2)$ complex MAC complexity).
   - Divide-and-conquer Decimation-in-Time (DIT): splitting into even ($2m$) and odd ($2m+1$) $(N/2)$-point sub-sequences:
     $$X[k] = E[k] + W_N^k O[k], \quad X[k + N/2] = E[k] - W_N^k O[k]$$
   - Reduces arithmetic operations from $N^2$ to $\frac{N}{2} \log_2 N$ ($682\times$ reduction for $N = 4096$).

2. **Butterfly Mechanics & Twiddle Factor Symmetries**:
   - Twiddle factor $W_N^k = e^{-j 2\pi k / N}$.
   - Symmetries exploited in DSP engines:
     - Periodicity: $W_N^{k+N} = W_N^k$
     - Half-period negation: $W_N^{k + N/2} = -W_N^k$ (producing dual butterfly outputs from a single complex multiply $T = W_N^k O[k]$)
     - Quarter-turn reductions: $W_N^0 = 1, W_N^{N/4} = -j, W_N^{N/2} = -1, W_N^{3N/4} = j$ (trivial sign flips and real/imag lane swaps, zero floating-point multiplications)
     - Conjugate symmetry: $W_N^{N-k} = (W_N^k)^* = W_N^{-k}$ (halves LUT memory footprint).

3. **Bit-Reversal Permutation Mechanics**:
   - DIT recursively decomposes sequences based on least significant bits ($b_0, b_1, \dots$), placing sample $n$ at index $\text{bitrev}(n)$.
   - In-place Cooley-Tukey requires an upfront bit-reversal pass so that successive butterfly stages can write results back into the same memory locations.
   - Hardware implementation: single-cycle `RBIT` instructions on ARM; table-based or bit-shift sequences on x86-64.

4. **Cache Locality, Thrashing, and the Stockham Autosort Architecture**:
   - Naive recursive FFTs cause immense stack allocation and memory copy overhead.
   - In-place iterative Cooley-Tukey accesses memory across strides of $2^{s-1}$. In late stages of large transforms, power-of-two strides match CPU cache line boundaries and set-associativity strides, causing severe cache conflict misses (thrashing).
   - The Stockham Autosort FFT alternates between two ping-pong buffers with unit-stride streaming reads and writes at every stage.
   - Eliminates the bit-reversal pass entirely and maximizes CPU hardware prefetcher efficiency (L1/L2 streamers), forming the basis of high-performance libraries like FFTW and Apple vDSP.

5. **SIMD Vectorization of Complex Butterflies**:
   - Interleaved $[I_0, Q_0, I_1, Q_1, \dots]$ 256-bit AVX2 layout ($4 \times \text{complex } f32$).
   - Complex multiplication $(B_r + j B_i)(W_r + j W_i) = (B_r W_r - B_i W_i) + j(B_r W_i + B_i W_r)$ vectorized via `_mm256_moveldup_ps`, `_mm256_movehdup_ps`, `_mm256_permute_ps`, and FMA `_mm256_fmsubadd_ps`.
   - Executes four independent complex butterflies per iteration at $\sim 0.5$ cycles per butterfly.

6. **The Physics of Spectral Leakage**:
   - Truncation of continuous RF signals into finite observation aperture $T = N T_s$ represents time-domain multiplication by rectangular pulse $\Pi(t/T)$.
   - Fourier Convolution Theorem: time-domain multiplication becomes continuous frequency-domain convolution with a $\text{sinc}$ Dirichlet kernel.
   - Rectangular window sidelobes peak at $-13.26\ \text{dB}$ and roll off at $-6\ \text{dB/octave}$ ($-20\ \text{dB/decade}$).
   - The Amateur Radio dynamic range challenge: a local $1.5\ \text{kW}$ station ($+30\ \text{dBm}$ ERP, $-10\ \text{dBm}$ at SDR input) produces $-23.3\ \text{dBm}$ sidelobes, completely burying a weak $-125\ \text{dBm}$ QRP/DX signal (e.g., FT8/CW) located tens of kilohertz away under artificial spectral leakage.

7. **Windowing Functions Deep-Dive**:
   - Fundamental Fourier trade-off: Mainlobe width vs Sidelobe roll-off vs Peak Sidelobe Level (PSLL).
   - Hann: $0.5 - 0.5\cos(2\pi n / (N-1))$, $-31.5\ \text{dB}$ PSLL, $-18\ \text{dB/octave}$ roll-off due to continuous first derivative at borders.
   - Hamming: $0.54 - 0.46\cos(2\pi n / (N-1))$, optimizes first sidelobe null to $-42.7\ \text{dB}$ but has edge discontinuity ($-6\ \text{dB/octave}$ roll-off).
   - 4-Term Blackman-Harris: $a_0 = 0.35875, a_1 = 0.48829, a_2 = 0.14128, a_3 = 0.01168$, delivering $-92\ \text{dB}$ PSLL—indispensable for wide-dynamic-range weak signal SDR reception.
   - Flat-Top: 5-term cosine window with flat crest, reducing scalloping loss to $< 0.01\ \text{dB}$ for precise RF power and S-meter calibration.
   - Kaiser Window: Bessel-tuned ($I_0$) parametric window with $\beta \in [0, 12]$ continuously trading spectral resolution for sidelobe suppression.

8. **ENBW, Coherent Gain, and Scalloping Loss**:
   - Coherent Gain $\text{CG} = \frac{1}{N} \sum w[n]$ scales sinusoidal tone amplitude (Hann $= 0.50$, $-6.02\ \text{dB}$).
   - Equivalent Noise Bandwidth $\text{ENBW} = N \frac{\sum w^2[n]}{(\sum w[n])^2}$ in bins (Rect $= 1.0$, Hann $= 1.50$, Blackman-Harris $= 2.00$, Flat-Top $= 3.77$).
   - Scalloping loss: peak attenuation when carrier falls halfway between bins ($k + 0.5$). Rectangular exhibits $-3.92\ \text{dB}$ loss; Blackman-Harris $-0.83\ \text{dB}$; Flat-Top $< -0.01\ \text{dB}$.
   - SIMD windowing kernel applying real window coefficients to interleaved complex baseband samples in $< 850\ \text{ns}$ for $N = 4096$.
