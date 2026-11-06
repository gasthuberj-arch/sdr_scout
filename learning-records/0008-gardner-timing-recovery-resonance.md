# Gardner Timing Recovery Resonated: Moving to Polyphase Channelization

The user had a profound breakthrough understanding the Gardner Timing Error Detector: how two samples per symbol and a single multiplication/subtraction ($e[k] = x[k - 1/2](x[k] - x[k - 1])$) seamlessly extracts clock phase and steers a fractional interpolator without any preambles or data knowledge.

## Next Step: Track 2 — Polyphase Filterbanks (PFB)
Address the multi-channel SDR scaling problem:
- The naive approach: $M$ parallel frequency rotators and $M$ FIR filters consumes $O(M \cdot L)$ multiply-accumulates per sample, quickly melting the CPU.
- The multirate breakthrough: Polyphase decomposition and the Noble Identities commute decimation before filtering.
- Pairing an $M$-phase sub-filter commutator with an $M$-point IFFT produces an $M$-channel receiver in $O(L/M + \log M)$ time—a 500x computational efficiency gain that allows an RTL-SDR to monitor dozens of HAM channels simultaneously.
