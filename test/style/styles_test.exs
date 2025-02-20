# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.StylesTest do
  @moduledoc """
  A place for tests that make sure our styles play nicely with each other
  """
  use Quokka.StyleCase, async: true
  use Mimic

  describe "pipes + defs" do
    test "pipes doesn't abuse meta and break defs" do
      stub(Quokka.Config, :zero_arity_parens?, fn -> true end)
      stub(Quokka.Config, :single_pipe_flag?, fn -> true end)

      assert_style(
        """
        foo
        |> bar(fn baz ->
          def widget do
            :bop
          end
        end)
        """,
        """
        bar(foo, fn baz ->
          def widget() do
            :bop
          end
        end)
        """
      )
    end
  end
end
