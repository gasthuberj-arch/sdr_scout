# Geometric DSP Grasped: Consolidating Phase Invariance and Rayleigh Resolution

The user grasped the vector dot-product mental model of DSP and correctly answered the APRS and FT8 questions, but requested another round of iteration to consolidate the mechanics and bridge intuition into concrete software design.

## Target Insights for Next Iteration
1. **The Phase Blindspot of a Single Dot Product:** A single real cosine template $\cos(\omega t)$ drops out completely if the incoming wave is phase-shifted by $90^\circ$ ($\sin(\omega t)$). The solution is dual I/Q projections: $I = \langle \mathbf{x}, \cos \rangle$, $Q = \langle \mathbf{x}, \sin \rangle$, yielding phase-invariant energy $E = I^2 + Q^2$.
2. **The Rayleigh Tone Spacing Limit ($\Delta f \cdot \Delta t \ge 1$):** Why tone separation is physically bound to symbol duration, explaining both the 1000 Hz separation of APRS (1200 baud) and the 6.25 Hz spacing of FT8 (0.16s symbols).
3. **The DFT/FFT Unmasked:** An FFT is nothing more than an array of orthogonal complex dot products computed in $O(N \log N)$ rather than $O(N^2)$.
