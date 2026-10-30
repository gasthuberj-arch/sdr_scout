defmodule SdrScout.ModeS.CRC do
  @moduledoc """
  Mode-S / ADS-B 24-bit CRC calculation and verification.
  Standard Mode-S CRC polynomial: 0x1FFF409
  Bitwise division over 112 bits: remainder should be 0.
  """
  import Bitwise

  @generator 0x1FFF409

  @doc """
  Calculates the 24-bit CRC remainder over an arbitrary binary.
  Returns a 24-bit integer.
  """
  def checksum(binary) when is_binary(binary) do
    # Bitwise LFSR CRC division over bitstream
    bits = for <<b::1 <- binary>>, do: b
    do_lfsr(bits, 0)
  end

  defp do_lfsr([], reg), do: band(reg, 0xFFFFFF)

  defp do_lfsr([bit | rest], reg) do
    msb = reg >>> 23 &&& 1
    new_reg = band(reg <<< 1, 0xFFFFFF) ||| bit

    next_reg =
      if msb == 1 do
        bxor(new_reg, @generator)
      else
        new_reg
      end

    do_lfsr(rest, next_reg)
  end

  @doc """
  Verifies that a 112-bit (14-byte) Mode-S Extended Squitter frame has a zero CRC remainder.
  """
  def valid?(<<_::binary-size(14)>> = frame) do
    checksum(frame) == 0
  end

  def valid?(_), do: false

  @doc """
  Given an 11-byte (88-bit) message payload, computes the 24-bit parity and
  returns the complete 14-byte (112-bit) frame.
  """
  def encode(<<payload::binary-size(11)>>) do
    # Append 24 zero bits
    parity = checksum(<<payload::binary, 0, 0, 0>>)
    <<payload::binary, parity::24>>
  end
end
