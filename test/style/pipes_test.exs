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
    stub(Quokka.Config, :one_pipe_per_line?, fn -> false end)

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

    test "breaks multiple pipes on one line when credo check enabled" do
      stub(Quokka.Config, :one_pipe_per_line?, fn -> true end)

      assert_style(
        "a |> b() |> c()",
        """
        a
        |> b()
        |> c()
        """
      )

      assert_style(
        "1 |> Integer.to_string() |> String.to_integer()",
        """
        1
        |> Integer.to_string()
        |> String.to_integer()
        """
      )

      assert_style(
        """
        foo
        |> bar() |> baz()
        """,
        """
        foo
        |> bar()
        |> baz()
        """
      )

      assert_style(
        """
        a()
        |> b()
        |> c()
        """,
        """
        a()
        |> b()
        |> c()
        """
      )
    end

    test "preserves multiple pipes on one line when credo check disabled" do
      stub(Quokka.Config, :one_pipe_per_line?, fn -> false end)

      assert_style("a |> b() |> c()")
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

    test "pipe chain start rewrite respects function exclusions" do
      stub(Quokka.Config, :pipe_chain_start_excluded_functions, fn -> ["my_query", "Repo.insert"] end)

      # Repo.insert is excluded, so `Repo.insert(changeset) |> other()` is not extracted
      assert_style("""
      Repo.insert(changeset)
      |> Ecto.Multi.run(:something, fn _, _ -> :ok end)
      |> Repo.transaction()
      """)

      # my_query is excluded, so `my_query(arg) |> other()` is not extracted
      assert_style("""
      my_query(arg)
      |> Repo.all()
      |> Enum.map(& &1.id)
      """)

      # non-excluded functions are still extracted
      assert_style(
        """
        String.trim(input)
        |> String.upcase()
        """,
        """
        input
        |> String.trim()
        |> String.upcase()
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

    test "single pipe rewrite respects piped_function_exclusions" do
      stub(Quokka.Config, :piped_function_exclusions, fn -> [:from, :"Repo.insert"] end)

      # Repo.insert is excluded, so `changeset |> Repo.insert()` is not rewritten to `Repo.insert(changeset)`
      # pipe chain start extraction still applies
      assert_style(
        """
        MyModule.changeset()
        |> Repo.insert()
        """,
        """
        MyModule.changeset()
        |> Repo.insert()
        """
      )

      assert_style("""
      from(f in Foo, where: f.id == ^id)
      |> Repo.all()
      """)
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

    test "copes with module names defined as module attributes" do
      assert_style(
        """

        defmodule Foo do
          use ExUnit.Case

          @module_to_call Bar

          test "piping" do
            assert 42 ==
                     @module_to_call.bar(%Bop{})
                     |> foo()
                     |> baz()
          end
        end
        """,
        """
        defmodule Foo do
          use ExUnit.Case

          @module_to_call Bar

          test "piping" do
            assert 42 ==
                     %Bop{}
                     |> @module_to_call.bar()
                     |> foo()
                     |> baz()
          end
        end
        """
      )
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
      assert_style "a |> foo() |> then(&(&1 / 1)) |> c", "a |> foo() |> Kernel./(1) |> c()"
      # the extracted kernel op lands at the pipe start, so it's folded inline (then unpiped here)
      assert_style "a |> then(&(&1 / 1)) |> c", "c(a / 1)"
      assert_style "a |> then(&(&1 * 2 / 1)) |> c()"
      assert_style "a |> then(&fun/1)", "fun(a)"
      assert_style "a |> then(&fun(&1)) |> c", "a |> fun() |> c()"
      assert_style "a |> then(&fun(&1, d)) |> c", "a |> fun(d) |> c()"
      assert_style "a |> then(&M.f(&1)) |> c", "a |> M.f() |> c()"

      # Doesn't rewrite multiple refs / non-starting argument
      assert_style "a |> then(&fun(d, &1)) |> c()"
      assert_style "a |> then(&fun(&1, d, %{foo: &1})) |> c()"

      # then + kernel ops: the extracted op lands at the pipe start and is folded inline
      # (and then unpiped, since these are single pipes once folded)
      assert_style "a |> then(&(-&1)) |> c", "c(-a)"
      assert_style "a |> then(&(+&1)) |> c", "c(+a)"
      assert_style "a |> foo() |> then(&(-&1)) |> c", "a |> foo() |> Kernel.-() |> c()"
      assert_style "a |> foo() |> then(&(+&1)) |> c", "a |> foo() |> Kernel.+() |> c()"

      for op <- ~w(++ -- && || in - * + / > < <= >= == and or != !== === <>) do
        assert_style "a |> then(&(&1 #{op} x)) |> c", "c(a #{op} x)"
        assert_style "a |> foo() |> then(&(&1 #{op} x)) |> c", "a |> foo() |> Kernel.#{op}(x) |> c()"
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
      assert_style("a |> Enum.reverse(bar) |> Kernel.++(foo)", "Enum.reverse(a, bar) ++ foo")
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

    test "folds a Kernel op at the start of a pipe into an inline expression" do
      # single pipe off so the folded expression stays the start of the (still multi-step) pipe
      stub(Quokka.Config, :single_pipe_flag?, fn -> false end)

      assert_style(
        """
        foo
        |> Kernel.||(bar)
        |> Enum.map(baz)
        """,
        """
        (foo || bar)
        |> Enum.map(baz)
        """
      )

      assert_style(
        """
        inherited_rows
        |> Kernel.++(account_rows)
        |> Enum.map(&put_group/1)
        """,
        """
        (inherited_rows ++ account_rows)
        |> Enum.map(&put_group/1)
        """
      )

      assert_style(
        """
        (assigns.invoice.amount_due || 0)
        |> Kernel./(100)
        |> :erlang.float_to_binary(decimals: 2)
        """,
        """
        ((assigns.invoice.amount_due || 0) / 100)
        |> :erlang.float_to_binary(decimals: 2)
        """
      )

      assert_style(
        """
        (contacts || [])
        |> Kernel.++([contact])
        |> Enum.uniq_by(& &1.id)
        """,
        """
        ((contacts || []) ++ [contact])
        |> Enum.uniq_by(& &1.id)
        """
      )

      assert_style(
        """
        foo
        |> Kernel.<>("bar")
        |> String.length()
        """,
        """
        (foo <> "bar")
        |> String.length()
        """
      )
    end

    test "folds every Kernel binary/unary operator that starts a pipe" do
      stub(Quokka.Config, :single_pipe_flag?, fn -> false end)

      for op <- ~w(++ -- && || in - * + / > < <= >= == and or != !== === <>) do
        assert_style("a |> Kernel.#{op}(x) |> c()", "(a #{op} x) |> c()")
      end

      assert_style("a |> Kernel.-() |> c()", "-a |> c()")
      assert_style("a |> Kernel.+() |> c()", "+a |> c()")
    end

    test "only folds a later Kernel op at the end of an exact two-step pipe" do
      stub(Quokka.Config, :single_pipe_flag?, fn -> false end)

      assert_style("a |> b() |> Kernel.++(c)", "b(a) ++ c")
      assert_style("a |> b() |> Kernel.++(c) |> d()")
    end

    test "folds a two-step pipe ending in a Kernel infix operator" do
      assert_style(
        "list |> Enum.sum_by(& &1.amount) |> Kernel./(@divisor)",
        "Enum.sum_by(list, & &1.amount) / @divisor"
      )

      assert_style(
        "list |> Enum.map(fn x -> x / 100 end) |> Kernel.*(1.6)",
        "Enum.map(list, fn x -> x / 100 end) * 1.6"
      )

      for op <- ~w(++ -- && || in - * + / > < <= >= == and or != !== === <>) do
        assert_style("a |> b() |> Kernel.#{op}(c)", "b(a) #{op} c")
      end
    end

    test "only folds an infix operator at the end of an exact two-step pipe" do
      assert_style("a |> b() |> Kernel.++(c) |> d()")
      assert_style("a |> b() |> c() |> Kernel.++(d)")
      assert_style("a |> b() |> Kernel.-()")
      assert_style("a |> b() |> Kernel.!()")
    end

    test "two-step infix folding does not depend on SinglePipe" do
      stub(Quokka.Config, :single_pipe_flag?, fn -> false end)
      assert_style("a |> b() |> Kernel.++(c)", "b(a) ++ c")
    end

    test "two-step infix folding respects piped function exclusions" do
      stub(Quokka.Config, :piped_function_exclusions, fn -> [:b] end)
      assert_style("a |> b() |> Kernel.++(c)")
    end

    test "folded single pipe gets unpiped when single pipe rewriting is enabled" do
      assert_style("a |> Kernel.||(b) |> c()", "c(a || b)")
      assert_style("a |> Kernel.++(b)", "a ++ b")
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

    test "drop/take => slice" do
      # single pipes collapse to a function call
      assert_style(
        "a |> Enum.drop(2) |> Enum.take(5)",
        "Enum.slice(a, 2, 5)"
      )

      # zero is a valid non-negative literal
      assert_style(
        "a |> Enum.drop(0) |> Enum.take(5)",
        "Enum.slice(a, 0, 5)"
      )

      # preserved inside a longer chain
      assert_style(
        """
        a
        |> b()
        |> Enum.drop(2)
        |> Enum.take(5)
        """,
        """
        a
        |> b()
        |> Enum.slice(2, 5)
        """
      )

      # followed by another pipe
      assert_style(
        """
        a
        |> Enum.drop(2)
        |> Enum.take(5)
        |> Enum.sum()
        """,
        """
        a
        |> Enum.slice(2, 5)
        |> Enum.sum()
        """
      )

      # assignment form
      assert_style(
        """
        paginated =
          sorted
          |> Enum.drop(10)
          |> Enum.take(20)
        """,
        "paginated = Enum.slice(sorted, 10, 20)"
      )
    end

    test "drop/take => slice only rewrites non-negative integer literals" do
      assert_style("a |> Enum.drop(-1) |> Enum.take(5)")
      assert_style("a |> Enum.drop(2) |> Enum.take(-5)")
      assert_style("a |> Enum.drop(-1) |> Enum.take(-5)")

      assert_style("a |> Enum.drop(offset) |> Enum.take(per_page)")
      assert_style("a |> Enum.drop(offset) |> Enum.take(5)")
      assert_style("a |> Enum.drop(2) |> Enum.take(per_page)")

      assert_style("a |> Enum.drop(x + 1) |> Enum.take(5)")
      assert_style("a |> Enum.drop(2) |> Enum.take(length(b))")
    end

    test "drop/take => slice ignores non-matching variants" do
      assert_style("a |> Stream.drop(2) |> Stream.take(5)")

      assert_style("a |> Enum.drop(2) |> Stream.take(5)")
      assert_style("a |> Stream.drop(2) |> Enum.take(5)")
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

    test "map/sum rewrites Enum.map and Stream.map followed by Enum.sum" do
      enable_sum_by_rewrite()

      for enum <- ~w(Enum Stream) do
        assert_style("a |> #{enum}.map(mapper) |> Enum.sum()", "Enum.sum_by(a, mapper)")
      end
    end

    test "map/sum rewrites within a longer pipe chain" do
      enable_sum_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.map(& &1.total_accounts) |> Enum.sum()",
        "Enum.sum_by(mapping, fn {_, value} -> value.total_accounts end)"
      )

      assert_style(
        "items |> Enum.map(mapper) |> Enum.sum() |> IO.inspect()",
        "items |> Enum.sum_by(mapper) |> IO.inspect()"
      )
    end

    test "Map.values/map/sum rewrites inside a keyword-style map" do
      enable_sum_by_rewrite()

      assert_style(
        "%{total_accounts: hierarchy_index |> Map.values() |> Enum.map(& &1.total_accounts) |> Enum.sum()}",
        "%{total_accounts: Enum.sum_by(hierarchy_index, fn {_, value} -> value.total_accounts end)}"
      )
    end

    test "Map.values/sum_by merges an anonymous mapper inside a keyword-style map" do
      enable_sum_by_rewrite()

      assert_style(
        "%{total_accounts: hierarchy_index |> Map.values() |> Enum.sum_by(fn account -> account.total_accounts end)}",
        "%{total_accounts: Enum.sum_by(hierarchy_index, fn {_, account} -> account.total_accounts end)}"
      )
    end

    test "Map.values/sum_by sums mapped map values directly" do
      enable_sum_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.sum_by(mapper)",
        "Enum.sum_by(mapping, fn {_, value} -> mapper.(value) end)"
      )

      assert_style(
        "mapping |> Map.values |> Enum.sum_by(& &1.amount)",
        "Enum.sum_by(mapping, fn {_, value} -> value.amount end)"
      )

      assert_style(
        "input |> load_mapping() |> Map.values() |> Enum.sum_by(&amount/1) |> round()",
        "input |> load_mapping() |> Enum.sum_by(fn {_, value} -> amount(value) end) |> round()"
      )
    end

    test "Map.values/sum_by avoids shadowing variables used by the mapper" do
      enable_sum_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.sum_by(value)",
        "Enum.sum_by(mapping, fn {_, value2} -> value.(value2) end)"
      )
    end

    test "Map.values/sum_by merges an anonymous mapper's argument pattern" do
      enable_sum_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.sum_by(fn val -> grok(val) end)",
        "Enum.sum_by(mapping, fn {_, val} -> grok(val) end)"
      )

      assert_style(
        "mapping |> Map.values() |> Enum.map(fn val -> grok(val) end) |> Enum.sum()",
        "Enum.sum_by(mapping, fn {_, val} -> grok(val) end)"
      )

      assert_style(
        "mapping |> Map.values() |> Enum.sum_by(fn %{amount: amount} -> amount end)",
        "Enum.sum_by(mapping, fn {_, %{amount: amount}} -> amount end)"
      )
    end

    test "Map.values/sum_by preserves anonymous mapper clauses, guards, and comments" do
      enable_sum_by_rewrite()

      assert_style(
        """
        mapping
        |> Map.values()
        |> Enum.sum_by(fn
          val when val > 0 ->
            # Transform positive values.
            grok(val)

          _ ->
            0
        end)
        """,
        """
        Enum.sum_by(
          mapping,
          fn
            {_, val} when val > 0 ->
              # Transform positive values.
              grok(val)

            {_, _} ->
              0
          end
        )
        """
      )
    end

    test "Map.values/map/sum sums mapped map values directly" do
      enable_sum_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.map(mapper) |> Enum.sum()",
        "Enum.sum_by(mapping, fn {_, value} -> mapper.(value) end)"
      )

      assert_style(
        "mapping |> Map.values() |> Stream.map(& &1.amount) |> Enum.sum()",
        "Enum.sum_by(mapping, fn {_, value} -> value.amount end)"
      )
    end

    test "Map.values/sum_by does not rewrite if a mapper might have side-effects" do
      enable_sum_by_rewrite()

      assert_style("mapping |> Map.values() |> Enum.sum_by(build_mapper())")
    end

    test "Map.values/sum_by only rewrites calls to Map.values and Enum.sum_by" do
      enable_sum_by_rewrite()

      assert_style("mapping |> Other.values() |> Enum.sum_by(mapper)")
      assert_style("mapping |> Map.values() |> Other.sum_by(mapper)")
    end

    test "Map.values/sum_by preserves results" do
      if Version.match?(System.version(), ">= 1.18.0-dev") do
        enable_sum_by_rewrite()

        sources = [
          "mapping |> Map.values() |> Enum.sum_by(mapper)",
          "mapping |> Map.values() |> Enum.map(mapper) |> Enum.sum()"
        ]

        for source <- sources do
          {_, styled, _} = style(source)

          for mapping <- [%{}, %{a: 1}, %{a: -2, b: 3, c: 4.5}] do
            binding = [mapping: mapping, mapper: &(&1 * 2)]
            {original_result, _binding} = Code.eval_string(source, binding)
            {styled_result, _binding} = Code.eval_string(styled, binding)

            assert styled_result == original_result
          end
        end
      end
    end

    test "map/sum preserves a multiline mapper and its comments" do
      enable_sum_by_rewrite()

      assert_style(
        """
        items
        |> Enum.map(fn item ->
          # Normalize missing amounts.
          item.amount || 0
        end)
        |> Enum.sum()
        """,
        """
        Enum.sum_by(items, fn item ->
          # Normalize missing amounts.
          item.amount || 0
        end)
        """
      )
    end

    test "map/sum does not rewrite calls to other modules" do
      enable_sum_by_rewrite()

      assert_style("items |> Other.map(mapper) |> Enum.sum()")
      assert_style("items |> Enum.map(mapper) |> Other.sum()")
    end

    test "map/sum does not rewrite before Enum.sum_by/2 is available" do
      stub(Quokka.Config, :elixir_version, fn -> "1.17.3" end)
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)

      assert_style("items |> Enum.map(mapper) |> Enum.sum()")
    end

    test "map/sum respects the inefficient_functions exclusion" do
      stub(Quokka.Config, :elixir_version, fn -> "1.18.0" end)
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)

      assert_style("items |> Enum.map(mapper) |> Enum.sum()")
      assert_style("mapping |> Map.values() |> Enum.sum_by(mapper)")
    end

    test "map/sum preserves results for numeric mapper outputs" do
      if Version.match?(System.version(), ">= 1.18.0-dev") do
        enable_sum_by_rewrite()

        source = "items |> Enum.map(& &1.amount) |> Enum.sum()"
        {_, styled, _} = style(source)

        for items <- [
              [],
              [%{amount: 0}],
              [%{amount: 1}, %{amount: 2}, %{amount: 3}],
              [%{amount: -10}, %{amount: 3}, %{amount: 7}],
              [%{amount: 1}, %{amount: 2.5}, %{amount: -0.5}]
            ] do
          {original_result, _binding} = Code.eval_string(source, items: items)
          {styled_result, _binding} = Code.eval_string(styled, items: items)

          assert styled_result == original_result
        end
      end
    end

    test "map/product rewrites Enum.map and Stream.map followed by Enum.product" do
      enable_product_by_rewrite()

      for enum <- ~w(Enum Stream) do
        assert_style(
          "a |> #{enum}.map(mapper) |> Enum.product()",
          "Enum.product_by(a, mapper)"
        )
      end
    end

    test "map/product rewrites within a longer pipe chain" do
      enable_product_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.map(& &1.quantity) |> Enum.product()",
        "Enum.product_by(mapping, fn {_, value} -> value.quantity end)"
      )

      assert_style(
        "items |> Enum.map(mapper) |> Enum.product() |> IO.inspect()",
        "items |> Enum.product_by(mapper) |> IO.inspect()"
      )
    end

    test "Map.values/product_by multiplies mapped map values directly" do
      enable_product_by_rewrite()

      assert_style(
        "mapping |> Map.values() |> Enum.product_by(mapper)",
        "Enum.product_by(mapping, fn {_, value} -> mapper.(value) end)"
      )

      assert_style(
        "mapping |> Map.values |> Enum.product_by(& &1.quantity)",
        "Enum.product_by(mapping, fn {_, value} -> value.quantity end)"
      )
    end

    test "map/product preserves a multiline mapper and its comments" do
      enable_product_by_rewrite()

      assert_style(
        """
        items
        |> Enum.map(fn item ->
          # Default missing quantities.
          item.quantity || 1
        end)
        |> Enum.product()
        """,
        """
        Enum.product_by(items, fn item ->
          # Default missing quantities.
          item.quantity || 1
        end)
        """
      )
    end

    test "map/product does not rewrite calls to other modules" do
      enable_product_by_rewrite()

      assert_style("items |> Other.map(mapper) |> Enum.product()")
      assert_style("items |> Enum.map(mapper) |> Other.product()")
    end

    test "map/product does not rewrite before Enum.product_by/2 is available" do
      stub(Quokka.Config, :elixir_version, fn -> "1.17.3" end)
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)

      assert_style("items |> Enum.map(mapper) |> Enum.product()")
    end

    test "map/product respects the inefficient_functions exclusion" do
      stub(Quokka.Config, :elixir_version, fn -> "1.18.0" end)
      stub(Quokka.Config, :inefficient_function_rewrites?, fn -> false end)

      assert_style("items |> Enum.map(mapper) |> Enum.product()")
      assert_style("mapping |> Map.values() |> Enum.product_by(mapper)")
    end

    test "map/product preserves results for numeric mapper outputs" do
      if Version.match?(System.version(), ">= 1.18.0-dev") do
        enable_product_by_rewrite()

        sources_and_items = [
          {
            "items |> Enum.map(& &1.quantity) |> Enum.product()",
            [
              [],
              [%{quantity: 0}],
              [%{quantity: 1}, %{quantity: 2}, %{quantity: 3}],
              [%{quantity: -2}, %{quantity: 3}, %{quantity: 4}],
              [%{quantity: 2}, %{quantity: 2.5}, %{quantity: -0.5}]
            ]
          },
          {
            "items |> Map.values() |> Enum.product_by(& &1.quantity)",
            [%{}, %{a: %{quantity: -2}, b: %{quantity: 3}, c: %{quantity: 4}}]
          },
          {
            "items |> Map.values() |> Enum.map(& &1.quantity) |> Enum.product()",
            [%{}, %{a: %{quantity: 2}, b: %{quantity: 2.5}, c: %{quantity: -0.5}}]
          }
        ]

        for {source, collections} <- sources_and_items, items <- collections do
          {_, styled, _} = style(source)
          {original_result, _binding} = Code.eval_string(source, items: items)
          {styled_result, _binding} = Code.eval_string(styled, items: items)

          assert styled_result == original_result
        end
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

  describe "UtcNowTruncate" do
    test "rewrites DateTime.utc_now() |> DateTime.truncate(:second)" do
      stub(Quokka.Config, :utc_now_truncate?, fn -> true end)
      assert_style("DateTime.utc_now() |> DateTime.truncate(:second)", "DateTime.utc_now(:second)")
      assert_style("NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)", "NaiveDateTime.utc_now(:second)")

      assert_style(
        "NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)",
        "NaiveDateTime.utc_now(:microsecond)"
      )
    end

    test "rewrites pipeless function composition" do
      stub(Quokka.Config, :utc_now_truncate?, fn -> true end)

      assert_style("DateTime.truncate(DateTime.utc_now(), :microsecond)", "DateTime.utc_now(:microsecond)")

      assert_style(
        "NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)",
        "NaiveDateTime.utc_now(:millisecond)"
      )
    end

    test "does not attempt to rewrite odd cases of double truncation " do
      stub(Quokka.Config, :utc_now_truncate?, fn -> true end)

      assert_style(
        "DateTime.utc_now(:second) |> DateTime.truncate(:millisecond)",
        ":second |> DateTime.utc_now() |> DateTime.truncate(:millisecond)"
      )

      assert_style(
        ":millisecond |> NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)",
        ":millisecond |> NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:microsecond)"
      )
    end

    test "does not rewrite other modules" do
      stub(Quokka.Config, :utc_now_truncate?, fn -> true end)
      assert_style("Timex.truncate(Timex.utc_now(), :second)")

      assert_style(
        "MyModule.utc_now() |> MyModule.truncate(:millisecond)",
        "MyModule.truncate(MyModule.utc_now(), :millisecond)"
      )
    end

    test "does not rewrite if utc_now_truncate? is false" do
      stub(Quokka.Config, :utc_now_truncate?, fn -> false end)
      assert_style("DateTime.utc_now() |> DateTime.truncate(:second)", "DateTime.truncate(DateTime.utc_now(), :second)")

      assert_style(
        "NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)",
        "NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)"
      )

      assert_style("DateTime.truncate(DateTime.utc_now(), :microsecond)")
      assert_style("NaiveDateTime.truncate(NaiveDateTime.utc_now(), :millisecond)")
    end
  end

  defp enable_sum_by_rewrite() do
    stub(Quokka.Config, :elixir_version, fn -> "1.18.0" end)
    stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)
  end

  defp enable_product_by_rewrite() do
    stub(Quokka.Config, :elixir_version, fn -> "1.18.0" end)
    stub(Quokka.Config, :inefficient_function_rewrites?, fn -> true end)
  end
end
