defmodule ConduktSiteWeb.Docs.Markdown do
  @moduledoc """
  Converts a documentation Markdown source into safe, highlighted HTML and the
  metadata needed by the documentation layout.
  """

  alias ConduktSiteWeb.Docs.HTML

  @type heading :: %{level: pos_integer(), id: String.t(), text: String.t()}
  @type t :: %{
          source_path: String.t() | nil,
          title: String.t() | nil,
          html: String.t(),
          headings: [heading()],
          markdown: String.t()
        }

  @syntax_highlight (if Mix.env() == :test do
                       [syntax_highlight: nil]
                     else
                       [
                         syntax_highlight: [
                           engine: :lumis,
                           opts: [
                             formatter:
                               {:html_multi_themes,
                                themes: [light: "github_light", dark: "github_dark"],
                                default_theme: "light-dark()"}
                           ]
                         ]
                       ]
                     end)

  @options [
             extension: [
               header_id_prefix: "",
               table: true,
               strikethrough: true,
               tasklist: true,
               autolink: true
             ],
             render: [unsafe: false]
           ] ++ @syntax_highlight

  @spec render(String.t()) :: t()
  def render(markdown) do
    source = strip_frontmatter(markdown)
    rendered = MDEx.to_html!(source, @options)
    tree = Floki.parse_fragment!(rendered)

    %{
      source_path: nil,
      title: extract_title(tree),
      headings: extract_headings(tree),
      html:
        rendered |> HTML.wrap_code_blocks() |> HTML.add_heading_anchors() |> HTML.rewrite_links(),
      markdown: source
    }
  end

  defp strip_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [_frontmatter, body] -> String.trim_leading(body, "\n")
      _ -> "---\n" <> rest
    end
  end

  defp strip_frontmatter(markdown), do: markdown

  defp extract_title(tree) do
    case Floki.find(tree, "h1") do
      [node | _] -> node |> Floki.text() |> String.trim()
      [] -> nil
    end
  end

  defp extract_headings(tree) do
    tree
    |> Floki.find("h2, h3, h4")
    |> Enum.map(fn {tag, attributes, _children} = node ->
      text = node |> Floki.text() |> String.trim()
      %{level: level(tag), id: attribute(attributes, "id") || slugify(text), text: text}
    end)
  end

  defp level("h2"), do: 2
  defp level("h3"), do: 3
  defp level("h4"), do: 4

  defp attribute(attributes, key) do
    Enum.find_value(attributes, fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
