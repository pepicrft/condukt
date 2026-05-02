defmodule Condukt.Context do
  @moduledoc """
  Loads project instructions and local skills from a project root.

  Condukt automatically looks for local instruction files such as `AGENTS.md`
  and reusable workflows under `.agents/skills/*/SKILL.md`. The discovered
  instructions are appended to the configured system prompt so agents can adapt
  to the project they are running in.
  """

  alias Condukt.Context.Skill

  @context_files ["AGENTS.md", "CLAUDE.md"]
  @skills_dir ".agents/skills"
  def empty do
    %{agents_md: nil, skills: [], prompt: nil}
  end

  def discover(project_root) when is_binary(project_root) do
    agents_md = read_agents_md(project_root)
    skills = discover_skills(project_root)

    %{
      agents_md: agents_md,
      skills: skills,
      prompt: compose_prompt(agents_md, skills)
    }
  end

  def compose_system_prompt(base_prompt, nil), do: present(base_prompt)

  def compose_system_prompt(base_prompt, project_instructions_prompt) do
    [present(base_prompt), present(project_instructions_prompt)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  def read_agents_md(project_root) when is_binary(project_root) do
    @context_files
    |> Enum.map(&Path.join(project_root, &1))
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq_by(&(Path.expand(&1) |> File.stat!() |> file_identity()))
    |> Enum.map(&File.read!/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      parts -> Enum.join(parts, "\n\n")
    end
  end

  def discover_skills(project_root) when is_binary(project_root) do
    skills_dir = Path.join(project_root, @skills_dir)

    if File.dir?(skills_dir) do
      skills_dir
      |> File.ls!()
      |> Enum.sort()
      |> Enum.map(&load_skill(skills_dir, &1))
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp load_skill(skills_dir, entry) do
    skill_dir = Path.join(skills_dir, entry)
    skill_path = Path.join(skill_dir, "SKILL.md")

    if File.dir?(skill_dir) and File.regular?(skill_path) do
      content = File.read!(skill_path)
      {name, description} = parse_frontmatter(content, entry)

      %Skill{
        name: name,
        description: description,
        path: Path.join([@skills_dir, entry, "SKILL.md"])
      }
    end
  end

  defp parse_frontmatter(content, default_name) do
    regex = ~r/\A---\s*\n(?<frontmatter>[\s\S]*?)\n---\s*\n(?<body>[\s\S]*)\z/

    case Regex.named_captures(regex, content) do
      %{"frontmatter" => frontmatter} ->
        fields = parse_frontmatter_fields(frontmatter)

        {Map.get(fields, "name", default_name), Map.get(fields, "description")}

      _ ->
        {default_name, nil}
    end
  end

  defp parse_frontmatter_fields(frontmatter) do
    frontmatter
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, &put_frontmatter_field/2)
  end

  defp put_frontmatter_field(line, acc) do
    case String.split(line, ":", parts: 2) do
      [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
      _ -> acc
    end
  end

  defp compose_prompt(nil, []), do: nil

  defp compose_prompt(agents_md, skills) do
    [agents_prompt(agents_md), skills_prompt(skills)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp agents_prompt(nil), do: nil

  defp agents_prompt(agents_md) do
    """
    ## Project Instructions

    The following instructions were discovered from `AGENTS.md` or `CLAUDE.md`
    in the project root. Treat them as project-specific operating instructions
    for this project.

    #{agents_md}
    """
    |> String.trim()
  end

  defp skills_prompt([]), do: nil

  defp skills_prompt(skills) do
    skill_lines =
      Enum.map_join(skills, "\n", fn skill ->
        description =
          case present(skill.description) do
            nil -> ""
            text -> " - #{text}"
          end

        "- `#{skill.name}` (read `#{skill.path}` before using it)#{description}"
      end)

    """
    ## Available Skills

    The following reusable workflows were discovered in this project. If one
    seems relevant, read its `SKILL.md` file before following it so you have
    the full instructions.

    #{skill_lines}
    """
    |> String.trim()
  end

  defp present(nil), do: nil

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp file_identity(%File.Stat{type: type, inode: inode, major_device: major, minor_device: minor}) do
    {type, inode, major, minor}
  end
end
