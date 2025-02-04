defmodule Quokka.ConfigTest do
  use ExUnit.Case, async: false

  import Quokka.Config

  test "no config is good times" do
    assert :ok = set!([])
  end
end
