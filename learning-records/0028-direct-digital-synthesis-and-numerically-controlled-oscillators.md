# Direct Digital Synthesis (DDS) & Numerically Controlled Oscillators (NCO): Phase Accumulators, LUT Quantization, and CORDIC

Authored Lesson 24 addressing digital carrier frequency generation, phase accumulator mechanics, truncation spur dynamics, and multiplierless CORDIC vector rotation.

## Core Architecture & DSP Insights

1. **The Fundamental SDR Frequency Synthesis Problem**:
   - Analog Local Oscillators (LC tanks, varactor diodes, analog PLLs) introduce settling latency (hundreds of microseconds for loop filter stabilization), phase transients, microphonics, thermal drift, and component aging.
   - Numerically Controlled Oscillators (NCOs) and Direct Digital Synthesizers (DDS) provide instantaneous (0-cycle settling latency) frequency agile switching, micro-Hertz frequency resolution, and phase-continuous ($\mathcal{C}^0$) transitions.
   - Multiple parallel NCO instances driven by the same master clock exhibit exact, deterministic phase coherence, an absolute requirement for multi-antenna phased array beamforming (Lesson 20) and MIMO channel sounding.

2. **Phase Accumulator Mechanics & Modular Geometry**:
   - The phase accumulator implements the difference equation:
     $$\theta[n] = (\theta[n-1] + FTW) \pmod{2^N}$$
   - Leveraging two's complement binary unsigned arithmetic, register overflow automatically and branchlessly implements the periodic boundary condition of the unit circle $[0, 2\pi) \equiv [0, 2^N)$.
   - Frequency equation:
     $$f_{\text{out}} = \frac{f_{\text{clk}} \cdot FTW}{2^N}, \quad \Delta f_{\text{min}} = \frac{f_{\text{clk}}}{2^N}$$
   - At $f_{\text{clk}} = 100\text{ MHz}$, a 32-bit accumulator yields $\Delta f_{\text{min}} \approx 0.0233\text{ Hz}$ ($23.3\text{ mHz}$); a 48-bit accumulator yields $\Delta f_{\text{min}} \approx 0.355\,\mu\text{Hz}$, eliminating phase drift over astronomical observation and satellite tracking durations.

3. **Phase Truncation vs. Amplitude Quantization Dynamics**:
   - A full $2^{32} \times 16\text{-bit}$ LUT requires $8.59\text{ GB}$, unfeasible for on-chip BRAM or CPU L1/L2 caches.
   - Truncating phase to $W$ bits introduces a periodic sawtooth phase error $\epsilon_\theta[n]$, which phase-modulates the carrier into discrete line-spectrum spurs:
     $$\text{SFDR}_{\text{phase truncation}} \approx 6.02 \cdot W\text{ dBc}$$
   - Quantizing table amplitude entries to $D$ bits produces an uncorrelated broadband white noise floor:
     $$\text{SQNR} \approx 6.02 D + 1.76\text{ dB}$$
   - Balanced design rule: $W \approx D + 2$ to $D + 3$ ensures phase truncation spurs are suppressed beneath the amplitude quantization noise floor.

4. **Spurious Reduction Mechanics**:
   - **LFSR Phase Dithering:** Adding pseudo-random noise of amplitude $(N-W)$ bits prior to truncation breaks error periodicity, smearing sharp spurs into the uniform noise floor and boosting SFDR by $12\text{--}18\text{ dB}$ at the cost of $1\text{--}2\text{ dB}$ higher broadband floor.
   - **Taylor Series Interpolation:** Decomposing phase $\theta = \theta_c + \theta_f$ and expanding $\sin(\theta_c + \theta_f) \approx \sin\theta_c + \theta_f \cos\theta_c$ achieves $>110\text{ dBc}$ SFDR from a compact 10-bit LUT ($1\text{ KB}$) with a single hardware MAC.

5. **CORDIC Multiplierless Vector Rotation**:
   - Constrains rotation angles to $\alpha_i = \arctan(2^{-i})$, transforming matrix multiplication into arithmetic right shifts ($x \gg i$) and additions:
     $$x_{i+1} = x_i - d_i (y_i \gg i), \quad y_{i+1} = y_i + d_i (x_i \gg i), \quad z_{i+1} = z_i - d_i \alpha_i$$
   - Vector magnitude scales by $A = \prod \sqrt{1 + 2^{-2i}} \approx 1.64676$; pre-multiplying initial input by $K = 1/A \approx 0.607253$ yields exact unit circle sine and cosine outputs.
   - Yields 1 bit of precision per iteration ($M=16$ stages $\implies 16$ bits of precision / $>96\text{ dB}$ dynamic range).
   - FPGA & SIMD Advantages: In FPGAs, pipelined CORDIC consumes zero dedicated DSP slices or BRAM tiles, running at 1 sample/clock cycle. In SIMD registers, it avoids non-contiguous vector gathers and cache misses, running entirely in vector ALUs.

## Learner Background Calibration & Zone of Proximal Development (ZPD)

- **Pedagogical Alignment:**
  - Leaned directly into the learner's Computational Engineering and CS Master's background: bit-manipulation, Galois LFSRs, fixed-point Q15 formatting, two's complement overflow properties, and CPU cache line / memory gather limits.
  - Grounded the theory in concrete amateur radio use cases: sub-Hertz FT8 tone generation, APRS CPFSK frequency agility, satellite Doppler shift compensation, and multi-channel coherent antenna array LO synthesis.

- **Zone of Proximal Development (Next Iteration Targets):**
  - **Complete Digital Down-Converter (DDC) Pipeline:** Combining the NCO / CORDIC mixer with Cascaded Integrator-Comb (CIC) decimation filters and half-band FIR resamplers to extract narrowband channels from wideband ADC streams at line rate.
  - **Numerically Controlled Fractional-N Resampling:** Using phase accumulators not just for carrier mixing, but as arbitrary sample rate converters (Farrow filter structures) to bridge non-integer clock domains without analog re-sampling.
