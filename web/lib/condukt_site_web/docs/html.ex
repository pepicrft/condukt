defmodule ConduktSiteWeb.Docs.HTML do
  @moduledoc "HTML post-processing for documentation code blocks, links, and heading anchors."

  @code_block_regex ~r/<pre[^>]*><code(?:[^>]*class="language-([^"]+)")?[^>]*>(.*?)<\/code><\/pre>/s
  @heading_regex ~r/<h([2-4]) id="([^"]*)">(.*?)<a[^>]*class="anchor"[^>]*><\/a><\/h\1>/s
  @site_link_regex ~r/href="(\/(?:cli|framework)(?:\/[^"]*)?)"/
  @relative_link_regex ~r/href="([a-z0-9-]+)\.md(#[^"]*)?"/

  @spec wrap_code_blocks(String.t()) :: String.t()
  def wrap_code_blocks(html) do
    Regex.replace(@code_block_regex, html, fn _full, language, code ->
      language = if language == "", do: "text", else: language

      ~s(<div class="code-window"><div data-part="bar">) <>
        ~s(<div data-part="language">#{language}</div>) <>
        ~s(<div data-part="copy" role="button" tabindex="0" aria-label="Copy code">) <>
        ~s(<span data-part="copy-icon"><noora-icon name="copy" label="" size="20"></noora-icon></span>) <>
        ~s(<span data-part="copy-check-icon"><noora-icon name="copy_check" label="" size="20"></noora-icon></span>) <>
        ~s(</div></div><template data-part="copy-source">#{copy_source(code)}</template>) <>
        ~s(<div data-part="code"><code>#{code}</code></div></div>)
    end)
  end

  @spec add_heading_anchors(String.t()) :: String.t()
  def add_heading_anchors(html) do
    Regex.replace(@heading_regex, html, fn _full, level, id, text ->
      ~s(<h#{level} id="#{id}"><a data-part="heading-anchor" href="##{id}">) <>
        ~s(<span>#{text}</span><span data-part="hash">#</span></a></h#{level}>)
    end)
  end

  @doc """
  Resolves documentation links to site paths.

  Site-authored pages link to other sections with root-relative paths such as
  `/framework/elixir`. Pages that are also published as ExDoc extras link to
  their siblings with relative Markdown paths such as `tools.md`, which resolve
  against the directory the page lives in.
  """
  @spec rewrite_links(String.t(), String.t()) :: String.t()
  def rewrite_links(html, base_slug) do
    html
    |> then(&Regex.replace(@site_link_regex, &1, ~s(href="/docs\\1")))
    |> then(
      &Regex.replace(@relative_link_regex, &1, fn _full, page, fragment ->
        ~s(href="#{sibling_slug(base_slug, page)}#{fragment}")
      end)
    )
  end

  defp sibling_slug(base_slug, "index"), do: base_slug
  defp sibling_slug(base_slug, page), do: "#{base_slug}/#{page}"

  defp copy_source(code) do
    code
    |> then(&Regex.replace(~r/<[^>]*>/, &1, ""))
    |> decode_entities()
    |> String.trim()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp decode_entities(text) do
    Regex.replace(~r/&(?:#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);/, text, fn entity ->
      case Floki.Entities.decode(entity) do
        {:ok, decoded} -> decoded
        _ -> entity
      end
    end)
  end
end
