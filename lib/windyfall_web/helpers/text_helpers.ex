defmodule WindyfallWeb.TextHelpers do
  def truncate(text, max_length, suffix \\ "...") do
    if text && String.length(text) > max_length do
      String.slice(text, 0, max_length) <> suffix
    else
      text
    end
  end

  @doc """
  Returns the count followed by the singular or plural form of a word.

  ## Examples

      iex> pluralize(1, "message", "messages")
      "1 message"

      iex> pluralize(5, "reply", "replies")
      "5 replies"

      iex> pluralize(0, "item", "items")
      "0 items"
  """
  def pluralize(count, singular, plural) when is_integer(count) do
    "#{count} #{if count == 1, do: singular, else: plural}"
  end
end
