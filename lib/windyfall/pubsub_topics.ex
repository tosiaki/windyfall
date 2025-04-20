defmodule Windyfall.PubSubTopics do
  @moduledoc """
  Generates standardized topic strings for Phoenix PubSub.
  """

  @doc "Generates the topic string for a specific chat thread."
  @spec thread(pos_integer() | String.t()) :: String.t()
  def thread(thread_id), do: "thread:#{thread_id}"

  @doc "Generates the topic string for reactions related to a specific message."
  @spec reactions(pos_integer() | String.t()) :: String.t()
  def reactions(message_id), do: "reactions:#{message_id}"

  @doc "Generates the topic string for presence tracking within a scope (e.g., 'chat')."
  @spec presence(String.t()) :: String.t()
  def presence(scope), do: "presence:#{scope}"

  # Add more topics as needed, e.g.:
  # def global_threads(), do: "threads"
  # def user_notifications(user_id), do: "user_notify:#{user_id}"

  @doc "Generates the topic string for general thread list updates."
  @spec thread_list_updates() :: String.t()
  def thread_list_updates(), do: "threads:updates"
end
