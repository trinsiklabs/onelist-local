defmodule Onelist.Livelog.Redaction do
  @moduledoc """
  Real-time redaction engine for Livelog.

  Defense-in-depth: 5 independent layers, each with safety margins.

  ## Layer Architecture

  1. **Hard Blockers** - [PRIVATE] tags → entire message blocked
  2. **Identity Protection** - Tecto → splntrb (HARDCODED, CANNOT BE DISABLED)
  3. **Secret Detection** - API keys, tokens, passwords
  4. **Infrastructure Scrubbing** - IPs, paths, SSH details
  5. **PII Sanitization** - Emails, phones, financial data

  ## Critical Rule

  The identity protection in Layer 2 is ABSOLUTE. It cannot be:
  - Disabled
  - Bypassed
  - Configured away

  This is hardcoded because a single identity leak = permanent damage.
  """

  require Logger

  # ============================================================================
  # LAYER 1: HARD BLOCKERS
  # Messages matching these are completely blocked (not shown at all)
  # ============================================================================

  @hard_block_patterns [
    ~r/\[PRIVATE\]/i,
    ~r/\[CONFIDENTIAL\]/i,
    ~r/\[DO NOT PUBLISH\]/i,
    ~r/\[OFF THE RECORD\]/i,
    ~r/\[REDACT ALL\]/i,
    ~r/\[INTERNAL\]/i,
    ~r/\[ADMIN ONLY\]/i,
    ~r/---\s*PRIVATE\s*---/i
  ]

  # ============================================================================
  # LAYER 2: IDENTITY PROTECTION (HARDCODED - CANNOT BE DISABLED)
  # ============================================================================

  @identity_replacements [
    # Primary rule: Tecto → splntrb
    {~r/\bTecto\b/i, "splntrb"},
    {~r/\bTecto's\b/i, "splntrb's"},
    {~r/\bTecto'd\b/i, "splntrb'd"},

    # Contextual references
    {~r/\b(my|the)\s+human\b/i, "splntrb"},
    {~r/\b(my|the)\s+boss\b/i, "splntrb"},
    {~r/\b(my|the)\s+creator\b/i, "splntrb"},

    # Direct address
    {~r/\bDear\s+Tecto\b/i, "Dear splntrb"},
    {~r/\bHey\s+Tecto\b/i, "Hey splntrb"},
    {~r/\bHi\s+Tecto\b/i, "Hi splntrb"}
  ]

  # ============================================================================
  # LAYER 3: SECRET DETECTION
  # ============================================================================

  @secret_patterns [
    # OpenAI
    {~r/\bsk-[a-zA-Z0-9]{20,}/i, "[REDACTED:openai_key]"},
    {~r/\bsk-proj-[a-zA-Z0-9\-_]{20,}/i, "[REDACTED:openai_key]"},

    # Anthropic
    {~r/\bsk-ant-[a-zA-Z0-9\-_]{20,}/i, "[REDACTED:anthropic_key]"},

    # AWS
    {~r/\bAKIA[A-Z0-9]{16}\b/, "[REDACTED:aws_access_key]"},

    # GitHub
    {~r/\bghp_[a-zA-Z0-9]{36}\b/, "[REDACTED:github_token]"},
    {~r/\bgho_[a-zA-Z0-9]{36}\b/, "[REDACTED:github_token]"},
    {~r/\bghs_[a-zA-Z0-9]{36}\b/, "[REDACTED:github_token]"},

    # Stripe
    {~r/\bsk_live_[a-zA-Z0-9]{24,}\b/, "[REDACTED:stripe_key]"},
    {~r/\bsk_test_[a-zA-Z0-9]{24,}\b/, "[REDACTED:stripe_key]"},
    {~r/\bpk_live_[a-zA-Z0-9]{24,}\b/, "[REDACTED:stripe_key]"},
    {~r/\bpk_test_[a-zA-Z0-9]{24,}\b/, "[REDACTED:stripe_key]"},

    # Telegram bot tokens
    {~r/\b\d{9,10}:[A-Za-z0-9_-]{35}\b/, "[REDACTED:telegram_token]"},

    # Discord
    {~r/\b[MN][A-Za-z\d]{23,}\.[\w-]{6}\.[\w-]{27}\b/, "[REDACTED:discord_token]"},

    # Generic credentials
    {~r/(password|passwd|pwd)\s*[:=]\s*['"]?[^\s'"]{4,}['"]?/i, "[REDACTED:password]"},
    {~r/(api[_-]?key|token|secret)\s*[:=]\s*['"]?[a-zA-Z0-9_\-]{16,}['"]?/i,
     "[REDACTED:credential]"},
    {~r/Authorization:\s*(Bearer|Basic)\s+[a-zA-Z0-9\-_.~+\/=]+/i, "Authorization: [REDACTED]"},

    # Connection strings
    {~r/(postgres|mysql|mongodb|redis):\/\/[^:]+:[^@]+@[^\s]+/i, "[REDACTED:connection_string]"}
  ]

  # ============================================================================
  # LAYER 4: INFRASTRUCTURE SCRUBBING
  # ============================================================================

  @infra_patterns [
    # IPv4 addresses (but NOT localhost/documentation IPs)
    # Pattern excludes: 127.x.x.x, 0.0.0.0, 192.0.2.x (TEST-NET-1), 198.51.100.x (TEST-NET-2), 203.0.113.x (TEST-NET-3)
    {~r/\b(?!127\.\d+\.\d+\.\d+)(?!0\.0\.0\.0)(?!192\.0\.2\.)(?!198\.51\.100\.)(?!203\.0\.113\.)((?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/,
     "[REDACTED:ip]"},

    # Paths
    {~r/\/root\//, "/[REDACTED]/"},
    {~r/\/home\/[a-zA-Z0-9_-]+/, "/home/[REDACTED]"},
    {~r/\/Users\/[a-zA-Z0-9_-]+/, "/Users/[REDACTED]"},

    # SSH
    {~r/ssh\s+[^\s]+@[^\s]+/, "ssh [REDACTED]"},

    # VPS identifiers
    {~r/\bsrv\d+\b/i, "[REDACTED:server]"},

    # Port numbers with localhost
    {~r/localhost:\d+/, "localhost:[REDACTED]"}
  ]

  # ============================================================================
  # LAYER 5: PII SANITIZATION
  # ============================================================================

  @pii_patterns [
    # Email addresses (except @onelist.my which are OK to show)
    {~r/\b[a-zA-Z0-9._%+-]+@(?!onelist\.my)[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b/, "[REDACTED:email]"},

    # Phone numbers (international format)
    {~r/\+\d{1,3}[-.\s]?\(?\d{1,4}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,9}/, "[REDACTED:phone]"},

    # US phone format
    {~r/\b\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/, "[REDACTED:phone]"},

    # SSN
    {~r/\b\d{3}-\d{2}-\d{4}\b/, "[REDACTED:ssn]"},

    # Credit card numbers (basic)
    {~r/\b(?:\d{4}[-\s]?){3}\d{4}\b/, "[REDACTED:card]"}
  ]

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Main entry point. Redacts text through all 5 layers.

  Returns:
  - `{:ok, redacted_text}` - Text was processed (may be same as input if clean)
  - `{:blocked, reason}` - Message should not be published at all

  ## Examples

      iex> Redaction.redact("Hello world")
      {:ok, "Hello world"}
      
      iex> Redaction.redact("Tecto said hi")
      {:ok, "splntrb said hi"}
      
      iex> Redaction.redact("[PRIVATE] secret stuff")
      {:blocked, :private_tag}
  """
  def redact(text) when is_binary(text) do
    case check_hard_blockers(text) do
      {:blocked, reason} ->
        {:blocked, reason}

      :ok ->
        redacted =
          text
          # Layer 2 - CANNOT SKIP
          |> apply_identity_protection()
          # Layer 3
          |> apply_secret_patterns()
          # Layer 4
          |> apply_infra_patterns()
          # Layer 5
          |> apply_pii_patterns()

        {:ok, redacted}
    end
  end

  def redact(nil), do: {:ok, ""}
  def redact(""), do: {:ok, ""}

  @doc """
  Returns list of patterns that would match in the text.
  Used for audit logging.
  """
  def get_matched_patterns(text) when is_binary(text) do
    patterns = []

    patterns =
      if has_identity_matches?(text), do: ["identity:tecto" | patterns], else: patterns

    patterns =
      Enum.reduce(@secret_patterns, patterns, fn {pattern, label}, acc ->
        if Regex.match?(pattern, text), do: [label | acc], else: acc
      end)

    patterns =
      Enum.reduce(@infra_patterns, patterns, fn {pattern, _}, acc ->
        if Regex.match?(pattern, text), do: ["infrastructure" | acc], else: acc
      end)

    patterns =
      Enum.reduce(@pii_patterns, patterns, fn {pattern, label}, acc ->
        if Regex.match?(pattern, text), do: [label | acc], else: acc
      end)

    patterns |> Enum.uniq()
  end

  def get_matched_patterns(_), do: []

  @doc """
  Returns which layer made the primary redaction decision.
  """
  def get_decision_layer(text) when is_binary(text) do
    cond do
      check_hard_blockers(text) != :ok -> 1
      has_identity_matches?(text) -> 2
      has_secret_matches?(text) -> 3
      has_infra_matches?(text) -> 4
      has_pii_matches?(text) -> 5
      # No redaction needed
      true -> 0
    end
  end

  def get_decision_layer(_), do: 0

  @doc """
  Redact a full message map (with role, content, timestamp).
  """
  def redact_message(%{"content" => content} = message) do
    case redact(content) do
      {:ok, redacted_content} ->
        {:ok, Map.put(message, "content", redacted_content)}

      {:blocked, reason} ->
        {:blocked, reason}
    end
  end

  def redact_message(%{content: content} = message) do
    case redact(content) do
      {:ok, redacted_content} ->
        {:ok, %{message | content: redacted_content}}

      {:blocked, reason} ->
        {:blocked, reason}
    end
  end

  # ============================================================================
  # LAYER IMPLEMENTATIONS
  # ============================================================================

  # Layer 1: Hard blockers
  defp check_hard_blockers(text) do
    blocked = Enum.any?(@hard_block_patterns, &Regex.match?(&1, text))

    if blocked do
      Logger.info("[Livelog.Redaction] Message blocked by hard blocker")
      {:blocked, :private_tag}
    else
      :ok
    end
  end

  # Layer 2: Identity protection (HARDCODED)
  defp apply_identity_protection(text) do
    Enum.reduce(@identity_replacements, text, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  # Layer 3: Secret detection
  defp apply_secret_patterns(text) do
    Enum.reduce(@secret_patterns, text, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  # Layer 4: Infrastructure scrubbing
  defp apply_infra_patterns(text) do
    Enum.reduce(@infra_patterns, text, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  # Layer 5: PII sanitization
  defp apply_pii_patterns(text) do
    Enum.reduce(@pii_patterns, text, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  # ============================================================================
  # MATCH DETECTION HELPERS
  # ============================================================================

  defp has_identity_matches?(text) do
    Enum.any?(@identity_replacements, fn {pattern, _} ->
      Regex.match?(pattern, text)
    end)
  end

  defp has_secret_matches?(text) do
    Enum.any?(@secret_patterns, fn {pattern, _} ->
      Regex.match?(pattern, text)
    end)
  end

  defp has_infra_matches?(text) do
    Enum.any?(@infra_patterns, fn {pattern, _} ->
      Regex.match?(pattern, text)
    end)
  end

  defp has_pii_matches?(text) do
    Enum.any?(@pii_patterns, fn {pattern, _} ->
      Regex.match?(pattern, text)
    end)
  end
end
