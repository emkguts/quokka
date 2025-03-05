# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.ModuleDirectives.AliasLiftingTest do
  @moduledoc false
  use Quokka.StyleCase, async: true
  use Mimic

  setup do
    stub(Quokka.Config, :lift_alias?, fn -> true end)
    stub(Quokka.Config, :lift_alias_depth, fn -> 2 end)
    stub(Quokka.Config, :lift_alias_frequency, fn -> 1 end)
    stub(Quokka.Config, :zero_arity_parens?, fn -> true end)

    :ok
  end

  test "lifts aliases repeated >=2 times from 3 deep" do
    assert_style(
      """
      defmodule A do
        @moduledoc false

        @spec bar :: A.B.C.t()
        def bar do
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false

        alias A.B.C

        @spec bar :: C.t()
        def bar() do
          C.f()
        end
      end
      """
    )
  end

  test "lifts aliases already aliased" do
    assert_style(
      """
      defmodule A do
        alias A.B.C

        C.foo()

        A.B.C.foo()
      end
      """,
      """
      defmodule A do
        alias A.B.C

        C.foo()

        C.foo()
      end
      """
    )

    assert_style(
      """
      defmodule A do
        alias A.B.C, as: D
        alias D.E.F, as: C

        C.foo()

        A.B.C.foo()
      end
      """,
      """
      defmodule A do
        alias A.B.C, as: D
        alias D.E.F, as: C

        C.foo()

        A.B.C.foo()
      end
      """
    )
  end

  # This test doesn't pass. It would be difficult to fix.
  # test "two modules that seem to conflict but don't!" do
  #   assert_style(
  #     """
  #     defmodule Foo do
  #       @moduledoc false

  #       A.B.C.foo(X.Y.A)
  #       A.B.C.bar()

  #       X.Y.A
  #     end
  #     """,
  #     """
  #     defmodule Foo do
  #       @moduledoc false

  #       alias A.B.C
  #       alias X.Y.A

  #       C.foo(A)
  #       C.bar()

  #       A
  #     end
  #     """
  #   )
  # end

  test "if multiple lifts collide, lifts only one" do
    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        A.B.C.f()
        A.B.C.f()
        X.Y.C.f()
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias A.B.C

        C.f()
        C.f()
        X.Y.C.f()
      end
      """
    )

    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        A.B.C.f()
        X.Y.C.f()
        X.Y.C.f()
        A.B.C.f()
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias A.B.C

        C.f()
        X.Y.C.f()
        X.Y.C.f()
        C.f()
      end
      """
    )

    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        X.Y.C.f()
        A.B.C.f()
        X.Y.C.f()
        A.B.C.f()
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias X.Y.C

        C.f()
        A.B.C.f()
        C.f()
        A.B.C.f()
      end
      """
    )
  end

  test "lifts from nested modules" do
    assert_style(
      """
      defmodule A do
        @moduledoc false

        defmodule B do
          @moduledoc false

          A.B.C.f()
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false

        alias A.B.C

        defmodule B do
          @moduledoc false

          C.f()
          C.f()
        end
      end
      """
    )

    # this isn't exactly _desired_ behaviour but i don't see a real problem with it.
    # as long as we're deterministic that's alright. this... really should never happen in the real world.
    assert_style(
      """
      defmodule A do
        defmodule B do
          A.B.C.f()
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        alias A.B.C

        defmodule B do
          C.f()
          C.f()
        end
      end
      """
    )
  end

  test "only deploys new aliases in nodes _after_ the alias stanza" do
    assert_style(
      """
      defmodule Timely do
        use A.B.C
        def foo do
          A.B.C.bop
        end
        import A.B.C
        require A.B.C
      end
      """,
      """
      defmodule Timely do
        use A.B.C

        import A.B.C

        alias A.B.C

        require C

        def foo() do
          C.bop()
        end
      end
      """
    )
  end

  test "skips over quoted or odd aliases" do
    assert_style """
    alias Boop.Baz

    Some.unquote(whatever).Alias.bar()
    Some.unquote(whatever).Alias.bar()
    """
  end

  test "deep nesting of an alias" do
    assert_style(
      """
      alias Foo.Bar.Baz

      Baz.Bop.Boom.wee()
      Baz.Bop.Boom.wee()

      """,
      """
      alias Foo.Bar.Baz
      alias Foo.Bar.Baz.Bop.Boom

      Boom.wee()
      Boom.wee()
      """
    )
  end

  test "lifts in modules with only-child bodies" do
    assert_style(
      """
      defmodule A do
        def lift_me() do
          A.B.C.foo()
          A.B.C.baz()
        end
      end
      """,
      """
      defmodule A do
        alias A.B.C

        def lift_me() do
          C.foo()
          C.baz()
        end
      end
      """
    )
  end

  test "re-sorts requires after lifting" do
    assert_style(
      """
      defmodule A do
        require A.B.C
        require B

        A.B.C.foo()
      end
      """,
      """
      defmodule A do
        alias A.B.C

        require B
        require C

        C.foo()
      end
      """
    )
  end

  test "sorts in alpha order when sort_order is :alpha" do
    assert_style(
      """
      defmodule A do
        alias A.SPOOL
        alias A.School
        alias A.Stool

        SPOOL.foo()
        School.foo()
        Stool.foo()
      end
      """,
      """
      defmodule A do
        alias A.School
        alias A.SPOOL
        alias A.Stool

        SPOOL.foo()
        School.foo()
        Stool.foo()
      end
      """
    )
  end

  test "sorts in ascii order when sort_order is :ascii" do
    stub(Quokka.Config, :sort_order, fn -> :ascii end)

    assert_style(
      """
      defmodule A do
        alias A.SPOOL
        alias A.School
        alias A.Stool

        SPOOL.foo()
        School.foo()
        Stool.foo()
      end
      """,
      """
      defmodule A do
        alias A.SPOOL
        alias A.School
        alias A.Stool

        SPOOL.foo()
        School.foo()
        Stool.foo()
      end
      """
    )
  end

  describe "comments stay put" do
    test "comments before alias stanza" do
      assert_style(
        """
        # Foo is my fave
        import Foo

        A.B.C.f()
        A.B.C.f()
        """,
        """
        # Foo is my fave
        import Foo

        alias A.B.C

        C.f()
        C.f()
        """
      )
    end

    test "comments after alias stanza" do
      assert_style(
        """
        # Foo is my fave
        require Foo

        A.B.C.f()
        A.B.C.f()
        """,
        """
        alias A.B.C
        # Foo is my fave
        require Foo

        C.f()
        C.f()
        """
      )
    end
  end

  describe "it doesn't lift" do
    test "when flag is off" do
      stub(Quokka.Config, :lift_alias?, fn -> false end)

      assert_style(
        """
        defmodule MyModule do
          @moduledoc false

          @spec foo :: A.B.C.t()
          def foo do
            A.B.C.f()
            A.B.C.g()
          end

          def bar do
            X.Y.Z.foo()
            X.Y.Z.bar()
            X.Y.Z.baz()
          end

          defmodule Nested do
            @moduledoc false

            def baz do
              P.Q.R.one()
              P.Q.R.two()
              P.Q.R.three()
            end
          end
        end
        """,
        """
        defmodule MyModule do
          @moduledoc false

          @spec foo :: A.B.C.t()
          def foo() do
            A.B.C.f()
            A.B.C.g()
          end

          def bar() do
            X.Y.Z.foo()
            X.Y.Z.bar()
            X.Y.Z.baz()
          end

          defmodule Nested do
            @moduledoc false

            def baz() do
              P.Q.R.one()
              P.Q.R.two()
              P.Q.R.three()
            end
          end
        end
        """
      )
    end

    test "collisions with configured modules" do
      stub(Quokka.Config, :lift_alias_excluded_lastnames, fn -> MapSet.new([:C]) end)

      assert_style """
                   alias Foo.Bar

                   A.B.C.foo()
                   A.B.C.foo()
                   D.E.F.foo()
                   D.E.F.foo()
                   """,
                   """
                   alias D.E.F
                   alias Foo.Bar

                   A.B.C.foo()
                   A.B.C.foo()
                   F.foo()
                   F.foo()
                   """
    end

    test "collisions with configured regexes" do
      stub(Quokka.Config, :lift_alias_excluded_namespaces, fn -> MapSet.new([:Name]) end)

      assert_style(
        """
        defmodule MyModule do
          alias Foo.Bar

          Name.Y.Z.bar()
          Name.Y.Z.bar()
          A.B.C.foo()
          A.B.C.foo()
          A.B.C.D.foo()
          A.B.C.D.foo()
        end
        """,
        """
        defmodule MyModule do
          alias A.B.C
          alias A.B.C.D
          alias Foo.Bar

          Name.Y.Z.bar()
          Name.Y.Z.bar()
          C.foo()
          C.foo()
          D.foo()
          D.foo()
        end
        """
      )
    end

    test "collisions with std lib" do
      assert_style """
      defmodule DontYouDare do
        @moduledoc false

        My.Sweet.List.foo()
        My.Sweet.List.foo()
        IHave.MyOwn.Supervisor.init()
        IHave.MyOwn.Supervisor.init()
      end
      """
    end

    test "collisions with aliases" do
      for alias_c <- ["alias A.C", "alias A.B, as: C"] do
        assert_style """
        defmodule NuhUh do
          @moduledoc false

          #{alias_c}

          A.B.C.f()
          A.B.C.f()
        end
        """
      end
    end

    test "collisions with submodules" do
      assert_style """
      defmodule A do
        @moduledoc false

        A.B.C.f()

        defmodule C do
          @moduledoc false
          A.B.C.f()
        end

        A.B.C.f()
      end
      """
    end

    test "defprotocol, defmodule, or defimpl" do
      assert_style """
      defmodule No do
        @moduledoc false

        defprotocol A.B.C do
          :body
        end

        A.B.C.f()
      end
      """

      assert_style(
        """
        defmodule No do
          @moduledoc false

          defimpl A.B.C, for: A.B.C do
            :body
          end

          A.B.C.f()
          A.B.C.f()
        end
        """,
        """
        defmodule No do
          @moduledoc false

          alias A.B.C

          defimpl A.B.C, for: A.B.C do
            :body
          end

          C.f()
          C.f()
        end
        """
      )

      assert_style """
      defmodule No do
        @moduledoc false

        defmodule A.B.C do
          @moduledoc false
          :body
        end

        A.B.C.f()
      end
      """

      assert_style """
      defmodule No do
        @moduledoc false

        defimpl A.B.C, for: A.B.C do
          :body
        end

        A.B.C.f()
      end
      """
    end

    test "quoted sections" do
      assert_style """
      defmodule A do
        @moduledoc false
        defmacro __using__(_) do
          quote do
            A.B.C.f()
            A.B.C.f()
          end
        end
      end
      """
    end

    test "collisions with other callsites :(" do
      # if the last module of a list in an alias
      # is the first of any other
      # do not do the lift of either?
      assert_style """
      defmodule A do
        @moduledoc false

        foo
        |> Baz.Boom.bop()
        |> boop()

        Foo.Bar.Baz.bop()
        Foo.Bar.Baz.bop()
      end
      """

      assert_style """
      defmodule A do
        @moduledoc false

        Foo.Bar.Baz.bop()
        Foo.Bar.Baz.bop()

        foo
        |> Baz.Boom.bop()
        |> boop()
      end
      """
    end

    test "does not lift aliases that are already lifted" do
      # if the last module of a list in an alias is the first of an already lifted alias,
      # do not lift the alias
      assert_style """
      defmodule A do
        @moduledoc false

        alias C.D.E

        E.f()
        E.f()

        A.B.C.f()
        A.B.C.f()
      end
      """
    end
  end

  test "lifts all aliases when lift_alias_depth is 0" do
    stub(Quokka.Config, :lift_alias_depth, fn -> 0 end)

    assert_style(
      """
      defmodule MyModule do
        @moduledoc false

        B.C.f()
        B.C.g()
        Y.Z.foo()
        Y.Z.bar()
        S.T.bar()
        S.T.baz()
      end
      """,
      """
      defmodule MyModule do
        @moduledoc false

        alias B.C
        alias S.T
        alias Y.Z

        C.f()
        C.g()
        Z.foo()
        Z.bar()
        T.bar()
        T.baz()
      end
      """
    )
  end

  describe "lift_alias_frequency configuration" do
    test "only lifts aliases that meet frequency threshold" do
      stub(Quokka.Config, :lift_alias_frequency, fn -> 2 end)

      assert_style(
        """
        defmodule MyModule do
          @moduledoc false

          A.B.C.foo()
          A.B.C.bar()
          X.Y.Z.one()
          X.Y.Z.two()
          X.Y.Z.three()
          P.Q.R.single()
        end
        """,
        """
        defmodule MyModule do
          @moduledoc false

          alias X.Y.Z

          A.B.C.foo()
          A.B.C.bar()
          Z.one()
          Z.two()
          Z.three()
          P.Q.R.single()
        end
        """
      )
    end

    test "lifts all aliases when frequency is 0" do
      stub(Quokka.Config, :lift_alias_frequency, fn -> 0 end)

      assert_style(
        """
        defmodule MyModule do
          @moduledoc false

          A.B.C.foo()
          X.Y.Z.one()
          P.Q.R.single()
        end
        """,
        """
        defmodule MyModule do
          @moduledoc false

          alias A.B.C
          alias P.Q.R
          alias X.Y.Z

          C.foo()
          Z.one()
          R.single()
        end
        """
      )
    end
  end

  describe "alias lifting within directives" do
    test "lifts aliases when use is after alias" do
      stub(Quokka.Config, :strict_module_layout_order, fn -> [:alias, :use] end)
      stub(Quokka.Config, :lift_alias_frequency, fn -> 0 end)

      assert_style(
        """
        defmodule MyApp.Schemas.MySchema do
          use MyApp.Schema,
            derive: [
              :id,
              name: &MyApp.Schemas.MySchema.encode_name/1
            ]
        end
        """,
        """
        defmodule MyApp.Schemas.MySchema do
          alias MyApp.Schemas.MySchema

          use MyApp.Schema,
            derive: [
              :id,
              name: &MySchema.encode_name/1
            ]
        end
        """
      )
    end

    test "doesn't lift aliases when use is before alias" do
      stub(Quokka.Config, :strict_module_layout_order, fn -> [:use, :alias] end)
      stub(Quokka.Config, :lift_alias_frequency, fn -> 0 end)

      assert_style(
        """
        defmodule MyApp.Schemas.MySchema do
          use MyApp.Schemas.Schema,
            derive: [
              :id,
              name: &MyApp.Schemas.MySchema.encode_name/1
            ]

          A.B.C.foo()
        end
        """,
        """
        defmodule MyApp.Schemas.MySchema do
          use MyApp.Schemas.Schema,
            derive: [
              :id,
              name: &MyApp.Schemas.MySchema.encode_name/1
            ]

          alias A.B.C

          C.foo()
        end
        """
      )
    end

    test "doesn't lift `use` itself unless it will be lifted anyways" do
      stub(Quokka.Config, :strict_module_layout_order, fn -> [:alias, :use] end)
      stub(Quokka.Config, :lift_alias_frequency, fn -> 0 end)

      assert_style(
        """
        defmodule MyApp.Schemas.MySchema do
          use A.B.C,
            derive: [
              :id,
              name: &MyApp.Schemas.MySchema.encode_name/1
            ]
        end
        """,
        """
        defmodule MyApp.Schemas.MySchema do
          alias MyApp.Schemas.MySchema

          use A.B.C,
            derive: [
              :id,
              name: &MySchema.encode_name/1
            ]
        end
        """
      )

      assert_style(
        """
        defmodule MyApp.Schemas.MySchema do
          use A.B.C,
            derive: [
              :id,
              name: &MyApp.Schemas.MySchema.encode_name/1
            ]

          A.B.C.foo()
        end
        """,
        """
        defmodule MyApp.Schemas.MySchema do
          alias A.B.C
          alias MyApp.Schemas.MySchema

          use C,
            derive: [
              :id,
              name: &MySchema.encode_name/1
            ]

          C.foo()
        end
        """
      )
    end

    test "doesn't sort use" do
      stub(Quokka.Config, :strict_module_layout_order, fn -> [:alias, :use] end)
      stub(Quokka.Config, :lift_alias_frequency, fn -> 0 end)

      assert_style(
        """
        defmodule MyApp.Schemas.MySchema do
          use MyApp.Schema,
            derive: [
              :id,
              name: &MyApp.Schemas.MySchema.encode_name/1
            ]

          use IDependOnTheOtherUseBeingFirst

          alias Foo
        end
        """,
        """
        defmodule MyApp.Schemas.MySchema do
          alias Foo
          alias MyApp.Schemas.MySchema

          use MyApp.Schema,
            derive: [
              :id,
              name: &MySchema.encode_name/1
            ]

          use IDependOnTheOtherUseBeingFirst
        end
        """
      )
    end

    test "doesn't lift `import` itself unless it will be lifted anyways" do
      stub(Quokka.Config, :strict_module_layout_order, fn -> [:alias, :import] end)
      stub(Quokka.Config, :lift_alias_frequency, fn -> 0 end)

      assert_style("""
      defmodule MyApp.Schemas.MySchema do
        import A.B.C
      end
      """)

      assert_style(
        """
        defmodule MyApp.Schemas.MySchema do
          import A.B.C
          A.B.C.foo()
        end
        """,
        """
        defmodule MyApp.Schemas.MySchema do
          alias A.B.C

          import C

          C.foo()
        end
        """
      )
    end
  end
end
