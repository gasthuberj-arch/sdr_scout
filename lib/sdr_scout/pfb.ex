defmodule SdrScout.PFB do
  @moduledoc """
  High-level Polyphase Filterbank (PFB) Channelizer interface.
  Designs windowed-sinc prototype lowpass filters and routes wideband I/Q streams
  through native Zig SIMD polyphase branch filters and Cooley-Tukey FFTs.
  """
  alias SdrScout.Native.Pfb

  defstruct [
    :context,
    :num_channels,
    :taps_per_branch,
    :prototype_taps
  ]

  @doc """
  Initializes a new M-channel PFB channelizer.
  Options:
    - `:taps_per_branch` - Number of filter taps per branch (default: 8)
    - `:window` - Windowing function (:blackman_harris, :hamming, :hann) (default: :blackman_harris)
  """
  def new(num_channels, opts \\ []) when num_channels in [4, 8, 16, 32] do
    taps_per_branch = Keyword.get(opts, :taps_per_branch, 8)
    window = Keyword.get(opts, :window, :blackman_harris)

    ctx = Pfb.new_context(num_channels, taps_per_branch)
    taps = design_prototype_filter(num_channels, taps_per_branch, window)

    true = Pfb.set_prototype_taps(ctx, taps)

    %__MODULE__{
      context: ctx,
      num_channels: num_channels,
      taps_per_branch: taps_per_branch,
      prototype_taps: taps
    }
  end

  @doc """
  Designs a windowed-sinc prototype lowpass filter for M-channel channelization.
  Total taps $L = M \\times K$. Cutoff frequency $f_c = \\frac{1}{2M}$.
  """
  def design_prototype_filter(m, k, window \\ :blackman_harris) do
    total_taps = m * k
    fc = 1.0 / (2.0 * m)
    mid = (total_taps - 1) / 2.0

    raw_taps =
      for i <- 0..(total_taps - 1) do
        n = i - mid

        # Sinc calculation
        sinc_val =
          if abs(n) < 1.0e-7 do
            2.0 * fc
          else
            :math.sin(2.0 * :math.pi() * fc * n) / (:math.pi() * n)
          end

        # Window weighting
        w_val = compute_window(i, total_taps, window)
        sinc_val * w_val
      end

    # Normalize filter gain so DC gain = 1.0 across prototype
    sum = Enum.sum(raw_taps)
    Enum.map(raw_taps, fn val -> val / sum end)
  end

  @doc """
  Processes a raw 8-bit unsigned I/Q baseband chunk through the channelizer.
  Returns a list of M binaries, one for each sub-channel.
  """
  def channelize(%__MODULE__{context: ctx}, chunk) when is_binary(chunk) do
    Pfb.channelize(ctx, chunk)
  end

  @doc """
  Retrieves channelizer telemetry `[samples_in, blocks_processed]`.
  """
  def get_telemetry(%__MODULE__{context: ctx}) do
    Pfb.get_telemetry(ctx)
  end

  # ===========================================================================
  # Window Functions
  # ===========================================================================

  defp compute_window(n, total, :blackman_harris) do
    # 4-term Blackman-Harris window with -92 dB sidelobe suppression
    a0 = 0.35875
    a1 = 0.48829
    a2 = 0.14128
    a3 = 0.01168

    theta = 2.0 * :math.pi() * n / (total - 1)
    a0 - a1 * :math.cos(theta) + a2 * :math.cos(2.0 * theta) - a3 * :math.cos(3.0 * theta)
  end

  defp compute_window(n, total, :hamming) do
    0.54 - 0.46 * :math.cos(2.0 * :math.pi() * n / (total - 1))
  end

  defp compute_window(n, total, :hann) do
    0.5 * (1.0 - :math.cos(2.0 * :math.pi() * n / (total - 1)))
  end

  defp compute_window(_n, _total, _), do: 1.0
end
