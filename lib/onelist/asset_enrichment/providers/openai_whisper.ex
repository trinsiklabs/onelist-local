defmodule Onelist.AssetEnrichment.Providers.OpenAIWhisper do
  @moduledoc """
  OpenAI Whisper API for audio transcription.

  Supports:
  - Audio transcription with timestamps
  - Language detection
  - Segment-level timing

  ## Cost
  Whisper costs approximately $0.006 per minute of audio.
  """

  @behaviour Onelist.AssetEnrichment.WhisperBehaviour

  require Logger

  @api_url "https://api.openai.com/v1/audio/transcriptions"
  @timeout_ms 300_000

  @doc """
  Transcribe audio file using Whisper API.

  ## Options
    * `:language` - ISO-639-1 language code (auto-detect if nil)

  ## Returns
    * `{:ok, result}` - Transcription with text, language, duration, segments
    * `{:error, reason}` - Error details
  """
  @impl Onelist.AssetEnrichment.WhisperBehaviour
  def transcribe(file_path, opts \\ []) do
    api_key = get_api_key()
    language = Keyword.get(opts, :language)

    unless File.exists?(file_path) do
      {:error, {:file_not_found, file_path}}
    else
      do_transcribe(file_path, api_key, language)
    end
  end

  defp do_transcribe(file_path, api_key, language) do
    # Build multipart form
    form =
      [
        {:file, file_path},
        {:model, "whisper-1"},
        {:response_format, "verbose_json"},
        {:timestamp_granularities, ["segment"]}
      ]
      |> maybe_add_language(language)

    headers = [
      {"Authorization", "Bearer #{api_key}"}
    ]

    case Req.post(@api_url,
           form_multipart: form,
           headers: headers,
           receive_timeout: @timeout_ms
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok,
         %{
           text: body["text"],
           language: body["language"],
           duration: body["duration"],
           segments: parse_segments(body["segments"])
         }}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Whisper API error: #{status} - #{inspect(body)}")
        {:error, {:api_error, status, body["error"]["message"] || body}}

      {:error, reason} ->
        Logger.error("Whisper request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp maybe_add_language(form, nil), do: form
  defp maybe_add_language(form, language), do: [{:language, language} | form]

  defp parse_segments(nil), do: []

  defp parse_segments(segments) when is_list(segments) do
    Enum.map(segments, fn seg ->
      %{
        "id" => seg["id"],
        "start" => seg["start"],
        "end" => seg["end"],
        "text" => seg["text"]
      }
    end)
  end

  defp get_api_key do
    Application.get_env(:onelist, :openai_api_key) ||
      System.get_env("OPENAI_API_KEY") ||
      raise "OpenAI API key not configured"
  end

  @doc """
  Estimate cost for transcribing audio of given duration.

  ## Examples

      iex> estimate_cost(60)
      1  # ~1 cent for 1 minute

      iex> estimate_cost(600)
      6  # ~6 cents for 10 minutes
  """
  @impl Onelist.AssetEnrichment.WhisperBehaviour
  def estimate_cost(duration_seconds) when is_number(duration_seconds) do
    # $0.006 per minute
    minutes = duration_seconds / 60
    round(minutes * 0.6)
  end

  def estimate_cost(_), do: 0
end
