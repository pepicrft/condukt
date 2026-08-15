defmodule Condukt.CLI.OAuth do
  @moduledoc """
  OAuth 2.0 PKCE sign-in for OpenRouter over a one-shot loopback server.

  `start_login/1` generates a PKCE pair (RFC 7636), binds a listener on an
  ephemeral loopback port, and returns the authorize URL without waiting for
  anything. The listener runs in its own process and reports the outcome as a
  single message to whoever started it, so an interactive host can hand the URL
  to a browser and keep drawing frames while the user signs in.

  OpenRouter issues no client secret for the PKCE flow, so the only secrets
  involved are the verifier, which stays in the listener process, and the
  resulting key.
  """

  alias Condukt.CLI.OAuth.CallbackPage
  alias Condukt.CLI.OpenRouter

  @authorize_url "https://openrouter.ai/auth"
  @callback_path "/oauth/callback/condukt"
  @login_timeout to_timeout(minute: 5)
  @read_timeout 500
  @bind_timeout 5_000
  @unreserved ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

  defstruct [:pid, :ref, :authorize_url]

  @doc """
  Starts a browser sign-in without blocking the caller.

  Returns `{:ok, login}`. The caller opens `login.authorize_url` and then either
  waits with `await/2` or handles the `{ref, result}` message itself, where
  `result` is `{:ok, key}` or `{:error, message}`.

  ## Options

    * `:base_url` - OpenRouter API base URL, for pointing tests at a local server
    * `:authorize_url` - authorize endpoint, for the same reason
    * `:timeout` - how long the listener waits for the browser callback
  """
  def start_login(opts \\ []) do
    parent = self()
    ref = make_ref()
    pid = spawn_link(fn -> listen(parent, ref, opts) end)

    receive do
      {^ref, {:bound, authorize_url}} ->
        {:ok, %__MODULE__{pid: pid, ref: ref, authorize_url: authorize_url}}

      {^ref, {:error, reason}} ->
        {:error, reason}
    after
      @bind_timeout ->
        Process.exit(pid, :kill)
        {:error, "Could not open a local port for the sign-in callback."}
    end
  end

  @doc """
  Waits for a started login to produce a key.

  Returns `{:ok, key}` or `{:error, message}`.
  """
  def await(%__MODULE__{ref: ref}, timeout \\ @login_timeout) do
    receive do
      {^ref, {:ok, key}} -> {:ok, key}
      {^ref, {:error, reason}} -> {:error, reason}
    after
      timeout -> {:error, "Timed out waiting for the sign-in callback"}
    end
  end

  @doc """
  Stops a login attempt and releases its port.

  Safe to call after the login already finished.
  """
  def cancel(%__MODULE__{pid: pid}) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    :ok
  end

  @doc """
  Runs the whole flow for hosts that have nothing else to do while waiting.

  `open_browser` receives the authorize URL.
  """
  def login(open_browser, opts \\ []) when is_function(open_browser, 1) do
    with {:ok, login} <- start_login(opts) do
      open_browser.(login.authorize_url)
      await(login, Keyword.get(opts, :timeout, @login_timeout))
    end
  end

  @doc """
  Generates a PKCE verifier and its S256 challenge.

  The verifier is 64 random unreserved characters; the challenge is the
  base64url encoding of the verifier's SHA-256 digest.
  """
  def generate_pkce do
    verifier =
      64
      |> :crypto.strong_rand_bytes()
      |> :binary.bin_to_list()
      |> Enum.map(fn byte -> Enum.at(@unreserved, rem(byte, length(@unreserved))) end)
      |> List.to_string()

    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)
    {verifier, challenge}
  end

  @doc """
  Percent-encodes everything outside the unreserved set.

  URI.encode/2 keeps reserved characters that OpenRouter's callback parameter
  must carry encoded, so the encoding is spelled out here.
  """
  def url_encode(input) do
    input
    |> :binary.bin_to_list()
    |> Enum.map_join(fn byte ->
      if byte in @unreserved do
        <<byte>>
      else
        "%" <> String.upcase(Base.encode16(<<byte>>))
      end
    end)
  end

  defp listen(parent, ref, opts) do
    {verifier, challenge} = generate_pkce()

    case :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true, packet: :raw]) do
      {:ok, socket} ->
        {:ok, port} = :inet.port(socket)
        callback_url = "http://127.0.0.1:#{port}#{@callback_path}"
        send(parent, {ref, {:bound, authorize_url(callback_url, challenge, opts)}})
        send(parent, {ref, capture_and_exchange(socket, verifier, opts)})
        :gen_tcp.close(socket)

      {:error, reason} ->
        send(parent, {ref, {:error, "Could not open a local port for the sign-in callback: #{inspect(reason)}"}})
    end
  end

  defp authorize_url(callback_url, challenge, opts) do
    base = Keyword.get(opts, :authorize_url, @authorize_url)

    "#{base}?callback_url=#{url_encode(callback_url)}&code_challenge=#{url_encode(challenge)}&code_challenge_method=S256"
  end

  defp capture_and_exchange(socket, verifier, opts) do
    with {:ok, code} <- capture_code(socket, Keyword.get(opts, :timeout, @login_timeout)) do
      exchange_code(code, verifier, opts)
    end
  end

  defp capture_code(socket, timeout) do
    case :gen_tcp.accept(socket, timeout) do
      {:ok, client} ->
        result = handle_callback(client)
        :gen_tcp.close(client)
        result

      {:error, :timeout} ->
        {:error, "Timed out waiting for the sign-in callback"}

      {:error, :closed} ->
        {:error, "Sign-in cancelled"}

      {:error, reason} ->
        {:error, "Sign-in callback listener failed: #{inspect(reason)}"}
    end
  end

  defp handle_callback(client) do
    case :gen_tcp.recv(client, 0, @read_timeout) do
      {:ok, request} -> respond(client, interpret(request))
      {:error, reason} -> {:error, "Could not read the sign-in callback: #{inspect(reason)}"}
    end
  end

  defp respond(client, {:ok, code}) do
    send_response(client, 200, CallbackPage.render(:success))
    {:ok, code}
  end

  defp respond(client, {:error, status, message}) do
    send_response(client, status, CallbackPage.render(:error))
    {:error, message}
  end

  @doc """
  Interprets a raw HTTP callback request.

  Returns `{:ok, code}` or `{:error, status, message}`.
  """
  def interpret(request) do
    with {:ok, target} <- request_target(request),
         :ok <- ensure_callback_path(target) do
      target |> query_string() |> interpret_query()
    end
  end

  defp request_target(request) do
    request
    |> String.split(["\r\n", "\n"])
    |> List.first()
    |> case do
      nil -> {:error, 400, "Malformed sign-in callback request"}
      line -> target_from_request_line(line)
    end
  end

  defp target_from_request_line(line) do
    case String.split(line, " ") do
      [_method, target | _rest] -> {:ok, target}
      _other -> {:error, 400, "Malformed sign-in callback request"}
    end
  end

  defp ensure_callback_path(target) do
    if target |> String.split("?") |> List.first() == @callback_path do
      :ok
    else
      {:error, 404, "Unexpected callback path: #{target}"}
    end
  end

  defp query_string(target) do
    case String.split(target, "?", parts: 2) do
      [_path, query] -> query
      _other -> ""
    end
  end

  defp interpret_query(query) do
    parameters = parse_query(query)

    cond do
      error = parameters["error"] ->
        {:error, 400, "Sign-in failed: #{error}: #{parameters["error_description"] || ""}"}

      code = parameters["code"] ->
        {:ok, code}

      true ->
        {:error, 400, "Sign-in callback did not include a code"}
    end
  end

  defp parse_query(""), do: %{}

  defp parse_query(query) do
    query
    |> String.split("&")
    |> Enum.reduce(%{}, fn pair, parameters ->
      case String.split(pair, "=", parts: 2) do
        [key, value] -> Map.put(parameters, key, url_decode(value))
        _other -> parameters
      end
    end)
  end

  defp url_decode(value) do
    value |> String.replace("+", " ") |> URI.decode()
  end

  defp send_response(client, status, body) do
    reason =
      case status do
        200 -> "OK"
        400 -> "Bad Request"
        404 -> "Not Found"
        _other -> "OK"
      end

    payload =
      "HTTP/1.1 #{status} #{reason}\r\n" <>
        "Content-Type: text/html; charset=utf-8\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n" <>
        "Connection: close\r\n\r\n" <> body

    :gen_tcp.send(client, payload)
  end

  defp exchange_code(code, verifier, opts) do
    base = Keyword.get(opts, :base_url, OpenRouter.base_url())

    request =
      Req.new(
        url: base <> "/auth/keys",
        json: %{code: code, code_verifier: verifier, code_challenge_method: "S256"},
        headers: [accept: "application/json"],
        retry: false
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status, body: %{"key" => key}}} when status in 200..299 and is_binary(key) ->
        {:ok, key}

      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:error, "OpenRouter OAuth response did not include a key: #{inspect(body)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "OpenRouter OAuth key exchange failed (HTTP #{status}): #{exchange_detail(body)}"}

      {:error, reason} ->
        {:error, "OpenRouter key exchange request failed: #{inspect(reason)}"}
    end
  end

  defp exchange_detail(%{"error" => error}) when is_binary(error), do: error
  defp exchange_detail(%{"message" => message}) when is_binary(message), do: message
  defp exchange_detail(_body), do: "unknown error"
end
