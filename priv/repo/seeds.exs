# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Windyfall.Repo.insert!(%Windyfall.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Windyfall.Messages

Messages.create_topic("Main", "main")
Messages.set_main_topic
Messages.set_message_default_user
