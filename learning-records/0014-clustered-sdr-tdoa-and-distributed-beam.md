# Clustered SDRs, TDOA, and Distributed BEAM Explored

The user envisioned clustering two Arduino Portenta X8 boards with RTL-SDR dongles to correlate radio signals over a network.

## Key Architectural Dimensions Explored
1. **The Signal Processing (TDOA & Cross-Correlation):** Time Difference of Arrival ($\Delta t = t_A - t_B$) maps to hyperbolic position curves ($c \approx 300\text{ m}/\mu\text{s}$). Cross-correlating baseband streams via Fourier transform ($R_{xy}(\tau) = \mathcal{F}^{-1}\{X(f)Y^*(f)\}$) calculates sub-sample delay.
2. **The Distributed Architecture (BEAM Nodes):** Distributed Erlang connects the two Portenta X8s over Wi-Fi/Ethernet with zero middleware (no Kafka/Redis needed). Process groups (`:pg`) aggregate and deduplicate frames across physical nodes.
3. **The Synchronization Challenge:** Because light travels 300 meters per microsecond, standard NTP (with millisecond jitter) is insufficient. Solutions include PTP (IEEE 1588), hardware GPS PPS interrupts on the STM32H7, or opportunistic reference beacon cross-calibration.
