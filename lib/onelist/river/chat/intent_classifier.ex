defmodule Onelist.River.Chat.IntentClassifier do
  @moduledoc """
  Classify user intent from natural language input.

  Uses pattern matching for fast, deterministic classification.
  No LLM call needed for basic intent detection.
  """

  @doc """
  Classify the intent of a user message.
  Returns an atom representing the intent.
  """
  def classify(message) when is_binary(message) do
    message_lower = String.downcase(message)

    cond do
      matches_greeting?(message_lower) -> :chat  # Greetings are chat, not queries
      matches_create_task?(message_lower) -> :create_task
      matches_complete_task?(message_lower) -> :complete_task
      matches_list_tasks?(message_lower) -> :list_tasks
      matches_review?(message_lower) -> :review
      matches_briefing?(message_lower) -> :briefing
      matches_query?(message_lower) -> :query
      true -> :chat
    end
  end

  # ============================================
  # GREETING PATTERNS (should be chat, not query)
  # ============================================

  defp matches_greeting?(msg) do
    patterns = [
      ~r/^(hi|hello|hey|good\s+(morning|afternoon|evening)|howdy)/,
      ~r/how\s+are\s+you/,
      ~r/^(thanks|thank\s+you)/,
      ~r/^(bye|goodbye|see\s+you|talk\s+later)/,
      ~r/^river[,!?]?\s*$/  # Just saying "River"
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end

  @doc """
  Classify intent and return metadata about the classification.
  """
  def classify_with_metadata(message) when is_binary(message) do
    message_lower = String.downcase(message)

    cond do
      matches_greeting?(message_lower) ->
        {:chat, %{}}

      matches_create_task?(message_lower) ->
        {:create_task, %{}}

      matches_complete_task?(message_lower) ->
        {:complete_task, %{}}

      matches_list_tasks?(message_lower) ->
        {:list_tasks, extract_list_metadata(message_lower)}

      matches_review?(message_lower) ->
        {:review, extract_review_metadata(message_lower)}

      matches_briefing?(message_lower) ->
        {:briefing, %{}}

      matches_query?(message_lower) ->
        {:query, %{}}

      true ->
        {:chat, %{}}
    end
  end

  # ============================================
  # TASK CREATION PATTERNS
  # ============================================

  defp matches_create_task?(msg) do
    patterns = [
      ~r/^add\s+task[:\s]/,
      ~r/^create\s+(a\s+)?task/,
      ~r/^remind\s+me\s+to\s/,
      ~r/^i\s+need\s+to\s/,
      ~r/^todo[:\s]/,
      ~r/^don'?t\s+forget\s+to\s/
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end

  # ============================================
  # TASK COMPLETION PATTERNS
  # ============================================

  defp matches_complete_task?(msg) do
    patterns = [
      ~r/^done\s+with\s/,
      ~r/^finished\s+(with\s+)?/,
      ~r/^completed?\s/,
      ~r/^complete[:\s]/,
      ~r/^mark\s+.+\s+(done|complete)/,
      ~r/^set\s+.+\s+(as\s+)?(done|complete)/
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end

  # ============================================
  # LIST TASKS PATTERNS
  # ============================================

  defp matches_list_tasks?(msg) do
    patterns = [
      ~r/^show\s+(my\s+)?inbox/,
      ~r/^what'?s?\s+(in\s+)?(my\s+)?inbox/,
      ~r/^inbox$/,
      ~r/^(show|list|what\s+are)\s+(my\s+)?next\s+actions/,
      ~r/^what\s+am\s+i\s+waiting\s+for/,
      ~r/^(show|list)\s+waiting\s+for/,
      ~r/waiting\s+for\s+list/,
      ~r/^(show\s+)?someday\s+maybe/,
      ~r/someday\s+maybe\s+list/,
      ~r/@(phone|computer|home|errands|office|anywhere)/,
      ~r/^(show\s+)?tasks\s+@/,
      ~r/^what'?s?\s+overdue/,
      ~r/^(show|list)\s+overdue/
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end

  defp extract_list_metadata(msg) do
    metadata = %{}

    # Extract bucket
    metadata =
      cond do
        msg =~ ~r/inbox/ -> Map.put(metadata, :bucket, "inbox")
        msg =~ ~r/next\s+actions?/ -> Map.put(metadata, :bucket, "next_actions")
        msg =~ ~r/waiting\s+for/ -> Map.put(metadata, :bucket, "waiting_for")
        msg =~ ~r/someday\s+maybe/ -> Map.put(metadata, :bucket, "someday_maybe")
        msg =~ ~r/overdue/ -> Map.put(metadata, :filter, :overdue)
        true -> metadata
      end

    # Extract context
    case Regex.run(~r/@(phone|computer|home|errands|office|anywhere)/, msg) do
      [_, context] -> Map.put(metadata, :context, "@#{context}")
      nil -> metadata
    end
  end

  # ============================================
  # REVIEW PATTERNS
  # ============================================

  defp matches_review?(msg) do
    patterns = [
      ~r/(start\s+)?(my\s+)?(daily|weekly|monthly)\s+review/,
      ~r/^(let'?s\s+)?(do\s+)?(a\s+)?review/,
      ~r/^start\s+(my\s+)?review/,
      ~r/^review$/
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end

  defp extract_review_metadata(msg) do
    cond do
      msg =~ ~r/daily/ -> %{review_type: :daily}
      msg =~ ~r/weekly/ -> %{review_type: :weekly}
      msg =~ ~r/monthly/ -> %{review_type: :monthly}
      true -> %{review_type: :daily}
    end
  end

  # ============================================
  # BRIEFING PATTERNS
  # ============================================

  defp matches_briefing?(msg) do
    patterns = [
      ~r/briefing/,
      ~r/what'?s?\s+(is\s+)?(on\s+)?(my\s+)?(calendar|schedule|agenda)/,
      ~r/what\s+is\s+on\s+(my\s+)?calendar/,
      ~r/what'?s?\s+on\s+for\s+today/,
      ~r/give\s+me\s+(a\s+|an\s+)?(summary|overview)/,
      ~r/what\s+should\s+i\s+(focus|work)\s+on/
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end

  # ============================================
  # QUERY PATTERNS
  # ============================================

  defp matches_query?(msg) do
    patterns = [
      # Question words at start
      ~r/^what\s/,
      ~r/^who\s/,
      ~r/^where\s/,
      ~r/^when\s/,
      ~r/^why\s/,
      ~r/^how\s/,
      # Questions ending with ?
      ~r/\?$/,
      # Search commands
      ~r/^find\s/,
      ~r/^search\s/,
      ~r/^look\s+for\s/,
      ~r/^show\s+me\s+what/
    ]

    Enum.any?(patterns, &Regex.match?(&1, msg))
  end
end
