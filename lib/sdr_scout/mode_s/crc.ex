defmodule SdrScout.ModeS.CRC do
  @moduledoc """
  Mode-S / ADS-B 24-bit CRC calculation and verification.
  Standard Mode-S CRC polynomial: 0x1FFF409
  Bitwise division over 112 bits: remainder should be 0.
  """
  alias SdrScout.ModeS

  @doc """
  Calculates the 24-bit CRC remainder over an arbitrary binary.
  Returns a 24-bit integer.
  """
  defdelegate checksum(binary), to: ModeS

  @doc """
  Verifies that a 112-bit (14-byte) Mode-S Extended Squitter frame has a zero CRC remainder.
  """
  defdelegate valid?(frame), to: ModeS

  @doc """
  Given an 11-byte (88-bit) message payload, computes the 24-bit parity and
  returns the complete 14-byte (112-bit) frame.
  """
  defdelegate encode(payload), to: ModeS, as: :append_crc
end
