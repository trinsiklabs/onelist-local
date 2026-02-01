defmodule Onelist.Repo.Migrations.AddEnrichmentSupport do
  use Ecto.Migration

  def change do
    alter table(:search_configs) do
      add :auto_enrich_enabled, :boolean, default: true
      add :max_enrichment_tier, :integer, default: 2
      add :enrichment_settings, :map, default: %{}
      add :daily_enrichment_budget_cents, :integer
      add :spent_enrichment_today_cents, :integer, default: 0
      add :enrichment_budget_reset_at, :utc_datetime_usec
    end
  end
end
