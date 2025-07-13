# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.CommentDirectivesTest do
  @moduledoc false
  use Quokka.StyleCase, async: true

  describe "autosort" do
    test "autosorts schema fields" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:schema] end)

      assert_style(
        """
        defmodule MySchema do
          use Ecto.Schema
          schema "my_schema" do
            field :name, :string
            field :age, :integer
            field :email, :string
          end
        end
        """,
        """
        defmodule MySchema do
          use Ecto.Schema

          schema "my_schema" do
            field(:age, :integer)
            field(:email, :string)
            field(:name, :string)
          end
        end
        """
      )
    end

    test "autosorts schema fields with associations" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:schema] end)

      assert_style(
        """
        defmodule MySchema do
          use Ecto.Schema
          schema "my_schema" do
            field :name, :string
            field :age, :integer
            has_many :posts, Post
            field :email, :string
            has_one :profile, Profile
            belongs_to :user, User
            many_to_many :tags, Tag, join_through: "my_schema_tags"
            embeds_many :comments, Comment
            embeds_one :settings, Settings
          end
        end
        """,
        """
        defmodule MySchema do
          use Ecto.Schema

          schema "my_schema" do
            field(:age, :integer)
            field(:email, :string)
            field(:name, :string)

            belongs_to(:user, User)

            has_many(:posts, Post)

            has_one(:profile, Profile)

            many_to_many(:tags, Tag, join_through: "my_schema_tags")

            embeds_many(:comments, Comment)

            embeds_one(:settings, Settings)
          end
        end
        """
      )

      assert_style(
        """
        defmodule MySchema do
          use Ecto.Schema
          schema "my_schema" do
            field :name, :string
            field :age, :integer
            field :email, :string
            has_many :posts, Post
            has_one :profile, Profile
            weird_thing :foo
            belongs_to :user, User
            many_to_many :tags, Tag, join_through: "my_schema_tags"
          end
        end
        """,
        """
        defmodule MySchema do
          use Ecto.Schema

          schema "my_schema" do
            field(:age, :integer)
            field(:email, :string)
            field(:name, :string)

            belongs_to(:user, User)

            has_many(:posts, Post)

            has_one(:profile, Profile)

            many_to_many(:tags, Tag, join_through: "my_schema_tags")

            weird_thing(:foo)
          end
        end
        """
      )
    end

    test "autosorts typed schema fields" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:schema] end)

      assert_style(
        """
        defmodule MySchema do
          use Ecto.Schema
          typed_schema "my_schema" do
            field :name, :string
            field :age, :integer
            field :email, :string
          end
        end
        """,
        """
        defmodule MySchema do
          use Ecto.Schema

          typed_schema "my_schema" do
            field(:age, :integer)
            field(:email, :string)
            field(:name, :string)
          end
        end
        """
      )
    end

    test "autosorts embedded schema fields" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:schema] end)

      assert_style(
        """
        defmodule MySchema do
          use Ecto.Schema
          embedded_schema do
            field :name, :string
            field :age, :integer
            field :email, :string
          end
        end
        """,
        """
        defmodule MySchema do
          use Ecto.Schema

          embedded_schema do
            field(:age, :integer)
            field(:email, :string)
            field(:name, :string)
          end
        end
        """
      )
    end

    test "autosorts even after comment directive" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:schema] end)

      assert_style(
        """
        defmodule Schemas.DemographicSchema do
          use MyApp.Schema,
            # quokka:sort
            derive: [
              :sex,
              :age,
              :id
            ]

          typed_schema "demographic" do
            has_many(:people, PersonSchema, foreign_key: :person_id)
            belongs_to(:census, CensusSchema)
            timestamps()
            field(:sex, :string)
            field(:age, :integer)
          end
        end
        """,
        """
        defmodule Schemas.DemographicSchema do
          use MyApp.Schema,
            # quokka:sort
            derive: [
              :age,
              :id,
              :sex
            ]

          typed_schema "demographic" do
            field(:age, :integer)
            field(:sex, :string)

            belongs_to(:census, CensusSchema)

            has_many(:people, PersonSchema, foreign_key: :person_id)

            timestamps()
          end
        end
        """
      )
    end

    test "autosorts map update keys" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        %{var | new_elem: val, another_elem: other_val}
        """,
        """
        %{var | another_elem: other_val, new_elem: val}
        """
      )
    end

    test "autosorts maps" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        %{c: 2, b: 3, a: 4, d: 1}
        """,
        """
        %{a: 4, b: 3, c: 2, d: 1}
        """
      )
    end

    test "autosorts maps with numeric keys" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      # Integer keys
      assert_style(
        """
        %{10 => "ten", 1 => "one", 2 => "two", 20 => "twenty"}
        """,
        """
        %{1 => "one", 2 => "two", 10 => "ten", 20 => "twenty"}
        """
      )

      # Float keys
      assert_style(
        """
        %{10.5 => "ten-five", 1.5 => "one-five", 2.0 => "two", 20.1 => "twenty-one"}
        """,
        """
        %{1.5 => "one-five", 2.0 => "two", 10.5 => "ten-five", 20.1 => "twenty-one"}
        """
      )

      # Mixed numeric keys
      assert_style(
        """
        %{10 => "ten", 1.5 => "one-five", 2 => "two", 20.0 => "twenty"}
        """,
        """
        %{1.5 => "one-five", 2 => "two", 10 => "ten", 20.0 => "twenty"}
        """
      )
    end

    test "autosorts maps with mixed atom and string keys" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        %{:b => 1, "a" => 2, :c => 3}
        """,
        """
        %{"a" => 2, :b => 1, :c => 3}
        """
      )
    end

    test "autosorts maps with mixed numeric and atom keys" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        %{1 => "one", :c => "c", 1.5 => "one and a half", :b => "b", :a => "a", 10 => "ten", 2 => "two"}
        """,
        """
        %{1 => "one", 1.5 => "one and a half", 2 => "two", 10 => "ten", :a => "a", :b => "b", :c => "c"}
        """
      )
    end

    test "autosorts maps with numeric range keys" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        %{
          1 => "first",
          (13..17) => "thirteen to seventeen",
          (18..22) => "eighteen to twenty-two", 
          2 => "second",
          (23..24) => "twenty-three to twenty-four",
          (25..29) => "twenty-five to twenty-nine",
          (3..5) => "three to five",
          (30..36) => "thirty to thirty-six"
        }
        """,
        """
        %{
          1 => "first",
          2 => "second",
          (3..5) => "three to five",
          (13..17) => "thirteen to seventeen",
          (18..22) => "eighteen to twenty-two",
          (23..24) => "twenty-three to twenty-four",
          (25..29) => "twenty-five to twenty-nine",
          (30..36) => "thirty to thirty-six"
        }
        """
      )
    end

    test "autosorts maps with mixed numeric keys, ranges, and string keys" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        %{
          "zebra" => "last string",
          1 => "first number",
          (10..15) => "ten to fifteen",
          "apple" => "first string",
          5 => "fifth number",
          (2..4) => "two to four",
          :atom_key => "atom value"
        }
        """,
        """
        %{
          1 => "first number",
          (2..4) => "two to four",
          5 => "fifth number",
          (10..15) => "ten to fifteen",
          "apple" => "first string",
          "zebra" => "last string",
          :atom_key => "atom value"
        }
        """
      )
    end

    test "autosorts ecto queries" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        defmodule Example do
          import Ecto.Query

          def union_query() do
            query1 =
              from u in "users",
                select: %{
                  name: u.name,
                  email: u.email,
                  active: true
                }
          end
        end
        """,
        """
        defmodule Example do
          import Ecto.Query

          def union_query() do
            query1 =
              from(u in "users",
                select: %{
                  active: true,
                  email: u.email,
                  name: u.name
                }
              )
          end
        end
        """
      )
    end

    test "skips autosort for ecto queries" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)
      Mimic.stub(Quokka.Config, :autosort_exclude_ecto?, fn -> true end)

      assert_style("""
      defmodule Example do
        import Ecto.Query

        def union_query() do
          query1 =
            from(u in "users",
              select: %{
                name: u.name,
                email: u.email,
                active: true
              }
            )
        end
      end
      """)

      # does sort another map with `from`
      assert_style("from = %{c: 1, b: 2, a: 3}", "from = %{a: 3, b: 2, c: 1}")
      assert_style("%{to: 3, from: 1, where: 2}", "%{from: 1, to: 3, where: 2}")
    end

    test "skips autosorting maps when there is a skip-sort directive" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style("""
      # quokka:skip-sort
      %{c: 2, b: 3, a: 4, d: 1}
      """)
    end

    test "skips autosort for remote Ecto.Query.from calls" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)
      Mimic.stub(Quokka.Config, :autosort_exclude_ecto?, fn -> true end)

      # Should not sort maps in remote Ecto.Query.from calls
      assert_style("""
      defmodule Example do
        def query_with_explicit_module() do
          Ecto.Query.from(u in "users",
            select: %{
              name: u.name,
              email: u.email,
              active: true
            }
          )
        end
      end
      """)
    end

    test "does not skip autosort for non-Ecto from functions" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)
      Mimic.stub(Quokka.Config, :autosort_exclude_ecto?, fn -> true end)

      # Should sort maps in non-Ecto from functions (false positive prevention)
      assert_style(
        """
        defmodule Example do
          def custom_from() do
            # This is not an Ecto query, just a function named 'from'
            result = from(%{z: 1, a: 2, m: 3})
            result
          end
        end
        """,
        """
        defmodule Example do
          def custom_from() do
            # This is not an Ecto query, just a function named 'from'
            result = from(%{a: 2, m: 3, z: 1})
            result
          end
        end
        """
      )

      # Should sort maps in module-qualified from calls that aren't Ecto
      assert_style(
        """
        defmodule Example do
          def custom_query() do
            MyModule.from(%{z: 1, a: 2, m: 3})
          end
        end
        """,
        """
        defmodule Example do
          def custom_query() do
            MyModule.from(%{a: 2, m: 3, z: 1})
          end
        end
        """
      )
    end

    test "correctly identifies Ecto queries with various patterns" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)
      Mimic.stub(Quokka.Config, :autosort_exclude_ecto?, fn -> true end)

      # Should not sort - standard Ecto query with 'in' clause
      assert_style("""
      import Ecto.Query

      from(p in Post, select: %{title: p.title, id: p.id})
      """)

      # Should sort - 'from' without 'in' clause (not an Ecto query pattern)
      assert_style(
        "from(%{z: 1, a: 2})",
        "from(%{a: 2, z: 1})"
      )
    end

    test "skips autosorting maps when there is a comment inside the map" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style("""
      %{
        c: 1,
        b: 2,
        # this needs to come last
        a: 3
      }
      """)
    end

    test "autosorts maps when map contains comment and there is a sort directive" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        # quokka:sort
        %{
          c: 1,
          b: 2,
          # this needs to come last
          a: 3
        }
        """,
        """
        # quokka:sort
        # this needs to come last
        %{
          a: 3,
          b: 2,
          c: 1
        }
        """
      )
    end

    test "autosorts module attributes" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:map] end)

      assert_style(
        """
        @attr %{c: 1, b: 2, a: 3}
        """,
        """
        @attr %{a: 3, b: 2, c: 1}
        """
      )
    end

    test "autosorts defstructs" do
      Mimic.stub(Quokka.Config, :autosort, fn -> [:defstruct] end)

      assert_style(
        """
        defstruct c: 1, b: 2, a: 3
        """,
        """
        defstruct a: 3, b: 2, c: 1
        """
      )

      assert_style(
        """
        defstruct [c, b, a]
        """,
        """
        defstruct [a, b, c]
        """
      )
    end
  end

  describe "sort" do
    test "we dont just sort by accident" do
      assert_style "[:c, :b, :a]"
    end

    test "sorts lists of atoms" do
      assert_style(
        """
        # quokka:sort
        [
          :c,
          :b,
          :c,
          :a
        ]
        """,
        """
        # quokka:sort
        [
          :a,
          :b,
          :c,
          :c
        ]
        """
      )
    end

    test "sort keywordy things" do
      assert_style(
        """
        # quokka:sort
        [
          c: 2,
          b: 3,
          a: 4,
          d: 1
        ]
        """,
        """
        # quokka:sort
        [
          a: 4,
          b: 3,
          c: 2,
          d: 1
        ]
        """
      )

      assert_style(
        """
        # quokka:sort
        %{
          c: 2,
          b: 3,
          a: 4,
          d: 1
        }
        """,
        """
        # quokka:sort
        %{
          a: 4,
          b: 3,
          c: 2,
          d: 1
        }
        """
      )

      assert_style(
        """
        # quokka:sort
        %Struct{
          c: 2,
          b: 3,
          a: 4,
          d: 1
        }
        """,
        """
        # quokka:sort
        %Struct{
          a: 4,
          b: 3,
          c: 2,
          d: 1
        }
        """
      )

      assert_style(
        """
        # quokka:sort
        defstruct c: 2, b: 3, a: 4, d: 1
        """,
        """
        # quokka:sort
        defstruct a: 4, b: 3, c: 2, d: 1
        """
      )

      assert_style(
        """
        # quokka:sort
        defstruct [
          :repo,
          :query,
          :order,
          :chunk_size,
          :timeout,
          :cursor
        ]
        """,
        """
        # quokka:sort
        defstruct [
          :chunk_size,
          :cursor,
          :order,
          :query,
          :repo,
          :timeout
        ]
        """
      )
    end

    test "inside keywords" do
      assert_style(
        """
        %{
          key:
          # quokka:sort
          [
            3,
            2,
            1
          ]
        }
        """,
        """
        %{
          # quokka:sort
          key: [
            1,
            2,
            3
          ]
        }
        """
      )

      assert_style(
        """
        %{
          # quokka:sort
          key: [
            3,
            2,
            1
          ]
        }
        """,
        """
        %{
          # quokka:sort
          key: [
            1,
            2,
            3
          ]
        }
        """
      )
    end

    test "sorts sigils" do
      assert_style("# quokka:sort\n~w|c a b|", "# quokka:sort\n~w|a b c|")

      assert_style(
        """
        # quokka:sort
        ~w(
          a
          long
          list
          of
          static
          values
        )
        """,
        """
        # quokka:sort
        ~w(
          a
          list
          long
          of
          static
          values
        )
        """
      )
    end

    test "assignments" do
      assert_style(
        """
        # quokka:sort
        my_var =
          ~w(
            a
            long
            list
            of
            static
            values
          )
        """,
        """
        # quokka:sort
        my_var =
          ~w(
            a
            list
            long
            of
            static
            values
          )
        """
      )

      assert_style(
        """
        defmodule M do
          @moduledoc false
          # quokka:sort
          @attr ~w(
              a
              long
              list
              of
              static
              values
            )
        end
        """,
        """
        defmodule M do
          @moduledoc false
          # quokka:sort
          @attr ~w(
              a
              list
              long
              of
              static
              values
            )
        end
        """
      )
    end

    test "doesnt affect downstream nodes" do
      assert_style(
        """
        # quokka:sort
        [:c, :a, :b]

        @country_codes ~w(
          po_PO
          en_US
          fr_CA
          ja_JP
        )
        """,
        """
        # quokka:sort
        [:a, :b, :c]

        @country_codes ~w(
          po_PO
          en_US
          fr_CA
          ja_JP
        )
        """
      )
    end

    test "list of tuples" do
      # 2ples are represented as block literals while >2ples are created via `:{}`
      # decided the easiest way to handle this is to just use string representation for meow
      assert_style(
        """
        # quokka:sort
        [
          {:styler, github: "adobe/elixir-styler"},
          {:ash, "~> 3.0"},
          {:fluxon, "~> 1.0.0", repo: :fluxon},
          {:phoenix_live_reload, "~> 1.2", only: :dev},
          {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
        ]
        """,
        """
        # quokka:sort
        [
          {:ash, "~> 3.0"},
          {:fluxon, "~> 1.0.0", repo: :fluxon},
          {:phoenix_live_reload, "~> 1.2", only: :dev},
          {:styler, github: "adobe/elixir-styler"},
          {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
        ]
        """
      )
    end

    test "nodes within a do end block" do
      assert_style(
        """
        # quokka:sort
        my_macro "some arg" do
          another_macro :q
          # w
          another_macro :w
          another_macro :e
          # r comment 1
          # r comment 2
          another_macro :r
          another_macro :t
          another_macro :y
        end
        """,
        """
        # quokka:sort
        my_macro "some arg" do
          another_macro(:e)
          another_macro(:q)
          # r comment 1
          # r comment 2
          another_macro(:r)
          another_macro(:t)
          # w
          another_macro(:w)
          another_macro(:y)
        end
        """
      )
    end

    test "treats comments nicely" do
      assert_style(
        """
        # pre-amble comment
        # quokka:sort
        [
          {:phoenix, "~> 1.7"},
          # hackney comment
          {:hackney, "1.18.1", override: true},
          {:styler, "~> 1.2", only: [:dev, :test], runtime: false},
          {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
          {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},
          # ecto
          {:ecto, "~> 3.12"},
          {:ecto_sql, "~> 3.12"},
          # genstage comment 1
          # genstage comment 2
          {:gen_stage, "~> 1.0", override: true},
          # telemetry
          {:telemetry, "~> 1.0", override: true},
          # dangling comment
        ]

        # some other comment
        """,
        """
        # pre-amble comment
        # quokka:sort
        [
          {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
          # ecto
          {:ecto, "~> 3.12"},
          {:ecto_sql, "~> 3.12"},
          {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},
          # genstage comment 1
          # genstage comment 2
          {:gen_stage, "~> 1.0", override: true},
          # hackney comment
          {:hackney, "1.18.1", override: true},
          {:phoenix, "~> 1.7"},
          {:styler, "~> 1.2", only: [:dev, :test], runtime: false},
          # telemetry
          {:telemetry, "~> 1.0", override: true}
          # dangling comment
        ]

        # some other comment
        """
      )
    end
  end
end
