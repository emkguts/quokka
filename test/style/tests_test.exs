# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.TestsTest do
  use Quokka.StyleCase, async: true
  use Mimic

  setup do
    stub(Quokka.Config, :zero_arity_parens?, fn -> true end)

    :ok
  end

  describe "assert not -> refute rewrites" do
    test "basic not expression" do
      assert_style "assert not user.active", "refute user.active"
      assert_style "assert not valid?", "refute valid?"
      assert_style "assert not Process.alive?(pid)", "refute Process.alive?(pid)"
    end

    test "not with parentheses" do
      assert_style "assert not(user.active)", "refute user.active"
      assert_style "assert not(valid?())", "refute valid?()"
    end

    test "complex not expressions" do
      assert_style "assert not (x > 5 and y < 10)", "refute x > 5 and y < 10"
    end

    test "membership testing with not in" do
      assert_style "assert elem not in my_list", "refute elem in my_list"
      assert_style "assert not (user in banned_users)", "refute user in banned_users"
      assert_style "assert !(key in forbidden_keys)", "refute key in forbidden_keys"
    end
  end

  describe "assert ! -> refute rewrites" do
    test "basic bang expression" do
      assert_style "assert !user.active", "refute user.active"
      assert_style "assert !valid?", "refute valid?"
      assert_style "assert !result", "refute result"
    end

    test "bang with parentheses" do
      assert_style "assert !(user.active)", "refute user.active"
      assert_style "assert !valid?()", "refute valid?()"
    end

    test "complex bang expressions" do
      assert_style "assert !(x > 5)", "refute x > 5"
      assert_style "assert !Enum.empty?(list)", "refute Enum.empty?(list)"
    end
  end

  # TODO: These test cases are commented out because the transformations
  # are not semantically equivalent (see lib/style/tests.ex for details).
  # May bring these back in the future somehow, because most of the time,
  # refute is appropriate even though not semantically equivalent.

  # describe "assert is_nil -> refute rewrites" do
  #   test "basic is_nil" do
  #     assert_style "assert is_nil(user)", "refute user"
  #     assert_style "assert is_nil(result)", "refute result"
  #     assert_style "assert is_nil(value)", "refute value"
  #   end

  #   test "is_nil with complex expressions" do
  #     assert_style "assert is_nil(Map.get(map, :key))", "refute Map.get(map, :key)"
  #     assert_style "assert is_nil(user.email)", "refute user.email"
  #     assert_style "assert is_nil(process |> Process.info())", "refute process |> Process.info()"
  #   end

  #   test "qualified is_nil" do
  #     assert_style "assert Kernel.is_nil(user)", "refute user"
  #   end
  # end

  # describe "assert == nil -> refute rewrites" do
  #   test "expression equals nil" do
  #     assert_style "assert user == nil", "refute user"
  #     assert_style "assert result == nil", "refute result"
  #     assert_style "assert Map.get(map, :key) == nil", "refute Map.get(map, :key)"
  #   end
  # end

  # describe "assert === nil -> refute rewrites" do
  #   test "expression strict equals nil" do
  #     assert_style "assert user === nil", "refute user"
  #     assert_style "assert result === nil", "refute result"
  #   end
  # end

  # describe "assert == false -> refute rewrites" do
  #   test "expression equals false" do
  #     assert_style "assert user.active == false", "refute user.active"
  #     assert_style "assert valid? == false", "refute valid?"
  #   end
  # end

  # describe "assert === false -> refute rewrites" do
  #   test "expression strict equals false" do
  #     assert_style "assert user.active === false", "refute user.active"
  #     assert_style "assert valid? === false", "refute valid?"
  #   end
  # end

  describe "edge cases and no-op scenarios" do
    test "assert with positive conditions - no change" do
      assert_style "assert user.active"
      assert_style "assert user.active == true"
      assert_style "assert user.active === true"
      assert_style "assert result"
      assert_style "assert count > 5"
    end

    test "assert with other comparison operators - no change" do
      assert_style "assert user.age > 18"
      assert_style "assert user.age >= 21"
      assert_style "assert user.age < 65"
      assert_style "assert user.age <= 100"
      assert_style "assert user.name != nil"
      assert_style "assert user.name !== nil"
    end

    test "nested assertions - no change" do
      assert_style "assert [not valid?, true]"
      assert_style "assert %{result: not valid?}"
      assert_style "assert {not valid?, :ok}"
    end

    test "other assertion macros - no change" do
      assert_style "assert_raise ArgumentError, fn -> raise ArgumentError end"
      assert_style "assert_receive :message"
      assert_style "assert_received :message"
    end

    test "refute statements - no change" do
      assert_style "refute user.active"
      assert_style "refute result"
      assert_style "refute is_nil(user)"
    end

    test "complex expressions with mixed operators" do
      assert_style "assert not user.active and other_condition"
      assert_style "assert result == nil or fallback"
    end
  end
end
