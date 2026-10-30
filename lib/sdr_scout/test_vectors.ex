defmodule SdrScout.TestVectors do
  @moduledoc """
  Standard real-world ADS-B / Mode-S test vectors with known decoded values.
  """

  # Standard test frames (14 bytes / 28 hex chars):
  # 1. Aircraft Identification (TC 4): "KLM1023"
  # Hex: 8D4840D6202CC371C32CE0576098
  # 2. Airborne Position (TC 11): Even frame
  # Hex: 8D40621D58C382D690C8AC2863A7
  # 3. Airborne Position (TC 11): Odd frame
  # Hex: 8D40621D58C386435CC412692AD6
  # 4. Airborne Velocity (TC 19): Subtype 1
  # Hex: 8D485020994409940838175B284F

  def identification_frame do
    Base.decode16!("8D4840D6202CC371C32CE0576098")
  end

  def airborne_pos_even do
    Base.decode16!("8D40621D58C382D690C8AC2863A7")
  end

  def airborne_pos_odd do
    Base.decode16!("8D40621D58C386435CC412692AD6")
  end

  def airborne_velocity do
    Base.decode16!("8D485020994409940838175B284F")
  end
end
