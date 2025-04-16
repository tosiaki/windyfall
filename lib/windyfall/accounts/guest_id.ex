defmodule Windyfall.Accounts.Guest do
  use Agent
  def start_link(_args) do
    Agent.start_link(fn -> 0 end, name: __MODULE__)
  end

  def new_id do
    id_num = Agent.get(__MODULE__, &(&1))
    Agent.update(__MODULE__, &(&1+1))
    id_num
  end

  def new_session do
    make_ref()
    |> :erlang.ref_to_list()
    |> List.to_string()
  end
end
