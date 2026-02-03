defmodule Onelist.TrustedMemoryChainTest do
  @moduledoc """
  Tests for memory chain integrity functions in TrustedMemory module.
  """
  use Onelist.DataCase, async: true

  alias Onelist.TrustedMemory
  alias Onelist.Reader.Memory
  alias Onelist.Accounts.User
  alias Onelist.Entries.Entry

  describe "memory_genesis_hash/1" do
    test "generates deterministic hash from chain_id" do
      chain_id = "user:abc123:agent:reader"

      hash1 = TrustedMemory.memory_genesis_hash(chain_id)
      hash2 = TrustedMemory.memory_genesis_hash(chain_id)

      assert hash1 == hash2
      # SHA256 hex is 64 chars
      assert String.length(hash1) == 64
      assert String.match?(hash1, ~r/^[a-f0-9]+$/)
    end

    test "different chain_ids produce different hashes" do
      hash1 = TrustedMemory.memory_genesis_hash("user:abc:agent:reader")
      hash2 = TrustedMemory.memory_genesis_hash("user:xyz:agent:reader")
      hash3 = TrustedMemory.memory_genesis_hash("user:abc:agent:claude-code")

      assert hash1 != hash2
      assert hash1 != hash3
      assert hash2 != hash3
    end
  end

  describe "compute_content_hash/1" do
    test "generates deterministic hash from content" do
      content = "User prefers dark mode"

      hash1 = TrustedMemory.compute_content_hash(content)
      hash2 = TrustedMemory.compute_content_hash(content)

      assert hash1 == hash2
      assert String.length(hash1) == 64
    end

    test "different content produces different hashes" do
      hash1 = TrustedMemory.compute_content_hash("content a")
      hash2 = TrustedMemory.compute_content_hash("content b")

      assert hash1 != hash2
    end

    test "handles nil content" do
      hash = TrustedMemory.compute_content_hash(nil)
      assert String.length(hash) == 64
    end
  end

  describe "calculate_memory_hash/1" do
    test "generates deterministic hash from memory data" do
      timestamp = ~U[2026-02-03 12:00:00.000000Z]

      data = %{
        sequence: 1,
        previous_memory_hash: "abc123",
        chain_id: "user:test:agent:reader",
        content_hash: "def456",
        source_entry_hash: "ghi789",
        canonical_timestamp: timestamp
      }

      hash1 = TrustedMemory.calculate_memory_hash(data)
      hash2 = TrustedMemory.calculate_memory_hash(data)

      assert hash1 == hash2
      assert String.length(hash1) == 64
    end

    test "changing any field produces different hash" do
      timestamp = ~U[2026-02-03 12:00:00.000000Z]

      base = %{
        sequence: 1,
        previous_memory_hash: "abc123",
        chain_id: "user:test:agent:reader",
        content_hash: "def456",
        source_entry_hash: "ghi789",
        canonical_timestamp: timestamp
      }

      base_hash = TrustedMemory.calculate_memory_hash(base)

      # Different sequence
      assert TrustedMemory.calculate_memory_hash(%{base | sequence: 2}) != base_hash

      # Different previous hash
      assert TrustedMemory.calculate_memory_hash(%{base | previous_memory_hash: "xxx"}) !=
               base_hash

      # Different content hash
      assert TrustedMemory.calculate_memory_hash(%{base | content_hash: "xxx"}) != base_hash

      # Different timestamp
      assert TrustedMemory.calculate_memory_hash(%{
               base
               | canonical_timestamp: ~U[2026-02-04 12:00:00.000000Z]
             }) != base_hash
    end
  end

  describe "chain_memories_r1/3" do
    setup do
      user = insert_user(trusted_memory_mode: true)
      entry = insert_entry(user)
      {:ok, user: user, entry: entry}
    end

    test "chains memories with correct sequence numbers", %{user: user, entry: entry} do
      memories = [
        %{content: "fact 1", memory_type: "fact", user_id: user.id, entry_id: entry.id},
        %{content: "fact 2", memory_type: "fact", user_id: user.id, entry_id: entry.id}
      ]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      assert length(chained) == 2
      assert Enum.at(chained, 0).memory_sequence == 1
      assert Enum.at(chained, 1).memory_sequence == 2
    end

    test "links previous_memory_hash correctly", %{user: user, entry: entry} do
      memories = [
        %{content: "fact 1", memory_type: "fact", user_id: user.id, entry_id: entry.id},
        %{content: "fact 2", memory_type: "fact", user_id: user.id, entry_id: entry.id}
      ]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      first = Enum.at(chained, 0)
      second = Enum.at(chained, 1)

      # First memory links to genesis
      chain_id = "user:#{user.id}:agent:reader"
      assert first.previous_memory_hash == TrustedMemory.memory_genesis_hash(chain_id)

      # Second memory links to first
      assert second.previous_memory_hash == first.memory_hash
    end

    test "sets chain_id correctly", %{user: user, entry: entry} do
      memories = [%{content: "fact 1", memory_type: "fact", user_id: user.id, entry_id: entry.id}]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      expected_chain_id = "user:#{user.id}:agent:reader"
      assert Enum.at(chained, 0).chain_id == expected_chain_id
    end

    test "sets source_entry_hash when entry provided", %{user: user, entry: entry} do
      memories = [%{content: "fact 1", memory_type: "fact", user_id: user.id, entry_id: entry.id}]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      assert Enum.at(chained, 0).source_entry_hash == entry.entry_hash
    end

    test "handles nil source_entry", %{user: user} do
      memories = [%{content: "fact 1", memory_type: "fact", user_id: user.id}]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, nil)

      assert Enum.at(chained, 0).source_entry_hash == nil
    end

    test "sets source_agent_id to reader", %{user: user, entry: entry} do
      memories = [%{content: "fact 1", memory_type: "fact", user_id: user.id, entry_id: entry.id}]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      assert Enum.at(chained, 0).source_agent_id == "reader"
    end

    test "computes content_hash for each memory", %{user: user, entry: entry} do
      memories = [
        %{content: "fact 1", memory_type: "fact", user_id: user.id, entry_id: entry.id},
        %{content: "fact 2", memory_type: "fact", user_id: user.id, entry_id: entry.id}
      ]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      assert Enum.at(chained, 0).content_hash == TrustedMemory.compute_content_hash("fact 1")
      assert Enum.at(chained, 1).content_hash == TrustedMemory.compute_content_hash("fact 2")
    end

    test "returns empty list for empty input", %{user: user} do
      {:ok, chained} = TrustedMemory.chain_memories_r1(user, [], nil)
      assert chained == []
    end

    test "continues sequence from existing chain", %{user: user, entry: entry} do
      # Insert existing chained memories
      chain_id = "user:#{user.id}:agent:reader"
      genesis = TrustedMemory.memory_genesis_hash(chain_id)

      existing_hash = insert_chained_memory(user, chain_id, 5, genesis)

      # Chain new memories
      memories = [
        %{content: "new fact", memory_type: "fact", user_id: user.id, entry_id: entry.id}
      ]

      {:ok, chained} = TrustedMemory.chain_memories_r1(user, memories, entry)

      assert Enum.at(chained, 0).memory_sequence == 6
      assert Enum.at(chained, 0).previous_memory_hash == existing_hash
    end
  end

  describe "verify_memory_chain/1" do
    setup do
      user = insert_user(trusted_memory_mode: true)
      chain_id = "user:#{user.id}:agent:reader"
      {:ok, user: user, chain_id: chain_id}
    end

    test "returns :empty_chain for chain with no memories", %{chain_id: chain_id} do
      assert {:ok, :empty_chain} = TrustedMemory.verify_memory_chain(chain_id)
    end

    test "verifies intact single-memory chain", %{user: user, chain_id: chain_id} do
      genesis = TrustedMemory.memory_genesis_hash(chain_id)
      insert_chained_memory(user, chain_id, 1, genesis)

      assert {:ok, :verified} = TrustedMemory.verify_memory_chain(chain_id)
    end

    test "verifies intact multi-memory chain", %{user: user, chain_id: chain_id} do
      genesis = TrustedMemory.memory_genesis_hash(chain_id)
      hash1 = insert_chained_memory(user, chain_id, 1, genesis)
      hash2 = insert_chained_memory(user, chain_id, 2, hash1)
      _hash3 = insert_chained_memory(user, chain_id, 3, hash2)

      assert {:ok, :verified} = TrustedMemory.verify_memory_chain(chain_id)
    end

    test "detects broken chain (wrong previous hash)", %{user: user, chain_id: chain_id} do
      genesis = TrustedMemory.memory_genesis_hash(chain_id)
      _hash1 = insert_chained_memory(user, chain_id, 1, genesis)

      # Insert second memory with wrong previous hash
      insert_chained_memory(user, chain_id, 2, "wrong_hash")

      assert {:error, :broken_chain, details} = TrustedMemory.verify_memory_chain(chain_id)
      assert details.sequence == 2
    end
  end

  describe "verify_reader_chain/1" do
    test "delegates to verify_memory_chain with correct chain_id" do
      user = insert_user(trusted_memory_mode: true)

      # Empty chain should return :empty_chain
      assert {:ok, :empty_chain} = TrustedMemory.verify_reader_chain(user.id)
    end
  end

  describe "get_memory_chain_status/1" do
    test "returns status for empty chain" do
      user = insert_user()
      status = TrustedMemory.get_memory_chain_status(user.id)

      assert status.chain_id == "user:#{user.id}:agent:reader"
      assert status.chain_length == 0
      assert status.memory_count == 0
      assert status.latest_memory_id == nil
    end

    test "returns status for chain with memories" do
      user = insert_user(trusted_memory_mode: true)
      chain_id = "user:#{user.id}:agent:reader"
      genesis = TrustedMemory.memory_genesis_hash(chain_id)

      insert_chained_memory(user, chain_id, 1, genesis)
      insert_chained_memory(user, chain_id, 2, "hash1")

      status = TrustedMemory.get_memory_chain_status(user.id)

      assert status.chain_length == 2
      assert status.memory_count == 2
      assert status.latest_memory_id != nil
    end
  end

  # ============================================
  # Test Helpers
  # ============================================

  defp insert_user(opts \\ []) do
    %User{
      id: Ecto.UUID.generate(),
      email: "test-#{System.unique_integer()}@example.com",
      trusted_memory_mode: Keyword.get(opts, :trusted_memory_mode, false)
    }
    |> Repo.insert!()
  end

  defp insert_entry(user) do
    %Entry{
      id: Ecto.UUID.generate(),
      user_id: user.id,
      entry_type: "note",
      title: "Test Entry",
      public_id: Nanoid.generate(),
      entry_hash: TrustedMemory.compute_content_hash("test content"),
      sequence_number: 1
    }
    |> Repo.insert!()
  end

  defp insert_chained_memory(user, chain_id, sequence, previous_hash) do
    content = "Memory content #{sequence}"
    content_hash = TrustedMemory.compute_content_hash(content)
    canonical_ts = DateTime.utc_now()

    memory_hash =
      TrustedMemory.calculate_memory_hash(%{
        sequence: sequence,
        previous_memory_hash: previous_hash,
        chain_id: chain_id,
        content_hash: content_hash,
        source_entry_hash: nil,
        canonical_timestamp: canonical_ts
      })

    %Memory{
      id: Ecto.UUID.generate(),
      user_id: user.id,
      content: content,
      memory_type: "fact",
      memory_sequence: sequence,
      previous_memory_hash: previous_hash,
      memory_hash: memory_hash,
      chain_id: chain_id,
      content_hash: content_hash,
      canonical_timestamp: canonical_ts,
      is_current: true
    }
    |> Repo.insert!()

    memory_hash
  end
end
