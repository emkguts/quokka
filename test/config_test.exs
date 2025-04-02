defmodule Quokka.ConfigTest do
  use ExUnit.Case, async: false
  use Mimic

  import Quokka.Config

  alias Credo.Check.Design.AliasUsage
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

  test "parses autosort in both formats" do
    assert :ok = set!(quokka: [autosort: [:map, schema: [:field, :belongs_to]]])
    assert [:map, :schema] == Quokka.Config.autosort()

    assert :ok = set!(quokka: [autosort: [:map, :schema]])
    assert [:map, :schema] == Quokka.Config.autosort()
  end

  test "sets autosort_schema_format correctly" do
    assert :ok = set!(quokka: [autosort: [:map, schema: [:many_to_many, :embeds_one]]])

    assert [:many_to_many, :embeds_one, :field, :belongs_to, :has_many, :has_one, :embeds_many] ==
             Quokka.Config.autosort_schema_order()
  end

  test "sets lift_alias_excluded_lastnames correctly" do
    Mimic.expect(Credo.ConfigFile, :read_or_default, fn _, _ ->
      {:ok, %{checks: [{AliasUsage, [excluded_lastnames: ["Name2"]]}]}}
    end)

    assert :ok = Quokka.Config.set!([])

    MapSet.member?(Quokka.Config.lift_alias_excluded_lastnames(), "Name2")
    # check that stdlib is included in the exclusions
    MapSet.member?(Quokka.Config.lift_alias_excluded_lastnames(), "File")
  end

  test "sets lift_alias_excluded_namespaces correctly" do
    Mimic.expect(Credo.ConfigFile, :read_or_default, fn _, _ ->
      {:ok, %{checks: [{AliasUsage, [excluded_namespaces: ["Name2"]]}]}}
    end)

    assert :ok = Quokka.Config.set!([])

    MapSet.member?(Quokka.Config.lift_alias_excluded_namespaces(), "Name2")
    # check that stdlib is included in the exclusions
    MapSet.member?(Quokka.Config.lift_alias_excluded_namespaces(), "File")
  end
end
