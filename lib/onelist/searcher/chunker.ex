defmodule Onelist.Searcher.Chunker do
  @moduledoc """
  Split long text into overlapping chunks for embedding.

  Long content is split into smaller chunks with overlap to ensure
  context is preserved across chunk boundaries. Each chunk is then
  embedded separately.
  """

  @default_max_tokens 500
  @default_overlap_tokens 50
  @approx_chars_per_token 4  # Rough estimate for English text
  @min_chunk_chars 20  # Minimum chunk size to prevent infinite loops

  defstruct [:text, :start_offset, :end_offset, :token_count]

  @type t :: %__MODULE__{
          text: String.t(),
          start_offset: non_neg_integer(),
          end_offset: non_neg_integer(),
          token_count: non_neg_integer()
        }

  @doc """
  Chunk text into pieces suitable for embedding.

  ## Options
    * `:max_tokens` - Maximum tokens per chunk (default: 500)
    * `:overlap_tokens` - Token overlap between chunks (default: 50)

  ## Examples

      iex> Onelist.Searcher.Chunker.chunk("Short text")
      [%Onelist.Searcher.Chunker{text: "Short text", start_offset: 0, end_offset: 10, token_count: 2}]

  """
  @spec chunk(String.t(), keyword()) :: [t()]
  def chunk(text, opts \\ [])

  def chunk(nil, _opts), do: []
  def chunk("", _opts), do: []

  def chunk(text, opts) when is_binary(text) do
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)
    overlap_tokens = Keyword.get(opts, :overlap_tokens, @default_overlap_tokens)

    max_chars = max(max_tokens * @approx_chars_per_token, @min_chunk_chars)
    overlap_chars = min(overlap_tokens * @approx_chars_per_token, div(max_chars, 2))

    text = String.trim(text)

    if String.length(text) <= max_chars do
      # Single chunk
      [%__MODULE__{
        text: text,
        start_offset: 0,
        end_offset: String.length(text),
        token_count: estimate_tokens(text)
      }]
    else
      # Multiple chunks with overlap
      chunk_with_overlap(text, max_chars, overlap_chars, 0, [])
    end
  end

  defp chunk_with_overlap(text, max_chars, overlap_chars, offset, acc) do
    text_length = String.length(text)

    if text_length <= max_chars do
      # Final chunk
      chunk = %__MODULE__{
        text: text,
        start_offset: offset,
        end_offset: offset + text_length,
        token_count: estimate_tokens(text)
      }
      Enum.reverse([chunk | acc])
    else
      # Find good break point (end of sentence or word)
      chunk_text = String.slice(text, 0, max_chars)
      break_point = find_break_point(chunk_text)

      # Ensure we make progress (break_point must be > overlap to avoid infinite loops)
      break_point = max(break_point, overlap_chars + @min_chunk_chars)
      break_point = min(break_point, text_length)

      actual_chunk = String.slice(text, 0, break_point)

      chunk = %__MODULE__{
        text: String.trim(actual_chunk),
        start_offset: offset,
        end_offset: offset + break_point,
        token_count: estimate_tokens(actual_chunk)
      }

      # Calculate next chunk start with overlap
      next_start = max(0, break_point - overlap_chars)

      # Ensure we make progress
      next_start = max(next_start, div(break_point, 2))

      remaining = String.slice(text, next_start, text_length - next_start)

      # Guard against infinite loops
      if String.length(remaining) >= text_length do
        # Force progress by taking at least half
        remaining = String.slice(text, div(text_length, 2), text_length)
        chunk_with_overlap(remaining, max_chars, overlap_chars, offset + div(text_length, 2), [chunk | acc])
      else
        chunk_with_overlap(remaining, max_chars, overlap_chars, offset + next_start, [chunk | acc])
      end
    end
  end

  defp find_break_point(text) do
    len = String.length(text)
    min_pos = div(len, 2)  # Don't break before halfway point

    # Look for break points in the second half of the text only
    search_text = String.slice(text, min_pos, len - min_pos)

    # Try to find a good break point using simple string operations
    # Priority: sentence end > paragraph > newline > word boundary
    cond do
      # Sentence end: look for ". " or "! " or "? "
      break = find_sentence_break(search_text) ->
        min_pos + break + 1

      # Paragraph break: "\n\n"
      break = find_substring(search_text, "\n\n") ->
        min_pos + break

      # Newline
      break = find_substring(search_text, "\n") ->
        min_pos + break + 1

      # Word boundary: space
      break = find_last_space(search_text) ->
        min_pos + break

      # No good break point found, use full length
      true ->
        len
    end
  end

  # Find the last sentence-ending punctuation followed by space
  defp find_sentence_break(text) do
    indices =
      [
        find_last_substring(text, ". "),
        find_last_substring(text, "! "),
        find_last_substring(text, "? ")
      ]
      |> Enum.filter(& &1)

    if Enum.empty?(indices), do: nil, else: Enum.max(indices)
  end

  # Find first occurrence of substring
  defp find_substring(text, substring) do
    case :binary.match(text, substring) do
      {pos, _} -> pos
      :nomatch -> nil
    end
  end

  # Find last occurrence of substring
  defp find_last_substring(text, substring) do
    case :binary.matches(text, substring) do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
    end
  end

  # Find last space character
  defp find_last_space(text) do
    text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.filter(fn {char, _} -> char in [" ", "\t"] end)
    |> case do
      [] -> nil
      list -> list |> List.last() |> elem(1)
    end
  end

  @doc """
  Estimate token count for text.

  Uses a simple character-based estimation. For more accurate counts,
  use a proper tokenizer.
  """
  @spec estimate_tokens(String.t()) :: non_neg_integer()
  def estimate_tokens(text) when is_binary(text) do
    # Rough estimate: ~4 chars per token for English
    max(1, div(String.length(text), @approx_chars_per_token))
  end

  def estimate_tokens(_), do: 0
end
