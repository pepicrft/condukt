defmodule Condukt.Session.TranslateTest do
  use ExUnit.Case, async: true

  alias Condukt.Session.Translate

  describe "llm_opts/2" do
    test "omits every unset option so the provider's own defaults apply" do
      assert Translate.llm_opts([], []) == []
    end

    test "carries the api key, base url, and tools" do
      opts = Translate.llm_opts([api_key: "sk-test", base_url: "https://proxy.test/v1"], [:tool])

      assert opts[:api_key] == "sk-test"
      assert opts[:base_url] == "https://proxy.test/v1"
      assert opts[:tools] == [:tool]
    end

    # A reasoning model spends the output budget thinking before it writes any
    # answer, so a ceiling sized for the answer alone truncates the response
    # mid-thought and returns empty content.
    test "carries an output-token ceiling when one is configured" do
      assert Translate.llm_opts([max_tokens: 16_384], [])[:max_tokens] == 16_384
    end

    test "omits the ceiling when it is unset" do
      refute Keyword.has_key?(Translate.llm_opts([max_tokens: nil], []), :max_tokens)
    end

    test "translates the thinking level into a reasoning effort" do
      assert Translate.llm_opts([thinking_level: :off], [])[:reasoning_effort] == :none
      assert Translate.llm_opts([thinking_level: :high], [])[:reasoning_effort] == :high
      refute Keyword.has_key?(Translate.llm_opts([thinking_level: nil], []), :reasoning_effort)
    end
  end
end
