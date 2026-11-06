# Quadrature Amplitude Modulation (QAM) & Adaptive Channel Equalization (LMS / CMA)

Authored Lesson 30 focusing on higher-order modulation physics (16-QAM, 64-QAM), constellation geometry, PAPR/amplifier back-off, multipath channel dispersion (ISI), linear equalizers (ZF vs. MMSE), Decision-Directed LMS, blind equalization via the Constant Modulus Algorithm (CMA / Godard), and Decision Feedback Equalizers (DFE).

## Core Architecture & DSP Insights

1. **Higher-Order Modulation Physics & Spectral Efficiency vs. SNR Penalty**:
   - Expanding from constant-envelope phase keying (BPSK/QPSK) to joint amplitude-phase keying ($M$-QAM) yields theoretical spectral efficiency $\eta = \log_2(M)\text{ bits/s/Hz}$ (or $\frac{\log_2(M)}{1+\beta}$ under Root-Raised Cosine roll-off $\beta$).
   - Doubling throughput from QPSK ($2\text{ bits/s/Hz}$) to 16-QAM ($4\text{ bits/s/Hz}$) requires nearly $+3.8\text{ dB}$ higher $E_b/N_0$ for $P_b = 10^{-5}$; scaling to 64-QAM ($6\text{ bits/s/Hz}$) imposes an $+8.2\text{ dB}$ penalty ($> 6.6\times$ transmitter power).
   - Union bound for Gray-coded square $M$-QAM bit error rate:
     $$P_b \approx \frac{4}{\log_2(M)} \left(1 - \frac{1}{\sqrt{M}}\right) Q\left(\sqrt{\frac{3 \log_2(M)}{M-1} \cdot \frac{E_b/N_0}{1}}\right)$$

2. **Constellation Geometry, Gray Coding, and PAPR / Amplifier Back-Off**:
   - Square lattice coordinates take values in $\{\pm 1, \pm 3, \dots, \pm (\sqrt{M}-1)\} d$. For 16-QAM, points partition into 3 concentric energy rings ($2d^2, 10d^2, 18d^2$), giving average symbol energy $E_s = 10d^2$ and peak energy $E_{\text{peak}} = 18d^2$.
   - Constellation PAPR is $1.8$ ($2.55\text{ dB}$) for 16-QAM and $2.33$ ($3.68\text{ dB}$) for 64-QAM. With continuous-time RRC pulse-shaping, peak envelope crest factors expand to $6.5\text{--}9.0\text{ dB}$.
   - Non-linear RF Power Amplifiers (Class C/E) cause severe AM-to-AM compression and AM-to-PM phase distortion. Transmitters require linear Class A/AB operation with $6\text{--}10\text{ dB}$ of Input/Output Back-Off (IBO/OBO) to suppress third-order intermodulation products (IMD3) and prevent adjacent-channel spectral regrowth.
   - Orthogonal 2D Gray coding ensures nearest-neighbor symbol errors produce exactly one bit error out of $\log_2(M)$, minimizing BER ($P_b \approx P_s / \log_2(M)$).

3. **Multipath Dispersion & The Intersymbol Interference (ISI) Catastrophe**:
   - Terrestrial and ionospheric channels exhibit multipath reflections:
     $$y[n] = (h * x)[n] + w[n] = h[0] x[n] + \sum_{k=1}^{L-1} h[k] x[n-k] + w[n]$$
   - In frequency-selective fading channels ($H(e^{j\omega}) = \sum h[k] e^{-j\omega k}$), reflections create deep spectral notches.
   - For tightly packed QAM constellations, the ISI term $\sum_{k=1}^{L-1} h[k] x[n-k]$ easily exceeds the decision boundary spacing ($d = \sqrt{E_s/10}$). The eye diagram closes completely, creating an irreducible Bit Error Rate floor near $50\%$ that cannot be overcome by increasing TX power.

4. **Linear Equalizers & The Noise Enhancement Dilemma**:
   - Tapped-delay line FIR architecture: $y[n] = \mathbf{w}^H \mathbf{x}[n] = \sum_{k=0}^{N-1} w_k^* x[n-k]$.
   - **Zero-Forcing (ZF):** Inverts channel response $W(e^{j\omega}) = 1/H(e^{j\omega})$. Completely cancels ISI, but when channel exhibits deep spectral notches ($H \to 0$), the equalizer gain explodes, driving output noise variance $\sigma_n^2 \to \infty$.
   - **MMSE:** Wiener-Hopf solution $\mathbf{w}_{\text{opt}} = (\mathbf{R}_{xx} + \sigma_w^2 \mathbf{I})^{-1} \mathbf{p}_{xd}$ optimally balances residual ISI against noise enhancement.

5. **Decision-Directed Least Mean Squares (DD-LMS)**:
   - Error detector: $e[n] = \hat{d}[n] - y[n]$, where $\hat{d}[n] = \text{slice}(y[n])$.
   - Complex tap weight update rule: $\mathbf{w}[n+1] = \mathbf{w}[n] + \mu e^*[n] \mathbf{x}[n]$.
   - Stability condition: $0 < \mu < \frac{2}{N \cdot P_{\text{in}}}$.
   - Vulnerability: Requires mostly correct slicer decisions. If the eye diagram is closed at startup or uncorrected Carrier Frequency Offset (CFO) is spinning the constellation, slicer decisions become random, causing catastrophic loop divergence ("decision runaway"). DD-LMS cannot cold-start on dispersive channels.

6. **Blind Equalization via Constant Modulus Algorithm (CMA / Godard 1980)**:
   - Solves cold-start without training preambles or carrier synchronization.
   - Cost function penalizes envelope squared deviation from the Godard radius:
     $$J_{\text{CMA}}(\mathbf{w}) = \frac{1}{4} \mathbb{E}\left[ \left(|y[n]|^2 - R_2\right)^2 \right], \quad R_2 = \frac{\mathbb{E}[|a[n]|^4]}{\mathbb{E}[|a[n]|^2]}$$
   - For 16-QAM normalized to $E_s = 1.0$: $\mathbb{E}[|a|^4] = 132 d^4$, $\mathbb{E}[|a|^2] = 10 d^2 \implies R_2 = 1.32$.
   - Gradient & Update: $e_{\text{CMA}}[n] = y[n](R_2 - |y[n]|^2)$, updating $\mathbf{w}[n+1] = \mathbf{w}[n] + \mu_{\text{CMA}} e_{\text{CMA}}[n] \mathbf{x}^*[n]$.
   - **Carrier Phase Invariance:** Because $J_{\text{CMA}}$ depends strictly on magnitude $|y[n]|$, it is completely invariant to carrier phase rotation ($|y e^{j\Delta\omega n}| = |y|$). CMA eliminates multipath dispersion and opens the eye diagram while the constellation is still spinning wildly. Once rings form, carrier synchronization (Costas loop) locks phase, and the modem hands off to DD-LMS.

7. **Decision Feedback Equalization (DFE)**:
   - Overcomes linear equalizer noise enhancement on deep channel nulls ($\ge 20\text{ dB}$).
   - Structure: Feedforward Filter (FFF) of length $N_{ff}$ + Feedback Filter (FBF) of length $N_{fb}$:
     $$y[n] = \mathbf{w}_f^H \mathbf{x}[n] - \mathbf{w}_b^H \hat{\mathbf{d}}[n]$$
   - FFF cancels precursor ISI and renders the channel minimum-phase; FBF cancels post-cursor ISI using *noiseless quantized decisions* $\hat{d}[n-m]$.
   - Because FBF processes discrete constellation points rather than raw noisy samples, it eliminates post-cursor ISI with zero noise amplification.
   - Trade-off: Error propagation—erroneous slicer decisions circulate through FBF for $N_{fb}$ clocks, producing error bursts mitigated via outer FEC (LDPC/Reed-Solomon) and interleaving.

8. **Systems Architecture & Line-Rate Implementation**:
   - Circular buffer implementation for FIR delay lines eliminates $O(N)$ memory copies in the DSP loop.
   - Branchless 16-QAM slicing maps 1D thresholds to clamped integer arithmetic without conditional jumps.
   - Dual-mode state machine transitions from CMA acquisition to DD-LMS tracking once output MSE drops below threshold.