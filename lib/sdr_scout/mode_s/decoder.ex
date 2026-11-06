defmodule SdrScout.ModeS.Decoder do
  @moduledoc """
  Mode-S Extended Squitter (DF17/DF18) Dissector.
  Delegates to the unified `SdrScout.ModeS` codec.
  """
  alias SdrScout.ModeS

  def decode(frame) do
    ModeS.decode(frame, validate_crc: false)
  end
end
