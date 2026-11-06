# Deep TDOA: GCC-PHAT, Sub-Sample Interpolation, and Hyperbolic Solvers

The user requested to go deeper into the signal correlation and multilateration mechanics between distributed SDR nodes.

## Target Deepening Concepts
1. **GCC-PHAT (Generalized Cross-Correlation with Phase Transform):** Eliminating multipath smear and colored noise by normalizing spectral cross-power to unit magnitude: $R_{xy}^{\text{PHAT}} = \mathcal{F}^{-1}\left\{\frac{X \cdot Y^*}{|X \cdot Y^*|}\right\}$.
2. **Sub-Sample Resolution via Parabolic Fitting:** Resolving the 2.0 MSPS quantization limit ($T_s = 0.5\ \mu\text{s} \equiv 150\text{ meters}$) down to $\pm 5\text{ meters}$ using local 3-point quadratic extrema: $\delta = \frac{y_{-1} - y_{+1}}{2(y_{-1} - 2y_0 + y_{+1})}$.
3. **Hyperbolic Intersection Solvers:** From non-linear range difference equations ($r_{i,1} = \|\mathbf{x} - \mathbf{x}_i\| - \|\mathbf{x} - \mathbf{x}_1\|$) to analytical closed-form algorithms (Fang/Bancroft) and iterative Gauss-Newton / Levenberg-Marquardt optimization.
