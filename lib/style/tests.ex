# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.Tests do
  @moduledoc """
  Rewrites test assertions to use `refute` and `assert` where appropriate.

  ## Transformations

  - `assert not expr` becomes `refute expr`
  - `assert !expr` becomes `refute expr`
  - `refute not expr` becomes `assert expr`
  - `refute !expr` becomes `assert expr`

  ## Examples

      # Before
      assert not user.active?
      assert !valid?
      refute not user.inactive?
      refute !invalid?

      # After
      refute user.active?
      refute valid?
      assert user.inactive?
      assert invalid?
  """

  @behaviour Quokka.Style

  alias Quokka.Zipper

  def run({{:assert, meta, [arg]}, _} = zipper, ctx) do
    case rewrite_assertion(arg) do
      {:refute, new_arg} ->
        new_node = {:refute, meta, [new_arg]}
        {:cont, Zipper.replace(zipper, new_node), ctx}

      :no_change ->
        {:cont, zipper, ctx}
    end
  end

  def run({{:refute, meta, [arg]}, _} = zipper, ctx) do
    case rewrite_refute_assertion(arg) do
      {:assert, new_arg} ->
        new_node = {:assert, meta, [new_arg]}
        {:cont, Zipper.replace(zipper, new_node), ctx}

      :no_change ->
        {:cont, zipper, ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  # assert not expr -> refute expr
  defp rewrite_assertion({:not, _meta, [expr]}), do: {:refute, expr}

  # assert !expr -> refute expr
  defp rewrite_assertion({:!, _meta, [expr]}), do: {:refute, expr}

  # No rewrite needed
  defp rewrite_assertion(_), do: :no_change

  # refute not expr -> assert expr
  defp rewrite_refute_assertion({:not, _meta, [expr]}), do: {:assert, expr}

  # refute !expr -> assert expr
  defp rewrite_refute_assertion({:!, _meta, [expr]}), do: {:assert, expr}

  # No rewrite needed
  defp rewrite_refute_assertion(_), do: :no_change

  # TODO: These transformations are not semantically equivalent and are commented out
  # because assert expr == nil only passes when expr is nil, while refute expr
  # passes when expr is any falsy value (nil or false).
  # May bring these back in the future somehow, because most of the time,
  # refute is appropriate even though not semantically equivalent.

  # # assert is_nil(expr) -> refute expr
  # defp rewrite_assertion({{:., _dot_meta, [{:__aliases__, _alias_meta, [:Kernel]}, :is_nil]}, _call_meta, [expr]}),
  #   do: {:refute, expr}

  # defp rewrite_assertion({:is_nil, _meta, [expr]}), do: {:refute, expr}

  # # assert expr == nil -> refute expr
  # defp rewrite_assertion({:==, _meta, [expr, {:__block__, _, [nil]}]}), do: {:refute, expr}

  # # assert expr === nil -> refute expr
  # defp rewrite_assertion({:===, _meta, [expr, {:__block__, _, [nil]}]}), do: {:refute, expr}

  # # assert expr == false -> refute expr
  # defp rewrite_assertion({:==, _meta, [expr, {:__block__, _, [false]}]}), do: {:refute, expr}

  # # assert expr === false -> refute expr
  # defp rewrite_assertion({:===, _meta, [expr, {:__block__, _, [false]}]}), do: {:refute, expr}
end
