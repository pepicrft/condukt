defmodule ConduktSiteWeb.Blog.Markdown do
  @moduledoc """
  Converts a blog post Markdown source into safe, highlighted HTML and the
  metadata needed by the blog layout.

  Each post starts with a YAML frontmatter block delimited by `---` lines.
  Supported fields are `title`, `date`, `description`, and `author`.
  """

  alias ConduktSiteWeb.Docs.HTML, as: DocsHTML

  @type heading :: %{level: pos_integer(), id: String.t(), text: String.t()}
  @type t :: %{
          source_path: String.t() | nil,
          slug: String.t(),
          title: String.t() | nil,
          date: Date.t() | nil,
          description: String.t() | nil,
          author: String.t() | nil,
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

  @spec render(String.t(), Path.t()) :: t()
  def render(markdown, file) do
    {frontmatter, body} = parse_frontmatter(markdown)
    rendered = MDEx.to_html!(body, @options)
    tree = Floki.parse_fragment!(rendered)

    %{
      source_path: nil,
      slug: Path.basename(file, ".md"),
      title: Map.get(frontmatter, "title") || extract_title(tree),
      date: parse_date(Map.get(frontmatter, "date")),
      description: Map.get(frontmatter, "description"),
      author: Map.get(frontmatter, "author"),
      html:
        rendered
        |> DocsHTML.wrap_code_blocks()
        |> DocsHTML.add_heading_anchors()
        |> rewrite_internal_links(),
      headings: extract_headings(tree),
      markdown: body
    }
  end

  defp parse_frontmatter("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [frontmatter, body] ->
        {parse_yaml(frontmatter), String.trim_leading(body, "\n")}

      _ ->
        {%{}, "---\n" <> rest}
    end
  end

  defp parse_frontmatter(markdown), do: {%{}, markdown}

  defp parse_yaml(frontmatter) do
    frontmatter
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [key, value] ->
          Map.put(acc, String.trim(key), strip_value(value))

        _ ->
          acc
      end
    end)
  end

  defp strip_value(value) do
    value
    |> String.trim()
    |> String.trim("\"")
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

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

  defp rewrite_internal_links(html) do
    Regex.replace(~r/href="(\/blog\/[^"]*)"/, html, ~s(href="\\1"))
  end
end
