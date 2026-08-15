defmodule Condukt.CLI.MockServer do
  @moduledoc """
  A single-shot loopback HTTP server for tests.

  Each server binds its own ephemeral port and serves one request, so tests that
  exercise the OpenRouter calls stay asynchronous and never depend on a shared
  fixture port or on the real service.
  """

  @doc """
  Starts a server that answers one request with `status` and `body`.

  Returns `{base_url, requests}` where `requests` is an agent-free reference the
  test can await with `received_request/1`.
  """
  def start(status, body) do
    test = self()

    {:ok, socket} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true, packet: :raw])

    {:ok, port} = :inet.port(socket)

    spawn_link(fn -> serve(socket, status, body, test) end)

    {"http://127.0.0.1:#{port}", port}
  end

  @doc "Waits for the request the server received, failing the test on timeout."
  def received_request(timeout \\ 2_000) do
    receive do
      {:mock_request, request} -> request
    after
      timeout -> raise "the mock server did not receive a request"
    end
  end

  defp serve(socket, status, body, test) do
    {:ok, client} = :gen_tcp.accept(socket, 5_000)
    {:ok, request} = :gen_tcp.recv(client, 0, 5_000)
    send(test, {:mock_request, request})

    response =
      "HTTP/1.1 #{status} #{reason(status)}\r\n" <>
        "Content-Type: application/json\r\n" <>
        "Content-Length: #{byte_size(body)}\r\n" <>
        "Connection: close\r\n\r\n" <> body

    :gen_tcp.send(client, response)
    :gen_tcp.close(client)
    :gen_tcp.close(socket)
  end

  defp reason(200), do: "OK"
  defp reason(400), do: "Bad Request"
  defp reason(401), do: "Unauthorized"
  defp reason(_status), do: "Status"
end
