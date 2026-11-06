# SDR RF Front-End Physics: Direct Conversion, I/Q Imbalance, and Phase Noise

Authored Lesson 32 covering physical front-end receiver architectures, analog hardware impairments in direct-conversion (Zero-IF/Low-IF) transceivers, quadrature I/Q imbalance mathematics, blind digital compensation algorithms, and local oscillator phase noise dynamics (reciprocal mixing).

## Core Architecture & RF Physics Insights

1. **Receiver Architectures (Superheterodyne vs. Zero-IF vs. Low-IF)**:
   - **Classic Superheterodyne:** High IF ($f_{\text{IF}} = |f_{\text{RF}} - f_{\text{LO}}|$). Excellent selectivity and dynamic range with no baseband DC offset, but requires sharp, bulky RF preselection and crystal/SAW bandpass filters to suppress images at $f_{\text{image}} = f_{\text{LO}} \mp f_{\text{IF}}$. Inflexible across wide tuning ranges in monolithic silicon.
   - **Direct-Conversion (Zero-IF / Homodyne):** $f_{\text{LO}} = f_c \implies f_{\text{IF}} = 0\text{ Hz}$. Eliminates bulky analog IF filters and image bands, enabling wideband single-chip CMOS transceivers (AD9361, MAX2837, R820T2). However, it exposes the receiver directly to baseband physical impairments.
   - **Low-IF:** Places $f_{\text{IF}}$ just outside the flicker noise and DC offset boundary (e.g., $f_{\text{IF}} = 250\text{ kHz}$ to $1\text{ MHz}$), relying on digital complex polyphase filtering for image rejection.

2. **Zero-IF Hardware Impairments**:
   - **DC Offset & LO Leakage (Self-Mixing):** LO drive power ($0$ to $+10\text{ dBm}$) leaks into the mixer RF input or radiates via the antenna, self-mixing ($\cos(\omega_{\text{LO}} t) \times \cos(\omega_{\text{LO}} t) = \frac{1}{2} + \dots$) into a massive static/slowly varying DC spike at $0\text{ Hz}$. Dynamic reflections from moving objects create time-varying DC drift.
   - **Flicker Noise ($1/f$ noise):** Carrier trapping at $\text{Si-SiO}_2$ gate interfaces creates $S_v(f) \propto 1/f^\gamma$. Deep-submicron CMOS corner frequencies $f_c$ reach several hundred kHz to $1\text{ MHz}$, severely degrading NF for narrowband signals (CW, SSB, FT8) centered at DC.
   - **Even-Order Distortion ($IP2$):** Nonlinear quadratic terms ($a_2 x^2(t)$) in the mixer/LNA downconvert the envelope of strong out-of-band AM interferers directly to baseband audio/data, requiring high differential balance to maximize $IIP2$.

3. **Quadrature I/Q Imbalance & Image Rejection Ratio (IRR)**:
   - Analog quadrature splitting introduces amplitude mismatch $\epsilon$ and phase mismatch $\Delta\phi$, yielding:
     $$z_{\text{imb}}(t) = K_1 z(t) + K_2 z^*(t)$$
     where $K_2 \neq 0$ mirrors negative frequencies across $0\text{ Hz}$ onto positive frequencies ($Z^*(-f)$ image ghost).
   - Image Rejection Ratio approximation:
     $$\text{IRR} \approx \frac{4}{\Delta\alpha^2 + \Delta\phi^2} \quad \implies \quad \text{IRR}_{\text{dB}} \approx 10 \log_{10}\left(\frac{4}{\Delta\alpha^2 + \Delta\phi^2}\right)$$
   - A mere $1^\circ$ phase error ($\Delta\phi \approx 0.01745\text{ rad}$) limits image rejection to $\approx 41.18\text{ dB}$, easily blinding weak DX signals when adjacent strong channels are present.

4. **Blind Digital I/Q Compensation**:
   - Exploits **properness/circularity** of communication signals: for ideal signals, $\mathbb{E}[I^2] = \mathbb{E}[Q^2]$ and $\mathbb{E}[IQ] = 0$, meaning pseudo-covariance $\mathcal{C}_{zz} = \mathbb{E}[z^2[n]] = 0$.
   - **Gram-Schmidt Orthogonalization:** Scales $Q[n]$ by $\sqrt{\hat{P}_I / \hat{P}_Q}$ and projects out the correlation $\rho \approx -\sin(\Delta\phi)$ via matrix transformation.
   - **Widrow-Hoff LMS Adaptive Filter:** Single-tap feed-forward structure $z_{\text{corr}}[n] = z_{\text{imb}}[n] - w[n] z_{\text{imb}}^*[n]$ with weight update $w[n+1] = w[n] + \mu z_{\text{corr}}^2[n]$ adaptively cancels image leakage and tracks thermal drift.

5. **Local Oscillator Phase Noise & Reciprocal Mixing**:
   - Phase noise spectral density $\mathcal{L}(\Delta f)$ in $\text{dBc/Hz}$ represents single-sideband noise relative to carrier power.
   - Integrated phase noise variance connects directly to RMS time jitter:
     $$\sigma_t = \frac{\sqrt{2 \int_{f_1}^{f_2} 10^{\frac{\mathcal{L}(f)}{10}} df}}{2\pi f_0}$$
   - **Reciprocal Mixing:** Time-domain mixing is frequency-domain convolution ($Y(f) = X(f) * V_{\text{LO}}(f)$). A strong out-of-channel blocker at $f_0 + \Delta f$ convolves with the LO's phase noise skirt $\mathcal{L}(-\Delta f)$, depositing broadband noise directly onto the weak on-channel signal:
     $$P_{\text{rm}} = P_{\text{blocker}} + \mathcal{L}(\Delta f) + 10 \log_{10}(B) \quad [\text{dBm}]$$
   - Because reciprocal mixing occurs in the analog mixer prior to digitization, no downstream digital FIR filter or DSP selectivity can remove the deposited noise floor.
