defmodule Onelist.AssetEnrichment.WhisperBehaviour do
  @moduledoc """
  Behaviour for audio transcription providers.
  
  Implement this behaviour to provide audio transcription capabilities.
  The default implementation uses OpenAI's Whisper API.
  """

  @type transcription_result :: %{
    text: String.t(),
    language: String.t() | nil,
    duration: number() | nil,
    segments: list(map())
  }

  @type transcription_error :: 
    {:file_not_found, String.t()} | 
    {:api_error, integer(), term()} |
    {:request_failed, term()}

  @doc """
  Transcribe an audio file.
  
  ## Arguments
    * `file_path` - Path to the audio file
    * `opts` - Options (e.g., `:language` for ISO-639-1 code)
  
  ## Returns
    * `{:ok, result}` - Transcription with text, language, duration, segments
    * `{:error, reason}` - Error details
  """
  @callback transcribe(file_path :: String.t(), opts :: keyword()) ::
    {:ok, transcription_result()} | {:error, transcription_error()}

  @doc """
  Estimate the cost of transcribing audio of given duration.
  
  ## Arguments
    * `duration_seconds` - Duration of audio in seconds
  
  ## Returns
    * Cost in cents
  """
  @callback estimate_cost(duration_seconds :: number()) :: integer()
end
