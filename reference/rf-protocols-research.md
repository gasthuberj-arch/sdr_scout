# RF & High-Throughput DSP Protocol Architecture: Elixir + Zig SIMD Candidate Analysis

> **Target Systems**: RTL-SDR v3/v4 (USB 2.0, 8-bit I/Q, up to 3.2 MSPS RX) & Nuand bladeRF 2.0 micro (USB 3.0, 16-bit I/Q, up to 61.44 MSPS full-duplex TX/RX).  
> **Host Environment**: Linux x86_64 / aarch64 (AVX2, AVX-512, ARM NEON).  
> **Language Stack**: Elixir 1.18+ (OTP 27, BEAM, GenStage/Broadway) with Zig 0.13+/0.14+ NIFs (native vector extensions `@Vector`, zero-copy `ERL_NIF_BIN`).  
> **Operational Stance**: 100% legal, non-interception protocols; public safety, broadcast, and amateur telemetry; realistic indoor/window antenna feasibility.

---

## 1. Legal, Regulatory & At-Home Practicality Framework

Before evaluating physical layer DSP, any experimental SDR platform operated in a domestic environment must satisfy strict legal boundaries and realistic antenna physics.

```
+----------------------------------------------------------------------------------------------------+
| DOMESTIC SDR OPERATIONAL CRITERIA                                                                  |
+----------------------------------------------------------------------------------------------------+
| 1. LEGAL COMPLIANCE & PRIVACY                                                                      |
|    - Permitted: Unencrypted public broadcasts (DAB, FM-RDS), open aeronautical/maritime safety      |
|      telemetry (ADS-B, AIS, VDL Mode 2), public weather satellites (NOAA/Meteor), amateur radio.   |
|    - Strictly Prohibited / Avoided: Personal messaging / pagers (POCSAG/FLEX - UK Wireless        |
|      Telegraphy Act 2006 s.48 & German TKG § 89 make intercepting non-broadcast messages a crime),|
|      cellular basebands (GSM/LTE/5G), and encrypted government/emergency services (TETRA/P25).     |
|                                                                                                    |
| 2. AT-HOME ANTENNA PRACTICALITY                                                                    |
|    - Tier 1 (Indoor / Window Dipole): VHF Air (136 MHz), VHF Marine (162 MHz), DAB+ (174-240 MHz),  |
|      Amateur 2m/70cm (144/430 MHz), ISM (433/868 MHz). High SNR without rooftop access.            |
|    - Tier 2 (Stationary Window V-Dipole): Polar Low-Earth Orbit satellites at 137 MHz (Meteor-M2). |
|    - Tier 3 (Directional Dish / Active Tracking): L-Band Satellite Telemetry (HRPT 1.7 GHz).       |
|                                                                                                    |
| 3. BLADERF TRANSMISSION SAFETY (LEGAL AT-HOME TX)                                                  |
|    - Enclosed Cabled Loopback: TX directly connected to RX via 50-ohm SMA cable with 30-40 dB     |
|      inline RF attenuator (0 nW radiated, 100% legal, ideal for BER and protocol testing).         |
|    - Dummy Load: 50-ohm termination plug for transmitter calibration.                              |
|    - Unlicensed ISM Rules: Sub-10 mW / 25 mW ERP with <1% duty cycle in 433 / 868 MHz allocations.|
|    - Amateur Radio: Unencrypted transmission permitted strictly within HAM bands with callsign.    |
+----------------------------------------------------------------------------------------------------+
```

---

## 2. Architectural Foundations: The Elixir + Zig Paradigm for SDR

Building high-throughput SDR processing engines requires reconciling two opposing execution models:
1. **Continuous Baseband DSP (Microsecond Scale)**: High-rate sample streams (2 to 60 MSPS) demanding gigabytes-per-second memory bandwidth, SIMD vectorization, deterministic cache locality, and zero branch mispredictions.
2. **Discrete Protocol Demultiplexing & State Machines (Millisecond to Second Scale)**: Heterogeneous packet deframing, burst synchronization, dynamic routing, session state tracking, distributed fan-out, and failure isolation.

```
       +--------------------------------------------------------------+
       |                  RF Front-End (Antenna & LNA)                |
       +--------------------------------------------------------------+
                                      |
                     [Raw RF Electromagnetic Energy]
                                      |
       +--------------------------------------------------------------+
       | Hardware Digitizer: RTL-SDR (8-bit) / bladeRF (16-bit)       |
       +--------------------------------------------------------------+
                                      |
                [Bulk Isochronous USB Transfer (I/Q Streams)]
                                      |
======================================|================================
OS Kernel & Native Boundary           v
======================================================================
  Zig Native Worker Thread (C/Zig Driver Binding)
    - Ring buffer ingestion (zero-copy OS DMA)
    - Downconversion / Polyphase Resampling
    - SIMD Channelizer / Matched Filter (@Vector(8, f32))
    - Slicing / Hard & Soft Decision Detection
                                      |
                [Candidate Burst Buffers: ERL_NIF_BIN]
                                      |
======================================|================================
BEAM VM / OTP Supervision             v
======================================================================
  Elixir GenStage Producer (:dirty_cpu or enif_send event loop)
    - Refc binary pointer preservation (0-copy across process heap)
                                      |
  Elixir GenStage ProducerConsumer (Protocol Engine)
    - Bitstring binary pattern matching: <<header::16, payload::bits>>
    - CRC-16 / CRC-32 / Reed-Solomon validation
    - Frame synchronization & slot state machine
                                      |
  Elixir Broadcast / Persistence Consumers (Phoenix PubSub / SQLite)
    - State tracking (MMSI, ICAO, Callgroup, AVHRR Line Raster)
    - Web dashboard / WebSocket JSON broadcast
```

### 2.1 The Division of Responsibility

| Pipeline Stage | Implementation Domain | Mechanism / Primitive | Rationale |
| :--- | :--- | :--- | :--- |
| **I/Q Ingestion** | Native Zig OS Thread | `librtlsdr` / `libbladeRF` async ring-buffer | Precludes BEAM VM scheduler preemption jitter during kernel USB DMA packet transfers. |
| **Channelization & Decimation** | Zig SIMD (`@Vector`) | Polyphase FIR filter banks, Cascaded Integrator-Comb (CIC) | Memory-bound floating/fixed-point SIMD arithmetic with $O(N)$ linear complexity. |
| **Demodulation & Slicing** | Zig SIMD (`@Vector`) | Complex correlation, Gardner TED, Delay-conjugate FM discriminator, 2048-point FFT | Tight inner loops exploiting vector registers (FMA, AVX2, NEON) directly on L1/L2 caches. |
| **Burst Boundary Transfer** | NIF Boundary | `ERL_NIF_BIN` (>64 bytes refc binary allocation) | Yields zero-copy pointers passed into the BEAM VM without heap copying. |
| **Deframing & Deinterleaving** | Elixir Pattern Matching | `<<sync::32, data::binary-size(len), crc::16>>` | High developer ergonomics, compile-time bytecode optimization, zero pointer arithmetic errors. |
| **MAC / State Tracking** | Elixir OTP (`GenServer` / `GenStage`) | Process-per-station, process-per-timeslot supervision trees | Fault isolation: corrupt bursts crash only an isolated worker, never the SDR pipeline. |

---

## 3. Protocol Progression & Selection Overview

The five selected candidate protocols represent a mathematically rich progression from simple constant-envelope FSK up to wideband multi-carrier OFDM and deep-space concatenated coding, while remaining **100% legal and viable for home reception**:

```
+---------------------------------------------------------------------------------------------------+
| CANDIDATE PROTOCOL PROGRESSION & AT-HOME FEASIBILITY                                              |
+---------------------------------------------------------------------------------------------------+
|  [1] AIS (VHF Maritime)                                                                           |
|      Modulation: GMSK (BT=0.4), 9.6 kbps | Spectrum: 161.975 & 162.025 MHz (Dual 25 kHz)          |
|      At-Home Feasibility: High. Standard indoor VHF whip picks up coastal, river, or lake traffic.|
|      Core DSP: Heterodyne Dual Decimator, Delay-Conjugate FM Discriminator, HDLC Bit Unstuffing.  |
|  -----------------------------------------------------------------------------------------------  |
|  [2] VDL Mode 2 (Aeronautical VHF)                                                                |
|      Modulation: D8PSK, 10.5 kbaud (31.5 kbps) | Spectrum: 136.975 MHz (25 kHz Channel)           |
|      At-Home Feasibility: Exceptional. High-altitude aircraft line-of-sight (150-250 miles).      |
|      Core DSP: Polyphase SRRC (a=0.6), Gardner Clock Recovery, Shortened Reed-Solomon RS(255,249).|
|  -----------------------------------------------------------------------------------------------  |
|  [3] DMR Tier II Amateur (Digital Mobile Radio)                                                   |
|      Modulation: 4-FSK, 4.8 kbaud (9.6 kbps) | Spectrum: 144-148 MHz (2m) & 430-440 MHz (70cm)     |
|      At-Home Feasibility: High. Continuous repeater activity on open amateur BrandMeister network.|
|      Core DSP: RRC (a=0.2), 4-Level Eye Slicer, Golay(24,12), Trellis 3/4, AMBE/Signalling Deframing|
|  -----------------------------------------------------------------------------------------------  |
|  [4] DAB / DAB+ (Digital Audio Broadcasting)                                                      |
|      Modulation: Wideband DQPSK OFDM Mode I | Spectrum: VHF Band III 174-240 MHz (1.536 MHz BW)   |
|      At-Home Feasibility: Maximum. High-power local broadcast towers (>30 dB SNR with indoor wire)|
|      Core DSP: 2048-point FFT, Frequency Deinterleaver, Viterbi K=7 Soft Decoding, RS(120,110).    |
|  -----------------------------------------------------------------------------------------------  |
|  [5] Meteor-M2 LRPT & NOAA POES (Satellite Direct Readout)                                        |
|      Modulation: QPSK (72 kbps LRPT) / BPSK (665.4 kbps HRPT) | Spectrum: 137 MHz VHF / 1.7 GHz L-Band|
|      At-Home Feasibility: High for 137 MHz VHF with simple stationary V-dipole on window sill.    |
|      Core DSP: Costas Carrier Phase Recovery, Root Raised Cosine, CCSDS Sync 0x1ACFFC1D, AVHRR.  |
+---------------------------------------------------------------------------------------------------+
```

---

## 4. In-Depth Protocol Engineering Analyses

---

### Protocol 1: AIS (Automatic Identification System)

#### 1. Specification & Standards
- **Standard Identifier**: [ITU-R M.1371-5](https://www.itu.int/rec/R-REC-M.1371/en) ("Technical characteristics for an automatic identification system using time division multiple access in the VHF maritime mobile band").
- **Complementary Standards**: IEC 61993-2 (Class A Shipborne Equipment), IEC 62287-1 (Class B Shipborne Equipment), [IALA Recommendation A-123](https://www.iala-aism.org/).
- **RF Spectrum**: VHF Maritime Mobile Band.
  - **AIS 1**: $161.975\text{ MHz}$ (Maritime Ch 87B).
  - **AIS 2**: $162.025\text{ MHz}$ (Maritime Ch 88B).
  - **Channel Bandwidth**: $25\text{ kHz}$ each (split by $50\text{ kHz}$ carrier spacing).
- **Multiple Access Scheme**: SOTDMA (Self-Organizing Time Division Multiple Access). 2,250 time slots per minute per channel ($26.67\text{ ms}$ slot duration).
- **Legal & Domestic Status**: 100% public, unencrypted maritime navigational safety broadcast. Anyone may receive and decode without a license.

#### 2. Modulation & Physical Layer
- **Modulation**: GMSK (Gaussian Minimum Shift Keying) with a nominal bandwidth-time product $BT = 0.4$ (standard allows $BT = 0.3$ to $0.5$).
- **Modulation Index**: $h = 0.5$ (MSK condition: frequency separation equals half the bit rate).
- **Bit Rate**: $9,600\text{ bps} \pm 50\text{ ppm}$.
- **Frequency Deviation**: $\Delta f = \pm 2,400\text{ Hz}$.
- **Data Encoding**: Non-Return-to-Zero Inverted (NRZI) where a binary `0` produces a phase transition and binary `1` produces no transition.
- **Framing**: High-Level Data Link Control (HDLC).
  - Preamble: Alternating 24-bit pattern `010101010101010101010101`.
  - Start Flag: 8-bit HDLC Flag `01111110` (`0x7E`).
  - Data Payload: Variable (typically 168 to 440 bits).
  - Bit Stuffing: Transmitter inserts an extra `0` after any sequence of five consecutive `1`s.
  - Frame Check Sequence (FCS): 16-bit CRC-CCITT (polynomial $x^{16} + x^{12} + x^5 + 1$).
  - End Flag: 8-bit HDLC Flag `01111110` (`0x7E`).

#### 3. Hot DSP Paths for Zig SIMD
1. **Dual-Channel Heterodyne Decimator**:
   - Because AIS 1 ($161.975\text{ MHz}$) and AIS 2 ($162.025\text{ MHz}$) are separated by only $50\text{ kHz}$, an SDR tuned to the center frequency $f_c = 162.000\text{ MHz}$ captures both channels simultaneously within a modest bandwidth (e.g. $192\text{ kHz}$ or $1.024\text{ MSPS}$).
   - Downconversion mixing requires multiplying complex baseband samples $x[n]$ with complex digital oscillators:
     $$x_{\text{AIS1}}[n] = x[n] \cdot e^{-j 2\pi (-25\text{ kHz}) n / f_s}, \quad x_{\text{AIS2}}[n] = x[n] \cdot e^{-j 2\pi (+25\text{ kHz}) n / f_s}$$
   - **Zig SIMD Implementation**: Vectorized complex multiplication using SIMD fused multiply-accumulate (`@mulAdd`) across batches of 8 samples.
2. **Quadrature FM Discriminator**:
   - Instead of expensive transcendentals (`atan2`), compute the instantaneous phase differential via conjugate multiplication:
     $$y[n] = x[n] \cdot x^*[n-1] = (I[n]I[n-1] + Q[n]Q[n-1]) + j(Q[n]I[n-1] - I[n]Q[n-1])$$
     $$\Delta \theta[n] \approx \frac{\Im(y[n])}{\Re(y[n])} \quad (\text{for small } \Delta \theta) \quad \text{or fast polynomial } \operatorname{atan2}(Q, I)$$
   - In Zig, rational approximation of $\operatorname{atan2}(y, x)$ using Chebyshev or Padé polynomials completely eliminates scalar branch stalls across 8-lane SIMD registers (`@Vector(8, f32)`).
3. **Matched Gaussian Filter & Symbol Clock Slicing**:
   - GMSK pulse shaping spans 3-4 symbol periods. A symmetric FIR filter with Gaussian impulse response is applied to the discriminator output:
     $$h[k] = \frac{1}{\sqrt{2\pi}\sigma} \exp\left(-\frac{k^2}{2\sigma^2}\right), \quad \sigma = \frac{\sqrt{\ln 2}}{2\pi BT}$$
   - A vectorized Zero-Crossing Detector or Early-Late Gate estimates fractional symbol timing jitter.

```zig
// Zig SIMD snippet: 8-wide Complex Multiply-Accumulate for FIR Decimation
pub fn firConvolve8(
    in_i: @Vector(8, f32),
    in_q: @Vector(8, f32),
    taps: @Vector(8, f32),
    acc_i: *f32,
    acc_q: *f32,
) void {
    const prod_i = in_i * taps;
    const prod_q = in_q * taps;
    acc_i.* += @reduce(.Add, prod_i);
    acc_q.* += @reduce(.Add, prod_q);
}
```

#### 4. Elixir / OTP Architecture & Binary Pattern Matching
- **Process Topology**:
  - `Ais.Receiver` (GenStage Producer): Ingests raw frames from Zig NIF.
  - `Ais.Demux` (GenStage ProducerConsumer): Routes channel A and channel B frames.
  - `Ais.SessionRouter` (DynamicSupervisor): Spawns or directs traffic to a per-vessel `Ais.VesselState` `GenServer` indexed by MMSI.
- **Binary Pattern Matching**: Once HDLC unstuffing and NRZI inversion take place in Zig (or Elixir), AIS payloads decode cleanly via bitstring matching:

```elixir
defmodule Ais.Decoder do
  @doc "Decodes Type 1, 2, and 3 Position Reports (168 bits total)"
  def decode_message(<<type::6, repeat::2, mmsi::32, status::4, rot::signed-8,
                       sog::10, pos_acc::1, lon::signed-28, lat::signed-27,
                       cog::12, true_hdg::9, ts::6, flags::4, _rest::bitstring>>)
      when type in [1, 2, 3] do
    %{
      type: type,
      repeat: repeat,
      mmsi: mmsi,
      nav_status: decode_status(status),
      rate_of_turn_deg_min: rot,
      speed_over_ground_knots: sog * 0.1,
      position_accurate: pos_acc == 1,
      longitude: lon / 600_000.0,
      latitude: lat / 600_000.0,
      course_over_ground: cog * 0.1,
      heading: true_hdg,
      timestamp: ts
    }
  end
end
```

#### 5. Hardware Mapping & At-Home Practicality
- **At-Home Reception**: A standard telescoping antenna extended to $\approx 46\text{ cm}$ (1/4 wave at $162\text{ MHz}$) positioned near any window receives maritime traffic if within 15-30 miles of coastlines, navigable rivers, or shipping canals.
- **RTL-SDR v3/v4**: Ideal. Setting sample rate to $288\text{ kHz}$ or $1.024\text{ MSPS}$ centered at $162.000\text{ MHz}$ encompasses both AIS 1 and AIS 2 with $<1\%$ CPU load.
- **bladeRF**: Enclosed testing: Connect TX to RX via an SMA cable with a 30 dB attenuator. Transmit simulated SOTDMA bursts on $161.975\text{ MHz}$ and decode them on the RX path with zero RF radiated into the environment.

---

### Protocol 2: VDL Mode 2 (VHF Digital Link Mode 2)

#### 1. Specification & Standards
- **Standard Identifier**: [ICAO Annex 10, Volume III, Part I, Chapter 6](https://www.icao.int/) and [ICAO Doc 9776](https://store.icao.int/en/manual-on-vhf-digital-link-vdl-mode-2-doc-9776) ("Manual on VHF Digital Link (VDL) Mode 2").
- **Avionics Standards**: RTCA DO-224 (Signal-in-Space Minimum Aviation System Performance Standards), RTCA DO-281 / EUROCAE ED-92.
- **RF Spectrum**: Aeronautical VHF Communications Band ($117.975 - 137.000\text{ MHz}$).
  - **Common Signalling Channel (CSC)**: $136.975\text{ MHz}$ (worldwide).
  - Additional regional operational carriers: $136.725\text{ MHz}$, $136.775\text{ MHz}$, $136.875\text{ MHz}$.
  - **Channel Bandwidth**: $25\text{ kHz}$.
- **Multiple Access Scheme**: CSMA / $p$-persistent slotted ALOHA.
- **Legal & Domestic Status**: 100% legal open public safety air traffic data. Unencrypted flight plans, weather clearances, and aircraft position reports.

#### 2. Modulation & Physical Layer
- **Modulation**: Differentially Encoded 8-Phase Shift Keying (D8PSK).
- **Symbol Rate**: $10,500\text{ symbols/sec} \pm 50\text{ ppm}$.
- **Data Throughput**: 3 bits per symbol $\implies 31,500\text{ bps}$.
- **Pulse Shaping**: Square Root Raised Cosine (SRRC) with roll-off factor $\alpha = 0.6$.
- **Symbol Differential Phase Shift Table**:
  $$\begin{array}{|c|c|c|c|c|c|c|c|c|}
  \hline
  \text{Bits } (b_k, b_{k+1}, b_{k+2}) & 000 & 001 & 011 & 010 & 110 & 111 & 101 & 100 \\
  \hline
  \Delta \phi_k & 0^\circ & 45^\circ & 90^\circ & 135^\circ & 180^\circ & 225^\circ & 270^\circ & 315^\circ \\
  \hline
  \end{array}$$
- **Transmission Frame Structure**:
  1. **Preamble**: 5 unmodulated symbol phases for initial carrier and clock acquisition.
  2. **Sync Sequence**: 16-symbol unique word (`0x00B0` / `0xE590` depending on differential initialization).
  3. **Transmission Header**: 27 bits (bit-rate indicator, length).
  4. **FEC Coding**: Shortened Reed-Solomon Code $\text{RS}(255, 249)$ over $\text{GF}(2^8)$ correcting up to $t = 3$ symbol errors. Primitive polynomial $p(x) = x^8 + x^4 + x^3 + x^2 + 1$.
  5. **Data Link Layer**: Frame Check Sequence using 16-bit CRC followed by bit interleaving across blocks.

#### 3. Hot DSP Paths for Zig SIMD
1. **Polyphase RRC Matched Filter**:
   - Applying an SRRC matched filter to eliminate ISI:
     $$H_{\text{RRC}}(f) = \begin{cases} 
     T, & |f| \le \frac{1-\alpha}{2T} \\
     \frac{T}{2} \left[1 + \cos\left(\frac{\pi T}{\alpha}\left(|f| - \frac{1-\alpha}{2T}\right)\right)\right], & \frac{1-\alpha}{2T} < |f| \le \frac{1+\alpha}{2T} \\
     0, & |f| > \frac{1+\alpha}{2T} 
     \end{cases}$$
   - **Zig SIMD Polyphase Implementation**: Resampling from $1.05\text{ MSPS}$ (typical SDR rate) down to 2 samples per symbol ($21\text{ kSPS}$) using a 50-phase polyphase filter bank. Each polyphase arm is vectorized using 4-wide or 8-wide float vectors.
2. **Gardner / Mueller-Müller Timing Error Detector (TED)**:
   - For complex samples $y[n]$, compute timing error:
     $$e_k = \Re\left\{(y[k] - y[k-1]) \cdot y^*[k - 1/2]\right\}$$
   - Steers a fractional Farrow interpolation filter with quadratic or cubic coefficients vectorized via Horner’s scheme in Zig.
3. **Galois Field $\text{GF}(2^8)$ SIMD Reed-Solomon Syndrome Calculator**:
   - Decoding $\text{RS}(255, 249)$ requires calculating 6 syndromes ($S_1, S_2, \dots, S_6$):
     $$S_i = \sum_{j=0}^{N-1} r_j \alpha^{i \cdot j} \quad \text{in } \text{GF}(2^8)$$
   - In Zig, Galois field multiplications can be vectorized across 16 lanes simultaneously using either vector shuffle table lookups (`vpshufb` on x86, `vtbl1` on ARM NEON) or carry-less multiplication (`pclmulqdq` / `pmull`).

```zig
// Zig SIMD snippet: 8-Phase Constellation Slicer
pub inline fn sliceD8PSK(phase_delta: f32) u3 {
    const normalized = @mod(phase_delta + std.math.pi / 8.0, 2.0 * std.math.pi);
    const sector: u3 = @intFromFloat(@floor(normalized / (std.math.pi / 4.0)));
    const gray_table = [_]u3{ 0b000, 0b001, 0b011, 0b010, 0b110, 0b111, 0b101, 0b100 };
    return gray_table[sector];
}
```

#### 4. Elixir / OTP Architecture & Binary Pattern Matching
- **Layer 2 / 3 Parsing**: VDL Mode 2 carries AVLC (Aviation VHF Link Control), an adaptation of HDLC, which encapsulates ISO 8473 (CLNP), ISO 9542 (ESIS), or ARINC 622 / ACARS datagrams:

```elixir
defmodule Vdl2.AvlcDecoder do
  @doc "Decodes AVLC frame header with compressed Aircraft and Ground Station addresses"
  def decode_avlc(<<_flag::8, c_r::1, poll_final::1, frame_type::6, 
                    dest_addr::24, src_addr::24, payload_and_fcs::binary>>) do
    fcs_size = 2
    data_size = byte_size(payload_and_fcs) - fcs_size
    <<data::binary-size(data_size), fcs::16>> = payload_and_fcs
    
    %{
      command_response: c_r,
      poll_final: poll_final,
      frame_type: decode_frame_type(frame_type),
      destination: <<dest_addr::24>>,
      source: <<src_addr::24>>,
      payload: decode_network_layer(data),
      fcs_valid: verify_crc16(data, fcs)
    }
  end

  defp decode_network_layer(<<0x81, 0x01, _proto_detail::binary>> = clnp), do: {:clnp, clnp}
  defp decode_network_layer(<<0x01, 0x01, acars_msg::binary>>), do: {:acars, acars_msg}
  defp decode_network_layer(unknown), do: {:raw, unknown}
end
```

#### 5. Hardware Mapping & At-Home Practicality
- **At-Home Reception**: **Exceptional**. Aircraft cruising at 35,000 feet transmit with 15-20W into line-of-sight propagation spanning up to 250 nautical miles. A simple $55\text{ cm}$ indoor telescopic antenna at any window will pull dozens of bursts per minute on $136.975\text{ MHz}$.
- **RTL-SDR v3/v4**: Perfect match. The R820T2/R828D tuner has maximum sensitivity between $120 - 150\text{ MHz}$.
- **bladeRF**: Captures the entire $136.000 - 137.000\text{ MHz}$ sub-band in a single wideband I/Q stream ($2\text{ MSPS}$), allowing a Zig polyphase channelizer to demodulate multiple VDL2 channels simultaneously.

---

### Protocol 3: DMR (Digital Mobile Radio - Amateur Tier II)

#### 1. Specification & Standards
- **Standard Identifier**: [ETSI TS 102 361](https://www.etsi.org/deliver/etsi_ts/102300_102399/10236101/02.05.01_60/ts_10236101v020501p.pdf) (Parts 1 to 4).
- **RF Spectrum**: Amateur 2m ($144 - 148\text{ MHz}$) and 70cm ($430 - 440\text{ MHz}$) repeater allocations.
- **Channel Bandwidth**: $12.5\text{ kHz}$ equivalent spectrum efficiency via 2-slot TDMA.
- **Multiple Access Scheme**: 2-slot TDMA in a $30\text{ ms}$ slot structure ($60\text{ ms}$ full TDMA frame cycle).
- **Legal & Domestic Status**: 100% legal. Amateur DMR repeaters (connected to global networks like BrandMeister) are public, explicitly unencrypted under international amateur radio licensing laws.

#### 2. Modulation & Physical Layer
- **Modulation**: 4-level Continuous Phase FSK (4-FSK).
- **Symbol Rate**: $4,800\text{ symbols/sec} \pm 2\text{ ppm}$ ($9,600\text{ bps}$).
- **Pulse Shaping**: Root Raised Cosine (RRC) with roll-off $\alpha = 0.2$.
- **4-FSK Symbol Frequency Mapping**:
  $$\begin{array}{|c|c|c|}
  \hline
  \text{Dibit } (b_1, b_0) & \text{Symbol Level} & \text{Nominal Frequency Deviation } \Delta f \\
  \hline
  01 & +3 & +1,944\text{ Hz} \\
  00 & +1 & +648\text{ Hz} \\
  10 & -1 & -648\text{ Hz} \\
  11 & -3 & -1,944\text{ Hz} \\
  \hline
  \end{array}$$
- **Burst Format**:
  - Each $30\text{ ms}$ slot contains a $27.5\text{ ms}$ burst followed by a $2.5\text{ ms}$ guard / ramp-down time.
  - Total bits per burst: 264 symbols = 528 bits.
  - Central 48 bits carry Voice Sync (`0x77F55F77F55F`), Data Sync (`0xDFF57D75DF5D`), or Embedded Signalling (Link Control).

#### 3. Hot DSP Paths for Zig SIMD
1. **FM Discriminator + RRC Slicing Filter**:
   - Instantaneous frequency deviation is extracted via conjugate product.
   - An RRC filter with tight roll-off ($\alpha = 0.2$) is applied. With $\alpha = 0.2$, the impulse response spans 65-129 taps. Zig SIMD evaluates symmetric folded FIR filters:
     $$y[n] = h[0]x[n] + \sum_{k=1}^{(N-1)/2} h[k](x[n-k] + x[n+k])$$
2. **4-Level Eye Diagram Soft-Decision Slicer**:
   - Rather than hard-slicing into 2-bit symbols immediately, the detector computes Log-Likelihood Ratios (LLR) or distance metrics to the $+3, +1, -1, -3$ constellation levels:
     ```zig
     const v_dev: @Vector(8, f32) = get_deviations();
     const b0 = (v_dev > @as(@Vector(8, f32), @splat(0.0)));
     const b1 = (@abs(v_dev) < @as(@Vector(8, f32), @splat(1296.0)));
     ```
3. **Golay $(24, 12, 8)$ and $(20, 8, 7)$ Forward Error Correction**:
   - Embedded signalling and slot headers are protected by Extended Golay codes.
   - Zig SIMD syndrome decoding: A parity check matrix $H$ ($12 \times 24$) multiplies the 24-bit received vector in $\text{GF}(2)$ using bitwise operations (`@popCount(codeword & h_row)`), mapping nonzero syndromes to error patterns in a single unrolled loop.

#### 4. Elixir / OTP Architecture & Binary Pattern Matching
- **TDMA State Machine**: Two parallel `GenServer` actors track Slot 1 and Slot 2 independently with dynamic talkgroup routing:

```elixir
defmodule Dmr.SlotParser do
  @doc "Parses DMR 264-symbol (528-bit) burst structure"
  def parse_burst(<<payload1::bitstring-size(108), sync_or_emb::bitstring-size(48),
                    payload2::bitstring-size(108), _guard::bitstring-size(24)>>) do
    case sync_or_emb do
      <<0x77F55F77F55F::48>> ->
        {:voice_frame, :sync, payload1 <> payload2}

      <<0xDFF57D75DF5D::48>> ->
        {:data_frame, :sync, payload1 <> payload2}

      <<emb_sig::48>> ->
        {:voice_frame, {:embedded_lc, decode_embedded_lc(emb_sig)}, payload1 <> payload2}
    end
  end

  defp decode_embedded_lc(<<color_code::4, pi::1, lc_data::32, crc::11>>) do
    %{color_code: color_code, privacy_indicator: pi, lc: lc_data, crc: crc}
  end
end
```

#### 5. Hardware Mapping & At-Home Practicality
- **At-Home Reception**: High. Amateur radio repeaters on 70cm ($430 - 440\text{ MHz}$) and 2m ($144 - 148\text{ MHz}$) sit on elevated hills or towers with tens of watts of power. A standard window whip antenna locks onto local repeaters easily.
- **RTL-SDR v3/v4**: Requires a TCXO-stabilized dongle (v3/v4 has $\le 1\text{ ppm}$ TCXO), which is essential since 4-FSK inner deviation is only $\pm 648\text{ Hz}$.
- **bladeRF**: Perfect for building an amateur radio DMR simplex hotspot or repeater. **Safe home testing**: either run TX through a 30 dB attenuator back into RX, or connect a 50-ohm dummy load to TX to test local RF generation without outdoor radiation.

---

### Protocol 4: DAB / DAB+ (Digital Audio Broadcasting)

#### 1. Specification & Standards
- **Standard Identifier**: [ETSI EN 300 401](https://www.etsi.org/deliver/etsi_en/300400_300499/300401/02.01.01_60/en_300401v020101p.pdf) ("Radio Broadcasting Systems; Digital Audio Broadcasting (DAB) to mobile, portable and fixed receivers").
- **DAB+ Audio Specification**: [ETSI TS 102 563](https://www.etsi.org/deliver/etsi_ts/102500_102599/102563/01.02.01_60/ts_102563v010201p.pdf) (HE-AACv2 Audio Coding and Reed-Solomon RS(120, 110) transport).
- **RF Spectrum**: VHF Band III ($174 - 240\text{ MHz}$, Blocks 5A to 13F).
- **Bandwidth**: Transmitted signal bandwidth is $1.536\text{ MHz}$ within a $1.712\text{ MHz}$ total block channelization raster.
- **Multiple Access Scheme**: Multi-carrier C-OFDM (Coded Orthogonal Frequency Division Multiplexing).
- **Legal & Domestic Status**: 100% legal, high-power public broadcast. Ubiquitous across Europe, the UK, and Australia with dozens of stations per multiplex.

#### 2. Modulation & Physical Layer
- **Transmission Mode I (Terrestrial Single Frequency Networks)**:
  - Total Transmission Frame Duration: $T_F = 96\text{ ms}$.
  - Null Symbol: $T_{\text{null}} = 1.297\text{ ms}$ (carrier and frame synchronization).
  - Number of Active OFDM Symbols per Frame: 76 symbols.
  - Symbol Duration: $T_S = 1.246\text{ ms}$.
    - Useful Symbol Part: $T_U = 1.0\text{ ms} \implies$ Subcarrier spacing $\Delta f = 1 / T_U = 1\text{ kHz}$.
    - Guard Interval (Cyclic Prefix): $\Delta = 0.246\text{ ms}$ ($246\ \mu\text{s}$).
  - Total Subcarriers: $K = 1,536$ active carriers (placed across a 2,048-point FFT space, leaving 512 virtual null subcarriers at the band edges).
- **Subcarrier Modulation**: Differential QPSK (DQPSK) in time across consecutive OFDM symbols:
  $$\Delta \phi_{k, l} = \phi_{k, l} - \phi_{k, l-1}$$
- **Forward Error Correction & Interleaving**:
  - Punctured Convolutional Code with constraint length $K = 7$ (octal generator polynomials: $G_1 = 133, G_2 = 171, G_3 = 145, G_4 = 133$).
  - Time interleaving: Spanned over 16 transmission frames ($1.536\text{ seconds}$).
  - Frequency interleaving: Pseudorandom mapping of logical carrier indices to physical subcarrier indices.
  - DAB+ adds outer Reed-Solomon $\text{RS}(120, 110, t=5)$ code over $\text{GF}(2^8)$ to error-protect AAC audio super-frames.

#### 3. Hot DSP Paths for Zig SIMD
1. **Frame Synchronization via Null-Symbol & PRS Correlation**:
   - Envelope detection discovers the $1.297\text{ ms}$ transmission pause (Null symbol).
   - Coarse and fine carrier frequency offset (CFO) is obtained by cross-correlating the received Phase Reference Symbol (OFDM symbol 1) with the known reference PRS sequence.
2. **2,048-point SIMD Fast Fourier Transform (FFT)**:
   - Evaluates a 2,048-point complex FFT for every symbol (76 symbols per $96\text{ ms} \implies 792\text{ FFTs/sec}$).
   - **Zig SIMD Radix-4 / Radix-2 Kernel**: Leverages vector registers (`@Vector(8, f32)`) to perform SIMD butterfly evaluations with pre-computed twiddle factor tables.

```zig
// Zig SIMD butterfly step for Radix-2 DIF FFT
pub inline fn butterfly2(
    a_re: *f32, a_im: *f32,
    b_re: *f32, b_im: *f32,
    w_re: f32, w_im: f32,
) void {
    const u_re = a_re.*;
    const u_im = a_im.*;
    const v_re = b_re.*;
    const v_im = b_im.*;

    a_re.* = u_re + v_re;
    a_im.* = u_im + v_im;

    const diff_re = u_re - v_re;
    const diff_im = u_im - v_im;
    // Complex twiddle multiplication: diff * W
    b_re.* = diff_re * w_re - diff_im * w_im;
    b_im.* = diff_re * w_im + diff_im * w_re;
}
```

3. **Viterbi Soft-Decision Trellis Decoder ($K=7$)**:
   - Constraint length $K = 7 \implies 64$ trellis states.
   - The Add-Compare-Select (ACS) loop processes soft-bit branch metrics for all 64 states per bit.
   - In Zig, ACS is implemented using SIMD registers (`@Vector(16, u8)` or `@Vector(8, i16)`): parallel addition of branch metrics, SIMD minimum/select (`@select`), and traceback pointer storage.

#### 4. Elixir / OTP Architecture & Binary Pattern Matching
- **Multiplex Demultiplexing**: A single DAB RF ensemble carries 10-25 audio services and data streams multiplexed into the Main Service Channel (MSC).
- **Process Topology**:
  - `Dab.Receiver` (GenStage Producer): Calls Zig NIFs, streaming deinterleaved MSC Common Interleaved Frames (CIFs).
  - `Dab.EnsembleSupervisor`: Dynamically starts an isolated `Dab.AudioChannel` worker for each active Subchannel ID (SubChId) defined in the Fast Information Channel (FIC).

```elixir
defmodule Dab.FicDecoder do
  @doc "Parses Fast Information Group (FIG) Type 0 Extension 1 (Basic Subchannel Organization)"
  def decode_fig_0_1(<<subch_id::6, start_cu::10, form::1, rest::bitstring>>) do
    case form do
      0 -> # Short form table-based protection
        <<table_switch::1, table_index::6, _padding::bitstring>> = rest
        %{subch_id: subch_id, start_cu: start_cu, type: :short, table: table_index}
      1 -> # Long form explicit protection level
        <<option::3, prot_level::2, subch_size::10, _padding::bitstring>> = rest
        %{subch_id: subch_id, start_cu: start_cu, type: :long, protection: prot_level, size_cu: subch_size}
    end
  end
end
```

#### 5. Hardware Mapping & At-Home Practicality
- **At-Home Reception**: **Maximum ease**. High-power broadcast transmitters deliver $30-50\text{ dB}$ SNR indoors. Even an un-tuned wire dangling behind a desk will reliably capture strong DAB ensembles across Europe/UK.
- **RTL-SDR v3/v4**: Requires setting the sample rate to exactly $2.048\text{ MSPS}$ (conveniently yielding an exact 1:1 match with 2,048 samples per $1.0\text{ ms}$ useful OFDM symbol!). The RTL-SDR delivers continuous $2.048\text{ MSPS}$ without loss over USB 2.0.
- **bladeRF**: Wideband capture across multiple Band III ensembles simultaneously, or transmitting a private domestic DAB ensemble over a cabled attenuator loopback.

---

### Protocol 5: Meteor-M2 LRPT & NOAA POES (Polar Satellite Direct Readout)

#### 1. Specification & Standards
- **Standard Identifier**: 
  - Roscosmos / RKS: [Meteor-M N2 LRPT Specification](https://www.eumetsat.int/) (VHF 137 MHz).
  - NOAA KLM User’s Guide ([NOAA Polar Orbiter Direct Readout](https://www.star.nesdis.noaa.gov/jpss/documents/UserGuides/KLM_Users_Guide.pdf)).
  - [CCSDS 131.0-B-3](https://public.ccsds.org/Pubs/131x0b3e1.pdf) (TM Synchronization and Channel Coding Blue Book).
- **RF Spectrum**:
  - **Meteor-M2-3 / M2-4 LRPT**: $137.100\text{ MHz}$ or $137.900\text{ MHz}$ (VHF space-to-earth).
  - **NOAA POES (NOAA-15 / 18 / 19)**: $137.100 / 137.620 / 137.9125\text{ MHz}$ (VHF APT) and $1698.0 / 1707.0\text{ MHz}$ (L-Band HRPT).
- **Bandwidth**:
  - Meteor LRPT: $\approx 120\text{ kHz}$ (at $72\text{ kSPS}$ QPSK).
  - NOAA HRPT: $\approx 1.5\text{ MHz}$ (at $665.4\text{ kbps}$ BPSK).
- **Legal & Domestic Status**: 100% legal, open civilian Earth-observation meteorological data broadcast free to all humanity.

#### 2. Modulation & Physical Layer
- **Meteor-M2 LRPT (137 MHz)**:
  - **Modulation**: QPSK (Quadrature Phase Shift Keying) at $72\text{ kSPS}$ or $80\text{ kSPS}$ ($144\text{ kbps}$ raw).
  - **Pulse Shaping**: Root Raised Cosine (RRC) with $\alpha = 0.6$.
  - **Synchronization**: 32-bit CCSDS Attached Synchronization Marker (ASM): `0x1ACFFC1D`.
  - **Channel Coding**: Concatenated coding:
    - Inner Code: Rate $1/2$, constraint length $K = 7$ Convolutional Code (polynomials $G_1 = 171_8, G_2 = 133_8$).
    - Outer Code: Reed-Solomon $\text{RS}(255, 223, t=16)$ over $\text{GF}(2^8)$ with CCSDS interleaving ($I = 4$).
  - **Payload**: MSU-MR multispectral imaging scanner (6 visible and infrared channels).
- **NOAA HRPT (1.7 GHz)**:
  - **Modulation**: Split-phase (Manchester) BPSK at $665.4\text{ kbps}$.
  - **Framing**: 60-bit sync word `0x0284016035E0`, carrying AVHRR 10-bit multispectral lines.

#### 3. Hot DSP Paths for Zig SIMD
1. **Costas Loop Carrier Phase Recovery**:
   - Tracks Doppler shift ($\pm 3\text{ kHz}$ at $137\text{ MHz}$ or $\pm 40\text{ kHz}$ at $1.7\text{ GHz}$ as the satellite flies overhead at $7.5\text{ km/s}$):
     $$\text{QPSK}: e[n] = \operatorname{sgn}(I[n]) \cdot Q[n] - \operatorname{sgn}(Q[n]) \cdot I[n]$$
   - Vectorized in Zig using `@select` and float vector operations.
2. **Symbol Timing Recovery via Gardner TED**:
   - Decimates the incoming $250\text{ kSPS}$ (Meteor) or $2.4\text{ MSPS}$ (NOAA) stream to 1 sample per symbol at maximum eye opening.
3. **CCSDS Descrambler & Reed-Solomon $(255, 223)$ SIMD Matrix**:
   - CCSDS defines a standard 255-bit pseudorandom scrambler polynomial ($x^8 + x^7 + x^5 + x^3 + 1$). XORing this sequence against incoming packet bytes is vectorized using 64-byte SIMD XOR.
   - For Meteor LRPT, Reed-Solomon decoding with $t=16$ error correction capability demands substantial polynomial evaluation. Zig SIMD evaluates syndrome matrices using byte-sliced carry-less arithmetic.

```zig
// Zig SIMD snippet: Costas Loop Phase Error Detector for QPSK
pub inline fn costasErrorQPSK(i: @Vector(4, f32), q: @Vector(4, f32)) @Vector(4, f32) {
    const zero: @Vector(4, f32) = @splat(0.0);
    const one: @Vector(4, f32) = @splat(1.0);
    const neg_one: @Vector(4, f32) = @splat(-1.0);

    const sgn_i = @select(f32, i >= zero, one, neg_one);
    const sgn_q = @select(f32, q >= zero, one, neg_one);

    return (sgn_i * q) - (sgn_q * i);
}
```

#### 4. Elixir / OTP Architecture & Binary Pattern Matching
- **Line Raster Pipeline**:
  - `Hrpt.Receiver` (GenStage Producer): Ingests minor frames from Zig NIF.
  - `Hrpt.Deframer` (GenStage ProducerConsumer): Unpacks 10-bit contiguous bitstreams into separate channel scan lines.
  - `Hrpt.ImageRasterizer` (GenServer / Broadway): Streams raster rows directly to disk (PNG / TIFF) or pushes chunks to a live web canvas.

```elixir
defmodule Hrpt.FrameDecoder do
  @doc "Extracts AVHRR 10-bit multispectral sensor data from HRPT minor frame"
  def unpack_10bit_words(<<w0::10, w1::10, w2::10, w3::10, rest::bitstring>>, acc) do
    unpack_10bit_words(rest, [w3, w2, w1, w0 | acc])
  end
  def unpack_10bit_words(<<>>, acc), do: :lists.reverse(acc)

  def parse_minor_frame(<<0x0284016035E0::60, _header::bitstring-size(100), 
                          avhrr_data::bitstring-size(75000), _rest::bitstring>>) do
    words = unpack_10bit_words(avhrr_data, [])
    %{sync: true, channels: demux_5_channels(words)}
  end
end
```

#### 5. Hardware Mapping & At-Home Practicality
- **At-Home Reception**:
  - **Meteor-M2 LRPT (137 MHz)**: **Remarkably practical at home**. A simple horizontal V-dipole made of two $53.4\text{ cm}$ metal rods at a $120^\circ$ angle placed flat on a windowsill or balcony requires no tracking rotor and easily decodes full-pass 137 MHz digital imagery as the satellite passes overhead!
  - **NOAA HRPT (1.7 GHz)**: Requires a 60-100 cm dish or helical antenna with an LNA (Sawbird+ GOES) and manual or rotor tracking.
- **RTL-SDR v3/v4**: Outstanding on $137\text{ MHz}$ VHF for Meteor LRPT (sampling at $250\text{ kHz}$ to $1.024\text{ MSPS}$).
- **bladeRF**: Ideal for multi-satellite reception or wider L-Band bandwidths.

---

## 5. Cross-Protocol Comparison & Architecture Matrix

| Metric / Parameter | AIS | VDL Mode 2 | DMR Tier II | DAB / DAB+ | Meteor-M2 LRPT / HRPT |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Frequency Band** | VHF ($162\text{ MHz}$) | VHF ($136.975\text{ MHz}$) | VHF/UHF ($144 / 430\text{ MHz}$) | Band III ($174 - 240\text{ MHz}$) | VHF ($137\text{ MHz}$) / L-Band ($1.7\text{ GHz}$) |
| **RF Bandwidth** | $2 \times 25\text{ kHz}$ | $25\text{ kHz}$ | $12.5\text{ kHz}$ | $1.536\text{ MHz}$ | $120\text{ kHz}$ (LRPT) / $1.5\text{ MHz}$ (HRPT) |
| **Modulation** | GMSK ($BT=0.4$) | D8PSK | 4-FSK | OFDM (1536 carriers) | QPSK / BPSK |
| **Symbol Rate** | $9,600\text{ baud}$ | $10,500\text{ baud}$ | $4,800\text{ baud}$ | Mode I ($1\text{ kSPS/carrier}$) | $72\text{ kSPS}$ (LRPT) / $665.4\text{ kSPS}$ (HRPT) |
| **Bits / Symbol** | 1 bit | 3 bits | 2 bits | 2 bits (DQPSK) | 2 bits / 1 bit |
| **Legal Status** | 100% Legal Public Safety | 100% Legal Public Flight Data | 100% Legal Amateur Radio | 100% Legal Public Broadcast | 100% Legal Weather Telemetry |
| **At-Home Antenna** | Window telescopic whip | Window telescopic whip | Window / handheld whip | Simple indoor dangling wire | Simple stationary V-dipole on sill |
| **Inner FEC** | None (CRC-16 only) | None | Golay(24,12), Trellis 3/4 | Conv $K=7$ ($R=1/4 \dots 8/9$) | Conv $K=7$ ($R=1/2$) |
| **Outer FEC** | None | Shortened RS(255,249)| QR(16,8) | RS(120,110) (DAB+) | RS(255,223) (Meteor LRPT) |
| **Zig SIMD Targets**| Polyphase DDC, $\operatorname{atan2}$ | SRRC Matched FIR, GF($2^8$) RS | RRC Symmetric FIR, 4-level soft | 2048-FFT, Viterbi ACS unit | Costas Loop, Gardner TED, RS matrix |
| **RTL-SDR Support** | Full ($\checkmark\checkmark$) | Full ($\checkmark\checkmark$) | Full ($\checkmark\checkmark$) | Full ($2.048\text{ MSPS}$) ($\checkmark$) | Full for 137 MHz LRPT ($\checkmark\checkmark$) |
| **bladeRF Support** | Full + TX Loopback | Full + Multi-Ch | Full + Hotspot / TX | Full + TX Multiplex | Full (VHF + 1.7 GHz L-band) |
| **BEAM Process Model**| Vessel GenServer (MMSI)| Aircraft link state | Dual-slot TDMA workers | Dynamic audio stream pool | Scanline streaming worker |

---

## 6. Safe & 100% Legal bladeRF Transmission Operations

Because the Nuand bladeRF is a full-duplex transceiver capable of radiating up to $+6\text{ dBm}$ (approx. $4\text{ mW}$) across $47\text{ MHz} - 6\text{ GHz}$, domestic operation requires strict isolation techniques:

```
+-----------------------------------------------------------------------------------------------+
| SAFE DOMESTIC BLADERF TRANSMISSION TOPOLOGIES                                                 |
+-----------------------------------------------------------------------------------------------+
| 1. ENCLOSED DIRECT RF CABLE LOOPBACK (GOLD STANDARD)                                          |
|                                                                                               |
|    [bladeRF TX] ===(SMA)===> [ 30 dB / 40 dB Attenuator ] ===(SMA)===> [bladeRF / RTL-SDR RX]  |
|                                                                                               |
|    - Radiated Emission: Exactly 0 nW (no electromagnetic energy enters the atmosphere).       |
|    - Safe Input Power: +6 dBm attenuated by 30 dB delivers -24 dBm to the RX port,            |
|      comfortably preventing LNA burnout or saturation.                                        |
|    - Utility: Perfect loopback Bit Error Rate (BER) measurement, end-to-end protocol test      |
|      harnesses, and continuous automated CI integration testing.                              |
|                                                                                               |
| 2. 50-OHM DUMMY LOAD TERMINATION                                                              |
|    - Affixing a high-frequency 50-ohm terminator to the TX SMA port absorbs the RF power into |
|      a resistive thermal element with negligible near-field leakage (< -60 dBm).              |
|                                                                                               |
| 3. LOW-POWER UNLICENSED ISM BANDS                                                             |
|    - Frequencies: 433.05 - 434.79 MHz (Europe) or 868 MHz / 902-928 MHz (US).                 |
|    - Strict adherence to <10 mW ERP limits and <1% transmit duty cycle allocations.           |
|                                                                                               |
| 4. AMATEUR RADIO ALLOCATIONS                                                                  |
|    - Requires an active amateur radio operator license.                                       |
|    - All transmissions must be unencrypted and identify with the assigned callsign.          |
+-----------------------------------------------------------------------------------------------+
```

---

## 7. Recommended Implementation Pathway

Building upon the initial Mode-S / ADS-B foundation, the optimal implementation roadmap progresses in order of increasing DSP complexity:

1. **Milestone 1: AIS Receiver (GMSK Phase 1)**:
   - *Goal*: Implement dual-channel DDC and FM discriminator in Zig SIMD; decode HDLC and NRZI bit stuffing in Elixir; track vessels on an interactive OpenStreetMap canvas.
   - *Antenna*: Standard indoor telescopic whip at $46\text{ cm}$.
2. **Milestone 2: VDL Mode 2 (Linear Modulation & Reed-Solomon)**:
   - *Goal*: Build SRRC polyphase matched filter, Gardner clock synchronizer, D8PSK constellation slicer, and shortened Reed-Solomon decoder; parse ACARS and aviation telecommunication payloads.
   - *Antenna*: Indoor telescopic whip at $55\text{ cm}$ (hundreds of aircraft bursts/hour).
3. **Milestone 3: DMR Tier II (TDMA Framing & Digital Voice)**:
   - *Goal*: Implement 4-FSK matched slicer, 30 ms TDMA slot synchronization, Golay error correction, and embedded link control extraction.
   - *Antenna*: Handheld 70cm whip or rubber duck tuned to local repeater.
4. **Milestone 4: Meteor-M2 LRPT / NOAA Satellite Direct Readout**:
   - *Goal*: Build Costas carrier loop, QPSK carrier lock, CCSDS frame synchronization, and live line-by-line AVHRR multispectral image rasterization.
   - *Antenna*: Stationary home-made V-dipole ($120^\circ$, $53.4\text{ cm}$ legs) on a windowsill.
5. **Milestone 5: DAB / DAB+ Ensemble Engine (C-OFDM & Viterbi)**:
   - *Goal*: 2,048-point SIMD FFT baseband engine, cyclic prefix correlator, DQPSK demapping, and soft-decision Viterbi decoder delivering live AAC audio.
   - *Antenna*: Simple indoor wire dangling behind desk ($>30\text{ dB}$ SNR).

---

## 8. Primary Standards & Reference Documentation

1. **AIS**:
   - [ITU-R M.1371-5](https://www.itu.int/rec/R-REC-M.1371/en): Technical characteristics for an automatic identification system using TDMA in the VHF maritime mobile band.
   - [IEC 61993-2](https://webstore.iec.ch/publication/6274): Class A shipborne equipment.
   - Reference Codebase: [`ais-catcher`](https://github.com/jvde-github/AIS-catcher) (Optimized multi-platform C++ SIMD receiver).
2. **VDL Mode 2**:
   - [ICAO Doc 9776](https://store.icao.int/en/manual-on-vhf-digital-link-vdl-mode-2-doc-9776): Manual on VHF Digital Link (VDL) Mode 2.
   - [RTCA DO-224E](https://standards.globalspec.com/std/14352125/do-224-rev-e): Signal-in-Space MASPS for VDL Mode 2.
   - Reference Codebase: [`dumpvdl2`](https://github.com/szpajder/dumpvdl2) (SZPAJDER's production VDL2 demodulator and packet decoder).
3. **DMR (Digital Mobile Radio)**:
   - [ETSI TS 102 361-1](https://www.etsi.org/deliver/etsi_ts/102300_102399/10236101/02.05.01_60/ts_10236101v020501p.pdf): DMR Air Interface Protocol.
   - [ETSI TS 102 361-2](https://www.etsi.org/deliver/etsi_ts/102300_102399/10236102/02.04.01_60/ts_10236102v020401p.pdf): DMR Voice and Generic Services.
   - Reference Codebase: [`dsd-fme`](https://github.com/lwvmobile/dsd-fme) (Digital Speech Decoder Florida Man Edition).
4. **DAB / DAB+**:
   - [ETSI EN 300 401](https://www.etsi.org/deliver/etsi_en/300400_300499/300401/02.01.01_60/en_300401v020101p.pdf): Radio Broadcasting Systems; Digital Audio Broadcasting (DAB).
   - [ETSI TS 102 563](https://www.etsi.org/deliver/etsi_ts/102500_102599/102563/01.02.01_60/ts_102563v010201p.pdf): Transport of HE-AACv2 audio in DAB+.
   - Reference Codebase: [`welle.io`](https://github.com/AlbrechtL/welle.io) and [`dablin`](https://github.com/Opendigitalradio/dablin).
5. **Meteor-M2 & NOAA Satellite Direct Readout**:
   - [NOAA KLM User's Guide](https://www.star.nesdis.noaa.gov/jpss/documents/UserGuides/KLM_Users_Guide.pdf): Direct Readout Services and AVHRR format.
   - [CCSDS 131.0-B-3](https://public.ccsds.org/Pubs/131x0b3e1.pdf): TM Synchronization and Channel Coding Blue Book.
   - Reference Codebase: [`SatDump`](https://github.com/SatDump/SatDump) (Comprehensive multi-satellite DSP and decoding pipeline).
