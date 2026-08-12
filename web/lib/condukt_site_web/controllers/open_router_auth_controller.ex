defmodule ConduktSiteWeb.OpenRouterAuthController do
  use ConduktSiteWeb, :controller

  alias ConduktSite.OpenRouter

  def new(conn, params) do
    authorization =
      OpenRouter.authorization(fn state ->
        url(conn, ~p"/auth/openrouter/callback/#{state}")
      end)

    conn
    |> put_session(:openrouter_flow, %{
      "state" => authorization.state,
      "verifier" => authorization.verifier,
      "return_to" => safe_return_path(params["return_to"])
    })
    |> redirect(external: authorization.url)
  end

  def callback(conn, %{"state" => state, "code" => code}) do
    case get_session(conn, :openrouter_flow) do
      %{"state" => ^state, "verifier" => verifier, "return_to" => return_to} ->
        finish_connection(conn, code, verifier, return_to)

      _ ->
        conn
        |> delete_session(:openrouter_flow)
        |> put_flash(:error, "The OpenRouter sign-in request expired. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, _params) do
    conn
    |> delete_session(:openrouter_flow)
    |> put_flash(:error, "OpenRouter did not return an authorization code.")
    |> redirect(to: ~p"/")
  end

  def delete(conn, _params) do
    conn
    |> delete_session(:openrouter_key)
    |> delete_session(:openrouter_flow)
    |> configure_session(renew: true)
    |> put_flash(:info, "Disconnected from OpenRouter.")
    |> redirect(to: ~p"/")
  end

  defp finish_connection(conn, code, verifier, return_to) do
    case OpenRouter.exchange_code(code, verifier) do
      {:ok, key} ->
        conn
        |> delete_session(:openrouter_flow)
        |> put_session(:openrouter_key, key)
        |> configure_session(renew: true)
        |> put_flash(:info, "OpenRouter connected. You can now talk to Condukt.")
        |> redirect(to: return_to)

      {:error, message} ->
        conn
        |> delete_session(:openrouter_flow)
        |> put_flash(:error, message)
        |> redirect(to: ~p"/")
    end
  end

  defp safe_return_path(path) when is_binary(path) do
    uri = URI.parse(path)

    if uri.scheme == nil and uri.host == nil and safe_local_path?(path, uri.path) do
      path
    else
      "/"
    end
  end

  defp safe_return_path(_path), do: "/"

  defp safe_local_path?(original, parsed_path) do
    String.starts_with?(parsed_path || "", "/") and
      not String.starts_with?(original, "//") and
      not String.contains?(original, "\\") and
      not String.contains?(original, ["\r", "\n"])
  end
end
