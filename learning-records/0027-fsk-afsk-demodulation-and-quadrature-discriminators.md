# FSK & AFSK Demodulation: Quadrature Discriminators, Delay-Line Conjugates, and Packet Radio (APRS)

Authored Lesson 23 focusing on Continuous Phase Frequency Shift Keying (CPFSK), Audio FSK (AFSK), and line-rate FM/FSK quadrature demodulation algorithms for amateur packet radio (APRS).

## Core Architecture & DSP Insights

1. **Bell 202 Standard & CPFSK Modulation Index**:
   - 1200 baud, 1200 Hz Mark, 2200 Hz Space ($f_c = 1700\text{ Hz}$, $\Delta f = \pm 500\text{ Hz}$, shift $= 1000\text{ Hz}$).
   - Modulation index $h = \frac{1000}{1200} \approx 0.833$. Continuous phase prevents high-frequency step discontinuities, guaranteeing $O(1/f^4)$ sidelobe roll-off vs. $O(1/f^2)$ for discontinuous phase.

2. **Frequency as Phase Time-Derivative**:
   - Continuous definition: $f(t) = \frac{1}{2\pi} \frac{d\phi(t)}{dt}$. Discrete-time approximation: $\Delta\phi[n] \approx 2\pi f[n] T_s$.
   - Naive polar unwrapping ($\phi[n] - \phi[n-1]$ with modulo $2\pi$ branches) stalls SIMD pipelines and mispredicts near the negative real axis.

3. **Delay-Line Conjugate Quadrature Discriminator**:
   - Identity: $d[n] = z[n] \cdot z^*[n-1] = |z[n]||z[n-1]| e^{j(\phi[n] - \phi[n-1])}$.
   - Cartesian expansion:
     $$\text{Re}(d[n]) = I_n I_{n-1} + Q_n Q_{n-1} \quad (\text{dot product})$$
     $$\text{Im}(d[n]) = Q_n I_{n-1} - I_n Q_{n-1} \quad (\text{cross product})$$
   - Rotates the sample vector backward by the previous phase, keeping the result centered on the positive real axis. Phase unwrapping is completely eliminated for $|\Delta\phi| < \pi$.
   - For small angles ($|\Delta\phi| \ll 1$), $\Delta\phi \approx \frac{\text{Im}(d[n])}{|z[n]|^2}$, giving instantaneous frequency with zero trigonometric function calls.

4. **SIMD Vectorization & Fast Rational Arctan**:
   - Rational Chebyshev/Padé approximation: $\arctan(u) \approx \frac{u}{1.0 + 0.28086 u^2}$ ($< 0.005\text{ rad}$ error across $[-1, 1]$).
   - Easily vectorizable with Zig `@Vector` / AVX2 / NEON without pipeline branches or transcendental `libm` calls.

5. **Parabolic Noise Shaping & Reconstruction**:
   - Differentiation operator $|\mathcal{H}(f)|^2 = (2\pi f)^2$ magnifies high frequencies (parabolic $f^2$ noise PSD).
   - Requires post-discriminator low-pass filtering matched to the symbol rate ($B \approx 1.2 R$).

6. **NRZI & HDLC Framing Mechanics**:
   - NRZI encoding: transition on 0, no transition on 1 ($b_{\text{data}}[n] = \neg(b_{\text{raw}}[n] \oplus b_{\text{raw}}[n-1])$), providing polarity invariance.
   - HDLC framing: `01111110` (0x7E) delimiters with transmitter 0-bit stuffing after five consecutive 1s, preventing false flag matches and guaranteeing transition density for clock recovery.
