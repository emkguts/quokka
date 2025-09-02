# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.PipesTest do
  use Quokka.StyleCase, async: true
  use Mimic

  setup do
    stub(Quokka.Config, :single_pipe_flag?, fn -> true end)
    stub(Quokka.Config, :refactor_pipe_chain_starts?, fn -> true end)

    :ok
  end

  describe "big picture" do
    test "unnests multiple steps" do
      assert_style("f(g(h(x))) |> j()", "x |> h() |> g() |> f() |> j()")
    end

    test "doesn't modify valid pipe" do
      assert_style("""
      a()
      |> b()
      |> c()

      a |> b() |> c()
      """)
    end

    test "extracts >0 arity functions" do
      assert_style(
        """
        M.f(a, b)
        |> g()
        |> h()
        """,
        """
        a
        |> M.f(b)
        |> g()
        |> h()
        """
      )
    end

    test "pipe chain start should work with excluded alias lifting namespaces" do
      stub(Quokka.Config, :lift_alias_excluded_namespaces, fn -> MapSet.new([:Name]) end)

      assert_style(
        """
        defmodule MyModule do
          alias Foo.Bar

          Name.M.N.bar(x)
          |> Name.M.N.bar()

          A.B.C.foo()
        end
        """,
        """
        defmodule MyModule do
          alias A.B.C
          alias Foo.Bar

          x
          |> Name.M.N.bar()
          |> Name.M.N.bar()

          C.foo()
        end
        """
      )
    end

    test "fixes nested pipes" do
      stub(Quokka.Config, :block_pipe_flag?, fn -> true end)

      assert_style(
        """
        a
        |> e(fn x ->
          with({:ok, value} <- efoo(x), do: value)
          |> ebar()
          |> ebaz()
        end)
        |> b(fn x ->
          with({:ok, value} <- foo(x), do: value)
          |> bar()
          |> baz()
        end)
        |> c
        """,
        """
        a
        |> e(fn x ->
          with_result = with({:ok, value} <- efoo(x), do: value)

          with_result
          |> ebar()
          |> ebaz()
        end)
        |> b(fn x ->
          with_result = with({:ok, value} <- foo(x), do: value)

          with_result
          |> bar()
          |> baz()
        end)
        |> c()
        """
      )

      stub(Quokka.Config, :block_pipe_flag?, fn -> false end)

      assert_style("""
      a
      |> e(fn x ->
        with({:ok, value} <- efoo(x), do: value)
        |> ebar()
        |> ebaz()
      end)
      |> b(fn x ->
        with({:ok, value} <- foo(x), do: value)
        |> bar()
        |> baz()
      end)
      |> c()
      """)
    end
  end

  describe "block pipe starts" do
    setup do
      stub(Quokka.Config, :block_pipe_flag?, fn -> true end)

      :ok
    end

    test "parent is a function invocation" do
      assert_style(
        "a(if x do y end |> foo(), b)",
        """
        if_result =
          if x do
            y
          end

        if_result |> foo() |> a(b)
        """
      )
    end

    test "handles arbitrary do-block macros" do
      assert_style("""
      IO.puts(
        foo meow do
          :foo
        end
      )
      """)

      assert_style(
        """
        foo do
          "foo"
        end
        |> IO.puts()
        """,
        """
        foo_result =
          foo do
            "foo"
          end

        IO.puts(foo_result)
        """
      )

      assert_style(
        """
        foo meow? do
          :meow
        else
          :bark
        end
        |> IO.puts()
        """,
        """
        foo_result =
          foo meow? do
            :meow
          else
            :bark
          end

        IO.puts(foo_result)
        """
      )
    end

    test "block extraction: names aliased modules" do
      assert_style(
        """
        Foo.bar do
          :ok
        end
        |> case do
          :ok -> :ok
          _ -> :error
        end
        """,
        """
        bar_result =
          Foo.bar do
            :ok
          end

        case bar_result do
          :ok -> :ok
          _ -> :error
        end
        """
      )
    end

    test "macro with arg and do block" do
      assert_style("""
      "baz"
      |> foo do
        "foo"
      end
      |> IO.puts()
      """)
    end

    test "variable assignment of a block" do
      assert_style(
        """
        x =
          case y do
            :ok -> :ok |> IO.puts()
          end
          |> bar()
          |> baz()
        """,
        """
        case_result =
          case y do
            :ok -> IO.puts(:ok)
          end

        x =
          case_result
          |> bar()
          |> baz()
        """
      )
    end

    test "rewrites fors" do
      assert_style(
        """
        for(a <- as, do: a)
        |> bar()
        |> baz()
        """,
        """
        for_result = for(a <- as, do: a)

        for_result
        |> bar()
        |> baz()
        """
      )
    end

    test "rewrites unless" do
      assert_style(
        """
        unless foo do
          bar
        end
        |> wee()
        """,
        """
        if_result =
          if !foo do
            bar
          end

        wee(if_result)
        """
      )
    end

    test "rewrites with" do
      assert_style(
        """
        with({:ok, value} <- foo(), do: value)
        |> bar()
        |> baz()
        """,
        """
        with_result = with({:ok, value} <- foo(), do: value)

        with_result
        |> bar()
        |> baz()
        """
      )
    end

    test "rewrites conds" do
      assert_style(
        """
        cond do
          x -> :ok
        end
        |> bar()
        |> baz()
        """,
        """
        cond_result =
          cond do
            x -> :ok
          end

        cond_result
        |> bar()
        |> baz()
        """
      )
    end

    test "rewrites case" do
      assert_style(
        """
        case x do
          x -> x
        end
        |> foo()
        """,
        """
        case_result =
          case x do
            x -> x
          end

        foo(case_result)
        """
      )

      assert_style(
        """
        def foo do
          case x do
            x -> x
          end
          |> foo()
        end
        """,
        """
        def foo() do
          case_result =
            case x do
              x -> x
            end

          foo(case_result)
        end
        """
      )
    end

    test "rewrites if" do
      assert_style(
        """
        def foo do
          if true do
            nil
          end
          |> a()
          |> b()
        end
        """,
        """
        def foo() do
          if_result =
            if true do
              nil
            end

          if_result
          |> a()
          |> b()
        end
        """
      )
    end

    test "rewrites quote" do
      assert_style(
        """
        quote do
          foo
        end
        |> bar()
        |> baz()
        """,
        """
        quote_result =
          quote do
            foo
          end

        quote_result
        |> bar()
        |> baz()
        """
      )
    end

    test "ignores excluded functions" do
      stub(Quokka.Config, :block_pipe_exclude, fn -> [:case] end)

      assert_style("""
      case x do
        x -> x
      end
      |> foo()
      |> bar()
      """)
    end
  end

  describe "block pipe starts when credo check disabled and PipeChainStart is enabled" do
    test "parent is a function invocation" do
      assert_style(
        "a(if x do y end |> foo(), b)",
        """
        if x do
          y
        end
        |> foo()
        |> a(b)
        """
      )
    end

    test "handles arbitrary do-block macros" do
      assert_style("""
      IO.puts(
        foo meow do
          :foo
        end
      )
      """)

      assert_style("""
      foo do
        "foo"
      end
      |> IO.puts()
      |> baz()
      """)

      assert_style("""
      foo meow? do
        :meow
      else
        :bark
      end
      |> IO.puts()
      |> baz()
      """)
    end

    test "macro with arg and do block" do
      assert_style("""
      "baz"
      |> foo do
        "foo"
      end
      |> IO.puts()
      """)
    end

    test "variable assignment of a block" do
      assert_style(
        """
        x =
          case y do
            :ok -> :ok |> IO.puts()
          end
          |> bar()
          |> baz()
        """,
        """
        x =
          case y do
            :ok -> IO.puts(:ok)
          end
          |> bar()
          |> baz()
        """
      )
    end

    test "doesn't rewrite for" do
      assert_style("""
      for(a <- as, do: a)
      |> bar()
      |> baz()
      """)
    end

    test "doesn't rewrite with" do
      assert_style("""
      with({:ok, value} <- foo(), do: value)
      |> bar()
      |> baz()
      """)
    end

    test "doesn't rewrite conds" do
      assert_style("""
      cond do
        x -> :ok
      end
      |> bar()
      |> baz()
      """)
    end

    test "doesn't rewrite case" do
      assert_style("""
      case x do
        x -> x
      end
      |> foo()
      |> baz()
      """)

      assert_style("""
      def foo() do
        case x do
          x -> x
        end
        |> foo()
        |> baz()
      end
      """)
    end

    test "doesn't rewrite if" do
      assert_style("""
      def foo() do
        if true do
          nil
        end
        |> a()
        |> b()
      end
      """)
    end

    test "doesn't rewrite quote" do
      assert_style("""
      quote do
        foo
      end
      |> bar()
      |> baz()
      """)
    end
  end

  describe "single pipe issues when credo check enabled" do
    test "allows unquote single pipes" do
      assert_style("foo |> unquote(bar)")
    end

    test "fixes simple single pipes" do
      assert_style("b(a) |> c()", "a |> b() |> c()")
      assert_style("a |> f()", "f(a)")
      assert_style("x |> bar", "bar(x)")
      assert_style("def a, do: b |> c()", "def a(), do: c(b)")
    end

    test "keeps invocation on a single line" do
      assert_style(
        """
        foo
        |> bar(baz, bop, boom)
        """,
        """
        bar(foo, baz, bop, boom)
        """
      )

      assert_style(
        """
        foo
        |> bar(baz)
        """,
        """
        bar(foo, baz)
        """
      )

      assert_style(
        """
        def halt(exec, halt_message) do
          %{exec | halted: true}
          |> put_halt_message(halt_message)
        end
        """,
        """
        def halt(exec, halt_message) do
          put_halt_message(%{exec | halted: true}, halt_message)
        end
        """
      )

      stub(Quokka.Config, :block_pipe_flag?, fn -> true end)

      assert_style(
        """
        if true do
          false
        end
        |> foo(
          bar
        )
        """,
        """
        if_result =
          if true do
            false
          end

        foo(if_result, bar)
        """
      )

      stub(Quokka.Config, :block_pipe_flag?, fn -> false end)
    end

    test "onelines assignments" do
      assert_style(
        """
        x =
          y
          |> Enum.map(&f/1)
          |> Enum.join()
        """,
        "x = Enum.map_join(y, &f/1)"
      )
    end
  end

  describe "single pipe when credo check disabled" do
    setup do
      stub(Quokka.Config, :single_pipe_flag?, fn -> false end)

      :ok
    end

    test "allows unquote single pipes" do
      assert_style("foo |> unquote(bar)")
    end

    test "fixes simple single pipes" do
      assert_style("b(a) |> c()", "a |> b() |> c()")
      assert_style("a |> f()")
      assert_style("x |> bar", "x |> bar()")
      assert_style("def a(), do: b |> c()")
    end

    test "keeps invocation on a single line" do
      assert_style("""
      foo
      |> bar(baz, bop, boom)
      """)

      assert_style("""
      foo
      |> bar(baz)
      """)

      assert_style("""
      def halt(exec, halt_message) do
        %{exec | halted: true}
        |> put_halt_message(halt_message)
      end
      """)

      stub(Quokka.Config, :block_pipe_flag?, fn -> true end)

      assert_style(
        """
        if true do
          false
        end
        |> foo(
          bar
        )
        """,
        """
        if_result =
          if true do
            false
          end

        if_result
        |> foo(bar)
        """
      )

      stub(Quokka.Config, :block_pipe_flag?, fn -> false end)
    end
  end

  describe "valid pipe starts & unpiping" do
    test "kernel unary starts" do
      assert_style("!b |> c() |> d()", "!b |> c() |> d()")
      assert_style("!x(b) |> c() |> d()")
      assert_style("not(b) |> c() |> d()", "not b |> c() |> d()")
      assert_style("not x(b) |> c() |> d()")
    end

    test "writes brackets for unpiped kwl" do
      assert_style("foo(kwl: :arg) |> bar()", "[kwl: :arg] |> foo() |> bar()")
      assert_style("%{a: foo(a: :b, c: :d) |> bar()}", "%{a: [a: :b, c: :d] |> foo() |> bar()}")
      assert_style("%{a: foo([a: :b, c: :d]) |> bar()}", "%{a: [a: :b, c: :d] |> foo() |> bar()}")
    end

    test "allows fn" do
      assert_style("""
      fn
        :ok -> :ok
        :error -> :error
      end
      |> b()
      |> c()
      """)
    end

    test "recognizes infix ops as valid pipe starts" do
      assert_style("(bar() == 1) |> foo()", "foo(bar() == 1)")
      assert_style("(x in 1..100) |> foo()", "foo(x in 1..100)")
    end

    test "0 arity is just fine!" do
      assert_style("foo() |> bar() |> baz()")
      assert_style("Module.foo() |> bar() |> baz()")
    end

    test "ecto funtimes" do
      for from <- ~w(from Query.from Ecto.Query.from) do
        assert_style("""
        #{from}(foo in Bar, where: foo.bool)
        |> some_query_helper()
        |> Repo.all()
        """)
      end

      assert_style("^foo |> Ecto.Query.bar() |> Ecto.Query.baz()")
    end

    test "ranges" do
      assert_style("start..stop//step |> foo()", "foo(start..stop//step)")
      assert_style("start..stop//step |> foo() |> bar()")
      assert_style("foo(start..stop//step) |> bar()", "start..stop//step |> foo() |> bar()")
    end
  end

  describe "optimizations & readability improvements" do
    test "rewrites anonymous function invocations to use then" do
      assert_style("a |> (& &1).()", "then(a, & &1)")
      assert_style("a |> (& {&1, &2}).(b)", "(&{&1, &2}).(a, b)")
      assert_style("a |> (& &1).() |> c", "a |> then(& &1) |> c()")

      assert_style(
        "a |> (fn x, y -> {x, y} end).() |> c",
        "a |> then(fn x, y -> {x, y} end) |> c()"
      )

      assert_style("a |> (fn x -> x end).()", "then(a, fn x -> x end)")
      assert_style("a |> (fn x -> x end).() |> c", "a |> then(fn x -> x end) |> c()")
    end

    test "rewrites then/2 when the passed function is a named function reference" do
      assert_style "a |> then(&fun/1) |> c", "a |> fun() |> c()"
      assert_style "a |> then(&(&1 / 1)) |> c", "a |> Kernel./(1) |> c()"
      assert_style "a |> then(&(&1 * 2 / 1)) |> c()"
      assert_style "a |> then(&fun/1)", "fun(a)"
      assert_style "a |> then(&fun(&1)) |> c", "a |> fun() |> c()"
      assert_style "a |> then(&fun(&1, d)) |> c", "a |> fun(d) |> c()"
      assert_style "a |> then(&M.f(&1)) |> c", "a |> M.f() |> c()"

      # Doesn't rewrite multiple refs / non-starting argument
      assert_style "a |> then(&fun(d, &1)) |> c()"
      assert_style "a |> then(&fun(&1, d, %{foo: &1})) |> c()"

      # then + kernel ops
      assert_style "a |> then(&(-&1)) |> c", "a |> Kernel.-() |> c()"
      assert_style "a |> then(&(+&1)) |> c", "a |> Kernel.+() |> c()"

      for op <- ~w(++ -- && || in - * + / > < <= >= == and or != !== === <>) do
        assert_style "a |> then(&(&1 #{op} x)) |> c", "a |> Kernel.#{op}(x) |> c()"
      end

      # Doesn't rewrite non-kernel operators
      for op <- ~w(||| &&& <<< >>> <<~ ~>> <~ ~> <~>) do
        assert_style "a |> then(&(&1 #{op} x)) |> c()"
      end
    end

    test "adds parens to 1-arity pipes" do
      assert_style("a |> b |> c", "a |> b() |> c()")
    end

    test "filter/first => find" do
      assert_style "a |> Enum.filter(fun) |> List.first()", "Enum.find(a, fun)"
      assert_style "a |> Enum.filter(fun) |> List.first(default)", "Enum.find(a, default, fun)"

      assert_style(
        """
        a
        |> Enum.filter(fun)
        |> List.first()
        |> foo()
        """,
        """
        a
        |> Enum.find(fun)
        |> foo()
        """
      )

      assert_style(
        """
        a
        |> Enum.filter(fun)
        |> List.first(default)
        |> foo()
        """,
        """
        a
        |> Enum.find(default, fun)
        |> foo()
        """
      )
    end

    test "reverse/concat" do
      assert_style("a |> Enum.reverse() |> Enum.concat()")
      assert_style("a |> Enum.reverse(bar) |> Enum.concat()")
      assert_style("a |> Enum.reverse(bar) |> Enum.concat(foo)")
      assert_style("a |> Enum.reverse() |> Enum.concat(foo)", "Enum.reverse(a, foo)")

      assert_style(
        """
        a
        |> Enum.reverse()
        |> Enum.concat([bar, baz])
        |> Enum.sum()
        """,
        """
        a
        |> Enum.reverse([bar, baz])
        |> Enum.sum()
        """
      )
    end

    test "reverse/Kernel.++" do
      assert_style("a |> Enum.reverse(bar) |> Kernel.++(foo)")
      assert_style("a |> Enum.reverse() |> Kernel.++(foo)", "Enum.reverse(a, foo)")

      assert_style(
        """
        a
        |> Enum.reverse()
        |> Kernel.++([bar, baz])
        |> Enum.sum()
        """,
        """
        a
        |> Enum.reverse([bar, baz])
        |> Enum.sum()
        """
      )
    end

    test "filter/count" do
      for enum <- ~w(Enum Stream) do
        assert_style(
          """
          a
          |> #{enum}.filter(fun)
          |> Enum.count()
          |> IO.puts()
          """,
          """
          a
          |> Enum.count(fun)
          |> IO.puts()
          """
        )

        assert_style(
          """
          a
          |> b()
          |> #{enum}.filter(fun)
          |> Enum.count()
          """,
          """
          a
          |> b()
          |> Enum.count(fun)
          """
        )

        stub(Quokka.Config, :block_pipe_flag?, fn -> true end)

        assert_style(
          """
          if true do
            []
          else
            [a, b, c]
          end
          |> #{enum}.filter(fun)
          |> Enum.count()
          """,
          """
          if_result =
            if true do
              []
            else
              [a, b, c]
            end

          Enum.count(if_result, fun)
          """
        )

        stub(Quokka.Config, :block_pipe_flag?, fn -> false end)
      end
    end

    test "Stream.{each/map}/Stream.run" do
      assert_style("a |> Stream.each(fun) |> Stream.run()", "Enum.each(a, fun)")
      assert_style("a |> Stream.map(fun) |> Stream.run()", "Enum.each(a, fun)")

      assert_style(
        """
        a
        |> foo
        |> Stream.map(fun)
        |> Stream.run()
        """,
        """
        a
        |> foo()
        |> Enum.each(fun)
        """
      )
    end

    test "map/join" do
      for enum <- ~w(Enum Stream) do
        assert_style("a |> #{enum}.map(mapper) |> Enum.join()", "Enum.map_join(a, mapper)")

        assert_style(
          """
          a
          |> b()
          |> #{enum}.map(mapper)
          |> Enum.join()
          """,
          """
          a
          |> b()
          |> Enum.map_join(mapper)
          """
        )

        assert_style(
          "a |> #{enum}.map(mapper) |> Enum.join(joiner)",
          "Enum.map_join(a, joiner, mapper)"
        )
      end
    end

    test "map/into" do
      for enum <- ~w(Enum Stream) do
        assert_style("a|> #{enum}.map(b)|> Enum.into(%{})", "Map.new(a, b)")
        assert_style("a |> #{enum}.map(b) |> Enum.into(unk)", "Enum.into(a, unk, b)")

        assert_style(
          "a |> #{enum}.map(b) |> Enum.into(%{some: :existing_map})",
          "Enum.into(a, %{some: :existing_map}, b)"
        )

        assert_style(
          """
          # a
          # b
          a_multiline_mapper
          |> #{enum}.map(fn %{gets: shrunk, down: to_a_more_reasonable} ->
            # c
            IO.puts "woo!"
            # d
            {shrunk, to_a_more_reasonable}
          end)
          |> Enum.into(size)
          """,
          """
          # a
          # b
          Enum.into(a_multiline_mapper, size, fn %{gets: shrunk, down: to_a_more_reasonable} ->
            # c
            IO.puts("woo!")
            # d
            {shrunk, to_a_more_reasonable}
          end)
          """
        )

        for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
          assert_style("a |> #{enum}.map(b) |> Enum.into(#{new}())", "#{new}(a, b)")

          # Regression: something about the meta wants newlines when it's in a def
          assert_style(
            """
            def foo() do
              filename_map = foo |> Enum.map(&{&1.filename, true}) |> Enum.into(%{})
            end
            """,
            """
            def foo() do
              filename_map = Map.new(foo, &{&1.filename, true})
            end
            """
          )
        end
      end
    end

    test "map/new" do
      for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
        assert_style("a |> Enum.map(b) |> #{new}()", "#{new}(a, b)")
      end
    end

    test "into(%{})" do
      assert_style("a |> Enum.into(%{}) |> b()", "a |> Map.new() |> b()")
      assert_style("a |> Enum.into(%{}, mapper) |> b()", "a |> Map.new(mapper) |> b()")
    end

    test "into(Collectable.new())" do
      assert_style("a |> Enum.into(foo) |> b()")
      assert_style("a |> Enum.into(foo, mapper) |> b()")

      for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
        assert_style("a |> Enum.into(#{new}) |> b()", "a |> #{new}() |> b()")
        assert_style("a |> Enum.into(#{new}, mapper) |> b()", "a |> #{new}(mapper) |> b()")

        assert_style(
          """
          a
          |> Enum.map(b)
          |> Enum.into(#{new}, c)
          """,
          """
          a
          |> Enum.map(b)
          |> #{new}(c)
          """
        )
      end
    end

    test "doesn't rewrite pipe start functions that are a part of piped_function_exclusions" do
      # Sanity check
      assert_style("foo(bar() |> baz() |> boz())", "bar() |> baz() |> boz() |> foo()")

      stub(Quokka.Config, :piped_function_exclusions, fn -> [:foo, :"Repo.update", :"Multi.Module.function"] end)

      assert_style("foo(bar() |> baz() |> boz())")

      assert_style("Repo.update(bar() |> baz() |> boz())")

      assert_style("Multi.Module.function(bar() |> baz() |> boz())")
    end
  end

  describe "comments and..." do
    test "unpiping" do
      assert_style(
        """
        aliased =
          aliases
          |> MapSet.new(fn
            {:alias, _, [{:__aliases__, _, aliases}]} -> List.last(aliases)
            {:alias, _, [{:__aliases__, _, _}, [{_as, {:__aliases__, _, [as]}}]]} -> as
            # alias __MODULE__ or other oddities
            {:alias, _, _} -> nil
          end)

        excluded_first = MapSet.union(aliased, @excluded_namespaces)
        """,
        """
        aliased =
          MapSet.new(aliases, fn
            {:alias, _, [{:__aliases__, _, aliases}]} -> List.last(aliases)
            {:alias, _, [{:__aliases__, _, _}, [{_as, {:__aliases__, _, [as]}}]]} -> as
            # alias __MODULE__ or other oddities
            {:alias, _, _} -> nil
          end)

        excluded_first = MapSet.union(aliased, @excluded_namespaces)
        """
      )

      assert_style(
        """
        foo =
          # bar
          bar
          # baz
          |> baz(fn ->
            # a
            a
            # b
            b
          end)
        """,
        """
        # bar
        # baz
        foo =
          baz(bar, fn ->
            # a
            a
            # b
            b
          end)
        """
      )

      assert_style(
        """
        foo =
          # bar
          bar
          # baz



          |> baz(fn ->
            # a
            a
            # b
            b
          end)
        """,
        """
        # bar
        # baz
        foo =
          baz(bar, fn ->
            # a
            a
            # b
            b
          end)
        """
      )
    end

    test "optimizing" do
      assert_style(
        """
        a
        |> Enum.map(fn b ->
          c
          # a comment
          d
        end)
        |> Enum.join(x)
        |> Enum.each(...)
        """,
        """
        a
        |> Enum.map_join(x, fn b ->
          c
          # a comment
          d
        end)
        |> Enum.each(...)
        """
      )

      assert_style(
        """
        a
        |> Enum.map(fn b ->
          c
          # a comment
          d
        end)
        |> Enum.into(x)
        |> Enum.each(...)
        """,
        """
        a
        |> Enum.into(x, fn b ->
          c
          # a comment
          d
        end)
        |> Enum.each(...)
        """
      )

      assert_style(
        """
        a
        |> Enum.map(fn b ->
          c
          # a comment
          d
        end)
        |> Keyword.new()
        |> Enum.each(...)
        """,
        """
        a
        |> Keyword.new(fn b ->
          c
          # a comment
          d
        end)
        |> Enum.each(...)
        """
      )
    end
  end

  describe "pipifying" do
    test "no false positives" do
      pipe = "a() |> b() |> c()"
      assert_style pipe
      assert_style String.replace(pipe, " |>", "\n|>")
      assert_style "fn -> #{pipe} end"
      assert_style "if #{pipe}, do: ..."
      assert_style "x\n\n#{pipe}"
      assert_style "@moduledoc #{pipe}"
      assert_style "!(#{pipe})"
      assert_style "not foo(#{pipe})"
      assert_style ~s<"\#{#{pipe}}">
    end

    test "when it's not actually the first argument!" do
      assert_style """
      a
      |> M.f0(b |> M.f1() |> M.f2())
      |> M.f3()
      """
    end

    test "pipifying" do
      assert_style("e(d(a |> b |> c), f)", "a |> b() |> c() |> d() |> e(f)")

      assert_style(
        """
        # d
        d(
        # a
          a
          # b
          |> b
          # c
          |> c
        )
        """,
        """
        # d
        # a
        a
        # b
        |> b()
        # c
        |> c()
        |> d()
        """
      )
    end
  end

  describe "Map.delete and Map.drop" do
    test "converts consecutive Map.delete calls to Map.drop" do
      assert_style(
        "foo |> Map.delete(key1) |> Map.delete(key2)",
        "Map.drop(foo, [key1, key2])"
      )

      assert_style(
        "foo |> Map.delete(key1) |> Map.delete(key2) |> bar()",
        "foo |> Map.drop([key1, key2]) |> bar()"
      )

      assert_style(
        "foo |> Map.delete(key1) |> Map.delete(key2) |> Map.delete(key3) |> Map.delete(key4)",
        "Map.drop(foo, [key1, key2, key3, key4])"
      )
    end

    test "does not rewrite non-consecutive Map.delete calls" do
      assert_style("foo |> Map.delete(key1) |> bar() |> Map.delete(key2)")
    end

    test "Map.delete followed by Map.drop" do
      assert_style(
        "foo |> Map.delete(key1) |> Map.drop([key2, key3]) |> bar()",
        "foo |> Map.drop([key1, key2, key3]) |> bar()"
      )
    end

    test "Map.drop followed by Map.delete" do
      assert_style(
        "foo |> Map.drop([key1, key2]) |> Map.delete(key3) |> bar()",
        "foo |> Map.drop([key1, key2, key3]) |> bar()"
      )
    end

    test "Map.drop followed by Map.drop" do
      assert_style(
        "foo |> Map.drop([key1, key2]) |> Map.drop([key3, key4]) |> Map.drop([key5, key6]) |> bar()",
        "foo |> Map.drop([key1, key2, key3, key4, key5, key6]) |> bar()"
      )
    end

    test "Map.drop and Map.delete sandwiched together" do
      assert_style(
        "foo |> Map.drop([key1, key2]) |> Map.delete(key3) |> Map.drop([key4, key5]) |> bar()",
        "foo |> Map.drop([key1, key2, key3, key4, key5]) |> bar()"
      )

      assert_style(
        "foo |> Map.delete(key1) |> Map.drop([key2, key3]) |> Map.delete(key4) |> Map.drop([key5, key6]) |> bar()",
        "foo |> Map.drop([key1, key2, key3, key4, key5, key6]) |> bar()"
      )
    end
  end

  describe "Keyword.delete and Keyword.drop" do
    test "converts consecutive Keyword.delete calls to Keyword.drop" do
      assert_style(
        "foo |> Keyword.delete(key1) |> Keyword.delete(key2)",
        "Keyword.drop(foo, [key1, key2])"
      )

      assert_style(
        "foo |> Keyword.delete(key1) |> Keyword.delete(key2) |> bar()",
        "foo |> Keyword.drop([key1, key2]) |> bar()"
      )

      assert_style(
        "foo |> Keyword.delete(key1) |> Keyword.delete(key2) |> Keyword.delete(key3) |> Keyword.delete(key4)",
        "Keyword.drop(foo, [key1, key2, key3, key4])"
      )
    end

    test "does not rewrite non-consecutive Keyword.delete calls" do
      assert_style("foo |> Keyword.delete(key1) |> bar() |> Keyword.delete(key2)")
    end

    test "Keyword.delete followed by Keyword.drop" do
      assert_style(
        "foo |> Keyword.delete(key1) |> Keyword.drop([key2, key3]) |> bar()",
        "foo |> Keyword.drop([key1, key2, key3]) |> bar()"
      )
    end

    test "Keyword.drop followed by Keyword.delete" do
      assert_style(
        "foo |> Keyword.drop([key1, key2]) |> Keyword.delete(key3) |> bar()",
        "foo |> Keyword.drop([key1, key2, key3]) |> bar()"
      )
    end

    test "Keyword.drop followed by Keyword.drop" do
      assert_style(
        "foo |> Keyword.drop([key1, key2]) |> Keyword.drop([key3, key4]) |> Keyword.drop([key5, key6]) |> bar()",
        "foo |> Keyword.drop([key1, key2, key3, key4, key5, key6]) |> bar()"
      )
    end

    test "Keyword.drop and Keyword.delete sandwiched together" do
      assert_style(
        "foo |> Keyword.drop([key1, key2]) |> Keyword.delete(key3) |> Keyword.drop([key4, key5]) |> bar()",
        "foo |> Keyword.drop([key1, key2, key3, key4, key5]) |> bar()"
      )

      assert_style(
        "foo |> Keyword.delete(key1) |> Keyword.drop([key2, key3]) |> Keyword.delete(key4) |> Keyword.drop([key5, key6]) |> bar()",
        "foo |> Keyword.drop([key1, key2, key3, key4, key5, key6]) |> bar()"
      )
    end
  end
end
