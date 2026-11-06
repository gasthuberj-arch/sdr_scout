# Costas Loops and Carrier Phase Synchronization

Authoring Lesson 16 for the learner (Computational Engineering BSc, CS MSc, well-versed in C/Rust, systems architecture, and amateur radio).

## Core Concepts & Architectural Takeaways

1. **Non-Coherent vs. Coherent Phase Physics**:
   - In ADS-B Mode-S, pulse position modulation is decoded via non-coherent envelope power $|s[n]|^2 = I^2 + Q^2$. Because complex rotation phasors have unit magnitude ($|e^{j(\Delta \omega n + \theta_0)}| \equiv 1$), Carrier Frequency Offset (CFO) and Doppler shift leave the power envelope invariant.
   - In coherent phase modulations (BPSK, QPSK, PSK31), symbols are encoded directly in carrier phase angle $\arg(s[n])$. Uncorrected CFO causes the constellation points to spin continuously at $\Delta \omega = 2\pi \Delta f T_s$ rad/sample, driving the bit slicer Bit Error Rate (BER) to an intractable 50%.

2. **The Costas Loop Derivation & Modulation Wipe-Off**:
   - Suppressed-carrier PSK transmits zero-mean data ($\mathbb{E}[d[n]] = 0$), leaving zero discrete carrier tone for standard Phase-Locked Loops (PLLs).
   - In-phase and quadrature mixing yields $I[n] = A d[n] \cos\Delta\theta[n]$ and $Q[n] = A d[n] \sin\Delta\theta[n]$.
   - The classic multiplier Phase Error Detector (PED) computes $e[n] = I[n] \cdot Q[n] = \frac{1}{2} A^2 d^2[n] \sin(2\Delta\theta[n])$. Because $d^2[n] = (\pm 1)^2 \equiv 1$, data modulation vanishes completely, yielding $e[n] \approx A^2 \Delta\theta[n]$ for small phase errors.
   - The decision-directed detector $e[n] = \text{sign}(I[n]) \cdot Q[n]$ doubles linear tracking range to $[-\pi/2, +\pi/2]$, avoids noise squaring at low SNR, and maps to branchless sign bit extraction in SIMD/C/Rust.

3. **Second-Order PI Loop Filter Synthesis**:
   - A first-order loop lacks an integrator and suffers persistent steady-state phase lag $\Delta\theta_{ss} = \Delta\omega / K_p$ under Doppler drift.
   - The second-order Proportional-Integral (PI) filter adds a frequency accumulator $\hat{\omega}[n+1] = \hat{\omega}[n] + K_i e[n]$, guaranteeing zero steady-state phase error for constant CFO.
   - Closed-loop parameters are synthesized using critical damping $\zeta = 1/\sqrt{2} \approx 0.7071$ (maximally flat step decay) and normalized loop bandwidth $B_n T_s$:
     $$K_p \approx \frac{4\zeta(\omega_n T_s)}{1 + 2\zeta(\omega_n T_s) + (\omega_n T_s)^2}, \quad K_i \approx \frac{4(\omega_n T_s)^2}{1 + 2\zeta(\omega_n T_s) + (\omega_n T_s)^2}$$

4. **Phase Ambiguity & False Lock Remediation**:
   - The error detector nulls at both $\Delta\theta = 0^\circ$ and $\Delta\theta = 180^\circ$ ($\pi$). A lock at $180^\circ$ inverts all decoded bits ($I[n] = -A d[n]$); QPSK exhibits 4-fold $90^\circ$ ambiguity.
   - Handled via Differential Encoding (DBPSK / DQPSK) where transitions encode data, or via known preamble / unique word (UW) cross-correlation (Barker / Gold codes) to dynamically detect polarity flips and un-invert payloads.

5. **Systems & Native Implementation**:
   - A cache-friendly C99 blueprint executes complex de-rotation, branchless sign decision, PI frequency clamping, and phase wrapping in-place without dynamic memory allocation, demonstrating optimal integration into streaming SDR pipelines.
