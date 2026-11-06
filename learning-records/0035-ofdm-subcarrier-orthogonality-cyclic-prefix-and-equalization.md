# OFDM: Subcarrier Orthogonality, Cyclic Prefix, and Channel Estimation

Authored Lesson 31 focusing on wideband multipath propagation, subcarrier orthogonality mechanics, discrete Fourier transform modulation engines, the cyclic prefix circular convolution equivalence, frequency-domain equalization (Zero-Forcing vs. MMSE), pilot-assisted channel estimation, and carrier frequency offset (CFO) sensitivity with Schmidl-Cox synchronization.

## Core Architecture & DSP Insights

1. **The Wideband Multipath Bottleneck:**
   - Terrestrial RF multipath creates dispersion with delay spread $\tau_{\text{delay}} = \tau_{\max} - \tau_{\min}$ and coherence bandwidth $B_c \approx \frac{1}{5 \tau_{\text{delay}}}$.
   - When signal bandwidth $B \gg B_c$ ($T_s \ll \tau_{\text{delay}}$), the channel is frequency-selective. Multipath echoes span $L = \lceil \tau_{\text{delay}} \cdot B \rceil$ taps.
   - Time-domain equalization complexity explodes: Viterbi MLSE requires $\mathcal{O}(M^L)$ states (intractable for $M \ge 4, L \ge 20$), while linear equalizers require $\mathcal{O}(L^3)$ matrix inversion and $2L$ complex MACs/sample at line rate.
   - **OFDM Paradigm Shift:** Partitions bandwidth $B$ into $N$ subcarriers of width $\Delta f = B/N \ll B_c$. With symbol duration $T_{\text{sym}} = N T_s \gg \tau_{\text{delay}}$, each subcarrier experiences flat fading, replacing multi-tap FIR matrix inversion with $N$ independent scalar divisions.

2. **Mathematical Condition for Subcarrier Orthogonality:**
   - Continuous-time inner product: $\langle \phi_k, \phi_m \rangle = \frac{1}{T} \int_0^T e^{j 2\pi (k - m)\Delta f t} \, dt$.
   - Evaluates to $\frac{e^{j 2\pi (k - m)\Delta f T} - 1}{j 2\pi (k - m)\Delta f T}$, which vanishes for all $k \ne m$ if and only if:
     $$\Delta f = \frac{1}{T_{\text{sym}}}$$
   - Rectangular gating gives each subcarrier a sinc spectrum: $\Phi_k(f) \propto \text{sinc}(\pi (f - f_k) T)$. At the exact center frequency of subcarrier $m$, all other subcarriers have spectral nulls ($\text{sinc}(\pi (m - k)) = 0$), enabling dense spectral overlap without Inter-Carrier Interference (ICI).

3. **IFFT / FFT Modulation Engine:**
   - Discrete baseband sampling at $t_n = n \frac{T}{N}$ transforms the continuous tone bank into an $N$-point Inverse Discrete Fourier Transform:
     $$s[n] = \sum_{k=0}^{N-1} X_k e^{j \frac{2\pi}{N} k n} = N \cdot \text{IDFT}\{X_k\}[n]$$
   - Receiver recovers constellation points via forward DFT: $Y_k = \text{DFT}\{r[n]\}[k]$.
   - Cooley-Tukey FFT drops complexity from $\mathcal{O}(N^2)$ to $\mathcal{O}(N \log_2 N)$ (e.g., $102\times$ compute reduction for $N=1024$, $630\times$ for $N=8192$), making multi-megahertz wideband transceivers feasible on general-purpose CPUs and embedded DSPs.

4. **The Cyclic Prefix (CP) Magic Trick: Linear to Circular Convolution:**
   - Linear physical channel convolution $y[n] = (s * h)[n]$ causes Inter-Symbol Interference (ISI) and destroys subcarrier orthogonality across finite observation windows.
   - Prepending the last $N_{\text{cp}}$ samples of the symbol to the front ($\mathbf{s}_{\text{tx}} = [s[N-N_{\text{cp}} \dots N-1], s[0 \dots N-1]]$) and discarding the first $N_{\text{cp}}$ samples at the receiver completely eliminates ISI if $N_{\text{cp}} \ge L$ ($\tau_{\text{delay}} \le T_{\text{cp}}$).
   - In discrete time, delayed copies that wrap into the discarded prefix reconstruct the modulo indexing of circular convolution:
     $$r[n] = \sum_{\ell=0}^{L-1} h[\ell] s[(n - \ell) \pmod N] + w[n] = (s \circledast h)[n] + w[n]$$
   - The circular convolution theorem diagonalizes the channel in the DFT basis ($\mathbf{H} = \mathbf{F} \mathbf{C}_h \mathbf{F}^H = \text{diag}(H_0, \dots, H_{N-1})$), guaranteeing **zero ISI and zero ICI**.

5. **Frequency-Domain Equalization (FEQ): Zero-Forcing vs. MMSE:**
   - Diagonal channel enables scalar equalization per subcarrier: $Y_k = H_k X_k + W_k$.
   - **Zero-Forcing (ZF):** $\hat{X}_k^{\text{ZF}} = Y_k / H_k$. In deep multipath notches ($|H_k| \to 0$), noise variance $\sigma_w^2 / |H_k|^2 \to \infty$, severely degrading error rates.
   - **Minimum Mean Square Error (MMSE):**
     $$G_k^{\text{MMSE}} = \frac{H_k^*}{|H_k|^2 + \frac{1}{\text{SNR}_k}}, \quad \hat{X}_k^{\text{MMSE}} = G_k^{\text{MMSE}} Y_k$$
   - Adapts dynamically: converges to ZF at high SNR, while gracefully attenuating faded subcarriers ($G_k \to 0$) in deep notches, letting downstream Forward Error Correction (FEC) resolve erased symbols.

6. **Pilot Subcarriers & Channel Estimation:**
   - Least-Squares estimation at pilot indices: $\hat{H}_p^{\text{LS}} = Y_p / X_p = Y_p X_p^*$ (for unit-power pilots).
   - 2D time-frequency interpolation (comb, block, or diamond grid) tracks frequency selectivity (delay spread) and time selectivity (Doppler).
   - Transform-domain denoising: IFFT of pilot estimates into delay domain, zeroing noise taps beyond channel delay spread $L \le N_{\text{cp}}$, and forward FFT back to frequency domain yields up to $10 \log_{10}(N / L)\text{ dB}$ SNR improvement.

7. **Carrier Frequency Offset (CFO) Sensitivity & Schmidl-Cox Synchronization:**
   - Fractional CFO $\epsilon = \Delta f_{\text{CFO}} / \Delta f$ shifts subcarrier sinc functions away from nulls, leaking power from all $N-1$ tones into each subcarrier as Inter-Carrier Interference (ICI): $\text{SIR}_{\text{CFO}} \approx 10 / (\pi^2 \epsilon^2)$.
   - Even $\epsilon = 0.04$ caps maximum SNR below $22\text{ dB}$, breaking 64/256-QAM constellations.
   - **Schmidl-Cox Preamble:** Uses repeated time-domain halves $[A, A]$ (even subcarriers modulated, odd zeroed).
   - Sliding cross-correlation $P(d)$ and energy $R(d)$ yield timing metric $M(d) = |P(d)|^2 / R(d)^2$ with an $N_{\text{cp}}$-wide plateau for frame detection.
   - Phase of $P(d)$ at peak timing directly estimates fractional CFO: $\hat{\epsilon}_{\text{frac}} = \angle P(d_{\text{opt}}) / \pi$. Applying time-domain NCO derotation prior to the FFT restores subcarrier orthogonality.

8. **SIMD & Systems Architecture:**
   - Frequency-domain MMSE equalization vectorizes cleanly across interleaved complex floats (e.g. 8-lane AVX2 or Zig `@Vector(8, f32)` processing 4 complex subcarriers per cycle).
   - Cyclic prefix handling in streaming pipelines is implemented zero-copy via ring-buffer pointer offsets, bypassing memory copies.
