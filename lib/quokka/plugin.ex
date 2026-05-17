defmodule Quokka.Plugin do
  @moduledoc """
  Provides support for writing Quokka plugins.

  Plugins are custom style rules that integrate with the Quokka auto-formatter.
  They run after all built-in styles, in the order they are declared in your
  `.formatter.exs` configuration.

  ## Usage

  Create a module that uses `Quokka.Plugin` and implements the `run/2` callback:

      defmodule MyApp.Styles.CurlyQuotes do
        use Quokka.Plugin, description: "Converts straight quotes to curly quotes in strings"

        @impl Quokka.Style
        def run({{:__block__, [{:delimiter, ~s(")} | _] = node_meta, [string]}, zipper_meta}, ctx)
            when is_binary(string) do
          new_string = String.replace(string, "'s", "’s")
          {:cont, {{:__block__, node_meta, [new_string]}, zipper_meta}, ctx}
        end

        def run(zipper, ctx), do: {:cont, zipper, ctx}
      end

  ## Configuration

  Register plugins in your `.formatter.exs`:

      [
        plugins: [Quokka],
        inputs: ["lib/**/*.ex", "test/**/*.exs"],
        quokka: [
          requires: ["lib/my_app/quokka_plugins/*.ex"],
          plugins: [
            MyApp.Styles.CurlyQuotes,
            {MyApp.Styles.CustomRule, option_1: "value", option_2: "other"}
          ]
        ]
      ]

  ## Execution Order

  1. Built-in styles run first (in their internal order)
  2. Plugins run after, in the order declared in `.formatter.exs`

  This means plugins get "the last word" on styling and can modify or undo
  what built-in styles did.

  ## Plugin Options

  The `use Quokka.Plugin` macro accepts:

  - `:description` - A short description of what the plugin does

  ## Accessing Configuration

  If your plugin is registered with options like `{MyPlugin, foo: "bar"}`,
  you can access those options via `ctx.plugin_opts`:

      def run(zipper, %{plugin_opts: opts} = ctx) do
        foo = Keyword.get(opts, :foo, "default")
        # ...
      end
  """

  @doc """
  Returns metadata about a plugin module.

  ## Keys

  - `:description` - The plugin's description
  - `:all` - All options passed to `use Quokka.Plugin`
  """
  @callback __quokka_plugin__(atom()) :: term()

  @optional_callbacks __quokka_plugin__: 1

  defmacro __using__(opts) do
    quote do
      @behaviour Quokka.Style

      @quokka_plugin_opts unquote(opts)

      @doc false
      def __quokka_plugin__(:description), do: @quokka_plugin_opts[:description]
      def __quokka_plugin__(:all), do: @quokka_plugin_opts
    end
  end

  @doc """
  Validates that a module is a valid Quokka plugin.

  Returns `{:ok, module}` if valid, or `{:error, reason}` if not.
  """
  @spec validate(module()) :: {:ok, module()} | {:error, String.t()}
  def validate(module) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, "module #{inspect(module)} could not be loaded"}

      not function_exported?(module, :run, 2) ->
        {:error, "module #{inspect(module)} must implement run/2 callback"}

      true ->
        {:ok, module}
    end
  end
end
