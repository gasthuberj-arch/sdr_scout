# Pulse Shaping, Intersymbol Interference, and Root-Raised Cosine (RRC)

Authored Lesson 17 bridging the physical realities of RF bandlimiting, Fourier spectral containment, and discrete-time baseband systems architecture for a learner with Computational Engineering BSc, CS MSc, systems programming (C/Rust), and HAM radio foundations.

## Core Architectural & DSP Insights

1. **The Physical Flaw of Rectangular Keying**:
   - In pure digital logic, square pulses are standard, but transmitting $p_{\text{rect}}(t) = \Pi(t/T_s)$ generates a $T_s \text{sinc}(f T_s)$ frequency spectrum with an envelope decaying at only $1/f$ ($-20\text{ dB/decade}$).
   - This creates massive Adjacent-Channel Interference (ACI), violating FCC Part 97 (§97.307) and ITU-R spectral masks (the physical origin of amateur CW "key clicks").

2. **The Bandlimiting Trap & Intersymbol Interference (ISI)**:
   - Passing pulses through bandlimited channels or sharp analog filters causes time-domain dispersion (Fourier duality).
   - Adjacent symbol tails bleed into the decision window: $r(m T_s) = a_m p(0) + \sum_{k \ne m} a_k p((m - k) T_s) + n(m T_s)$. Without deliberate pulse shaping, neighboring symbol tails can invert bit decisions even in zero-noise conditions.

3. **Nyquist's First Criterion & Sinc Limitations**:
   - Zero ISI requires $p(k T_s) = 0$ for all non-zero integers $k \in \mathbb{Z} \setminus \{0\}$, which in frequency requires folded replicas to sum to a constant: $\sum_k P(f - k/T_s) = T_s$.
   - The minimal Nyquist bandwidth is $B_{\min} = R_s / 2$, achieved by the brick-wall sinc pulse.
   - However, sinc is practically unusable: non-causal, infinite support, and $1/t$ tail decay that leads to harmonic series divergence ($\sum 1/k$) under slight timing jitter $\Delta t$.

4. **The Raised Cosine (RC) Filter & $1/t^3$ Asymptotic Decay**:
   - Introducing excess bandwidth parameter $\alpha \in [0, 1]$ yields total bandwidth $B = \frac{R_s}{2}(1 + \alpha)$ with odd spectral symmetry around $f_N = R_s / 2$.
   - The analytical impulse response $h_{RC}(t) = \text{sinc}(t/T_s) \frac{\cos(\pi \alpha t / T_s)}{1 - (2\alpha t / T_s)^2}$ decays asymptotically as $\mathcal{O}(1/t^3)$.
   - Rapid $1/t^3$ convergence ($\sum 1/k^3 \approx 1.202$) bounds timing jitter sensitivity and allows tight FIR truncation to 6–8 symbol spans.

5. **The Root-Raised Cosine (RRC) Split & The Matched Filter Dilemma**:
   - Placing the full Raised Cosine filter at the transmitter fails because the Matched Filter Theorem (Cauchy-Schwarz) demands that the receiver filter match the transmit pulse shape ($H_{RX} = H_{TX}^*$) to maximize SNR in AWGN.
   - Cascading two identical Raised Cosine filters would yield $H_{RC}^2(f)$, which violates Nyquist zero ISI.
   - Symmetrically factoring the response into $H_{TX}(f) = H_{RX}(f) = \sqrt{H_{RC}(f)} \equiv H_{RRC}(f)$ satisfies both optimal receiver SNR and zero end-to-end ISI ($H_{total} = H_{RC}$).
   - **Crucial engineering subtlety:** An isolated RRC pulse $h_{RRC}(t)$ does *not* have zero ISI; zero ISI exists solely at the output of the receiver matched filter.

6. **Eye Diagrams as Link Diagnostics**:
   - Vertical aperture directly measures noise margin.
   - Horizontal aperture measures timing jitter tolerance.
   - Transition slope ($dV/dt$) quantifies clock recovery tracking sensitivity.
   - Overshoot determines Peak-to-Average Power Ratio (PAPR) and required PA back-off.

7. **Systems Architecture: Polyphase Interpolation & SIMD Execution**:
   - Direct upsampling by $L$ followed by FIR convolution spends $(L-1)/L$ (75%–87.5%) of clock cycles multiplying inserted zero samples.
   - Polyphase decomposition partitions the $N_{\text{taps}}$-length RRC into $L$ parallel sub-filters $p_\ell[k] = h[k L + \ell]$, completely eliminating zero-multiplications.
   - Sub-filter kernels fit into L1 cache and vectorize directly into AVX2/NEON FMA registers.
   - Real-world standards: DMR 4FSK ($\alpha = 0.36$), P25 Phase 2 ($\alpha = 0.2$), DVB-S2 satellite ($\alpha = 0.20\text{–}0.35$), and FT8 Gaussian constant-envelope contrast ($BT = 2.0$).

## Next Frontier

- Bridge pulse-shaped complex baseband into carrier recovery and carrier phase tracking (Costas loop, squaring loop) for coherent PSK/QAM.
- Combine the polyphase RRC interpolator with the Gardner timing error detector and Farrow fractional resampler into a closed-loop timing recovery pipeline.
