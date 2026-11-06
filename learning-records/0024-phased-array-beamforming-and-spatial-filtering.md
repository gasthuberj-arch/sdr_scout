# Phased Array Beamforming: Delay-and-Sum, Steering Vectors, and Adaptive Spatial Nulling

The user requested authoring Lesson 20 covering phased array beamforming, spatial filtering, steering vectors, and adaptive spatial nulling for an advanced computational engineering / systems architecture background.

## Core Concepts & Architectural Dimensions

1. **The Physics of Spatial Filtering:**
   - Overcoming 1D temporal/spectral limits: When a high-power interferer or jammer occupies the exact same center frequency, modulation, and timeslot as a weak Signal of Interest (SOI), 1D filtering is powerless.
   - Antenna arrays sample the spatial wavefield across physical coordinates $\vec{r}_m$, creating a spatial FIR filter defined by spatial frequency / wavenumber projections.

2. **Uniform Linear Array (ULA) Geometry & Spatial Sampling:**
   - Incident angle $\theta$ relative to broadside induces an inter-element path delay $\Delta l = d \sin\theta$ and electrical phase shift $\psi(\theta) = \frac{2\pi d}{\lambda}\sin\theta$.
   - **Spatial Nyquist Limit ($d \le \lambda / 2$):** Visible space spans $\sin\theta \in [-1, 1]$ ($\Delta \nu_x = 2/\lambda$). If inter-element spacing exceeds $\lambda / 2$, spatial aliasing occurs, creating **grating lobes** ($0\text{ dB}$ secondary main lobes pointing in ambiguous directions). Spacing below $\lambda / 2$ avoids grating lobes but narrows aperture and escalates mutual coupling.

3. **Delay-and-Sum (Bartlett) Beamforming & Array Factor:**
   - Array manifold / steering vector: $\mathbf{a}(\theta) = [1, e^{-j\psi}, e^{-j 2\psi}, \dots, e^{-j (M-1)\psi}]^T$.
   - Coherent weighting $\mathbf{w} = \frac{1}{M}\mathbf{a}(\theta_0)$ cancels propagation delays, yielding unity gain for the look direction.
   - **Directivity SNR Gain:** Coherent signal voltages sum to $M \times V$ ($M^2 \times \text{Power}$), while uncorrelated white noise powers sum to $M \times \sigma^2$, delivering a linear **$M \times$ power SNR gain** ($10 \log_{10} M\text{ dB}$).
   - **Array Factor:** Follows the Dirichlet kernel $|AF(\theta)| = \frac{1}{M} \left| \frac{\sin(M \Delta\psi / 2)}{\sin(\Delta\psi / 2)} \right|$ with first sidelobes fixed at $-13.5\text{ dB}$.

4. **Adaptive Spatial Nulling (MVDR / Capon's Beamformer):**
   - Delay-and-Sum cannot suppress in-band jammers exceeding $+13.5\text{ dB}$ over the SOI.
   - MVDR minimizes total output power $\mathbf{w}^H \mathbf{R}_{xx} \mathbf{w}$ subject to $\mathbf{w}^H \mathbf{a}(\theta_0) = 1$.
   - Constrained optimization via Lagrange multipliers yields $\mathbf{w}_{\text{MVDR}} = \frac{\mathbf{R}_{xx}^{-1} \mathbf{a}(\theta_0)}{\mathbf{a}^H(\theta_0) \mathbf{R}_{xx}^{-1} \mathbf{a}(\theta_0)}$.
   - Inverting the spatial covariance matrix $\mathbf{R}_{xx}$ places deep spatial notches ($\le -50\text{ dB}$ to $-80\text{ dB}$) directly onto the arrival angles of interfering sources.
   - **Diagonal Loading:** Tikhonov regularization $\mathbf{R}_{xx} + \epsilon \mathbf{I}$ prevents numerical singularity and protects against signal self-cancellation caused by calibration mismatches or small snapshot sizes ($N < 2M$).

5. **Systems & Computational Architecture:**
   - RF front-end coherence requires common LO mixing, synchronized ADC sampling via PPS interrupts, and broadband noise-source inter-channel phase calibration.
   - Inner product $y[n] = \mathbf{w}^H \mathbf{x}[n]$ vectorizes across SIMD registers (AVX2/AVX-512/NEON) using fused multiply-add (FMA) instructions.
   - At 8 channels and 20 MSPS, arithmetic requirement ($1.28\text{ GFLOP/s}$) takes $<2\%$ of a modern CPU core; performance is governed by memory throughput ($1.28\text{ GB/s}$) and cache-aligned streaming buffers.
