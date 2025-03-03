# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka do
  @moduledoc """
  Quokka is a formatter plugin with stronger opinions on code organization, multi-line defs and other code-style matters.
  """
  @behaviour Mix.Tasks.Format

  alias Mix.Tasks.Format
  alias Quokka.Style.ModuleDirectives
  alias Quokka.StyleError
  alias Quokka.Zipper

  @doc false
  def style({ast, comments}, file, opts) do
    on_error = opts[:on_error] || :log
    zipper = Zipper.zip(ast)

    {{ast, _}, comments} =
      Enum.reduce(Quokka.Config.get_styles(), {zipper, comments}, fn style, {zipper, comments} ->
        context = %{comments: comments, file: file}

        try do
          {zipper, %{comments: comments}} = Zipper.traverse_while(zipper, context, &style.run/2)
          {zipper, comments}
        rescue
          exception ->
            exception = StyleError.exception(exception: exception, style: style, file: file)

            if on_error == :log do
              error = Exception.format(:error, exception, __STACKTRACE__)
              Mix.shell().error("#{error}\n#{IO.ANSI.reset()}Skipping style and continuing on")
              {zipper, context}
            else
              reraise exception, __STACKTRACE__
            end
        end
      end)

    zipper = Zipper.zip(ast)
    moduledoc_placeholder = ModuleDirectives.moduledoc_placeholder()

    {{ast, _}, _} =
      Zipper.traverse_while(zipper, nil, fn
        {{:@, _, [{:moduledoc, _, [{:__block__, _, [^moduledoc_placeholder]}]}]}, _} = z, _ ->
          {:cont, Zipper.remove(z), nil}

        z, _ ->
          {:cont, z, nil}
      end)

    {ast, comments}
  end

  @impl Format
  def features(_opts), do: [sigils: [], extensions: [".ex", ".exs"]]

  @impl Format
  def format(input, formatter_opts \\ []) do
    file = formatter_opts[:file]
    styler_opts = formatter_opts[:quokka] || []

    Quokka.Config.set(formatter_opts)

    if Quokka.Config.allowed_directory?(file) do
      {ast, comments} =
        input
        |> string_to_ast(to_string(file))
        |> style(file, styler_opts)

      ast_to_string(ast, comments, formatter_opts)
    else
      input
    end
  end

  @doc false
  # Wrap `Code.string_to_quoted_with_comments` with our desired options
  def string_to_ast(code, file \\ "nofile") when is_binary(code) do
    Code.string_to_quoted_with_comments!(code,
      literal_encoder: &__MODULE__.literal_encoder/2,
      token_metadata: true,
      unescape: false,
      file: file
    )
  end

  @doc false
  def literal_encoder(literal, meta), do: {:ok, {:__block__, meta, [literal]}}

  @doc "Turns an ast and comments back into code, formatting it along the way."
  def ast_to_string(ast, comments \\ [], formatter_opts \\ []) do
    opts = [{:comments, comments}, {:escape, false} | formatter_opts]
    line_length = Quokka.Config.line_length()

    formatted =
      ast
      |> Code.quoted_to_algebra(opts)
      |> Inspect.Algebra.format(line_length)

    IO.iodata_to_binary([formatted, ?\n])
  end
end
