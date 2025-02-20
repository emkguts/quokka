defmodule Quokka.ConfigTest do
  use ExUnit.Case, async: false

  import Quokka.Config

  alias Quokka.Style.Configs
  alias Quokka.Style.Deprecations

  test "no config is good times" do
    assert :ok = set!([])
  end

  test "respects the `:only` configuration" do
    assert :ok = set!(only: [:deprecations])
    assert [Deprecations] == Quokka.Config.get_styles()
  end

  test "respects the `:exclude` configuration" do
    assert :ok = set!(exclude: [:deprecations])

    # Check for one of the default configs
    assert Configs in Quokka.Config.get_styles()

    # Check that the excluded config is not present
    assert Deprecations not in Quokka.Config.get_styles()
  end

  test "respects the `:only` and `:exclude` configuration" do
    assert :ok = set!(only: [:configs, :deprecations], exclude: [:deprecations])

    assert [Configs] == Quokka.Config.get_styles()
  end

  test "only applies line-length changes if :line_length is present in the `:only` configuration" do
    assert :ok = set!(only: [:line_length])
    assert [] == Quokka.Config.get_styles()
  end
end
