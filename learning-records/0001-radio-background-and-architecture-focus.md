# Radio Background and Architectural Focus Established

The user is a self-described "radio nerd, but not an expert" looking to improve in Amateur (HAM) radio rather than ADS-B specifically. They want to master the architectural trade-offs (upsides and shortcomings) of this Elixir/OTP + Zig NIF system compared to traditional SDR pipelines.

## Implications
- Avoid deep rabbit holes into aviation-only domain rules (Gillham coding, CPR spherical trigonometry) unless used as an analogy or concrete example.
- Focus early lessons on the macro/micro architecture: how streaming I/Q baseband data flows through hardware, NIF buffers, and BEAM processes, contrasting with GNU Radio, Direwolf, and pure C/Rust pipelines.
- Frame DSP concepts (sampling, filtering, modulation, synchronization) in terms of HAM modes (e.g. APRS, FT8, AX.25, DMR).
