defmodule Quokka.Test.Plugins.CurlyQuotes do
  @moduledoc """
  A sample Quokka plugin that transforms straight apostrophes in possessives
  (like `'s`) to curly apostrophes (`’s`) within string literals.

  This serves as an example of how to write a Quokka plugin and is used in tests.
  """
  use Quokka.Plugin, description: "Converts straight apostrophes to curly quotes in strings"

  @default_patterns [{"'s", "’s"}]

  @impl Quokka.Style
  def run({{:__block__, [{:delimiter, ~s(")} | _] = node_meta, [string]}, zipper_meta}, ctx) when is_binary(string) do
    patterns = Keyword.get(ctx.plugin_opts, :patterns, @default_patterns)
    new_string = apply_replacements(string, patterns)
    {:cont, {{:__block__, node_meta, [new_string]}, zipper_meta}, ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp apply_replacements(string, patterns) do
    Enum.reduce(patterns, string, fn {from, to}, acc ->
      String.replace(acc, from, to)
    end)
  end
end

defmodule Quokka.Test.Plugins.StraightQuotes do
  @moduledoc "Transforms all curly single quotes to straight quotes in strings."
  use Quokka.Plugin, description: "Converts curly single quotes to straight quotes in strings"

  @impl Quokka.Style
  def run({{:__block__, [{:delimiter, ~s(")} | _] = node_meta, [string]}, zipper_meta}, ctx) when is_binary(string) do
    new_string = String.replace(string, "’", "'")
    {:cont, {{:__block__, node_meta, [new_string]}, zipper_meta}, ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}
end

defmodule NoRunCallback do
  def not_run(_, _), do: :ok
end

defmodule Quokka.PluginTest do
  # Can't be async because it monkeys with the global config to add a plugin
  use Quokka.StyleCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Quokka.Style.SingleNode
  alias Quokka.Test.Plugins.CurlyQuotes
  alias Quokka.Test.Plugins.StraightQuotes

  setup do
    on_exit(fn ->
      Quokka.Config.set!(quokka: [plugins: []])
    end)

    :ok
  end

  describe "Quokka.Plugin.validate/1" do
    test "validates a module with run/2 callback" do
      assert {:ok, CurlyQuotes} = Quokka.Plugin.validate(CurlyQuotes)
    end

    test "returns error for module without run/2" do
      assert {:error, message} = Quokka.Plugin.validate(NoRunCallback)
      assert message =~ "must implement run/2"
    end

    test "returns error for non-existent module" do
      assert {:error, message} = Quokka.Plugin.validate(NonExistentModule)
      assert message =~ "could not be loaded"
    end
  end

  describe "plugin registration in config" do
    test "registers plugins from config" do
      assert :ok = Quokka.Config.set!(quokka: [plugins: [CurlyQuotes]])
      assert CurlyQuotes in Quokka.Config.plugins()
    end

    test "registers plugins with options" do
      assert :ok = Quokka.Config.set!(quokka: [plugins: [{CurlyQuotes, patterns: [{"'t", "'t"}]}]])
      assert CurlyQuotes in Quokka.Config.plugins()
      assert [patterns: [{"'t", "'t"}]] = Quokka.Config.plugin_opts(CurlyQuotes)
    end

    test "plugins appear after built-in styles in get_styles" do
      assert :ok = Quokka.Config.set!(quokka: [plugins: [CurlyQuotes]])
      styles = Quokka.Config.get_styles()

      # CurlyQuotes should be last
      assert List.last(styles) == CurlyQuotes

      # Built-in styles should come before
      assert SingleNode in styles
      single_node_index = Enum.find_index(styles, &(&1 == SingleNode))
      curly_quotes_index = Enum.find_index(styles, &(&1 == CurlyQuotes))
      assert single_node_index < curly_quotes_index
    end

    test "plugins run in declaration order" do
      assert :ok =
               Quokka.Config.set!(
                 quokka: [
                   plugins: [
                     {CurlyQuotes, patterns: [{"'t", "'t"}]},
                     StraightQuotes
                   ]
                 ]
               )

      assert_style(
        """
        defmodule Foo do
          def bar(), do: "the dog's bone"
          def baz(), do: "the cat’s bowl"
        end
        """,
        """
        defmodule Foo do
          def bar(), do: "the dog's bone"
          def baz(), do: "the cat's bowl"
        end
        """
      )
    end

    test "warns about invalid plugins" do
      log =
        capture_log(fn ->
          Quokka.Config.set!(quokka: [plugins: [NoRunCallback]])
        end)

      assert log =~ "Invalid Quokka plugin"
      refute NoRunCallback in Quokka.Config.plugins()
    end
  end

  describe "CurlyQuotes plugin" do
    setup do
      Quokka.Config.set!(quokka: [plugins: [CurlyQuotes]])
      :ok
    end

    test "transforms straight apostrophe to curly in double-quoted strings" do
      assert_style(
        """
        defmodule Foo do
          def bar(), do: "the dog's bone"
        end
        """,
        """
        defmodule Foo do
          def bar(), do: "the dog’s bone"
        end
        """
      )
    end

    test "transforms multiple occurrences" do
      assert_style(
        """
        defmodule Foo do
          @module_attr "the girl's ball and the boy's toy"

          def bar(), do: "the dog's bone and cat's toy"

        end
        """,
        """
        defmodule Foo do
          @module_attr "the girl’s ball and the boy’s toy"

          def bar(), do: "the dog’s bone and cat’s toy"
        end
        """
      )
    end

    test "leaves strings without apostrophes unchanged" do
      assert_style(
        """
        defmodule Foo do
          def bar(), do: "the dog and cat"
        end
        """,
        """
        defmodule Foo do
          def bar(), do: "the dog and cat"
        end
        """
      )
    end

    test "respects custom patterns from plugin options" do
      Quokka.Config.set!(quokka: [plugins: [{CurlyQuotes, patterns: [{"'t", "’t"}]}]])

      assert_style(
        """
        defmodule Foo do
          def bar(), do: "the dog's and cat's"
          def baz(), do: "don't do that"
        end
        """,
        """
        defmodule Foo do
          def bar(), do: "the dog's and cat's"
          def baz(), do: "don’t do that"
        end
        """
      )
    end
  end
end
