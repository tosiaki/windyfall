defmodule WindyfallWeb.NumberHelpers do
  @moduledoc """
  Helper functions for working with numbers, especially for display.
  """

  @byte_units ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]

  @doc """
  Converts a number of bytes into a human-readable string with units.

  ## Examples

      iex> number_to_human_size(1024)
      "1.0 KB"

      iex> number_to_human_size(1500000)
      "1.4 MB"

      iex> number_to_human_size(500)
      "500 B"

      iex> number_to_human_size(0)
      "0 B"

      iex> number_to_human_size(nil)
      "N/A"
  """
  def number_to_human_size(nil), do: "N/A"
  def number_to_human_size(bytes) when not is_integer(bytes) or bytes < 0 do
    # Handle invalid input gracefully
    "Invalid size"
  end
  def number_to_human_size(0), do: "0 B"
  def number_to_human_size(bytes) when is_integer(bytes) and bytes > 0 do
    # Calculate the exponent for the unit (base 1024)
    exponent = :math.log(bytes) / :math.log(1024) |> floor() |> trunc()

    # Ensure exponent doesn't exceed available units
    exponent = min(exponent, Enum.count(@byte_units) - 1)

    # Calculate the value in the chosen unit
    human_value = bytes / :math.pow(1024, exponent)

    # Format the number (e.g., one decimal place)
    formatted_value = :erlang.float_to_binary(human_value, decimals: 1)

    # Get the unit string
    unit = Enum.at(@byte_units, exponent)

    "#{formatted_value} #{unit}"
  end
end
