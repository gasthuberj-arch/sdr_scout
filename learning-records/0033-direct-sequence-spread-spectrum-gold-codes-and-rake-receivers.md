# Direct-Sequence Spread Spectrum (DSSS): Gold Codes, Processing Gain, and Rake Receivers

Authored Lesson 29 covering the physics of wideband spread spectrum, pseudo-noise sequences, preferred pairs and Gold code generation, mathematical derivation of processing gain, high-performance despreading architectures (FFT convolution vs. bitwise XOR-popcount), and multipath diversity harvesting via Rake receivers and Maximal Ratio Combining (MRC).

## Core Architecture & DSP Insights

1. **The Physics & Information Theory of Bandwidth Spreading ($B_{ss} \gg B_{\text{info}}$):**
   - Transmit power $P$ is distributed across an expanded RF bandwidth $B_{ss} \approx 1/T_{\text{chip}} = N \cdot B_{\text{info}}$.
   - Power Spectral Density (PSD) drops by the spreading factor: $S_{\text{spread}}(f) \approx S_{\text{narrow}}(f) / N$. Dispersing power below the thermal noise floor ($S_{\text{spread}} \ll N_0$) achieves Low Probability of Intercept/Detection (LPI/LPD).
   - In wideband regimes ($\text{SNR} \ll 1$), Shannon capacity approaches $C \approx \frac{S}{N_0 \ln 2}$, proving communication is power-limited rather than bandwidth-limited.
   - Jamming Margin: $M_J = G_p - (E_b/N_0)_{\text{req}} - L_{\text{sys}}$. Despreading collapses the signal to $B_{\text{info}}$ while spreading narrowband jammers across $B_{ss}$, attenuating interference by $G_p$.

2. **Galois Field LFSRs & Maximal-Length Sequences (m-sequences):**
   - Characteristic polynomial $P(x) = x^m + \sum_{i=1}^{m-1} c_i x^i + 1 \in \mathbb{F}_2[x]$.
   - When $P(x)$ is primitive over $\text{GF}(2)$, the LFSR generates an m-sequence of maximal period $N = 2^m - 1$, satisfying Golomb's three randomness postulates (balance, run distributions, and ideal circular autocorrelation).
   - Bipolar circular autocorrelation: $R_a(0) = N$ and $R_a(\tau) = -1$ for all $\tau \not\equiv 0 \pmod N$. The Kronecker $\delta$-like peak enables sub-chip time-of-arrival ranging and Delay-Locked Loop (DLL) code tracking.

3. **Preferred Pairs & Robert Gold's Theorem (1967):**
   - The multi-user CDMA catastrophe: arbitrary m-sequences exhibit severe, unregulated cross-correlation sidelobes (peaking above $0.3N$ to $0.5N$), causing catastrophic Multi-Access Interference (MAI) and near-far blocking.
   - For degree $m \not\equiv 0 \pmod 4$, preferred primitive polynomial pairs $(u, v)$ produce cross-correlation bounded strictly to three discrete values:
     $$R_{uv}(\tau) \in \left\{ -t(m), \; -1, \; t(m) - 2 \right\}, \quad t(m) = 1 + 2^{\lfloor (m+2)/2 \rfloor}$$
   - Gold code family: $G(u, v) = \{u, v\} \cup \{u \oplus T^k v \mid 0 \le k < N\}$ yields $N + 2 = 2^m + 1$ unique sequences. All pairwise cross-correlations and out-of-phase autocorrelations are bounded by $t(m)$.
   - GPS L1 C/A implementation: $m=10$, $N=1023$, $f_{\text{chip}} = 1.023\text{ Mchip/s}$, $t(10) = 65$, bounding cross-correlation peaks to $65/1023 \approx -23.94\text{ dB}$.

4. **Rigorous Derivation of Processing Gain ($G_p$):**
   - Accumulating $L$ chips: signal chips add coherently ($S_{\text{out}} = L^2 P_{\text{sig}}$), while independent noise samples add incoherently ($\sigma_{\text{out}}^2 = L \sigma_w^2$).
   - Output SNR: $\text{SNR}_{\text{out}} = L \cdot \text{SNR}_{\text{RF}} \implies G_p = 10 \log_{10}(L) = 10 \log_{10}(T_{\text{symbol}} / T_{\text{chip}})$.
   - Operating at $-15\text{ dB}$ RF SNR: with $L = 1023$, $G_p \approx +30.1\text{ dB}$, yielding $\text{SNR}_{\text{out}} = +15.1\text{ dB}$ and theoretical BPSK Bit Error Rate $P_b \approx 4.4 \times 10^{-16}$ (virtually error-free).

5. **High-Performance Receiver Architectures:**
   - **Parallel Code Phase Acquisition via FFT Circular Convolution:** $R_{rc}[n] = \mathcal{F}^{-1}\{\mathcal{F}\{\mathbf{r}\} \odot (\mathcal{F}\{\mathbf{c}\})^*\}$. Evaluates all $N$ code phase hypotheses in $O(N \log N)$ rather than $O(N^2)$, speeding 2D code/Doppler search by over two orders of magnitude.
   - **SIMD Bitwise Sliding Correlator (C/Rust):** Mapping $\{+1, -1\} \mapsto \{0, 1\}$ transforms bipolar multiplication into bitwise XOR and hardware popcount:
     $$\sum_{i=0}^{K-1} a_i b_i = K - 2 \cdot \text{popcount}(u \oplus v)$$
     Using 64-bit registers or AVX-512 `_mm512_popcnt_epi64`, despreading executes at multi-gigachip-per-second line rate without floating-point ALU pressure.

6. **Multipath Resolution & The Rake Receiver:**
   - Wideband resolvability criterion: when differential multipath delay $|\tau_i - \tau_j| > T_{\text{chip}}$, arriving rays fall into separate correlation bins. Autocorrelation orthogonality renders delayed echoes harmless pseudo-noise rather than destructive Rayleigh fades.
   - Channel modeled as discrete tapped delay line: $h(t) = \sum_{l=1}^{L_p} \alpha_l e^{-j\theta_l} \delta(t - \tau_l)$.
   - Rake receiver structure: searcher engine dynamically identifies delay peaks; independent fingers track code phase delays $\tau_l$ via early-prompt-late DLLs.
   - **Maximal Ratio Combining (MRC):** Weighting finger outputs by $w_l = h_l^* = \alpha_l e^{-j\theta_l}$ satisfies Cauchy-Schwarz equality, achieving optimal output SNR:
     $$\text{SNR}_{\text{MRC}} = \sum_{l=1}^{L_p} \text{SNR}_l$$
     Multipath is transformed from a fading impairment into constructive diversity gain.
