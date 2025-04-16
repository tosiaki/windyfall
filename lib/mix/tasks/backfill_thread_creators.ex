defmodule Mix.Tasks.Windyfall.BackfillThreadCreators do
  use Mix.Task

  import Ecto.Query, warn: false
  alias Windyfall.Repo
  alias Windyfall.Messages.Thread
  alias Windyfall.Messages.Message

  @shortdoc "Backfills creator_id and cleans up context IDs in the threads table."
  def run(_) do
    Mix.Task.run("app.start") # Start the application to access Repo

    IO.puts("Starting thread data backfill...")

    backfill_creator_ids()
    cleanup_context_ids()

    IO.puts("Backfill complete.")
  end

  defp backfill_creator_ids() do
    IO.puts("Backfilling creator_id...")

    # Find threads missing creator_id
    threads_to_update = from(t in Thread, where: is_nil(t.creator_id), select: t.id) |> Repo.all()

    if threads_to_update == [] do
      IO.puts("No threads need creator_id backfill.")
      :ok
    else
      IO.puts("Found #{length(threads_to_update)} threads to update.")
      total_updated =
        Enum.reduce(threads_to_update, 0, fn thread_id, count ->
          # Find the user_id of the first message in the thread
          first_message_user_id =
            from(m in Message,
              where: m.thread_id == ^thread_id,
              order_by: [asc: m.inserted_at],
              limit: 1,
              select: m.user_id
            )
            |> Repo.one()

          if first_message_user_id do
            # Update the thread's creator_id
            from(t in Thread,
              where: t.id == ^thread_id,
              update: [set: [creator_id: ^first_message_user_id]]
            )
            |> Repo.update_all([]) # Returns {num_updated, nil}

            # IO.puts("Updated thread #{thread_id} with creator #{first_message_user_id}")
            count + 1
          else
            IO.warn("Thread #{thread_id} has no messages or first message has no user_id. Cannot set creator_id.")
            count
          end
        end)
      IO.puts("Successfully set creator_id for #{total_updated} threads.")
    end
  end

  defp cleanup_context_ids() do
    IO.puts("Cleaning up context IDs (setting user_id=NULL where topic_id is set)...")

    # Set user_id to NULL if topic_id is NOT NULL
    query =
      from t in Thread,
        where: not is_nil(t.topic_id) and not is_nil(t.user_id), # Find threads with both set
        update: [set: [user_id: nil]] # Nullify user_id

    {updated_count, _} = Repo.update_all(query, [])
    IO.puts("Set user_id to NULL for #{updated_count} topic-associated threads.")

    # Optional: Verify no threads have both topic_id and user_id as NULL
    # You might need this if some threads genuinely belong to neither (unlikely now)
    # threads_without_context = from(t in Thread, where: is_nil(t.topic_id) and is_nil(t.user_id)) |> Repo.all()
    # if threads_without_context != [] do
    #   IO.warn("Found #{length(threads_without_context)} threads with NEITHER topic_id NOR user_id set!")
    # end
  end
end
