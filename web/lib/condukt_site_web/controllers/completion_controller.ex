defmodule ConduktSiteWeb.CompletionController do
  use ConduktSiteWeb, :controller

  alias ConduktSite.CompletionRequest
  alias ConduktSite.OpenRouter

  def create(conn, params) do
    case get_session(conn, :openrouter_key) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Log in with OpenRouter before starting a conversation."})

      key ->
        complete(conn, key, params)
    end
  end

  defp complete(conn, key, params) do
    case CompletionRequest.validate(params) do
      {:ok, request} ->
        complete_valid_request(conn, key, request)

      {:error, message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: message})
    end
  end

  defp complete_valid_request(conn, key, request) do
    case OpenRouter.complete(key, request) do
      {:ok, message} ->
        json(conn, message)

      {:error, status, message} ->
        conn |> put_status(status) |> json(%{error: message})
    end
  end
end
