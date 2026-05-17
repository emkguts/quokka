# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.CommentDirectives do
  @moduledoc """
  Leave a comment for Quokka asking it to maintain code in a certain way.

  `# quokka:sort` maintains sorting of wordlists (by string comparison) and lists (string comparison of code representation)
  """

  @behaviour Quokka.Style

  alias Quokka.Style
  alias Quokka.Style.Autosort
  alias Quokka.Zipper

  def run(zipper, ctx) do
    {zipper, comments} =
      ctx.comments
      |> Enum.filter(&(&1.text == "# quokka:sort"))
      |> Enum.map(& &1.line)
      |> Enum.reduce({zipper, ctx.comments}, fn line, {zipper, comments} ->
        found = Zipper.find(zipper, &(line + 1 == Style.meta(&1)[:line]))

        if found do
          {sorted, comments} = found |> Zipper.node() |> Autosort.sort(comments)
          {Zipper.replace(found, sorted), comments}
        else
          {zipper, comments}
        end
      end)

    {:skip, zipper, %{ctx | comments: comments}}
  end
end
