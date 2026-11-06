# ADC Dynamic Range, Quantization Noise, and Automatic Gain Control (AGC)

Lesson 0021 authored to ground software-defined radio physical acquisition into rigorous mathematical derivations, real-world hardware limits, and systems-level AGC feedback control.

## Target Concepts & Pedagogical Framing

1. **Continuous-to-Discrete Quantization Physics:**
   - Formalized uniform quantization step size $\Delta = V_{\text{ref}} / 2^B$ across $B$-bit converters.
   - Proved quantization noise variance $\sigma_q^2 = \Delta^2 / 12$ by integrating the second moment of a uniform error distribution $p(e) = 1/\Delta$ over $[-\Delta/2, +\Delta/2]$ under Bennett's conditions.
   - Framed quantization error as irreducible additive white noise power across the Nyquist spectrum rather than reversible analog attenuation.

2. **Theoretical SQNR & The 6.02 dB Rule:**
   - Evaluated the peak full-scale sinusoidal power $P_{\text{signal}} = V_{\text{ref}}^2 / 8 = \Delta^2 2^{2B} / 8$.
   - Derived the classic Signal-to-Quantization-Noise Ratio: $\text{SQNR} = 1.5 \cdot 2^{2B}$, yielding $\text{SQNR}_{\text{dB}} \approx 6.02 B + 1.76\text{ dB}$.
   - Connected this theoretical ceiling to practical Effective Number of Bits (ENOB) degraded by aperture jitter, analog non-linearities, and thermal noise: $\text{ENOB} = (\text{SINAD}_{\text{dB}} - 1.76) / 6.02$.

3. **SDR Hardware Spectrum & The Amateur Radio Near-Far Problem:**
   - Categorized the hardware landscape: 8-bit entry SDRs (~48–50 dB dynamic range; RTL-SDR RTL2832U, HackRF One MAX5864), 12/14-bit intermediate receivers (~70–86 dB; Airspy R2, SDRplay RSPdx), and 14/16-bit direct-sampling HF rigs (~86–98 dB; Ettus USRP X310, Hermes-Lite 2, Icom IC-7300).
   - Grounded the Near-Far Dilemma in a 2-meter HAM scenario ($144\text{ MHz}$): a 100 W (+50 dBm) transmitter 400 meters away arriving at $-11.7\text{ dBm}$ alongside a distant weak DX station at $-120\text{ dBm}$ ($108.3\text{ dB}$ differential).
   - Demonstrated the mathematical bind for 8-bit receivers: either the strong blocker causes hard ADC clipping and destructive $\text{IMD3}$ spectral splattering, or attenuating the blocker drives the microvolt weak signal $58\text{ dB}$ below the quantizer step $\Delta$, vanishing beneath the noise floor.

4. **Processing Gain through Oversampling & Dithering:**
   - Demonstrated that white quantization noise power spreads across the full bandwidth $f_s$, with PSD $S_q(f) = \sigma_q^2 / f_s$.
   - Derived decimation processing gain $\Delta\text{SNR} = 10 \log_{10}(f_s / 2 B_{\text{signal}})$ and the corresponding ENOB increase $\Delta B = \frac{1}{2} \log_2(f_s / 2 B_{\text{signal}})$.
   - Emphasized the "Factor-of-4" rule (+6.02 dB / +1 bit per $4\times$ oversampling) and explained why analog dither ($\approx 0.5 - 1\text{ LSB}$ noise) is required to linearize static or sub-LSB signals.

5. **Digital Automatic Gain Control (AGC) Loop Engineering:**
   - Compared envelope detectors: peak detector (fast, protective against pulse clipping in ADS-B Mode-S) vs. RMS power detector (sliding window, smooth, optimal for SSB and continuous digital modes like FT8).
   - Explained asymmetric time constants: fast attack ($\tau_{\text{attack}} \approx 0.5 - 5\text{ ms}$) prevents saturation on sudden bursts, while slow decay ($\tau_{\text{decay}} \approx 200 - 1000\text{ ms}$) eliminates "noise pumping" during pauses.
   - Addressed loop stability and gain hunting: log-domain (dB) error feedback for loop linearity, deadband hysteresis ($\pm \epsilon$) to prevent limit cycles, and hang timers before initiating decay.
   - Provided a production-grade C/Rust implementation for continuous streaming buffers.
