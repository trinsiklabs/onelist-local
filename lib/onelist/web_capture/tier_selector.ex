defmodule Onelist.WebCapture.TierSelector do
  @moduledoc """
  Intelligent tier selection for web capture based on URL characteristics.

  Uses domain heuristics and site classification to recommend the optimal
  capture tier for each URL.
  """

  @doc """
  Select the best capture tier for a URL.

  ## Returns

  - `:simple_fetch` - Use HTTP fetch + Readability
  - `:intelligent_browser` - Use browser-based capture
  """
  @spec select(String.t()) :: :simple_fetch | :intelligent_browser
  def select(url) do
    domain = extract_domain(url)

    cond do
      domain in simple_fetch_domains() ->
        :simple_fetch

      domain in browser_required_domains() ->
        :intelligent_browser

      String.ends_with?(domain, ".substack.com") ->
        :simple_fetch

      String.ends_with?(domain, ".medium.com") ->
        :simple_fetch

      # Default to simple fetch
      true ->
        :simple_fetch
    end
  end

  @doc """
  Check if a tier is currently available.
  """
  @spec tier_available?(atom()) :: boolean()
  def tier_available?(:simple_fetch), do: true

  def tier_available?(:intelligent_browser) do
    # Check if browser service is configured and reachable
    case Application.get_env(:onelist, :browser_use_url) do
      nil -> false
      url -> browser_service_healthy?(url)
    end
  end

  def tier_available?(_), do: false

  @doc """
  Get fallback tier for a given tier.
  """
  @spec fallback_tier(atom()) :: atom() | nil
  def fallback_tier(:simple_fetch), do: :intelligent_browser
  def fallback_tier(:intelligent_browser), do: nil
  def fallback_tier(_), do: nil

  # ============================================
  # DOMAIN CLASSIFICATIONS
  # ============================================

  # Sites known to work well with simple HTTP fetch
  defp simple_fetch_domains do
    ~w(
      wikipedia.org
      en.wikipedia.org
      github.com
      medium.com
      dev.to
      stackoverflow.com
      arxiv.org
      paulgraham.com
      news.ycombinator.com
      arstechnica.com
      bbc.com
      bbc.co.uk
      theguardian.com
      reuters.com
      cnn.com
      substack.com
      mirror.xyz
      paragraph.xyz
    )
  end

  # Sites that require browser rendering
  defp browser_required_domains do
    ~w(
      twitter.com
      x.com
      linkedin.com
      instagram.com
      facebook.com
      bloomberg.com
      wsj.com
      ft.com
    )
  end

  # ============================================
  # HELPERS
  # ============================================

  defp extract_domain(url) do
    case URI.parse(url) do
      %{host: nil} -> ""
      %{host: host} -> String.replace(host, ~r/^www\./, "")
    end
  end

  defp browser_service_healthy?(url) do
    case Req.get("#{url}/health", receive_timeout: 2_000) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
