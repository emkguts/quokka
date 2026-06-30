defmodule Quokka.ConfigTest do
  use ExUnit.Case, async: false
  use Mimic

  import Quokka.Config
  import Quokka.StyleCase, only: [style: 1]

  alias Credo.Check.Design.AliasUsage
  alias Credo.Check.Readability.MaxLineLength
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

  test "parses elixir version from mix.exs with different requirement formats" do
    test_cases = [
      {~s("~> 1"), "1.0.0"},
      {~s("~> 1.15"), "1.15.0"},
      {~s(">= 1.16.0"), "1.16.0"},
      {~s("== 1.17.0"), "1.17.0"},
      {~s("> 1.18.0"), "1.18.0"},
      {~s(">= 1.15.0 and < 2.0.0"), "1.15.0"},
      {~s(">= 1.15.0-dev"), "1.15.0-dev"}
    ]

    Enum.each(test_cases, fn {requirement, expected} ->
      Mimic.stub(Mix.Project, :config, fn ->
        [elixir: requirement]
      end)

      assert :ok = Quokka.Config.set!([])
      assert expected == Quokka.Config.elixir_version()
    end)
  end

  test "falls back to System.version() if mix.exs cannot be read" do
    Mimic.stub(Mix.Project, :config, fn ->
      [elixir: "bogus"]
    end)

    assert :ok = Quokka.Config.set!([])
    assert System.version() == Quokka.Config.elixir_version()
  end

  describe "allowed_directory?/1 with `:files`" do
    test "excludes via a bare directory prefix (legacy behaviour)" do
      assert :ok = set!(quokka: [files: %{excluded: ["lib/quokka/"]}])

      refute Quokka.Config.allowed_directory?("lib/quokka/config.ex")
      assert Quokka.Config.allowed_directory?("lib/styler.ex")
    end

    test "excludes via a single-segment glob pattern" do
      assert :ok = set!(quokka: [files: %{excluded: ["lib/quokka/*.ex"]}])

      refute Quokka.Config.allowed_directory?("lib/quokka/config.ex")
      # `*` does not cross directory boundaries
      assert Quokka.Config.allowed_directory?("lib/quokka/config/credo.ex")
    end

    test "excludes via a recursive `**` glob pattern" do
      assert :ok = set!(quokka: [files: %{excluded: ["lib/**/*.ex"]}])

      refute Quokka.Config.allowed_directory?("lib/quokka/config.ex")
      refute Quokka.Config.allowed_directory?("lib/quokka/config/credo.ex")
    end

    test "includes only files matching a glob pattern" do
      assert :ok = set!(quokka: [files: %{included: ["lib/quokka/*.ex"]}])

      assert Quokka.Config.allowed_directory?("lib/quokka/config.ex")
      refute Quokka.Config.allowed_directory?("lib/styler.ex")
    end

    test "exclusion wins over inclusion" do
      assert :ok = set!(quokka: [files: %{included: ["lib/**/*.ex"], excluded: ["lib/quokka/*.ex"]}])

      refute Quokka.Config.allowed_directory?("lib/quokka/config.ex")
      assert Quokka.Config.allowed_directory?("lib/styler.ex")
    end

    test "empty `:files` allows everything" do
      assert :ok = set!([])

      assert Quokka.Config.allowed_directory?("lib/quokka/config.ex")
    end
  end
end
