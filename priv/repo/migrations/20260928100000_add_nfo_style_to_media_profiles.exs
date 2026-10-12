defmodule Pinchflat.Repo.Migrations.AddNfoStyleToMediaProfiles do
  use Ecto.Migration

  def change do
    alter table(:media_profiles) do
      add :nfo_style, :string, null: false, default: "episode"
    end
  end
end
