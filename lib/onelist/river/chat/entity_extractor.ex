defmodule Onelist.River.Chat.EntityExtractor do
  @moduledoc """
  Extract entities from user messages.

  Extracts:
  - GTD contexts (@phone, @computer, etc.)
  - Due dates (tomorrow, next week, specific dates)
  - Person names
  - Topics
  - Priority indicators
  """

  @doc """
  Extract all entities from a message.
  """
  def extract(message) when is_binary(message) do
    %{}
    |> extract_context(message)
    |> extract_due_date(message)
    |> extract_priority(message)
    |> extract_person(message)
  end

  # ============================================
  # CONTEXT EXTRACTION
  # ============================================

  @contexts ~w(@phone @computer @home @errands @office @anywhere @energy:high @energy:low)

  defp extract_context(entities, message) do
    case Regex.run(~r/@\w+(?::\w+)?/, message) do
      [context] when context in @contexts ->
        Map.put(entities, :context, context)

      _ ->
        entities
    end
  end

  # ============================================
  # DUE DATE EXTRACTION
  # ============================================

  defp extract_due_date(entities, message) do
    message_lower = String.downcase(message)

    due_date =
      cond do
        message_lower =~ ~r/\btomorrow\b/ ->
          Date.utc_today() |> Date.add(1) |> Date.to_string()

        message_lower =~ ~r/\btoday\b/ ->
          Date.utc_today() |> Date.to_string()

        message_lower =~ ~r/\bnext week\b/ ->
          Date.utc_today() |> Date.add(7) |> Date.to_string()

        message_lower =~ ~r/\bnext month\b/ ->
          Date.utc_today() |> Date.add(30) |> Date.to_string()

        message_lower =~ ~r/\bfriday\b/ ->
          days_until_friday()

        message_lower =~ ~r/\bmonday\b/ ->
          days_until_day(1)

        # Try to extract explicit date
        true ->
          extract_explicit_date(message)
      end

    if due_date do
      Map.put(entities, :due_date, due_date)
    else
      entities
    end
  end

  defp days_until_friday do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    # Friday is 5, Monday is 1
    days = if day_of_week >= 5, do: 12 - day_of_week, else: 5 - day_of_week
    Date.add(today, days) |> Date.to_string()
  end

  defp days_until_day(target_day) do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)

    days =
      if day_of_week >= target_day do
        7 - day_of_week + target_day
      else
        target_day - day_of_week
      end

    Date.add(today, days) |> Date.to_string()
  end

  defp extract_explicit_date(message) do
    # Try to match patterns like "Jan 15", "1/15", "2026-01-15"
    cond do
      # ISO format
      result = Regex.run(~r/\b(\d{4}-\d{2}-\d{2})\b/, message) ->
        [_, date] = result
        date

      # US format M/D or M/D/YY
      result = Regex.run(~r/\b(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?\b/, message) ->
        parse_us_date(result)

      # Month name format "Jan 15" or "January 15"
      result =
          Regex.run(
            ~r/\b(Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+(\d{1,2})\b/i,
            message
          ) ->
        parse_month_day(result)

      true ->
        nil
    end
  end

  defp parse_us_date([_, month, day]) do
    year = Date.utc_today().year
    month = String.to_integer(month)
    day = String.to_integer(day)

    case Date.new(year, month, day) do
      {:ok, date} -> Date.to_string(date)
      _ -> nil
    end
  end

  defp parse_us_date([_, month, day, year]) do
    year = String.to_integer(year)
    year = if year < 100, do: 2000 + year, else: year
    month = String.to_integer(month)
    day = String.to_integer(day)

    case Date.new(year, month, day) do
      {:ok, date} -> Date.to_string(date)
      _ -> nil
    end
  end

  defp parse_month_day([_, month_name, day]) do
    month = month_name_to_number(month_name)
    day = String.to_integer(day)
    year = Date.utc_today().year

    case Date.new(year, month, day) do
      {:ok, date} -> Date.to_string(date)
      _ -> nil
    end
  end

  defp month_name_to_number(name) do
    case String.downcase(String.slice(name, 0, 3)) do
      "jan" -> 1
      "feb" -> 2
      "mar" -> 3
      "apr" -> 4
      "may" -> 5
      "jun" -> 6
      "jul" -> 7
      "aug" -> 8
      "sep" -> 9
      "oct" -> 10
      "nov" -> 11
      "dec" -> 12
      _ -> nil
    end
  end

  # ============================================
  # PRIORITY EXTRACTION
  # ============================================

  defp extract_priority(entities, message) do
    message_lower = String.downcase(message)

    priority =
      cond do
        message_lower =~ ~r/\b(urgent|asap|critical)\b/ -> 2
        message_lower =~ ~r/\b(high\s+priority|important)\b/ -> 1
        message_lower =~ ~r/\b(low\s+priority|eventually)\b/ -> -1
        true -> nil
      end

    if priority do
      Map.put(entities, :priority, priority)
    else
      entities
    end
  end

  # ============================================
  # PERSON EXTRACTION
  # ============================================

  defp extract_person(entities, message) do
    # Look for patterns like "call Sarah", "email John", etc.
    # This is a simple extraction - could be enhanced with NER
    case Regex.run(
           ~r/\b(?:call|email|text|message|meet(?:ing)?\s+with|ask|tell|remind)\s+([A-Z][a-z]+)\b/,
           message
         ) do
      [_, person] ->
        Map.put(entities, :person, person)

      nil ->
        entities
    end
  end
end
