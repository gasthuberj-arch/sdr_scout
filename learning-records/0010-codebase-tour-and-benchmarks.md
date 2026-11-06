# Live Codebase Tour and Empirical Benchmarks

The user initiated a live code tour of `SdrScout`. The implementation was inspected across the Zigler NIF (`lib/sdr_scout/native/dsp.ex`), GenStage streaming pipeline (`lib/sdr_scout/pipeline/`), and Elixir bitstring dissector (`lib/sdr_scout/mode_s/decoder.ex`).

## Empirical Benchmark Results
- Test suite: 15 ExUnit tests passing (100% green).
- Benchmark throughput: **27.51 MSPS** (Mega-samples/sec) and **55.01 MB/sec**.
- Realtime factor: **13.8x real-time** at 2.0 MSPS (consuming ~7.2% of a single CPU core).
- Average NIF execution time per 64 KB chunk: ~1.19 ms (fits within soft-realtime BEAM boundaries).
