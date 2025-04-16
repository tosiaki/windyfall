defmodule Windyfall.Repo.Migrations.RemoveAvatarFromUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :avatar, :string
    end
  end
end
