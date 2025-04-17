defmodule WindyfallWeb.AttachmentHelpers do
  alias Windyfall.Messages.Attachment # Alias the struct if needed

  @displayable_image_types ~w(image/jpeg image/png image/gif image/webp image/bmp)
  @displayable_text_types ~w(text/plain text/markdown text/csv text/html text/xml application/json)
  @text_extensions [".log", ".txt", ".md", ".csv", ".json", ".ex", ".exs", ".js", ".css", ".heex"]

  @doc """
  Checks if an attachment struct or map represents a displayable image.
  """
  # Match on Struct
  def is_displayable_image?(%Attachment{content_type: ct}) when is_binary(ct), do: ct in @displayable_image_types
  # Match on Map (handle atom or string keys)
  def is_displayable_image?(%{content_type: ct}) when is_binary(ct), do: ct in @displayable_image_types
  def is_displayable_image?(%{"content_type" => ct}) when is_binary(ct), do: ct in @displayable_image_types
  # Fallback
  def is_displayable_image?(_), do: false

  @doc """
  Checks if an attachment struct or map represents displayable text content.
  """
  # Match on Struct
  def is_displayable_text?(%Attachment{filename: fname, content_type: ct}) when is_binary(ct) and is_binary(fname) do
    ct in @displayable_text_types or String.ends_with?(ct, "+xml") or Path.extname(fname) in @text_extensions
  end
  # Match on Map (handle atom or string keys)
  def is_displayable_text?(%{filename: fname, content_type: ct}) when is_binary(ct) and is_binary(fname) do
     ct in @displayable_text_types or String.ends_with?(ct, "+xml") or Path.extname(fname) in @text_extensions
  end
   def is_displayable_text?(%{"filename" => fname, "content_type" => ct}) when is_binary(ct) and is_binary(fname) do
     ct in @displayable_text_types or String.ends_with?(ct, "+xml") or Path.extname(fname) in @text_extensions
  end
  # Fallback
  def is_displayable_text?(_), do: false

end
