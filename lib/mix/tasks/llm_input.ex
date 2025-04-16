defmodule Mix.Tasks.LlmInput do
  @moduledoc """
  Mix task to compile project files for LLM input.
  
  Usage:
    mix llm_input
  """
  use Mix.Task

  @ignored_dirs ~w(_build deps node_modules cover priv/static vendor tmp config)
  @extensions ~w(.ex .exs .js .ts .css .html .heex .eex .json .txt .md)

  def run(_) do
    project_root = File.cwd!()
    
    files =
      ["lib", "assets"]
      |> Enum.flat_map(&collect_files(project_root, &1))
      |> Enum.sort()

    output =
      Enum.reduce(files, "", fn file, acc ->
        relative_path = Path.relative_to(file, project_root)
        content = File.read!(file)
        acc <>
          """
          
          === FILE: #{relative_path} ===
          #{content}
          === END FILE ===
          """
      end)

    IO.puts(output)
  end

  defp collect_files(root, dir) do
    full_dir = Path.join(root, dir)
    
    if File.dir?(full_dir) do
      File.ls!(full_dir)
      |> Enum.flat_map(fn entry ->
        full_path = Path.join(full_dir, entry)
        cond do
          File.dir?(full_path) and entry in @ignored_dirs ->
            []
          File.dir?(full_path) ->
            collect_files(root, Path.relative_to(full_path, root))
          Path.extname(entry) in @extensions ->
            [full_path]
          true ->
            []
        end
      end)
    else
      []
    end
  end
end
