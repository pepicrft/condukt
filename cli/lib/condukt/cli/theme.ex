defmodule Condukt.CLI.Theme do
  @moduledoc """
  Semantic presentation tokens for Condukt's terminal interface.

  A terminal renders styles rather than Cascading Style Sheets, so this module
  is the typed equivalent of a web theme's custom properties. Views ask for
  roles such as `activity_marker/0` or `muted_text/0`; they never choose a
  terminal colour directly, which makes an alternate palette a data change
  rather than a search-and-replace across renderers.
  """

  alias ExRatatui.Style

  @colors %{
    text: :gray,
    muted: :dark_gray,
    accent: :cyan,
    user: :green,
    danger: :red,
    border: :dark_gray
  }

  @doc "The named colour scale, following Theme UI's `colors` convention."
  def colors, do: @colors

  @doc "Colour for one semantic role."
  def color(role), do: Map.fetch!(@colors, role)

  def text, do: %Style{fg: @colors.text}

  def title, do: %Style{fg: @colors.accent, modifiers: [:bold]}

  def accent_text, do: %Style{fg: @colors.accent}

  def selected, do: %Style{fg: @colors.accent, modifiers: [:bold]}

  def muted_text, do: %Style{fg: @colors.muted}

  def muted_italic, do: %Style{fg: @colors.muted, modifiers: [:italic]}

  def prompt_prefix, do: %Style{fg: @colors.accent, modifiers: [:bold]}

  def border, do: %Style{fg: @colors.border}

  def user_marker, do: %Style{fg: @colors.user}

  @doc "A cyan left edge identifies model activity and tool invocations."
  def activity_marker, do: %Style{fg: @colors.accent}

  def error_marker, do: %Style{fg: @colors.danger}

  def error_text, do: %Style{fg: @colors.danger}

  @doc "Adds a modifier to an existing style without dropping its colours."
  def with_modifier(%Style{} = style, modifier) do
    %{style | modifiers: Enum.uniq([modifier | style.modifiers])}
  end
end
