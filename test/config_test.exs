defmodule Quokka.ConfigTest do
  use ExUnit.Case, async: false

  import Quokka.Config

  test "no config is good times" do
    assert :ok = set!([])
  end

  test "rewrite deprecations flag is respected" do
    assert :ok = set!(rewrite_deprecations: false)
    assert Quokka.Style.Deprecations not in Quokka.Config.get_styles()

    assert :ok = set!(rewrite_deprecations: true)
    assert Quokka.Style.Deprecations in Quokka.Config.get_styles()
  end

  test "reorder configs flag is respected" do
    assert :ok = set!(reorder_configs: false)
    assert Quokka.Style.Configs not in Quokka.Config.get_styles()

    assert :ok = set!(reorder_configs: true)
    assert Quokka.Style.Configs in Quokka.Config.get_styles()
  end
end
