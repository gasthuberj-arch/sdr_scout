# Digital AGC Loops & Receiver Dynamic Range Budgeting

Authored Lesson 27 focusing on receiver dynamic range budgeting, cascaded analog RF non-linearities, closed-loop AGC architecture, logarithmic vs. linear feedback stability, dual-time constant dynamics, and Hang AGC.

## Core Architecture & DSP Insights

1. **The Dynamic Range Dilemma in Amateur Radio:**
   - The physical RF ether spans $> 140\text{ dB}$ of power differential ($10^{14}:1$), from thermal noise floors at $-130\text{ dBm}$ (Johnson-Nyquist limit $k_B T B = -174\text{ dBm/Hz} + 10\log_{10}(B) + \text{NF}$) up to $+10\text{ dBm}$ local kilowatt transmitters coupled across adjacent antennas.
   - Fixed-gain receivers fail under near-far conditions: excessive gain saturates ADCs, producing intermodulation distortion (IMD) and phase splatter; insufficient gain drops microvolt DX signals below the ADC least significant bit ($\Delta$), where they are destroyed by quantization noise.
   - Dual-tier gain control: Coarse analog RF/IF gain budgeting (preserving ADC headroom) paired with fine digital baseband AGC (stabilizing signal energy for carrier recovery and demodulation).

2. **RF Front-End Gain Budgeting (Friis vs. Linearity):**
   - **Friis' Formula for Noise Factor:**
     $$F_{\text{total}} = F_1 + \frac{F_2 - 1}{G_1} + \frac{F_3 - 1}{G_1 G_2} + \dots$$
     Demonstrated that first-stage LNA gain ($G_1$) suppresses subsequent stage noise (including the high $25 - 35\text{ dB}$ noise figure of the ADC buffer).
   - **Cascaded Third-Order Intercept Point ($\text{IIP3}$):**
     $$\frac{1}{\text{IIP3}_{\text{total}}} \approx \frac{1}{\text{IIP3}_1} + \frac{G_1}{\text{IIP3}_2} + \frac{G_1 G_2}{\text{IIP3}_3} + \dots$$
   - **The LNA Paradox:** Adding front-end preamplification ($G_1 \gg 1$) lowers system noise figure but multiplies downstream non-linear distortion into the passband, degrading system IIP3 by $G_1$ (e.g., adding a $+20\text{ dB}$ LNA degrades receiver IIP3 from $+5\text{ dBm}$ to $-15\text{ dBm}$). This collapses Spurious-Free Dynamic Range ($\text{SFDR} = \frac{2}{3}(\text{IIP3} - \text{MDS})$).

3. **Closed-Loop Feedback AGC Architecture:**
   - Four core blocks:
     - Digital Multiplier / Variable Gain Stage: $y[n] = g[n] \cdot x[n]$
     - Envelope / Power Detector: $P[n] = |y[n]|^2 = I_y^2[n] + Q_y^2[n]$
     - Setpoint Error Comparator: $e[n] = V_{\text{ref}} - P[n]$ (maintaining $-12\text{ dBFS}$ PAPR headroom)
     - Loop Filter & Integrator: Accumulating gain adjustments and enforcing bandwidth constraints.

4. **Instability of Linear Loops vs. Constant Pole in Log-Domain Loops:**
   - **Linear AGC Failure:**
     Recurrence $g[n+1] = g[n](1 - \mu |x[n]|) + \mu V_{\text{ref}}$ places the discrete-time pole at:
     $$z_{\text{pole}} = 1 - \mu |x[n]|$$
     Loop bandwidth is signal-dependent: for weak signals ($|x[n]| \to 0$), $z_{\text{pole}} \to 1$ (sluggish convergence); for strong signals ($|x[n]| > 2/\mu$), $z_{\text{pole}} < -1$, driving the loop into explosive non-linear limit-cycle oscillations.
   - **Logarithmic (dB-Domain) Stability:**
     Formulating error in decibels ($y_{\text{dB}} = x_{\text{dB}} + g_{\text{dB}}$) yields:
     $$g_{\text{dB}}[n+1] = (1 - \alpha) g_{\text{dB}}[n] + \alpha (V_{\text{ref, dB}} - x_{\text{dB}}[n])$$
     The closed-loop pole is strictly constant ($z_{\text{pole}} = 1 - \alpha$), completely decoupled from input signal power. Loop bandwidth and time constant $\tau \approx T_s / \alpha$ remain invariant across the entire dynamic range.

5. **Dual-Time Constant Dynamics & Hang AGC State Machine:**
   - **Attack vs. Decay Asymmetry:** Fast attack ($\tau_{\text{attack}} \approx 1 - 5\text{ ms}$) clamps sudden bursts to prevent ADC/audio clipping; slow decay ($\tau_{\text{decay}} \approx 500 - 2000\text{ ms}$) prevents amplifying background noise floor during momentary modulation dips.
   - **Noise Pumping:** Rapid decay causes the receiver to amplify thermal/atmospheric hiss to full volume between words in SSB voice or between Morse code elements in CW.
   - **Hang AGC Architecture:**
     - State machine transitions between Attack, Hang, and Decay.
     - Sudden peaks trigger fast attack and reset the Hang Counter ($N_{\text{hang}} = f_s \times t_{\text{hang}}$, $200 - 600\text{ ms}$).
     - During speech pauses, gain is completely frozen while the counter decrements. If new syllables arrive before timeout, the counter refreshes, keeping the background noise floor dead silent. Gain decays only after complete transmission cessation.

6. **Systems Architecture & Line-Rate DSP Vectorization:**
   - Fast IEEE 754 floating-point exponent manipulation to compute $\log_2(x)$ and decibels without expensive runtime `log10f()` calls.
   - Hysteresis deadband ($[-\epsilon, +\epsilon]$) to inhibit limit cycles on thermal fluctuations and prevent cache-line write thrashing.
   - Allocation-free, in-place Rust implementation for continuous complex baseband streams.
