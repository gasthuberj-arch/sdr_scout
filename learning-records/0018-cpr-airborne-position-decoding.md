# Compact Position Reporting (CPR): Non-Linear Spherical Coordinates & Disambiguation

The user is exploring the mathematical and protocol boundaries of Mode-S Extended Squitter (DF17), specifically how CPR encodes global airborne positions into a constrained 34-bit payload without incurring the unacceptable spatial quantization errors of naive floating-point or fixed-point representations.

## Core Architectural & Mathematical Insights

1. **The 34-Bit Payload Bottleneck:** Naive linear fixed-point over $[-90^\circ, +90^\circ]$ (lat) and $[-180^\circ, +180^\circ]$ (lon) using 17 bits yields $\sim 153\text{ m}$ and $\sim 305\text{ m}$ steps—catastrophic for runway separation and TCAS. CPR separates coarse zone indices from fine sub-zone fractions, achieving $\approx 5.09\text{ m}$ resolution ($\frac{6^\circ}{131,072}$) within the exact same 17-bit register.
2. **The Vernier Disambiguation Principle:** By partitioning latitude into two coprime modular grids ($60$ zones for Even, $59$ zones for Odd; $\gcd(60, 59) = 1$), CPR introduces an intentional spatial phase shift across the globe. Receiving an Even and Odd pair within $\le 10\text{ seconds}$ enables analytical recovery of the global latitude zone index $j = \lfloor 59 y_0 - 60 y_1 + 0.5 \rfloor$ without transmitting absolute coordinates.
3. **Meridian Convergence & $NL(\text{lat})$:** On a sphere, parallels contract by $\cos(\phi)$. CPR prevents polar singularities and bit wastage by modulating the number of longitude zones via $NL(\text{lat}) = \lfloor 2\pi / \arccos(1 - (1 - \cos(\pi/30)) / \cos^2(\phi)) \rfloor$, keeping physical zone width nearly uniform ($\sim 360\text{ NM}$) from equator to poles.
4. **Global vs. Local Decoding Modes:** Global decoding bootstraps unknown targets from alternating frame pairs ($\le 10\text{ s}$ window to prevent off-by-one phase slips from high-speed displacement). Local decoding leverages a known reference fix ($\le 180\text{ NM}$) to resolve full 5-meter coordinates from a single 17-bit frame, doubling effective stream update rates (1–2 Hz).
5. **The Systems Modulo Trap:** Truncated integer remainder (`%` in C/Rust, `rem/2` in Elixir) yields negative results for negative dividends, while CPR requires true floored Euclidean modulo ($a - b \lfloor a/b \rfloor$). Implementing CPR in systems code requires explicit floored modulo (`rem_floor/2` or `((a % b) + b) % b`) to avoid massive coordinate jumps across hemisphere boundaries.

## Zone of Proximal Development (ZPD)

- Transitioning from single-receiver Mode-S squitter decoding to distributed sensor networks: cross-validating CPR GPS positions against TDOA hyperbolic multilateration estimates.
- Evaluating spoofing vulnerabilities and message replay attacks in unauthenticated ADS-B broadcasts against physical RF sanity checks (RSSI, Doppler shift, and TDOA consistency).
- Implementing SIMD-vectorized local CPR decoding for high-density multi-target airspace tracking engines.
