# Weak-Signal DSP: FT8, Costas Arrays, and Coherent Demodulation at -24 dB SNR

Authored Lesson 18 in the SDR Scout curriculum, covering the mathematical, information-theoretic, and algorithmic principles enabling reliable digital communications far below the thermal noise floor (-24 dB SNR).

## Core Architecture & Mathematical Insights

1. **The Negative-SNR Frontier & Shannon-Hartley Capacity**:
   - Analyzed $C = B \log_2(1 + \text{SNR})$. In the wideband limit ($\text{SNR} \ll 1$), Taylor expansion yields $C \approx \frac{S}{N_0 \ln 2}$, proving communication capacity does not vanish at negative SNR; it becomes power-bounded with the absolute Shannon limit $E_b/N_0 \ge \ln 2 \approx -1.59\text{ dB}$.
   - Deconstructed the WSJT-X convention ($B_{\text{ref}} = 2500\text{ Hz}$). Demodulating inside a matched $\Delta f = 6.25\text{ Hz}$ DFT bin yields a processing gain $G_p = 10\log_{10}(2500 / 6.25) \approx +26.02\text{ dB}$, converting an apparent $-24\text{ dB}$ passband SNR into $+2.02\text{ dB}$ in-bin SNR.

2. **FT8 Physical Layer & Continuous-Phase 8-MFSK**:
   - $M = 8$ tones, tone spacing $\Delta f = 6.25\text{ Hz}$, symbol rate $R_s = 6.25\text{ baud}$, symbol duration $T_s = 160\text{ ms}$.
   - Non-coherent tone orthogonality condition $\Delta f \cdot T_s = 1$ ensures zero mutual interference under envelope detection without carrier phase tracking.
   - Continuous Phase Frequency Shift Keying (CPFSK) prevents spectral splatter across the narrow $50\text{ Hz}$ occupied channel bandwidth. Total transmission duration $12.64\text{ s}$ across 79 symbols.

3. **Costas Array 2D Time-Frequency Synchronization**:
   - Employed the 7-symbol Costas sequence $[3, 1, 4, 0, 6, 5, 2]$ with non-repeating pairwise difference vectors $\Delta f_k = c_{k + \Delta t} - c_k$ for all shifts $\Delta t$.
   - Bounded the aperiodic 2D cross-ambiguity sidelobes strictly to $\chi(\tau, \nu) \le 1$ for $(\tau, \nu) \ne (0, 0)$, providing an $8.45\text{ dB}$ ($7:1$) peak-to-sidelobe ratio.
   - Distributed arrays across beginning ($0..6$), middle ($36..42$), and end ($72..78$) of the 79-symbol frame to resolve time offset $\tau$, carrier offset $f_0$, linear Doppler/crystal drift $\dot{f} = df/dt$, and ADC sampling clock drift $dt/dt$.

4. **Discrete Fourier Demodulation**:
   - Mapped 160 ms symbols at $f_s = 12000\text{ Hz}$ to 1920-sample DFT windows, yielding an exact bin spacing of $6.25\text{ Hz}$.
   - Formed a $79 \times 8$ energy spectrogram matrix $\mathbf{E}$ via non-coherent magnitude-squared bin power detection.

5. **Forward Error Correction via LDPC (174, 91) & Belief Propagation**:
   - Frame framing: 77 user bits + 14-bit CRC = 91 message bits ($K$). Coded into $N = 174$ bits ($58 \text{ data symbols} \times 3 \text{ bits}$) across an $83 \times 174$ parity-check matrix $\mathbf{H}$ (rate $R \approx 0.523$).
   - Soft demodulation: Max-Log approximation maps the 8 tone energies to 3 bit LLRs.
   - Belief propagation: Iterative message-passing on the bipartite Tanner graph between 174 Variable Nodes and 83 Check Nodes.
   - SIMD execution: Replaced transcendental $\tanh / \operatorname{artanh}$ operations with Normalized Min-Sum updates, enabling vectorized integer min/sign operations (`_mm256_min_epi16`, `vminq_s16`) and sub-millisecond frame decoding with syndrome-check early termination.
