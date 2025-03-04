defmodule Quokka.ConfigTest do
  use ExUnit.Case, async: false
  use Mimic

  import Quokka.Config

  alias Credo.Check.Readability.MaxLineLength
  alias Quokka.Style.Configs
  alias Quokka.Style.Deprecations

  test "no config is good times" do
    assert :ok = set!([])
  end

  test "respects the `:only` configuration" do
    assert :ok = set!(quokka: [only: [:deprecations]])
    assert [Deprecations] == Quokka.Config.get_styles()
  end

  test "respects the `:exclude` configuration" do
    assert :ok = set!(quokka: [exclude: [:deprecations]])

    # Check for one of the default configs
    assert Configs in Quokka.Config.get_styles()

    # Check that the excluded config is not present
    assert Deprecations not in Quokka.Config.get_styles()
  end

  test "respects the `:only` and `:exclude` configuration" do
    assert :ok = set!(quokka: [only: [:configs, :deprecations], exclude: [:deprecations]])

    assert [Configs] == Quokka.Config.get_styles()
  end

  test "only applies line-length changes if :line_length is present in the `:only` configuration" do
    assert :ok = set!(quokka: [only: [:line_length]])
    assert [] == Quokka.Config.get_styles()
  end

  test "respects the formatter_opts line_length configuration" do
    Mimic.expect(Credo.ConfigFile, :read_or_default, fn _, _ -> {:ok, %{checks: []}} end)
    assert :ok = set!(line_length: 999)
    assert Quokka.Config.get(:line_length) == 999
  end

  test "prioritize the minimum of line_length from .credo.exs and .formatter.exs (credo less)" do
    Mimic.expect(Credo.ConfigFile, :read_or_default, fn _, _ ->
      {:ok, %{checks: [{MaxLineLength, [max_length: 100]}]}}
    end)

    assert :ok = set!(line_length: 200)
    assert Quokka.Config.get(:line_length) == 100
  end

  test "prioritize the minimum of line_length from .credo.exs and .formatter.exs (formatter less)" do
    Mimic.expect(Credo.ConfigFile, :read_or_default, fn _, _ ->
      {:ok, %{checks: [{MaxLineLength, [max_length: 300]}]}}
    end)

    assert :ok = set!(line_length: 200)
    assert Quokka.Config.get(:line_length) == 200
  end
end
