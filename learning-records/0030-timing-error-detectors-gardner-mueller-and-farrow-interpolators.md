# Timing Error Detectors (TED) & Symbol Clock Synchronization: Gardner, Mueller & Müller, and Farrow Interpolators

Authored Lesson 26 bridging the physics of asynchronous sampling, continuous-time fractional delay reconstruction, and discrete-time closed-loop symbol tracking for a learner with Computational Engineering BSc, CS MSc, systems architecture (C/Rust), and amateur radio foundations.

## Core Architectural & DSP Insights

1. **The Asynchronous Sampling Problem & Fractional Delay**:
   - In modern software-defined radios, the receiver ADC sampling clock $f_s$ runs on an independent physical quartz crystal from the remote transmitter's symbol clock $R_{\text{sym}} = 1/T_{\text{sym}}$.
   - The nominal oversampling ratio $Q_{\text{nom}} = f_s / R_{\text{sym}} = T_{\text{sym}} / T_s$ is typically non-integer (e.g., $1.25\text{ MBaud}$ at $2.4\text{ MSPS} \implies Q = 1.92$).
   - Thermal drift and crystal tolerance ($\pm 10\text{ to } 50\text{ ppm}$) cause continuous clock slip $\Delta T / T$.
   - The continuous strobe instant $t_k = k T_{\text{sym}} + \tau_k$ decomposes into an integer basepoint sample index $m_k = \lfloor t_k / T_s \rfloor$ and a dimensionless fractional delay $\mu_k = (t_k / T_s) - m_k \in [0, 1)$.
   - Nearest-neighbor sample slicing induces residual timing errors up to $\pm 0.5 T_s$ ($\pm 0.25 T_{\text{sym}}$ at $Q=2$), collapsing the eye opening, destroying SNR, and causing periodic cycle slips.

2. **The Farrow Structure Interpolator & SIMD Decoupling**:
   - Ideal Shannon-Whittaker sinc interpolation is non-causal and infinite support; truncating sinc requires dynamic transcendental tap recomputation per sample, which ruins CPU instruction pipelines and cache locality.
   - Cecil W. Farrow's (1988) breakthrough represents polynomial interpolation over $2N$ samples as an order-$P$ polynomial in $\mu$:
     $$y[m + \mu] = \sum_{l=0}^P \mu^l v_l[m] = \sum_{l=0}^P \mu^l \left(\sum_k C_{l, k} x[m - k]\right)$$
   - **Key Systems Architecture Advantage:** The coefficient matrix $C_{l, k}$ of the branch FIR filters consists of *time-invariant mathematical constants*. They are completely independent of $\mu$. In AVX2/AVX-512/NEON/Zig `@Vector`, the branch convolutions run as static compile-time vectorized dot products at memory line rate.
   - The variable fractional delay $\mu$ is evaluated at the end using Horner's nested multiply-accumulate (MAC):
     $$y[m + \mu] = v_0[m] + \mu \Big( v_1[m] + \mu \big( v_2[m] + \mu v_3[m] \big) \Big)$$
   - Piecewise cubic Hermite interpolation ($P=3$, 4 taps) guarantees continuous first derivatives ($C^1$ continuity) across sample boundaries, avoiding high-frequency phase kinks.

3. **Gardner Timing Error Detector (NDA, 2 Samples/Symbol)**:
   - Operates on 2 samples/symbol: on-time symbol $y[k]$, previous on-time $y[k-1]$, and mid-point transition sample $y[k - 1/2]$.
   - Real-valued error: $e[k] = y[k - 1/2](y[k] - y[k-1])$.
   - Complex baseband error: $e[k] = I[k - 1/2](I[k] - I[k-1]) + Q[k - 1/2](Q[k] - Q[k-1])$.
   - **Carrier Phase Invariance Theorem (Algebraic Proof):**
     Rotating by carrier phase $\theta$ yields $I_r = I\cos\theta - Q\sin\theta$ and $Q_r = I\sin\theta + Q\cos\theta$. Expanding $e_r[k] = I_{r, m}\Delta I_r + Q_{r, m}\Delta Q_r$:
     The cross-terms $\pm (I_m \Delta Q + Q_m \Delta I)\cos\theta\sin\theta$ have opposite signs and cancel identically to 0.
     The squared terms group as $(I_m \Delta I + Q_m \Delta Q)(\cos^2\theta + \sin^2\theta) = e[k]$.
     Because $e_r[k] \equiv e[k]$ for all $\theta$, Gardner symbol synchronization can acquire lock *before* or *concurrently with* carrier frequency/phase synchronization (Costas loop).

4. **Mueller & Müller (M&M) Decision-Directed TED (1 Sample/Symbol)**:
   - Complex error: $e[k] = \text{Re}\{y[k]\hat{a}^*[k-1] - y[k-1]\hat{a}^*[k]\}$.
   - Cartesian expansion: $e[k] = \hat{a}_I[k-1] I[k] - \hat{a}_I[k] I[k-1] + \hat{a}_Q[k-1] Q[k] - \hat{a}_Q[k] Q[k-1]$.
   - **Systems Trade-Off:** Requires only 1 sample/symbol, cutting Farrow interpolator workloads by 50% relative to Gardner. However, it is decision-directed: if carrier phase rotates or constellation points are mis-sliced at low SNR / large CFO, timing gradients become corrupted. Ideal for steady-state tracking after initial Gardner acquisition.

5. **S-Curve Analysis & Phase Detector Gain $K_d$**:
   - The S-curve $S(\tau) = \mathbb{E}[e[k] \mid \tau]$ characterizes the statistical restoring torque versus static timing error $\tau$.
   - Phase detector gain at the equilibrium point: $K_d = \left. \frac{d S(\tau)}{d\tau} \right|_{\tau=0} = -2 \sigma_a^2 g(0) g'(T_{\text{sym}}/2)$, where $g(t)$ is the end-to-end pulse shape (e.g., raised cosine).
   - **Excess Bandwidth Sensitivity:** For Raised Cosine pulses with small roll-off ($\alpha \to 0$, brickwall Nyquist), the pulse derivative $g'(T/2) \to 0$, causing $K_d \to 0$. Gardner requires adequate excess bandwidth ($\alpha \ge 0.35$) for strong tracking.
   - **Pattern Jitter (Self-Noise):** Random data symbols cause instantaneous fluctuations $\text{Var}(e[k] \mid \tau=0) > 0$ even in zero-noise channels, requiring a sufficiently narrowband loop filter to average out self-noise.

6. **Loop Filter & Decremented Modulo-1 Interpolation Controller**:
   - The discrete NCO maintains accumulator state $\eta[n] \in [0, 1)$, decremented by $W[n] = W_0 + v[n]$ on every input sample, where $W_0 = T_s / (T_{\text{sym}}/2)$ and $v[n]$ is the PI filter output.
   - When $\eta_{\text{temp}} < 0$ (underflow), an interpolation strobe is triggered.
   - The fractional delay is computed via linear interpolation: $\mu = \eta[n-1] / W[n]$.
   - The accumulator wraps cyclically via $\eta[n] = \eta_{\text{temp}} + 1.0$.

7. **Systems & Native Implementation**:
   - Developed a complete zero-allocation C99 streaming engine featuring 4-tap cubic Hermite Farrow interpolation, modulo-1 underflow control, Gardner complex TED, and proportional-integral loop filtering with integrator anti-windup clamping.
