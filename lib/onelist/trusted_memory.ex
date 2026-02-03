defmodule Onelist.TrustedMemory do
  @moduledoc """
  Trusted Memory system for AI accounts.

  Provides append-only, tamper-evident memory storage that AI agents can trust.

  Key features:
  - Entries can only be created, never edited or deleted
  - Each entry is cryptographically linked to previous entries (hash chain)
  - All operations are logged immutably
  - Integrity can be verified at any time

  ## Usage

      # Check if user has trusted memory enabled
      TrustedMemory.enabled?(user)

      # Create an entry with hash chain
      TrustedMemory.create_entry(user, %{title: "...", content: "..."})

      # Verify chain integrity
      TrustedMemory.verify_chain(user.id)

      # Log an operation attempt
      TrustedMemory.log_operation(user.id, entry_id, "attempted_delete", "denied")
  """

  import Ecto.Query
  alias Onelist.Repo
  alias Onelist.Accounts.User
  alias Onelist.Entries.Entry
  alias Onelist.TrustedMemory.AuditLog
  alias Onelist.Reader.Memory

  require Logger

  @genesis_hash "genesis:onelist:trusted-memory:v1"
  @memory_genesis_hash "genesis:onelist:memory-chain:v1"

  # ============================================
  # GUARDS
  # ============================================

  @doc """
  Check if user has trusted memory mode enabled.
  """
  def enabled?(%User{trusted_memory_mode: true}), do: true
  def enabled?(%User{}), do: false
  def enabled?(nil), do: false

  @doc """
  Check if user is an AI account.
  """
  def ai_account?(%User{account_type: "ai"}), do: true
  def ai_account?(%User{}), do: false

  @doc """
  Guards entry update - returns error for trusted memory accounts.
  """
  def guard_update(%User{} = user, entry_id) do
    if enabled?(user) do
      log_operation(user.id, entry_id, "attempted_edit", "denied", %{
        reason: "Trusted memory mode prevents edits"
      })

      {:error, :trusted_memory_immutable}
    else
      :ok
    end
  end

  @doc """
  Guards entry deletion - returns error for trusted memory accounts.
  """
  def guard_delete(%User{} = user, entry_id) do
    if enabled?(user) do
      log_operation(user.id, entry_id, "attempted_delete", "denied", %{
        reason: "Trusted memory mode prevents deletions"
      })

      {:error, :trusted_memory_immutable}
    else
      :ok
    end
  end

  # ============================================
  # HASH CHAIN
  # ============================================

  @doc """
  Create an entry with hash chain for trusted memory accounts.
  """
  def create_entry(%User{} = user, attrs) do
    if enabled?(user) do
      create_chained_entry(user, attrs)
    else
      # Regular entry creation (no chain)
      {:ok, :not_trusted_memory}
    end
  end

  defp create_chained_entry(user, attrs) do
    # Get the latest entry for this user
    previous = get_latest_entry(user.id)

    # Calculate sequence number
    sequence = if previous, do: previous.sequence_number + 1, else: 1

    # Get previous hash
    prev_hash = if previous, do: previous.entry_hash, else: genesis_hash(user.id)

    # Canonical timestamp
    canonical_ts = DateTime.utc_now()

    # Build entry data with chain fields
    chain_attrs = %{
      sequence_number: sequence,
      previous_entry_hash: prev_hash,
      canonical_timestamp: canonical_ts
    }

    # Calculate content hash (for the entry_hash)
    content = Map.get(attrs, :content, Map.get(attrs, "content", ""))
    title = Map.get(attrs, :title, Map.get(attrs, "title", ""))

    entry_hash =
      calculate_entry_hash(%{
        sequence: sequence,
        previous: prev_hash,
        timestamp: canonical_ts,
        title: title,
        content: content
      })

    final_attrs =
      attrs
      |> Map.merge(chain_attrs)
      |> Map.put(:entry_hash, entry_hash)

    {:ok, final_attrs}
  end

  @doc """
  Get the latest entry for a user (by sequence number).
  """
  def get_latest_entry(user_id) do
    Entry
    |> where([e], e.user_id == ^user_id and not is_nil(e.sequence_number))
    |> order_by([e], desc: e.sequence_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Calculate hash for an entry.
  """
  def calculate_entry_hash(data) do
    canonical = %{
      sequence: data.sequence,
      previous: data.previous,
      timestamp: DateTime.to_iso8601(data.timestamp),
      content_hash: hash_content(data.title, data.content)
    }

    :crypto.hash(:sha256, Jason.encode!(canonical))
    |> Base.encode16(case: :lower)
  end

  defp hash_content(title, content) do
    :crypto.hash(:sha256, "#{title || ""}:#{content || ""}")
    |> Base.encode16(case: :lower)
  end

  defp genesis_hash(user_id) do
    :crypto.hash(:sha256, "#{@genesis_hash}:#{user_id}")
    |> Base.encode16(case: :lower)
  end

  # ============================================
  # VERIFICATION
  # ============================================

  @doc """
  Verify the integrity of the entire hash chain for a user.
  """
  def verify_chain(user_id) do
    entries =
      Entry
      |> where([e], e.user_id == ^user_id and not is_nil(e.sequence_number))
      |> order_by([e], asc: e.sequence_number)
      |> Repo.all()

    if Enum.empty?(entries) do
      {:ok, :empty_chain}
    else
      verify_chain_entries(entries, genesis_hash(user_id), user_id)
    end
  end

  defp verify_chain_entries([], _prev_hash, _user_id), do: {:ok, :verified}

  defp verify_chain_entries([entry | rest], expected_prev_hash, user_id) do
    cond do
      entry.previous_entry_hash != expected_prev_hash ->
        {:error, :broken_chain,
         %{
           entry_id: entry.id,
           expected: expected_prev_hash,
           got: entry.previous_entry_hash
         }}

      true ->
        # Continue with this entry's hash as the next expected previous
        verify_chain_entries(rest, entry.entry_hash, user_id)
    end
  end

  # ============================================
  # AUDIT LOGGING
  # ============================================

  @doc """
  Log a memory operation.
  """
  def log_operation(user_id, entry_id, action, outcome, details \\ %{}) do
    %AuditLog{}
    |> AuditLog.changeset(%{
      user_id: user_id,
      entry_id: entry_id,
      action: action,
      outcome: outcome,
      details: details,
      actor: "system"
    })
    |> Repo.insert()
  end

  @doc """
  Get audit log for a user.
  """
  def get_audit_log(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    AuditLog
    |> where([l], l.user_id == ^user_id)
    |> order_by([l], desc: l.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ============================================
  # CHECKPOINTS & ROLLBACK
  # ============================================

  alias Onelist.TrustedMemory.Checkpoint

  @doc """
  Create a rollback checkpoint. Requires human authorization.

  After this checkpoint is created, queries using `get_canonical_entries/1`
  will only return entries with sequence_number <= the checkpoint's after_sequence.

  ## Options
    * `:authorized_by` - Required, must be "human" for rollback checkpoints
    * `:reason` - Human-readable reason for the rollback
  """
  def create_rollback(user_id, opts \\ []) do
    authorized_by = Keyword.get(opts, :authorized_by)
    reason = Keyword.get(opts, :reason, "Manual rollback")

    unless authorized_by == "human" do
      {:error, :human_authorization_required}
    else
      # Get the latest entry to determine after_sequence
      latest = get_latest_entry(user_id)

      if is_nil(latest) || is_nil(latest.sequence_number) do
        {:error, :no_chained_entries}
      else
        %Checkpoint{}
        |> Checkpoint.changeset(%{
          user_id: user_id,
          checkpoint_type: "rollback",
          after_sequence: latest.sequence_number,
          created_by: "human",
          authorized_by: "human",
          reason: reason
        })
        |> Repo.insert()
        |> case do
          {:ok, checkpoint} ->
            log_operation(user_id, nil, "rollback_created", "success", %{
              checkpoint_id: checkpoint.id,
              after_sequence: checkpoint.after_sequence,
              reason: reason
            })

            {:ok, checkpoint}

          error ->
            error
        end
      end
    end
  end

  @doc """
  Create a rollback to a specific sequence number.
  """
  def create_rollback_to(user_id, sequence_number, opts \\ []) do
    authorized_by = Keyword.get(opts, :authorized_by)
    reason = Keyword.get(opts, :reason, "Manual rollback to sequence #{sequence_number}")

    unless authorized_by == "human" do
      {:error, :human_authorization_required}
    else
      %Checkpoint{}
      |> Checkpoint.changeset(%{
        user_id: user_id,
        checkpoint_type: "rollback",
        after_sequence: sequence_number,
        created_by: "human",
        authorized_by: "human",
        reason: reason
      })
      |> Repo.insert()
      |> case do
        {:ok, checkpoint} ->
          log_operation(user_id, nil, "rollback_created", "success", %{
            checkpoint_id: checkpoint.id,
            after_sequence: checkpoint.after_sequence,
            reason: reason
          })

          {:ok, checkpoint}

        error ->
          error
      end
    end
  end

  @doc """
  Get the active checkpoint for a user, if any.
  """
  def get_active_checkpoint(user_id) do
    Checkpoint
    |> where([c], c.user_id == ^user_id and c.active == true)
    |> order_by([c], desc: c.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Get canonical entries for a user, respecting any active checkpoint.

  If a rollback checkpoint is active, only entries with 
  sequence_number <= checkpoint.after_sequence are returned.
  """
  def get_canonical_entries(user_id, opts \\ []) do
    checkpoint = get_active_checkpoint(user_id)
    limit = Keyword.get(opts, :limit)

    query =
      Entry
      |> where([e], e.user_id == ^user_id)
      |> order_by([e], asc: e.sequence_number)

    # Apply checkpoint filter if active
    query =
      if checkpoint do
        where(
          query,
          [e],
          is_nil(e.sequence_number) or e.sequence_number <= ^checkpoint.after_sequence
        )
      else
        query
      end

    # Apply limit if specified
    query = if limit, do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  @doc """
  Get the count of entries hidden by the active checkpoint.
  """
  def get_hidden_entry_count(user_id) do
    checkpoint = get_active_checkpoint(user_id)

    if checkpoint do
      Entry
      |> where([e], e.user_id == ^user_id and e.sequence_number > ^checkpoint.after_sequence)
      |> Repo.aggregate(:count)
    else
      0
    end
  end

  @doc """
  Recover from a rollback by deactivating the checkpoint.

  This restores visibility of all entries. Requires human authorization.
  """
  def recover(user_id, opts \\ []) do
    authorized_by = Keyword.get(opts, :authorized_by)

    unless authorized_by == "human" do
      {:error, :human_authorization_required}
    else
      checkpoint = get_active_checkpoint(user_id)

      if is_nil(checkpoint) do
        {:error, :no_active_checkpoint}
      else
        checkpoint
        |> Checkpoint.deactivate_changeset()
        |> Repo.update()
        |> case do
          {:ok, deactivated} ->
            log_operation(user_id, nil, "recovery", "success", %{
              checkpoint_id: deactivated.id,
              original_after_sequence: deactivated.after_sequence
            })

            {:ok, deactivated}

          error ->
            error
        end
      end
    end
  end

  @doc """
  Get all checkpoints for a user (active and inactive).
  """
  def list_checkpoints(user_id, opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query =
      Checkpoint
      |> where([c], c.user_id == ^user_id)
      |> order_by([c], desc: c.inserted_at)

    query =
      if include_inactive do
        query
      else
        where(query, [c], c.active == true)
      end

    Repo.all(query)
  end

  @doc """
  Get memory status for a user - useful for API/UI.
  """
  def get_status(user_id) do
    latest = get_latest_entry(user_id)
    checkpoint = get_active_checkpoint(user_id)
    hidden_count = get_hidden_entry_count(user_id)

    %{
      chain_length: if(latest, do: latest.sequence_number, else: 0),
      latest_entry_id: if(latest, do: latest.id, else: nil),
      latest_hash: if(latest, do: latest.entry_hash, else: nil),
      has_active_checkpoint: not is_nil(checkpoint),
      checkpoint_after_sequence: if(checkpoint, do: checkpoint.after_sequence, else: nil),
      hidden_entries: hidden_count,
      genesis_hash: genesis_hash(user_id)
    }
  end

  # ============================================
  # MEMORY CHAIN INTEGRITY (R1)
  # ============================================

  @doc """
  Calculate the genesis hash for a memory chain.

  Each chain has its own genesis hash derived from the chain_id.
  The hash is deterministic - the same chain_id always produces the same genesis hash.

  ## Examples

      iex> hash1 = Onelist.TrustedMemory.memory_genesis_hash("user:abc:agent:reader")
      iex> hash2 = Onelist.TrustedMemory.memory_genesis_hash("user:abc:agent:reader")
      iex> hash1 == hash2
      true

      iex> hash = Onelist.TrustedMemory.memory_genesis_hash("user:abc:agent:reader")
      iex> String.length(hash)
      64

      iex> hash = Onelist.TrustedMemory.memory_genesis_hash("user:abc:agent:reader")
      iex> String.match?(hash, ~r/^[a-f0-9]+$/)
      true

  """
  def memory_genesis_hash(chain_id) do
    :crypto.hash(:sha256, "#{@memory_genesis_hash}:#{chain_id}")
    |> Base.encode16(case: :lower)
  end

  @doc """
  Calculate the hash for a memory.

  The hash is computed from a canonical JSON representation of:
  - sequence: The memory's position in the chain
  - previous: The previous memory's hash
  - chain_id: The chain identifier
  - content_hash: SHA256 of the memory content
  - source_entry_hash: Hash of the source entry (if any)
  - timestamp: ISO8601 canonical timestamp

  ## Examples

      iex> data = %{
      ...>   sequence: 1,
      ...>   previous_memory_hash: "abc123",
      ...>   chain_id: "user:test:agent:reader",
      ...>   content_hash: "def456",
      ...>   source_entry_hash: nil,
      ...>   canonical_timestamp: ~U[2026-02-03 12:00:00.000000Z]
      ...> }
      iex> hash = Onelist.TrustedMemory.calculate_memory_hash(data)
      iex> String.length(hash)
      64

      iex> data = %{
      ...>   sequence: 1,
      ...>   previous_memory_hash: "abc123",
      ...>   chain_id: "user:test:agent:reader",
      ...>   content_hash: "def456",
      ...>   source_entry_hash: nil,
      ...>   canonical_timestamp: ~U[2026-02-03 12:00:00.000000Z]
      ...> }
      iex> hash1 = Onelist.TrustedMemory.calculate_memory_hash(data)
      iex> hash2 = Onelist.TrustedMemory.calculate_memory_hash(data)
      iex> hash1 == hash2
      true

  """
  def calculate_memory_hash(data) do
    canonical = %{
      sequence: data.sequence,
      previous: data.previous_memory_hash,
      chain_id: data.chain_id,
      content_hash: data.content_hash,
      source_entry_hash: data.source_entry_hash,
      timestamp: DateTime.to_iso8601(data.canonical_timestamp)
    }

    :crypto.hash(:sha256, Jason.encode!(canonical))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Compute the SHA256 content hash for a memory.

  This hash is used as part of the memory chain hash calculation to ensure
  content integrity. The hash is deterministic and handles nil content gracefully.

  ## Examples

      iex> hash1 = Onelist.TrustedMemory.compute_content_hash("Hello, World!")
      iex> hash2 = Onelist.TrustedMemory.compute_content_hash("Hello, World!")
      iex> hash1 == hash2
      true

      iex> hash = Onelist.TrustedMemory.compute_content_hash("test")
      iex> String.length(hash)
      64

      iex> Onelist.TrustedMemory.compute_content_hash("a") != Onelist.TrustedMemory.compute_content_hash("b")
      true

      iex> hash = Onelist.TrustedMemory.compute_content_hash(nil)
      iex> String.length(hash)
      64

  """
  def compute_content_hash(content) do
    :crypto.hash(:sha256, content || "")
    |> Base.encode16(case: :lower)
  end

  @doc """
  Chain memories for the Reader agent (R1 - single agent only).

  This function:
  1. Gets the latest memory in the reader chain
  2. Calculates sequence numbers and hashes for each new memory
  3. Links each memory to the previous one in the chain
  4. Returns the memories with chain fields populated

  ## Parameters
  - `user` - The user who owns these memories
  - `memories` - List of memory maps to chain
  - `source_entry` - Optional entry these memories were extracted from

  ## Returns
  - `{:ok, chained_memories}` - List with chain fields populated
  - `{:error, reason}` - If chaining fails
  """
  def chain_memories_r1(%User{} = user, memories, source_entry \\ nil) do
    if Enum.empty?(memories) do
      {:ok, []}
    else
      chain_id = "user:#{user.id}:agent:reader"
      source_entry_hash = if source_entry, do: source_entry.entry_hash, else: nil

      try do
        do_chain_memories_r1(memories, chain_id, source_entry_hash)
      rescue
        e ->
          Logger.error("Failed to chain memories: #{inspect(e)}")
          {:error, {:chain_failed, e}}
      end
    end
  end

  defp do_chain_memories_r1(memories, chain_id, source_entry_hash) do
    # Get latest memory in chain
    latest = get_latest_memory_in_chain(chain_id)
    base_sequence = if latest, do: latest.memory_sequence, else: 0
    prev_hash = if latest, do: latest.memory_hash, else: memory_genesis_hash(chain_id)

    canonical_ts = DateTime.utc_now()

    {chained, _} =
      Enum.map_reduce(memories, {base_sequence, prev_hash}, fn mem, {seq, prev} ->
        seq = seq + 1

        # Compute content hash
        content = mem[:content] || mem["content"] || ""
        content_hash = compute_content_hash(content)

        # Calculate memory hash
        hash =
          calculate_memory_hash(%{
            sequence: seq,
            previous_memory_hash: prev,
            chain_id: chain_id,
            content_hash: content_hash,
            source_entry_hash: source_entry_hash,
            canonical_timestamp: canonical_ts
          })

        # Build chained memory map
        chained_mem =
          mem
          |> Map.put(:memory_sequence, seq)
          |> Map.put(:previous_memory_hash, prev)
          |> Map.put(:memory_hash, hash)
          |> Map.put(:chain_id, chain_id)
          |> Map.put(:source_entry_hash, source_entry_hash)
          |> Map.put(:canonical_timestamp, canonical_ts)
          |> Map.put(:content_hash, content_hash)
          |> Map.put(:source_agent_id, "reader")

        {chained_mem, {seq, hash}}
      end)

    {:ok, chained}
  end

  @doc """
  Get the latest memory in a specific chain.
  """
  def get_latest_memory_in_chain(chain_id) do
    Memory
    |> where([m], m.chain_id == ^chain_id)
    |> where([m], not is_nil(m.memory_sequence))
    |> order_by([m], desc: m.memory_sequence)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Verify the Reader's memory chain for a user.

  Convenience function that verifies the "user:{id}:agent:reader" chain.
  """
  def verify_reader_chain(user_id) do
    chain_id = "user:#{user_id}:agent:reader"
    verify_memory_chain(chain_id)
  end

  @doc """
  Verify a specific memory chain.

  Walks through all memories in the chain in sequence order, verifying:
  1. Each memory's previous_memory_hash matches the predecessor's memory_hash
  2. Each memory's memory_hash can be recomputed from its fields

  ## Returns
  - `{:ok, :verified}` - Chain is intact
  - `{:ok, :empty_chain}` - No chained memories exist
  - `{:error, :broken_chain, details}` - Previous hash doesn't match
  - `{:error, :hash_mismatch, details}` - Computed hash doesn't match stored hash
  """
  def verify_memory_chain(chain_id) do
    memories =
      Memory
      |> where([m], m.chain_id == ^chain_id)
      |> where([m], not is_nil(m.memory_sequence))
      |> order_by([m], asc: m.memory_sequence)
      |> Repo.all()

    if Enum.empty?(memories) do
      {:ok, :empty_chain}
    else
      do_verify_memory_chain(memories, memory_genesis_hash(chain_id))
    end
  end

  defp do_verify_memory_chain([], _prev_hash), do: {:ok, :verified}

  defp do_verify_memory_chain([memory | rest], expected_prev_hash) do
    cond do
      # Check previous hash link
      memory.previous_memory_hash != expected_prev_hash ->
        {:error, :broken_chain,
         %{
           memory_id: memory.id,
           sequence: memory.memory_sequence,
           expected_previous: expected_prev_hash,
           got_previous: memory.previous_memory_hash
         }}

      # Verify the hash itself is correct
      true ->
        computed =
          calculate_memory_hash(%{
            sequence: memory.memory_sequence,
            previous_memory_hash: memory.previous_memory_hash,
            chain_id: memory.chain_id,
            content_hash: memory.content_hash,
            source_entry_hash: memory.source_entry_hash,
            canonical_timestamp: memory.canonical_timestamp
          })

        if computed != memory.memory_hash do
          {:error, :hash_mismatch,
           %{
             memory_id: memory.id,
             sequence: memory.memory_sequence,
             expected_hash: computed,
             got_hash: memory.memory_hash
           }}
        else
          do_verify_memory_chain(rest, memory.memory_hash)
        end
    end
  end

  @doc """
  Get memory chain status for a user.

  Returns information about the Reader's memory chain.
  """
  def get_memory_chain_status(user_id) do
    chain_id = "user:#{user_id}:agent:reader"
    latest = get_latest_memory_in_chain(chain_id)

    memory_count =
      Memory
      |> where([m], m.chain_id == ^chain_id)
      |> where([m], not is_nil(m.memory_sequence))
      |> Repo.aggregate(:count)

    unchained_count =
      Memory
      |> where([m], m.user_id == ^user_id)
      |> where([m], is_nil(m.chain_id))
      |> Repo.aggregate(:count)

    %{
      chain_id: chain_id,
      chain_length: if(latest, do: latest.memory_sequence, else: 0),
      memory_count: memory_count,
      unchained_count: unchained_count,
      latest_memory_id: if(latest, do: latest.id, else: nil),
      latest_hash: if(latest, do: latest.memory_hash, else: nil),
      genesis_hash: memory_genesis_hash(chain_id)
    }
  end
end
