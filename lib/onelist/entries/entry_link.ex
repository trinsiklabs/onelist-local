defmodule Onelist.Entries.EntryLink do
  @moduledoc """
  Schema for linking entries together.

  Entry links represent relationships between entries such as:
  - Forum topic → replies (has_reply)
  - Nested reply → parent reply (reply_to)
  - Comments on entries (comment_on)
  - Copy/derivative tracking (derived_from)
  - Reference/citation tracking (cites)
  - General relationships (related_to)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @link_types ~w(has_reply reply_to comment_on derived_from cites related_to has_extracted_item contains contained_by blocks blocked_by delivers)

  schema "entry_links" do
    field :link_type, :string
    field :metadata, :map, default: %{}

    belongs_to :source_entry, Onelist.Entries.Entry
    belongs_to :target_entry, Onelist.Entries.Entry

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for an entry link.

  ## Required fields
  - `source_entry_id` - The ID of the entry linking FROM
  - `target_entry_id` - The ID of the entry linking TO
  - `link_type` - The type of relationship

  ## Optional fields
  - `metadata` - Additional data (e.g., reply_order, created_at)
  """
  def changeset(entry_link, attrs) do
    entry_link
    |> cast(attrs, [:source_entry_id, :target_entry_id, :link_type, :metadata])
    |> validate_required([:source_entry_id, :target_entry_id, :link_type])
    |> validate_inclusion(:link_type, @link_types)
    |> foreign_key_constraint(:source_entry_id)
    |> foreign_key_constraint(:target_entry_id)
    |> unique_constraint([:source_entry_id, :target_entry_id, :link_type])
  end

  @doc """
  Returns the list of valid link types.

  ## Link Types
  - `has_reply` - Forum topic → reply (Topic sources, Reply targets)
  - `reply_to` - Nested reply → parent reply (Child sources, Parent targets)
  - `comment_on` - Comment → any entry (Comment sources, Entry targets)
  - `derived_from` - Copy/derivative tracking (New sources, Original targets)
  - `cites` - Reference tracking (Citing sources, Cited targets)
  - `related_to` - General relationship (Bidirectional)
  - `has_extracted_item` - Entry → extracted item (Parent sources, Item targets)
  - `contains` - Container → contained item (Sprint/Project sources, Task/Item targets)
  - `contained_by` - Inverse of contains (Item sources, Container targets)
  - `blocks` - Blocking item → blocked item (Blocker sources, Blocked targets)
  - `blocked_by` - Inverse of blocks (Blocked sources, Blocker targets)
  - `delivers` - Deliverable → parent goal (Deliverable sources, Goal targets)
  """
  def link_types, do: @link_types

  @doc """
  Returns the inverse link type for bidirectional queries.

  This is useful when you want to find the corresponding link
  in the opposite direction.

  ## Examples

      iex> inverse_type("has_reply")
      "reply_to"

      iex> inverse_type("reply_to")
      "has_reply"

      iex> inverse_type("related_to")
      "related_to"

      iex> inverse_type("comment_on")
      nil
  """
  def inverse_type("has_reply"), do: "reply_to"
  def inverse_type("reply_to"), do: "has_reply"
  def inverse_type("related_to"), do: "related_to"
  def inverse_type("contains"), do: "contained_by"
  def inverse_type("contained_by"), do: "contains"
  def inverse_type("blocks"), do: "blocked_by"
  def inverse_type("blocked_by"), do: "blocks"
  def inverse_type(_), do: nil
end
