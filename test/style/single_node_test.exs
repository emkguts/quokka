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

  describe "folds non-piped Kernel operators into inline expressions" do
    test "binary operator" do
      assert_style "Kernel./(total, size)", "total / size"
      assert_style "Kernel.++(a, b)", "a ++ b"
      assert_style "Kernel.<>(a, b)", "a <> b"
      assert_style "Kernel.in(a, b)", "a in b"
      assert_style "Kernel.and(a, b)", "a and b"
    end

    test "every binary Kernel operator" do
      for op <- ~w(++ -- && || in - * + / > < <= >= == and or != !== === <>) do
        assert_style "Kernel.#{op}(a, b)", "a #{op} b"
      end
    end

    test "unary operator" do
      assert_style "Kernel.-(x)", "-x"
      assert_style "Kernel.+(x)", "+x"
      assert_style "Kernel.!(x)", "!x"
      assert_style "Kernel.not(x)", "not x"
    end

    test "folds when nested in other expressions" do
      assert_style "foo(Kernel./(a, b))", "foo(a / b)"
      assert_style "x = Kernel.*(a, b)", "x = a * b"
      assert_style "Kernel./(a, b) + c", "a / b + c"
    end

    test "preserves operator precedence with parens" do
      # `*` binds tighter than `+`, so the folded subtraction needs parens to keep its meaning
      assert_style "Kernel.*(Kernel.-(a, b), c)", "(a - b) * c"
    end

    test "leaves a piped Kernel operator alone (the Pipes style owns those)" do
      # later in a chain the operand count differs and folding would change semantics
      assert_style "a |> b() |> Kernel.++(c)"
      assert_style "a |> b() |> Kernel.-(c)"
    end
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

  describe "Timex.today/0,1" do
    test "Timex.today/0 => Date.utc_today/0" do
      assert_style("Timex.today()", "Date.utc_today()")
      assert_style("Timex.today() |> foo() |> bar()", "Date.utc_today() |> foo() |> bar()")
    end

    test "leaves Timex.today/1 alone" do
      assert_style("Timex.today(tz)", "Timex.today(tz)")

      assert_style(
        """
        timezone
        |> Timex.today()
        |> foo()
        """,
        """
        timezone
        |> Timex.today()
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
      assert_style("assert %{id: ^my_id} = Repo.one(query)")
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
      assert_style("%{id: id} = Repo.one(query)")
      assert_style("%{id: ^id} = Repo.one(query)")
      assert_style("%{id: 123} = Repo.one(query)")
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

    test "does not rewrite Repo.get in conditionals when matching to its result" do
      assert_style("""
      if my_var = Repo.one(Post) do
        :ok
      end
      """)

      assert_style("""
      if my_var = Repo.one(Post) && another_condition? do
        :ok
      end
      """)

      assert_style("""
      if ^my_var = Repo.one(Post) do
        :ok
      end
      """)

      assert_style("""
      if %{name: "foo"} = Repo.one(Post) do
        :ok
      end
      """)

      assert_style("""
      if Repo.one(Post, timeout: 5000) = my_var do
        :ok
      end
      """)

      assert_style("""
      if Repo.one(from(p in Post, where: p.id == ^id), timeout: 5000) = my_var do
        :ok
      else
        :error
      end
      """)
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

  describe "Map.get/3 with nil default rewrites" do
    test "rewrites Map.get(map, key, nil) to Map.get(map, key)" do
      assert_style("Map.get(map, :key, nil)", "Map.get(map, :key)")
      assert_style("Map.get(map, \"key\", nil)", "Map.get(map, \"key\")")
      assert_style("Map.get(map, key, nil)", "Map.get(map, key)")

      assert_style("map |> Map.get(:key, nil)", "map |> Map.get(:key)")
      assert_style("map |> Map.get(\"key\", nil)", "map |> Map.get(\"key\")")
      assert_style("map |> Map.get(key, nil)", "map |> Map.get(key)")
    end

    test "preserves Map.get with non-nil defaults" do
      assert_style("Map.get(map, key, default)")
      assert_style("Map.get(map, key, \"default\")")
      assert_style("Map.get(map, key, :default)")

      assert_style("map |> Map.get(key, default)")
      assert_style("map |> Map.get(key, \"default\")")
      assert_style("map |> Map.get(key, :default)")
    end
  end

  describe "Keyword.get/3 with nil default rewrites" do
    test "rewrites Keyword.get(kw, key, nil) to Keyword.get(kw, key)" do
      assert_style("Keyword.get(kw, :key, nil)", "Keyword.get(kw, :key)")
      assert_style("Keyword.get(kw, \"key\", nil)", "Keyword.get(kw, \"key\")")
      assert_style("Keyword.get(kw, key, nil)", "Keyword.get(kw, key)")

      assert_style("kw |> Keyword.get(:key, nil)", "kw |> Keyword.get(:key)")
      assert_style("kw |> Keyword.get(\"key\", nil)", "kw |> Keyword.get(\"key\")")
      assert_style("kw |> Keyword.get(key, nil)", "kw |> Keyword.get(key)")
    end

    test "preserves Keyword.get with non-nil defaults" do
      assert_style("Keyword.get(kw, key, default)")
      assert_style("Keyword.get(kw, key, \"default\")")
      assert_style("Keyword.get(kw, key, :default)")

      assert_style("kw |> Keyword.get(key, default)")
      assert_style("kw |> Keyword.get(key, \"default\")")
      assert_style("kw |> Keyword.get(key, :default)")
    end
  end

  describe "anonymous function capture rewrites" do
    test "rewrites &anon_func(&n) to &anon_func/n" do
      assert_style("&my_function(&1)", "&my_function/1")
      assert_style("&SomeModule.func(&1)", "&SomeModule.func/1")
      assert_style("&some_variable.(&1)", "some_variable")
      assert_style("&my_function(&2)", "&my_function/2")
      assert_style("&SomeModule.func(&2)", "&SomeModule.func/2")

      assert_style(
        """
        admin? = fn %{user_id: user_id} ->
          user_id == 1
        end

        Enum.any?(users, &admin?.(&1))
        """,
        """
        admin? = fn %{user_id: user_id} ->
          user_id == 1
        end

        Enum.any?(users, admin?)
        """
      )
    end

    test "works in various contexts" do
      assert_style("var |> func(&anon_func(&1))", "var |> func(&anon_func/1)")
      assert_style("my_func1(&my_func2(&2))", "my_func1(&my_func2/2)")
      assert_style("Enum.map(list, &String.upcase(&1))", "Enum.map(list, &String.upcase/1)")
    end

    test "respects inefficient_functions config" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)
      assert_style("&func(&1)")
      assert_style("&func(&2)")

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)
      assert_style("&func(&1)", "&func/1")
      assert_style("&func(&2)", "&func/2")
    end

    test "does not rewrite more complex captures" do
      assert_style("&func(&1, &2)")
      assert_style("&func(&1 + 1)")
      assert_style("&func(some_arg, &1)")
      assert_style("&(&1 + &2)")
      assert_style("& &1.(&2)")
      assert_style("Enum.reduce(actions, 0, & &1.run/2)")
      assert_style("Enum.reduce(actions, state, & &1.run(&2))")
      assert_style("Enum.reduce(actions, state, & &1.run(&1, &2))")
    end
  end

  describe "Enum.reduce summing => Enum.sum" do
    test "rewrites summing reducer with fn x, acc -> x + acc end" do
      assert_style(
        "Enum.reduce(enum, 0, fn x, acc -> x + acc end)",
        "Enum.sum(enum)"
      )
    end

    test "rewrites summing reducer with operands in either order" do
      assert_style(
        "Enum.reduce(enum, 0, fn x, acc -> acc + x end)",
        "Enum.sum(enum)"
      )
    end

    test "rewrites &(&1 + &2) capture" do
      assert_style("Enum.reduce(enum, 0, &(&1 + &2))", "Enum.sum(enum)")
      assert_style("Enum.reduce(enum, 0, &(&2 + &1))", "Enum.sum(enum)")
    end

    test "rewrites &+/2 and &Kernel.+/2 captures" do
      assert_style("Enum.reduce(enum, 0, &+/2)", "Enum.sum(enum)")
      assert_style("Enum.reduce(enum, 0, &Kernel.+/2)", "Enum.sum(enum)")
    end

    test "rewrites piped form" do
      assert_style(
        """
        string
        |> String.to_charlist()
        |> Enum.reduce(0, fn x, acc -> x + acc end)
        """,
        """
        string
        |> String.to_charlist()
        |> Enum.sum()
        """
      )
    end

    test "rewrites single-pipe form" do
      assert_style(
        "enum |> Enum.reduce(0, fn x, acc -> x + acc end)",
        "enum |> Enum.sum()"
      )
    end

    test "rewrites piped capture forms" do
      assert_style("enum |> Enum.reduce(0, &(&1 + &2))", "enum |> Enum.sum()")
      assert_style("enum |> Enum.reduce(0, &+/2)", "enum |> Enum.sum()")
    end

    test "does not rewrite a pipe-fed non-zero accumulator into Enum.sum/2" do
      # The inner node is `Enum.reduce(<acc>, &+/2)`: its first argument is the
      # accumulator (the enumerable is piped from the left), not the enumerable.
      # Rewriting would emit `enum |> Enum.sum(<acc>)` => `Enum.sum/2`, which
      # exists in no Elixir version. Only the zero-accumulator pure sum is
      # rewritten (handled at the pipe node, see below); every other initial
      # accumulator must be left intact.
      assert_style("enum |> Enum.reduce(0.0, &+/2)")
      assert_style("enum |> Enum.reduce(1, &+/2)")
      assert_style("enum |> Enum.reduce(acc, &+/2)")
      assert_style("enum |> Enum.reduce(%{}, fn x, acc -> x + acc end)")
      # lhs of the pipe is still traversed/untouched (subtree not skipped).
      assert_style("Enum.map(c, & &1.v) |> Enum.reduce(0.0, &+/2)")

      # The zero-accumulator pure-sum pipe is still rewritten.
      assert_style("enum |> Enum.reduce(0, &+/2)", "enum |> Enum.sum()")
    end

    test "rewrites Enum.reduce/2 summing form" do
      assert_style(
        "Enum.reduce(enum, fn x, acc -> x + acc end)",
        "Enum.sum(enum)"
      )

      assert_style("Enum.reduce(enum, &+/2)", "Enum.sum(enum)")
      assert_style("Enum.reduce(enum, &(&1 + &2))", "Enum.sum(enum)")

      assert_style(
        "enum |> Enum.reduce(fn x, acc -> x + acc end)",
        "enum |> Enum.sum()"
      )

      assert_style(
        """
        string
        |> String.to_charlist()
        |> Enum.reduce(fn x, acc -> x + acc end)
        """,
        """
        string
        |> String.to_charlist()
        |> Enum.sum()
        """
      )
    end

    test "does not rewrite when accumulator is not zero" do
      assert_style("Enum.reduce(enum, 1, fn x, acc -> x + acc end)")
      assert_style("Enum.reduce(enum, initial, fn x, acc -> x + acc end)")
    end

    test "does not rewrite when accumulator is 0.0 (preserves float type)" do
      assert_style("Enum.reduce(enum, 0.0, fn x, acc -> x + acc end)")
    end

    test "does not rewrite when body is not a simple sum of the two args" do
      assert_style("Enum.reduce(enum, 0, fn x, acc -> x - acc end)")
      assert_style("Enum.reduce(enum, 0, fn x, acc -> x * acc end)")
      assert_style("Enum.reduce(enum, 0, fn x, acc -> x + acc + 1 end)")
      assert_style("Enum.reduce(enum, 0, fn x, acc -> x + 1 end)")
      assert_style("Enum.reduce(enum, 0, fn x, _acc -> x end)")
      assert_style("Enum.reduce(enum, 0, fn x, _acc -> x + x end)")
      assert_style("Enum.reduce(enum, fn x, acc -> x - acc end)")
      assert_style("Enum.reduce(enum, fn x, acc -> x * acc end)")
      assert_style("Enum.reduce(enum, fn x, acc -> x + acc + 1 end)")
      assert_style("Enum.reduce(enum, fn x, acc -> x + 1 end)")
      assert_style("Enum.reduce(enum, fn x, _acc -> x end)")
      assert_style("Enum.reduce(enum, fn x, _acc -> x + x end)")
    end

    test "does not rewrite non-Enum modules" do
      assert_style("MyMod.reduce(enum, 0, fn x, acc -> x + acc end)")
    end

    test "does not rewrite when capture indices are wrong" do
      assert_style("Enum.reduce(enum, 0, &(&1 + &1))")
      assert_style("Enum.reduce(enum, 0, &(&1 + &3))")
    end

    test "respects inefficient_functions config" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)
      assert_style("Enum.reduce(enum, 0, fn x, acc -> x + acc end)")
      assert_style("enum |> Enum.reduce(0, &+/2)")

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)
      assert_style("Enum.reduce(enum, 0, fn x, acc -> x + acc end)", "Enum.sum(enum)")
      assert_style("enum |> Enum.reduce(0, &+/2)", "enum |> Enum.sum()")
    end
  end

  describe "String.starts_with?/ends_with?/contains? or-chains => list form" do
    test "combines two single-string checks" do
      for function <- [:starts_with?, :ends_with?, :contains?] do
        assert_style(
          ~s|String.#{function}(foo, "bar") or String.#{function}(foo, "baz")|,
          ~s|String.#{function}(foo, ["bar", "baz"])|
        )

        assert_style(
          ~s'String.#{function}(foo, "bar") || String.#{function}(foo, "baz")',
          ~s|String.#{function}(foo, ["bar", "baz"])|
        )
      end
    end

    test "combines a list and a single string" do
      for function <- [:starts_with?, :ends_with?, :contains?] do
        assert_style(
          ~s|String.#{function}(foo, ["bar", "baz"]) or String.#{function}(foo, "bop")|,
          ~s|String.#{function}(foo, ["bar", "baz", "bop"])|
        )
      end
    end

    test "combines a single string and a list" do
      assert_style(
        ~s|String.starts_with?(foo, "bar") or String.starts_with?(foo, ["baz", "bop"])|,
        ~s|String.starts_with?(foo, ["bar", "baz", "bop"])|
      )
    end

    test "combines two lists" do
      assert_style(
        ~s|String.ends_with?(foo, ["bar", "baz"]) or String.ends_with?(foo, ["bop", "whiz"])|,
        ~s|String.ends_with?(foo, ["bar", "baz", "bop", "whiz"])|
      )
    end

    test "combines a chain of three or more" do
      assert_style(
        ~s'String.starts_with?(foo, "a") or String.starts_with?(foo, "b") || String.starts_with?(foo, "c")',
        ~s|String.starts_with?(foo, ["a", "b", "c"])|
      )

      combiners =
        Stream.repeatedly(fn -> Enum.random([:or, :||]) end)
        |> Stream.take(4)

      a_through_d =
        combiners
        |> Enum.zip(["a", "b", ["c"], "d"])
        |> Enum.map(fn {combiner, arg} -> ~s'String.starts_with?(foo, #{inspect(arg)}) #{combiner} ' end)

      assert_style(
        ~s'#{a_through_d} String.starts_with?(foo, "e") ',
        ~s|String.starts_with?(foo, ["a", "b", "c", "d", "e"])|
      )
    end

    test "works with a non-variable subject" do
      assert_style(
        ~s|String.starts_with?(get_str(), "bar") or String.starts_with?(get_str(), "baz")|,
        ~s|String.starts_with?(get_str(), ["bar", "baz"])|
      )
    end

    test "does not touch chains with a non-literal sought argument" do
      assert_style(~s|String.ends_with?(foo, bar) or String.ends_with?(foo, baz)|)
      assert_style(~s'String.starts_with?(foo, "bar") || String.starts_with?(foo, baz)')
      assert_style(~s|String.contains?(foo, [bar, "baz"]) or String.contains?(foo, "bop")|)
    end

    test "does not combine mismatched functions" do
      assert_style(~s|String.starts_with?(foo, "bar") or String.ends_with?(foo, "baz")|)
      assert_style(~s|String.contains?(foo, "bar") or String.starts_with?(foo, "baz")|)
      assert_style(~s'String.contains?(foo, "bar") || String.ends_with?(foo, "baz")')
    end

    test "does not combine mismatched subjects" do
      assert_style(~s|String.starts_with?(foo, "bar") or String.starts_with?(bar, "baz")|)
    end

    test "only combines adjacent matches in a mixed chain" do
      assert_style(
        ~s|String.starts_with?(foo, "a") or flag or String.starts_with?(foo, "b") or String.starts_with?(foo, "c")|,
        ~s|String.starts_with?(foo, "a") or flag or String.starts_with?(foo, ["b", "c"])|
      )
    end

    test "respects inefficient_functions config" do
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)
      assert_style(~s|String.starts_with?(foo, "bar") or String.starts_with?(foo, "baz")|)

      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)

      assert_style(
        ~s|String.starts_with?(foo, "bar") or String.starts_with?(foo, "baz")|,
        ~s|String.starts_with?(foo, ["bar", "baz"])|
      )
    end
  end
end
