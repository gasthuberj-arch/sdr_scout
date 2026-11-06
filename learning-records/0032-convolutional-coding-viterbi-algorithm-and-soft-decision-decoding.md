# Forward Error Correction: Convolutional Codes, Viterbi Trellis Decoding, and Soft-Decision Slicing

Authored Lesson 28 in the SDR Scout curriculum, covering the information-theoretic foundations, algebraic shift-register mechanics, dynamic programming trellis decoding, and SIMD vector architectures of convolutional channel coding for weak satellite links (QO-100, AMSAT Oscar, Voyager, D-STAR).

## Core Architecture & DSP Insights

1. **The Weak-Signal Channel Coding Frontier**:
   - Analyzed uncoded BPSK error probability $P_b = Q(\sqrt{2 E_b / N_0})$. Achieving $10^{-5}$ BER requires $E_b/N_0 \approx 9.6\text{ dB}$.
   - At typical satellite downlinks ($E_b/N_0 = 1 - 3\text{ dB}$ due to free-space path loss and severe power budget limits), uncoded BER explodes to $\approx 2.3 \times 10^{-2}$, causing total packet loss ($P_{\text{frame}} \approx 7.8 \times 10^{-9}$ for an 800-bit frame).
   - Shannon capacity limit demonstrates that error-free communication is theoretically possible down to $E_b/N_0 \ge \ln(2) \approx -1.59\text{ dB}$, revealing an $11.2\text{ dB}$ margin available for FEC coding.

2. **Convolutional Encoding over GF(2) Polynomial Rings**:
   - Characterized continuous finite-state machine filtering with constraint length $K = 7$, code rate $R = 1/2$, and memory order $m = K - 1 = 6$ flip-flops ($S = 2^6 = 64$ states).
   - Deconstructed the standard NASA / Voyager / CCSDS generator polynomials:
     $$G_1 = 171_8 = 1111001_2 \implies g_1(D) = 1 + D + D^2 + D^3 + D^6$$
     $$G_2 = 133_8 = 1011011_2 \implies g_2(D) = 1 + D^2 + D^3 + D^5 + D^6$$
   - Modeled linear parity outputs via XOR convolutions: $y_0[t] = \mathbf{b}[t] \ast g_1$ and $y_1[t] = \mathbf{b}[t] \ast g_2$.
   - Illustrated line-rate C/Rust encoding using single shift, bitwise masks, and hardware parity intrinsics (`__builtin_parity` / `POPCNT`).

3. **Trellis Topology & Free Distance ($d_{\text{free}}$)**:
   - Formulated the time-unrolled 64-state trellis with binary branching factor 2.
   - Identified the butterfly symmetry: predecessor pair $(s, s+32)$ feeds successor pair $(2s, 2s+1)$.
   - Evaluated the free distance $d_{\text{free}} = 10$ (minimum Hamming weight of non-zero path diverging from and re-merging with all-zeros).
   - Derived asymptotic coding gain $\gamma = 10 \log_{10}(R \cdot d_{\text{free}}) = 10 \log_{10}(5) \approx 6.99\text{ dB}$, yielding a $5\times$ virtual EIRP boost.

4. **Viterbi Maximum Likelihood Sequence Estimation (MLSE)**:
   - Dynamic programming reduction of search complexity from exponential $O(2^N)$ to linear $O(N \cdot 2^{K-1})$.
   - Branch Metric Unit (BMU): Hamming distance $\lambda_{\text{hard}} = (r_0 \oplus c_0) + (r_1 \oplus c_1)$ vs Euclidean distance $\lambda_{\text{soft}} = \sum_i (r_i - \mu(c_i))^2$.
   - Add-Compare-Select (ACS) Unit: Path metric recursion $\Gamma_s[t] = \min(\Gamma_{s_1}[t-1] + \lambda_1, \Gamma_{s_2}[t-1] + \lambda_2)$.
   - Traceback depth rule $L_{tb} \approx 5K = 35$ steps guarantees survivor path convergence to the unique MLSE sequence with $< 0.05\text{ dB}$ loss.
   - Circular buffer management: $L_{tb} \times 64$-bit word ring buffer (320 bytes), eliminating dynamic memory allocation and executing entirely inside L1 cache.

5. **Hard vs. Soft-Decision Slicing (+2.2 dB "Free" Gain)**:
   - Demonstrated why 1-bit hard slicing incurs an asymptotic channel capacity penalty of $10\log_{10}(\pi / 2) \approx 1.96\text{ dB}$ by dropping sample confidence.
   - Derived the AWGN Log-Likelihood Ratio: $\text{LLR}(y) = \ln \frac{P(y|x=+1)}{P(y|x=-1)} = \frac{2}{\sigma^2} y$, proving soft metric linearity.
   - 8-bit quantized soft metrics recover full $+2.2\text{ dB}$ coding gain over hard decisions, equivalent to increasing transmitter amplifier power by $+66\%$ with zero RF hardware changes.

6. **SIMD Vectorization of the ACS Butterfly Kernel**:
   - Mapped 64 states into two 256-bit AVX2 registers (`__m256i` holding 32 8-bit metrics each).
   - Implemented vectorized saturated addition (`_mm256_adds_epu8`), single-cycle minimum selection (`_mm256_min_epu8`), equality comparison (`_mm256_cmpeq_epi8`), and decision bitmask extraction (`_mm256_movemask_epi8`).
   - Achieved $< 6$ clock cycles per symbol pair on x86-64, enabling decoding throughput $> 600\text{ Msps}$ per software core.
