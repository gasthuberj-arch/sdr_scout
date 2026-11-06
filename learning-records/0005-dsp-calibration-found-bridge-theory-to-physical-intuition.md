# DSP Calibration: Bridging Mathematical Formalism to Physical & Geometric Intuition

The user reported that Lesson 0004 was tough and noted that their signal processing background felt a little low for the level of formal integral derivations (Cauchy-Schwarz) and Galois Field polynomial quotient spaces.

## Pivot & Strategy
- Do not retreat to hand-wavy oversimplifications, but translate signal processing concepts into domains the user already excels at: **Linear Algebra** (vectors, dot products, projections, orthogonal bases) and **Software Systems** (sliding windows, array strides, multiply-accumulate loops).
- Connect the theory directly to real HAM radio modes the user cares about:
  - Explain matched filtering as a sliding vector dot-product $\mathbf{u} \cdot \mathbf{v} = \|\mathbf{u}\|\|\mathbf{v}\|\cos\theta$.
  - Demystify 2-meter APRS (1200 baud AFSK) as two parallel dot-product correlators for 1200 Hz and 2200 Hz.
  - Demystify FT8 as an 8-ary orthogonal tone projection that extracts signals buried 20 dB below the noise floor.
