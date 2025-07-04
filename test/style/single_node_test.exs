# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.SingleNodeTest do
  use Quokka.StyleCase, async: true
  use Mimic

  setup do
    stub(Quokka.Config, :zero_arity_parens?, fn -> true end)

    :ok
  end

  test "string sigil rewrites" do
    assert_style ~s|""|
    assert_style ~s|"\\""|
    assert_style ~s|"\\"\\""|
    assert_style ~s|"\\"\\"\\""|
    assert_style ~s|"\\"\\"\\"\\""|, ~s|~s("""")|

    # choose closing delimiter wisely, based on what has the least conflicts, in the styliest order
    assert_style ~s/"\\"\\"\\"\\" )"/, ~s/~s{"""" )}/
    assert_style ~s/"\\"\\"\\"\\" })"/, ~s/~s|"""" })|/
    assert_style ~s/"\\"\\"\\"\\" |})"/, ~s/~s["""" |})]/
    assert_style ~s/"\\"\\"\\"\\" ]|})"/, ~s/~s'"""" ]|})'/
    assert_style ~s/"\\"\\"\\"\\" ']|})"/, ~s/~s<"""" ']|})>/
    assert_style ~s/"\\"\\"\\"\\" >']|})"/, ~s|~s/"""" >']\|})/|
    assert_style ~s/"\\"\\"\\"\\" \/>']|})"/, ~s|~s("""" />']\|}\\))|
  end

  describe "{Keyword/Map}.merge/2 of a single key => *.put/3" do
    test "in a pipe" do
      for module <- ~w(Map Keyword) do
        assert_style(
          "foo |> #{module}.merge(%{one_key: :bar}) |> bop()",
          "foo |> #{module}.put(:one_key, :bar) |> bop()"
        )
      end
    end

    test "normal call" do
      for module <- ~w(Map Keyword) do
        assert_style(
          "#{module}.merge(foo, %{one_key: :bar})",
          "#{module}.put(foo, :one_key, :bar)"
        )

        assert_style("#{module}.merge(foo, one_key: :bar)", "#{module}.put(foo, :one_key, :bar)")
        # # doesn't rewrite if there's a custom merge strategy
        assert_style("#{module}.merge(foo, %{one_key: :bar}, custom_merge_strategy)")
        # # doesn't rewrite if > 1 key
        assert_style("#{module}.merge(foo, %{a: :b, c: :d})")
      end
    end
  end

  test "{Map/Keyword}.drop with a single key" do
    for module <- ~w(Map Keyword) do
      for singular <- ~w(:key key %{} [] 1 "key") do
        assert_style("#{module}.drop(foo, [#{singular}])", "#{module}.delete(foo, #{singular})")

        assert_style(
          "foo |> #{module}.drop([#{singular}]) |> bar()",
          "foo |> #{module}.delete(#{singular}) |> bar()"
        )
      end

      assert "#{module}.drop(foo, [])"
      assert "foo |> #{module}.drop([]) |> bar()"

      for plurality <- ["[]", "[a, b]", "[a | b]", "some_list"] do
        assert_style("#{module}.drop(foo, #{plurality})")
        assert_style("foo |> #{module}.drop(#{plurality}) |> bar()")
      end
    end
  end

  describe "checking empty enums" do
    test "Enum.count(enum, fn) == 0 => not Enum.any?(enum, fn)" do
      assert_style("Enum.count(foo, &my_fn/1) == 0", "not Enum.any?(foo, &my_fn/1)")
      assert_style("0 == Enum.count(foo, &my_fn/1)", "not Enum.any?(foo, &my_fn/1)")
      assert_style("foo |> bar() |> Enum.count(fn v -> length(v) end) == 0")
      assert_style("0 == foo |> bar() |> Enum.count(&my_fn/1)")
    end

    test "Enum.count(enum, fn) > 0 => Enum.any?(enum, fn)" do
      assert_style("Enum.count(foo, &my_fn/1) > 0", "Enum.any?(foo, &my_fn/1)")
      assert_style("0 < Enum.count(foo, &my_fn/1)", "Enum.any?(foo, &my_fn/1)")
      assert_style("Enum.count(foo, fn v -> length(v) end) > 0", "Enum.any?(foo, fn v -> length(v) end)")

      assert_style(
        "foo |> bar() |> Enum.count(fn v -> length(v) end) > 0",
        "foo |> bar() |> Enum.any?(fn v -> length(v) end)"
      )

      assert_style("0 < foo |> bar() |> Enum.count(&my_fn/1)", "foo |> bar() |> Enum.any?(&my_fn/1)")
    end

    test "Enum.count(enum, fn) != 0 => Enum.any?(enum, fn)" do
      assert_style("Enum.count(foo, &my_fn/1) != 0", "Enum.any?(foo, &my_fn/1)")

      assert_style(
        "foo |> bar() |> Enum.count(fn v -> length(v) end) != 0",
        "foo |> bar() |> Enum.any?(fn v -> length(v) end)"
      )

      assert_style("0 != foo |> bar() |> Enum.count(&my_fn/1)", "foo |> bar() |> Enum.any?(&my_fn/1)")
    end

    test "length(enum) == 0 => Enum.empty?(enum)" do
      assert_style("length(foo) == 0", "Enum.empty?(foo)")
      assert_style("0 == length(foo)", "Enum.empty?(foo)")
      assert_style("foo |> bar() |> length() === 0", "foo |> bar() |> Enum.empty?()")
      assert_style("0 == foo |> bar() |> length()", "foo |> bar() |> Enum.empty?()")
    end

    test "Enum.count(enum) == 0 => Enum.empty?(enum)" do
      assert_style("Enum.count(foo) == 0", "Enum.empty?(foo)")
      assert_style("0 == Enum.count(foo)", "Enum.empty?(foo)")
      assert_style("foo |> bar() |> Enum.count() === 0", "foo |> bar() |> Enum.empty?()")
      assert_style("0 == foo |> bar() |> Enum.count()", "foo |> bar() |> Enum.empty?()")
    end

    test "length(enum) > 0 => not Enum.empty?(enum)" do
      assert_style("length(foo) > 0", "not Enum.empty?(foo)")
      assert_style("0 < length(foo)", "not Enum.empty?(foo)")
    end

    test "length(enum) != 0 => not Enum.empty?(enum)" do
      assert_style("length(foo) != 0", "not Enum.empty?(foo)")
      assert_style("0 != length(foo)", "not Enum.empty?(foo)")
    end

    test "Enum.count(enum) > 0 => not Enum.empty?(enum)" do
      assert_style("Enum.count(foo) > 0", "not Enum.empty?(foo)")
      assert_style("0 < Enum.count(foo)", "not Enum.empty?(foo)")
    end

    test "Enum.count(enum) != 0 => not Enum.empty?(enum)" do
      assert_style("Enum.count(foo) != 0", "not Enum.empty?(foo)")
      assert_style("0 != Enum.count(foo)", "not Enum.empty?(foo)")
    end

    test "does not monkey with other variants of length or count functions" do
      assert_style("MyModule.length(foo) == 0", "MyModule.length(foo) == 0")
      assert_style("MyModule.Enum.count(foo) == 0", "MyModule.Enum.count(foo) == 0")
      assert_style("MyModule.Enum.count(foo, &my_fn/1) == 0", "MyModule.Enum.count(foo, &my_fn/1) == 0")
    end

    test "rewrites length in guards to guard-friendly expressions" do
      assert_style(
        """
        defmodule MyModule do
          def foo(bar) when length(bar) == 0 do
            :ok
          end

          defmodule Nested do
            def baz(bop) when length(bop) > 0 do
              :ok
            end
          end
        end
        """,
        """
        defmodule MyModule do
          def foo(bar) when bar == [] do
            :ok
          end

          defmodule Nested do
            def baz(bop) when is_list(bop) and bop != [] do
              :ok
            end
          end
        end
        """
      )

      # Function guards with length
      assert_style(
        """
        def foo(list) when length(list) > 0 do
          :ok
        end
        """,
        """
        def foo(list) when is_list(list) and list != [] do
          :ok
        end
        """
      )

      assert_style(
        """
        defp bar(items) when is_list(items) and length(items) > 0 do
          :ok
        end
        """,
        """
        defp bar(items) when is_list(items) and (is_list(items) and items != []) do
          :ok
        end
        """
      )

      # Function guards with Enum.count
      assert_style("""
      def baz(enum) when Enum.count(enum) > 0 do
        :not_empty
      end
      """)

      # Case statement guards
      assert_style(
        """
        case list do
          items when length(items) > 0 -> :has_items
          _ -> :empty
        end
        """,
        """
        case list do
          items when is_list(items) and items != [] -> :has_items
          _ -> :empty
        end
        """
      )

      # Multiple guard conditions
      assert_style(
        """
        def process(data) when is_list(data) and length(data) == 0 do
          :empty_list
        end
        """,
        """
        def process(data) when is_list(data) and data == [] do
          :empty_list
        end
        """
      )

      # Guards with < operator
      assert_style(
        """
        def validate(items) when 0 < length(items) do
          :valid
        end
        """,
        """
        def validate(items) when is_list(items) and [] != items do
          :valid
        end
        """
      )

      # Test length(enum) != 0 in guards
      assert_style(
        """
        def process(data) when length(data) != 0 do
          :non_empty
        end
        """,
        """
        def process(data) when is_list(data) and data != [] do
          :non_empty
        end
        """
      )

      # Test 0 != length(enum) in guards
      assert_style(
        """
        def process(data) when 0 != length(data) do
          :non_empty
        end
        """,
        """
        def process(data) when is_list(data) and [] != data do
          :non_empty
        end
        """
      )

      # Test 0 == length(enum) in guards
      assert_style(
        """
        def process(data) when 0 == length(data) do
          :empty
        end
        """,
        """
        def process(data) when [] == data do
          :empty
        end
        """
      )
    end

    test "rewrites length/count checks outside guard clauses" do
      # Normal function bodies should still be rewritten
      assert_style(
        """
        defmodule MyModule do
          def foo(list) when length(list) > 0 do
            perform_side_effect(list)

            if length(list) > 0 do
              :ok
            end
          end

          def baz(bop) when is_list(bop) do
            if Enum.count(bop) == 0 or length(bop) == 0 do
              :ok
            end
          end

          def whiz(a, b, c, d, e) when (length(a) > 0 and is_list(b)) or (is_list(c) and length(c) > 0) or (is_map(d) and length(e) == 3) do
            if length(bop) > 0 do
              :ok
            end
          end

          defmodule Nested do
            def bar(list) when length(list) == 0 do
              if length(list) == 0 do
                :ok
              end
            end
          end
        end
        """,
        """
        defmodule MyModule do
          def foo(list) when is_list(list) and list != [] do
            perform_side_effect(list)

            if not Enum.empty?(list) do
              :ok
            end
          end

          def baz(bop) when is_list(bop) do
            if Enum.empty?(bop) or Enum.empty?(bop) do
              :ok
            end
          end

          def whiz(a, b, c, d, e)
              when (is_list(a) and a != [] and is_list(b)) or (is_list(c) and (is_list(c) and c != [])) or
                     (is_map(d) and length(e) == 3) do
            if not Enum.empty?(bop) do
              :ok
            end
          end

          defmodule Nested do
            def bar(list) when list == [] do
              if Enum.empty?(list) do
                :ok
              end
            end
          end
        end
        """
      )

      # Case expressions (not guards) should be rewritten
      assert_style(
        """
        case length(items) > 0 do
          true -> :has_items
          false -> :empty
        end
        """,
        """
        case not Enum.empty?(items) do
          true -> :has_items
          false -> :empty
        end
        """
      )
    end
  end

  describe "Timex.now/0,1" do
    test "Timex.now/0 => DateTime.utc_now/0" do
      assert_style("Timex.now()", "DateTime.utc_now()")
      assert_style("Timex.now() |> foo() |> bar()", "DateTime.utc_now() |> foo() |> bar()")
    end

    test "leaves Timex.now/1 alone" do
      assert_style("Timex.now(tz)", "Timex.now(tz)")

      assert_style(
        """
        timezone
        |> Timex.now()
        |> foo()
        """,
        """
        timezone
        |> Timex.now()
        |> foo()
        """
      )
    end
  end

  test "{DateTime,NaiveDateTime,Time,Date}.compare to {DateTime,NaiveDateTime,Time,Date}.before?" do
    assert_style("DateTime.compare(foo, bar) == :lt", "DateTime.before?(foo, bar)")
    assert_style("NaiveDateTime.compare(foo, bar) == :lt", "NaiveDateTime.before?(foo, bar)")
    assert_style("Time.compare(foo, bar) == :lt", "Time.before?(foo, bar)")
    assert_style("Date.compare(foo, bar) == :lt", "Date.before?(foo, bar)")
  end

  test "{DateTime,NaiveDateTime,Time,Date}.compare to {DateTime,NaiveDateTime,Time,Date}.after?" do
    assert_style("DateTime.compare(foo, bar) == :gt", "DateTime.after?(foo, bar)")
    assert_style("NaiveDateTime.compare(foo, bar) == :gt", "NaiveDateTime.after?(foo, bar)")
    assert_style("Time.compare(foo, bar) == :gt", "Time.after?(foo, bar)")
    assert_style("Time.compare(foo, bar) == :gt", "Time.after?(foo, bar)")
  end

  describe "def / defp" do
    test "0-arity functions have parens added" do
      assert_style("def foo, do: :ok", "def foo(), do: :ok")
      assert_style("defp foo, do: :ok", "defp foo(), do: :ok")

      assert_style(
        """
        def foo do
        :ok
        end
        """,
        """
        def foo() do
          :ok
        end
        """
      )

      assert_style(
        """
        defp foo do
        :ok
        end
        """,
        """
        defp foo() do
          :ok
        end
        """
      )

      # Regression: be wary of invocations with extra parens from metaprogramming
      assert_style("def metaprogramming(foo)(), do: bar")
    end

    test "0-arity functions have parens removed when Quokka.Config.zero_arity_parens? is false" do
      stub(Quokka.Config, :zero_arity_parens?, fn -> false end)

      assert_style("def foo(), do: :ok", "def foo, do: :ok")
      assert_style("defp foo(), do: :ok", "defp foo, do: :ok")

      assert_style(
        """
        def foo() do
        :ok
        end
        """,
        """
        def foo do
          :ok
        end
        """
      )

      assert_style(
        """
        defp foo() do
        :ok
        end
        """,
        """
        defp foo do
          :ok
        end
        """
      )

      # Regression: be wary of invocations with extra parens from metaprogramming
      assert_style("def metaprogramming(foo)(), do: bar")
    end

    test "prefers implicit try" do
      for def_style <- ~w(def defp) do
        assert_style(
          """
          #{def_style} foo() do
            try do
              :ok
            rescue
              exception -> :excepted
            catch
              :a_throw -> :thrown
            else
              i_forgot -> i_forgot.this_could_happen
            after
              :done
            end
          end
          """,
          """
          #{def_style} foo() do
            :ok
          rescue
            exception -> :excepted
          catch
            :a_throw -> :thrown
          else
            i_forgot -> i_forgot.this_could_happen
          after
            :done
          end
          """
        )
      end
    end

    test "doesnt rewrite when there are other things in the body" do
      assert_style("""
      def foo() do
        try do
          :ok
        rescue
          exception -> :excepted
        end

        :after_try
      end
      """)
    end
  end

  describe "RHS pattern matching" do
    test "left arrows" do
      assert_style(
        "with {:ok, result = %{}} <- foo, do: result",
        "with {:ok, %{} = result} <- foo, do: result"
      )

      assert_style("for map = %{} <- maps, do: map[:key]", "for %{} = map <- maps, do: map[:key]")
    end

    test "case statements" do
      assert_style(
        """
        case foo do
          bar = %{baz: baz? = true} -> :baz?
          opts = [[a = %{}] | _] -> a
        end
        """,
        """
        case foo do
          %{baz: true = baz?} = bar -> :baz?
          [[%{} = a] | _] = opts -> a
        end
        """
      )
    end

    test "regression: ignores unquoted cases" do
      assert_style("case foo, do: unquote(quoted)")
    end

    test "removes a double-var assignment when one var is _" do
      assert_style("def foo(_ = bar), do: bar", "def foo(bar), do: bar")
      assert_style("def foo(bar = _), do: bar", "def foo(bar), do: bar")

      assert_style(
        """
        case foo do
          bar = _ -> :ok
        end
        """,
        """
        case foo do
          bar -> :ok
        end
        """
      )

      assert_style(
        """
        case foo do
          _ = bar -> :ok
        end
        """,
        """
        case foo do
          bar -> :ok
        end
        """
      )
    end

    test "defs" do
      assert_style(
        "def foo(bar = %{baz: baz? = true}, opts = [[a = %{}] | _]), do: :ok",
        "def foo(%{baz: true = baz?} = bar, [[%{} = a] | _] = opts), do: :ok"
      )
    end

    test "anonymous functions" do
      assert_style(
        "fn bar = %{baz: baz? = true}, opts = [[a = %{}] | _] -> :ok end",
        "fn %{baz: true = baz?} = bar, [[%{} = a] | _] = opts -> :ok end"
      )
    end

    test "leaves those poor case statements alone!" do
      assert_style("""
      cond do
        foo = Repo.get(Bar, 1) -> foo
        x == y -> :kaboom?
        true -> :else
      end
      """)
    end

    test "with statements" do
      assert_style(
        """
        with ok = :ok <- foo, :ok <- yeehaw() do
          ok
        else
          error = :error -> error
          other -> other
        end
        """,
        """
        with :ok = ok <- foo, :ok <- yeehaw() do
          ok
        else
          :error = error -> error
          other -> other
        end
        """
      )
    end
  end

  describe "numbers" do
    test "styles floats and integers with >4 digits" do
      stub(Quokka.Config, :large_numbers_gt, fn -> 9999 end)
      assert_style("10000", "10_000")
      assert_style("1_0_0_0_0", "10_000")
      assert_style("-543213", "-543_213")
      assert_style("123456789", "123_456_789")
      assert_style("55333.22", "55_333.22")
      assert_style("-123456728.0001", "-123_456_728.0001")
    end

    test "stays away from small numbers, strings and science" do
      assert_style("1234")
      assert_style("9999")
      assert_style(~s|"10000"|)
      assert_style("0xFFFF")
      assert_style("0x123456")
      assert_style("0b1111_1111_1111_1111")
      assert_style("0o777_7777")
    end

    test "respects quokka config exclude: :nums_with_underscores" do
      stub(Quokka.Config, :exclude_nums_with_underscores?, fn -> true end)
      assert_style("100_00", "100_00")
      assert_style("1_0_0_0_0", "1_0_0_0_0")

      stub(Quokka.Config, :exclude_nums_with_underscores?, fn -> false end)
      assert_style("100_00", "10_000")
      assert_style("1_0_0_0_0", "10_000")
    end

    test "respects credo config :only_greater_than" do
      stub(Quokka.Config, :large_numbers_gt, fn -> 20_000 end)
      assert_style("20000", "20000")
      assert_style("20001", "20_001")
    end

    test "respects credo config LargeNumbers false" do
      stub(Quokka.Config, :large_numbers_gt, fn -> :infinity end)
      assert_style("10000", "10000")
    end
  end

  describe "Enum.into and $collectable.new" do
    test "into an empty map" do
      assert_style("Enum.into(a, %{})", "Map.new(a)")
      assert_style("Enum.into(a, %{}, mapper)", "Map.new(a, mapper)")
    end

    test "into a list" do
      assert_style("Enum.into(a, [])", "Enum.to_list(a)")
      assert_style("Enum.into(a, [], mapper)", "Enum.map(a, mapper)")
      assert_style("a |> Enum.into([]) |> bar()", "a |> Enum.to_list() |> bar()")
      assert_style("a |> Enum.into([], mapper) |> bar()", "a |> Enum.map(mapper) |> bar()")
    end

    test "into a collectable" do
      assert_style("Enum.into(a, foo)")
      assert_style("Enum.into(a, foo, mapper)")

      for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
        assert_style("Enum.into(a, #{new})", "#{new}(a)")
        assert_style("Enum.into(a, #{new}, mapper)", "#{new}(a, mapper)")
      end
    end
  end

  describe "Enum.reverse/1 and ++" do
    test "optimizes into `Enum.reverse/2`" do
      assert_style("Enum.reverse(foo) ++ bar", "Enum.reverse(foo, bar)")
      assert_style("Enum.reverse(foo, bar) ++ bar")
    end
  end

  describe "to_timeout" do
    test "to next unit" do
      facts = [
        {1000, :millisecond, :second},
        {60, :second, :minute},
        {60, :minute, :hour},
        {24, :hour, :day},
        {7, :day, :week}
      ]

      for {n, unit, next} <- facts do
        assert_style "to_timeout(#{unit}: #{n} * m)", "to_timeout(#{next}: m)"
        assert_style "to_timeout(#{unit}: m * #{n})", "to_timeout(#{next}: m)"
        assert_style "to_timeout(#{unit}: #{n})", "to_timeout(#{next}: 1)"
      end

      assert_style "to_timeout(second: 60 * 60)", "to_timeout(hour: 1)"
    end

    test "doesnt mess with" do
      assert_style "to_timeout(hour: n * m)"
      assert_style "to_timeout(whatever)"
      assert_style "to_timeout(hour: 24 * 1, second: 60 * 4)"
    end
  end

  describe "assert Repo.one/1 rewrites" do
    test "rewrites Repo.one in assertions to Repo.exists?" do
      # Make sure legitimate comparisons are not rewritten
      assert_style("assert Repo.one(query) == %{some: :struct}")
      assert_style("assert Repo.one(query) |> Map.get(:my_key)")

      assert_style("assert Repo.one(query)", "assert Repo.exists?(query)")
      assert_style("assert MyApp.Repo.one(query)", "assert MyApp.Repo.exists?(query)")

      assert_style(
        "assert DB.Repo.one(from(u in User, where: u.active))",
        "assert DB.Repo.exists?(from(u in User, where: u.active))"
      )
    end

    test "preserves arguments and complex queries" do
      assert_style(
        "assert Repo.one(from(u in User, where: u.id == ^id, select: u.id))",
        "assert Repo.exists?(from(u in User, where: u.id == ^id, select: u.id))"
      )

      assert_style(
        "assert MyApp.Repo.one(query, timeout: 5000)",
        "assert MyApp.Repo.exists?(query, timeout: 5000)"
      )
    end

    test "does not rewrite non-Repo modules ending in different names" do
      assert_style("assert User.one(query)")
      assert_style("assert MyModule.one(query)")
      assert_style("assert Enum.one(query)")
    end

    test "does not rewrite non-assert/refute contexts" do
      assert_style("Repo.one(query)")
      assert_style("thing = Repo.one(query)")
    end

    test "handles piped Repo.one calls in assertions" do
      assert_style(
        "assert from(stuff) |> Repo.one()",
        "assert from(stuff) |> Repo.exists?()"
      )

      assert_style(
        "assert query |> MyApp.Repo.one()",
        "assert query |> MyApp.Repo.exists?()"
      )

      assert_style(
        "assert from(u in User, where: u.active) |> DB.Repo.one(timeout: 5000)",
        "assert from(u in User, where: u.active) |> DB.Repo.exists?(timeout: 5000)"
      )

      # Complex piped expressions
      assert_style(
        "assert query |> transform() |> Repo.one()",
        "assert query |> transform() |> Repo.exists?()"
      )
    end

    test "rewrites Repo.one in refute statements to Repo.exists?" do
      # Make sure legitimate comparisons are not rewritten
      assert_style("refute Repo.one(query) |> Map.get(:my_key)")

      assert_style("refute Repo.one(query)", "refute Repo.exists?(query)")
      assert_style("refute MyApp.Repo.one(query)", "refute MyApp.Repo.exists?(query)")

      assert_style(
        "refute DB.Repo.one(from(u in User, where: u.active))",
        "refute DB.Repo.exists?(from(u in User, where: u.active))"
      )

      # Preserves arguments and complex queries
      assert_style(
        "refute Repo.one(from(u in User, where: u.id == ^id, select: u.id))",
        "refute Repo.exists?(from(u in User, where: u.id == ^id, select: u.id))"
      )

      assert_style(
        "refute MyApp.Repo.one(query, timeout: 5000)",
        "refute MyApp.Repo.exists?(query, timeout: 5000)"
      )
    end

    test "handles piped Repo.one calls in refute statements" do
      assert_style(
        "refute from(stuff) |> Repo.one()",
        "refute from(stuff) |> Repo.exists?()"
      )

      assert_style(
        "refute query |> MyApp.Repo.one()",
        "refute query |> MyApp.Repo.exists?()"
      )

      assert_style(
        "refute from(u in User, where: u.active) |> DB.Repo.one(timeout: 5000)",
        "refute from(u in User, where: u.active) |> DB.Repo.exists?(timeout: 5000)"
      )

      # Complex piped expressions
      assert_style(
        "refute query |> transform() |> Repo.one()",
        "refute query |> transform() |> Repo.exists?()"
      )
    end

    test "does not rewrite non-Repo modules in refute statements" do
      assert_style("refute User.one(query)")
      assert_style("refute MyModule.one(query)")
      assert_style("refute Enum.one(query)")
    end

    test "respects inefficient_functions config" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)
      assert_style("assert Repo.one(query)")
      assert_style("assert MyApp.Repo.one(query)")
      assert_style("refute Repo.one(query)")
      assert_style("refute MyApp.Repo.one(query)")

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)
      assert_style("assert Repo.one(query)", "assert Repo.exists?(query)")
      assert_style("assert MyApp.Repo.one(query)", "assert MyApp.Repo.exists?(query)")
      assert_style("refute Repo.one(query)", "refute Repo.exists?(query)")
      assert_style("refute MyApp.Repo.one(query)", "refute MyApp.Repo.exists?(query)")
    end
  end

  describe "conditional Repo.one/1 rewrites" do
    test "rewrites Repo.one in if statements" do
      assert_style(
        """
        if Repo.one(query) do
          :ok
        end
        """,
        """
        if Repo.exists?(query) do
          :ok
        end
        """
      )

      assert_style(
        """
        if MyApp.Repo.one(query) do
          :ok
        end
        """,
        """
        if MyApp.Repo.exists?(query) do
          :ok
        end
        """
      )

      assert_style(
        """
        if DB.Repo.one(from(u in User, where: u.active)) do
          :ok
        end
        """,
        """
        if DB.Repo.exists?(from(u in User, where: u.active)) do
          :ok
        end
        """
      )
    end

    test "rewrites Repo.one in unless statements" do
      assert_style(
        """
        unless Repo.one(query) do
          :ok
        end
        """,
        """
        if !Repo.exists?(query) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless MyApp.Repo.one(query) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.exists?(query) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless DB.Repo.one(from(u in User, where: u.active)) do
          :ok
        end
        """,
        """
        if !DB.Repo.exists?(from(u in User, where: u.active)) do
          :ok
        end
        """
      )
    end

    test "rewrites Repo.one in complex conditional expressions" do
      assert_style(
        """
        if Repo.one(query) && other_condition do
          :ok
        end
        """,
        """
        if Repo.exists?(query) && other_condition do
          :ok
        end
        """
      )

      assert_style(
        """
        if other_condition || Repo.one(query) do
          :ok
        end
        """,
        """
        if other_condition || Repo.exists?(query) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless !Repo.one(query) do
          :ok
        end
        """,
        """
        if Repo.exists?(query) do
          :ok
        end
        """
      )
    end

    test "preserves arguments and complex queries in conditionals" do
      assert_style(
        """
        if Repo.one(from(u in User, where: u.id == ^id, select: u.id)) do
          :ok
        end
        """,
        """
        if Repo.exists?(from(u in User, where: u.id == ^id, select: u.id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless MyApp.Repo.one(query, timeout: 5000) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.exists?(query, timeout: 5000) do
          :ok
        end
        """
      )
    end

    test "does not rewrite non-Repo modules in conditionals" do
      assert_style("""
      if User.one(query) do
        :ok
      end
      """)

      assert_style("""
      if Enum.one(query) do
        :ok
      end
      """)
    end

    test "respects inefficient_functions config for conditionals" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)

      assert_style("""
      if Repo.one(query) do
        :ok
      end
      """)

      assert_style(
        """
        unless MyApp.Repo.one(query) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.one(query) do
          :ok
        end
        """
      )

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)

      assert_style(
        """
        if Repo.one(query) do
          :ok
        end
        """,
        """
        if Repo.exists?(query) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless MyApp.Repo.one(query) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.exists?(query) do
          :ok
        end
        """
      )
    end

    test "handles multiple Repo.one calls in conditionals" do
      assert_style(
        """
        if Repo.one(query1) && Repo.one(query2) do
          :ok
        end
        """,
        """
        if Repo.exists?(query1) && Repo.exists?(query2) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless Repo.one(query1) || MyApp.Repo.one(query2) do
          :ok
        end
        """,
        """
        if !(Repo.exists?(query1) || MyApp.Repo.exists?(query2)) do
          :ok
        end
        """
      )
    end

    test "handles piped Repo.one calls in conditionals" do
      assert_style(
        """
        if from(stuff) |> Repo.one() do
          :ok
        end
        """,
        """
        if from(stuff) |> Repo.exists?() do
          :ok
        end
        """
      )

      assert_style(
        """
        if query |> MyApp.Repo.one() do
          :ok
        end
        """,
        """
        if query |> MyApp.Repo.exists?() do
          :ok
        end
        """
      )

      assert_style(
        """
        if from(u in User, where: u.active) |> DB.Repo.one(timeout: 5000) do
          :ok
        end
        """,
        """
        if from(u in User, where: u.active) |> DB.Repo.exists?(timeout: 5000) do
          :ok
        end
        """
      )

      assert_style(
        """
        if query |> transform() |> Repo.one() && other_condition do
          :ok
        end
        """,
        """
        if query |> transform() |> Repo.exists?() && other_condition do
          :ok
        end
        """
      )
    end
  end

  describe "assert Repo.get/3 rewrites" do
    test "rewrites Repo.get in assertions to Repo.exists?" do
      # Make sure legitimate comparisons are not rewritten
      assert_style("assert Repo.get(Post, id) == %{some: :struct}")
      assert_style("assert %Post{id: ^id} = Repo.get(Post, id)")
      assert_style("assert Repo.get(Post, id) |> Map.get(:my_key)")
      assert_style("assert Repo.get(Post, id).some_field")

      assert_style("assert Repo.get(Post, id)", "assert Repo.exists?(from(p in Post, where: p.id == ^id))")
      assert_style("assert MyApp.Repo.get(Post, id)", "assert MyApp.Repo.exists?(from(p in Post, where: p.id == ^id))")

      assert_style(
        "assert DB.Repo.get(User, id, prefix: :foo)",
        "assert DB.Repo.exists?(from(u in User, where: u.id == ^id), prefix: :foo)"
      )
    end

    test "preserves arguments and complex queries" do
      assert_style(
        "assert Repo.get(User, \"abc-123\" <> some_binary)",
        "assert Repo.exists?(from(u in User, where: u.id == ^(\"abc-123\" <> some_binary)))"
      )

      assert_style(
        "assert Repo.get(User, \"abc-123\", prefix: :foo)",
        "assert Repo.exists?(from(u in User, where: u.id == \"abc-123\"), prefix: :foo)"
      )

      assert_style(
        "assert MyApp.Repo.get(User, \"abc-123\", timeout: 5000, prefix: :foo)",
        "assert MyApp.Repo.exists?(from(u in User, where: u.id == \"abc-123\"), timeout: 5000, prefix: :foo)"
      )
    end

    test "does not rewrite non-Repo modules ending in different names" do
      assert_style("assert User.get(Post)")
      assert_style("assert User.get(Post, id)")
      assert_style("assert User.get(Post, \"abc-123\")")
      assert_style("assert User.get(Post, \"abc-123\", timeout: 5000)")
      assert_style("assert MyModule.get(Post)")
      assert_style("assert MyModule.get(Post, id)")
      assert_style("assert MyModule.get(Post, \"abc-123\", timeout: 5000)")
      assert_style("assert Enum.get(Post, id)")
      assert_style("assert Enum.get(Post, \"abc-123\", timeout: 5000)")
    end

    test "does not rewrite non-assert/refute contexts" do
      assert_style("Repo.get(Post, id)")
      assert_style("thing = Repo.get(Post, id)")
    end

    test "handles piped Repo.get calls in assertions" do
      # If someone tries to pipe a query into Repo.get, it should remain unchanged.
      # Piped Repo.get calls are not common in practice since Repo.get takes 2-3 args
      # These tests verify the system doesn't break if someone pipes into Repo.get
      assert_style("assert Post |> Repo.get(id)")
      assert_style("assert Post |> MyApp.Repo.get(id)")
      assert_style("assert Post |> DB.Repo.get(id, timeout: 5000)")
      assert_style("assert query |> transform() |> Repo.get(id)")
    end

    test "rewrites Repo.get in refute statements to Repo.exists?" do
      # Make sure legitimate comparisons are not rewritten
      assert_style("refute Repo.get(Post, id) |> Map.get(:my_key)")
      assert_style("refute Repo.get(Post, id).some_field")

      assert_style("refute Repo.get(Post, id)", "refute Repo.exists?(from(p in Post, where: p.id == ^id))")
      assert_style("refute MyApp.Repo.get(Post, id)", "refute MyApp.Repo.exists?(from(p in Post, where: p.id == ^id))")

      assert_style(
        "refute DB.Repo.get(User, id)",
        "refute DB.Repo.exists?(from(u in User, where: u.id == ^id))"
      )

      # Preserves arguments and complex queries
      assert_style(
        "refute Repo.get(User, \"abc-123\")",
        "refute Repo.exists?(from(u in User, where: u.id == \"abc-123\"))"
      )

      assert_style(
        "refute MyApp.Repo.get(User, id, timeout: 5000)",
        "refute MyApp.Repo.exists?(from(u in User, where: u.id == ^id), timeout: 5000)"
      )
    end

    test "handles piped Repo.get calls in refute statements" do
      # If someone tries to pipe a query into Repo.get, it should remain unchanged.
      # Piped Repo.get calls are not common in practice since Repo.get takes 2-3 args
      # These tests verify the system doesn't break if someone pipes into Repo.get
      assert_style("refute Post |> Repo.get(id)")
      assert_style("refute Post |> MyApp.Repo.get(id)")
      assert_style("refute Post |> DB.Repo.get(id, timeout: 5000)")
      assert_style("refute query |> transform() |> Repo.get(id)")
    end

    test "does not rewrite non-Repo modules in refute statements" do
      assert_style("refute User.get(Post, id)")
      assert_style("refute MyModule.get(Post, id)")
      assert_style("refute Enum.get(Post, id)")
    end

    test "respects inefficient_functions config" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)
      assert_style("assert Repo.get(Post, id)")
      assert_style("assert MyApp.Repo.get(Post, id, timeout: 5000)")
      assert_style("refute Repo.get(Post, id)")
      assert_style("refute MyApp.Repo.get(Post, id)")

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)
      assert_style("assert Repo.get(Post, id)", "assert Repo.exists?(from(p in Post, where: p.id == ^id))")
      assert_style("assert MyApp.Repo.get(Post, id)", "assert MyApp.Repo.exists?(from(p in Post, where: p.id == ^id))")
      assert_style("refute Repo.get(Post, id)", "refute Repo.exists?(from(p in Post, where: p.id == ^id))")
      assert_style("refute MyApp.Repo.get(Post, id)", "refute MyApp.Repo.exists?(from(p in Post, where: p.id == ^id))")
    end
  end

  describe "conditional Repo.get/3 rewrites" do
    test "rewrites Repo.get in if statements" do
      assert_style(
        """
        if Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        if MyApp.Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if MyApp.Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        if DB.Repo.get(User, id) do
          :ok
        end
        """,
        """
        if DB.Repo.exists?(from(u in User, where: u.id == ^id)) do
          :ok
        end
        """
      )
    end

    test "rewrites Repo.get in unless statements" do
      assert_style(
        """
        unless Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if !Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless MyApp.Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless DB.Repo.get(User, id) do
          :ok
        end
        """,
        """
        if !DB.Repo.exists?(from(u in User, where: u.id == ^id)) do
          :ok
        end
        """
      )
    end

    test "rewrites Repo.get in complex conditional expressions" do
      assert_style(
        """
        if Repo.get(Post, id) && other_condition do
          :ok
        end
        """,
        """
        if Repo.exists?(from(p in Post, where: p.id == ^id)) && other_condition do
          :ok
        end
        """
      )

      assert_style(
        """
        if other_condition || Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if other_condition || Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless !Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )
    end

    test "preserves arguments and complex queries in conditionals" do
      assert_style(
        """
        if Repo.get(User, id, prefix: :foo) do
          :ok
        end
        """,
        """
        if Repo.exists?(from(u in User, where: u.id == ^id), prefix: :foo) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless MyApp.Repo.get(User, id, timeout: 5000) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.exists?(from(u in User, where: u.id == ^id), timeout: 5000) do
          :ok
        end
        """
      )
    end

    test "does not rewrite non-Repo modules in conditionals" do
      assert_style("""
      if User.get(Post, id) do
        :ok
      end
      """)

      assert_style("""
      if Enum.get(Post, id) do
        :ok
      end
      """)
    end

    test "respects inefficient_functions config for conditionals" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)

      assert_style("""
      if Repo.get(Post, id) do
        :ok
      end
      """)

      assert_style(
        """
        unless MyApp.Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.get(Post, id) do
          :ok
        end
        """
      )

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)

      assert_style(
        """
        if Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless MyApp.Repo.get(Post, id) do
          :ok
        end
        """,
        """
        if !MyApp.Repo.exists?(from(p in Post, where: p.id == ^id)) do
          :ok
        end
        """
      )
    end

    test "handles multiple Repo.get calls in conditionals" do
      assert_style(
        """
        if Repo.get(Post, id1) && Repo.get(User, id2) do
          :ok
        end
        """,
        """
        if Repo.exists?(from(p in Post, where: p.id == ^id1)) && Repo.exists?(from(u in User, where: u.id == ^id2)) do
          :ok
        end
        """
      )

      assert_style(
        """
        unless Repo.get(Post, id1) || MyApp.Repo.get(User, id2) do
          :ok
        end
        """,
        """
        if !(Repo.exists?(from(p in Post, where: p.id == ^id1)) || MyApp.Repo.exists?(from(u in User, where: u.id == ^id2))) do
          :ok
        end
        """
      )
    end

    test "handles piped Repo.get calls in conditionals" do
      # Note: Piped Repo.get calls are not common in practice since Repo.get takes 2-3 args
      # These tests verify the system doesn't break if someone pipes into Repo.get
      # Since piped calls to Repo.get are unusual, they should remain unchanged
      assert_style("""
      if Post |> Repo.get(id) do
        :ok
      end
      """)

      assert_style("""
      if User |> MyApp.Repo.get(id) do
        :ok
      end
      """)

      assert_style("""
      if Post |> DB.Repo.get(id) do
        :ok
      end
      """)

      assert_style("""
      if query |> transform() |> Repo.get(id) && other_condition do
        :ok
      end
      """)
    end
  end
end
