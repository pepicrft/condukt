defmodule ConduktSite.Repository do
  @moduledoc """
  Read-only access to Condukt's public repository on GitHub.

  These are the two capabilities the demo agent on the home page is given, and
  the reason it is safe to run that agent on the server: neither reaches the
  filesystem, the network beyond one pinned public repository, or anything
  belonging to the machine it runs on. An agent with these tools can read
  Condukt's own source and nothing else.

  ## Rate limits

  Unauthenticated GitHub requests are limited per address. When the agent ran in
  the visitor's browser each visitor spent their own allowance; running on the
  server, every visitor spends the same one, which is sixty requests an hour for
  everybody together.

  Configure a token to raise that to five thousand:

      config :condukt_site, ConduktSite.Repository, token: System.get_env("GITHUB_TOKEN")

  Without one the tools still work and report the limit plainly when it is
  reached, which is the difference between a demo that explains itself and one
  that appears broken.
  """

  @repository "tuist/condukt"
  @revision "main"
  @max_entries 200
  @max_file_bytes 128 * 1024
  @receive_timeout to_timeout(second: 10)

  @doc "The repository and revision the tools read."
  def source, do: %{repository: @repository, revision: @revision}

  @doc """
  Lists a directory, relative to the repository root.

  An empty path lists the root.
  """
  def list_directory(path \\ "") do
    with {:ok, entries} when is_list(entries) <- get("/contents/#{clean(path)}") do
      {:ok,
       entries
       |> Enum.take(@max_entries)
       |> Enum.map(&%{name: &1["name"], path: &1["path"], type: &1["type"], size: &1["size"]})}
    else
      {:ok, _file} -> {:error, "#{clean(path)} is a file, not a directory"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Reads a text file, relative to the repository root.

  Large files are refused rather than truncated: a partial source file read as
  if it were whole is worse than being told to look at less of it.
  """
  def read_file(path) do
    with {:ok, %{"content" => content, "encoding" => "base64", "size" => size}} <-
           get("/contents/#{clean(path)}"),
         :ok <- within_limit(size, path),
         {:ok, decoded} <- decode(content) do
      {:ok, decoded}
    else
      {:ok, entries} when is_list(entries) ->
        {:error, "#{clean(path)} is a directory, not a file"}

      {:ok, _other} ->
        {:error, "#{clean(path)} is not a text file"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp within_limit(size, path) when is_integer(size) and size > @max_file_bytes do
    {:error,
     "#{clean(path)} is #{div(size, 1024)}KB, larger than the #{div(@max_file_bytes, 1024)}KB limit"}
  end

  defp within_limit(_size, _path), do: :ok

  defp decode(content) do
    case content |> String.replace("\n", "") |> Base.decode64() do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, "the file could not be decoded as text"}
    end
  end

  # Path traversal is not a concern against the contents API, which resolves
  # paths within the repository, but a leading slash makes it a different
  # endpoint, so the path is normalized rather than trusted.
  defp clean(path) do
    path |> to_string() |> String.trim() |> String.trim_leading("/")
  end

  defp get(path) do
    [
      url: "https://api.github.com/repos/#{@repository}#{path}",
      params: [ref: @revision],
      headers: headers(),
      receive_timeout: @receive_timeout,
      retry: false
    ]
    |> Req.new()
    |> Req.get()
    |> interpret()
  end

  defp interpret({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}

  defp interpret({:ok, %Req.Response{status: 404}}),
    do: {:error, "no such path in #{@repository}"}

  defp interpret({:ok, %Req.Response{status: status, headers: headers}})
       when status in [403, 429] do
    if rate_limited?(headers) do
      {:error, "GitHub's rate limit for this server has been reached; try again shortly"}
    else
      {:error, "GitHub refused the request (HTTP #{status})"}
    end
  end

  defp interpret({:ok, %Req.Response{status: status}}),
    do: {:error, "GitHub returned HTTP #{status}"}

  defp interpret({:error, _reason}), do: {:error, "GitHub could not be reached"}

  defp rate_limited?(headers) do
    case headers["x-ratelimit-remaining"] do
      ["0" | _rest] -> true
      _other -> false
    end
  end

  defp headers do
    base = [accept: "application/vnd.github+json", user_agent: "condukt-site"]

    case token() do
      nil -> base
      token -> Keyword.put(base, :authorization, "Bearer #{token}")
    end
  end

  defp token do
    :condukt_site
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:token)
    |> case do
      value when is_binary(value) and value != "" -> value
      _other -> nil
    end
  end
end
