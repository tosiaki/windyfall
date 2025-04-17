defmodule Windyfall.FileHelpers do
  alias Windyfall.Messages.Attachment
  import Ecto.UUID, only: [generate: 0]
  require Logger

  @upload_sub_dir "messages" # Subdirectory for message attachments

  def create_text_attachment(content, original_filename_hint \\ "text_snippet") do
    # Basic sanitization/creation of filename
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    safe_hint = String.replace(original_filename_hint, ~r/[^\w.-]/, "_") |> String.slice(0, 50)
    filename = "#{safe_hint}_#{timestamp}.txt"

    dest_dir_rel = Path.join(["priv", "static", "uploads", @upload_sub_dir])
    dest_dir_abs = Path.expand(dest_dir_rel)
    dest_path_abs = Path.join(dest_dir_abs, filename)
    web_path = "/uploads/#{@upload_sub_dir}/#{filename}" # Path for URL

    try do
      File.mkdir_p!(dest_dir_abs)
      File.write!(dest_path_abs, content)
      {:ok, file_size} = File.stat(dest_path_abs, [:size])

      metadata = %{
        filename: filename,
        web_path: web_path,
        content_type: "text/plain",
        size: file_size
      }
      {:ok, metadata}
    rescue
      e ->
        Logger.error("Failed to create text attachment #{dest_path_abs}: #{inspect(e)}")
        {:error, :file_creation_failed}
    end
  end
end
