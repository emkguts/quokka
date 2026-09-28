defmodule Quokka.ConfigTest do
  use Quokka.StyleCase, async: false
  use Mimic

  import Quokka.Config

  alias Credo.Check.Design.AliasUsage
  alias Credo.Check.Readability.MaxLineLength
  alias Credo.Check.Readability.MultiAlias
  alias Credo.Check.Refactor.CondStatements
  alias Credo.Check.Refactor.NegatedConditionsWithElse
  alias Quokka.Style.Autosort
  alias Quokka.Style.CommentDirectives
  alias Quokka.Style.Configs
  alias Quokka.Style.Deprecations
  alias Quokka.Style.Pipes

  test "no config is good times" do
    assert :ok = set!([])
  end

  test "respects the `:only` configuration" do
    assert :ok = set!(quokka: [only: [:deprecations]])
    assert [CommentDirectives, Deprecations] == Quokka.Config.get_styles()
  end

  test "respects the `:exclude` configuration" do
    assert :ok = set!(quokka: [exclude: [:deprecations]])

    # Check for one of the default configs
    assert Configs in Quokka.Config.get_styles()

    # Check that the excluded config is not present
    refute Deprecations in Quokka.Config.get_styles()
  end

  test "exclude: [:comment_directives] has no effect" do
    assert :ok = set!(quokka: [exclude: [:comment_directives]])

    assert CommentDirectives in Quokka.Config.get_styles()

    {_, styled, _} =
      style("""
      # quokka:sort
      [:c, :a, :b]
      """)

    assert styled == "# quokka:sort\n[:a, :b, :c]"
  end

  test "only: [:comment_directives] does not enable config autosort" do
    assert :ok = set!(quokka: [autosort: [:map], only: [:comment_directives]])

    assert CommentDirectives in Quokka.Config.get_styles()
    refute Autosort in Quokka.Config.get_styles()
  end

  test "comment directives run even when not in :only" do
    assert :ok = set!(quokka: [only: [:pipes]])

    assert CommentDirectives in Quokka.Config.get_styles()
    assert Pipes in Quokka.Config.get_styles()
  end

  test "excluding :autosort disables config autosort but not comment directives" do
    assert :ok = set!(quokka: [autosort: [:map], exclude: [:autosort]])

    assert CommentDirectives in Quokka.Config.get_styles()
    refute Autosort in Quokka.Config.get_styles()
  end

  test "respects the `:only` and `:exclude` configuration" do
    assert :ok = set!(quokka: [only: [:configs, :deprecations], exclude: [:deprecations]])

    assert [CommentDirectives, Configs] == Quokka.Config.get_styles()
  end

  test "only applies line-length changes if :line_length is present in the `:only` configuration" do
    assert :ok = set!(quokka: [only: [:line_length]])
    assert [CommentDirectives] == Quokka.Config.get_styles()
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

  test "disabling CondStatements in Credo disables the rewrite and preserves cond statements" do
    stub_credo_checks(%{
      enabled: [],
      disabled: [{CondStatements, []}]
    })

    assert :ok = set!([])

    refute Quokka.Config.cond_statements?()
    assert_style("cond do\n  a -> b\n  true -> c\nend")
  end

  test "disabled Credo checks override entries in the enabled section" do
    stub_credo_checks(%{
      enabled: [{MultiAlias, []}],
      disabled: [{MultiAlias, []}]
    })

    assert :ok = set!([])

    refute Quokka.Config.rewrite_multi_alias?()
  end

  test "does not rewrite negated conditions when Credo disables the check" do
    stub_credo_checks(%{enabled: [{NegatedConditionsWithElse, false}]})

    assert :ok = set!([])

    assert_style("if !foo, do: :bar, else: :baz")
  end

  test "merges nested .credo.exs files that use the `extra` form" do
    # Outside the project, so the project's own .credo.exs is not picked up
    tmp_dir = Path.join(System.tmp_dir!(), "quokka-credo-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    nested = Path.join(tmp_dir, "nested")
    File.mkdir_p!(nested)

    File.write!(Path.join(tmp_dir, ".credo.exs"), """
    %{configs: [%{name: "default", checks: %{extra: [{Credo.Check.Readability.MultiAlias, []}]}}]}
    """)

    File.write!(Path.join(nested, ".credo.exs"), """
    %{configs: [%{name: "default", checks: %{extra: [{Credo.Check.Design.AliasUsage, [if_nested_deeper_than: 1]}]}}]}
    """)

    File.cd!(nested, fn -> assert :ok = set!([]) end)

    assert Quokka.Config.rewrite_multi_alias?()
    assert Quokka.Config.lift_alias?()
    assert Quokka.Config.lift_alias_depth() == 1
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

  test "parses elixir_version from .formatter.exs with different requirement formats" do
    test_cases = [
      {~s(~> 1), "1.0.0"},
      {~s(~> 1.15), "1.15.0"},
      {~s(>= 1.16.0), "1.16.0"},
      {~s(== 1.17.0), "1.17.0"},
      {~s(> 1.18.0), "1.18.0"},
      {~s(>= 1.15.0 and < 2.0.0), "1.15.0"},
      {~s(>= 1.15.0-dev), "1.15.0-dev"}
    ]

    Enum.each(test_cases, fn {requirement, expected} ->
      assert :ok = Quokka.Config.set!(quokka: [elixir_version: requirement])
      assert expected == Quokka.Config.elixir_version()
    end)
  end

  test "falls back to System.version() when elixir_version is not set" do
    assert :ok = Quokka.Config.set!([])
    assert System.version() == Quokka.Config.elixir_version()
  end

  defp stub_credo_checks(checks) do
    Mimic.expect(Credo.ConfigFile, :read_or_default, fn _, _ ->
      {:ok, %Credo.ConfigFile{checks: checks}}
    end)
  end
end
