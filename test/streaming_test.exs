defmodule StreamingTest do
  use ExUnit.Case
  doctest Streaming

  import Streaming

  test "single infinite generator" do
    doubles_stream =
      streaming x <- 1..100 do
        x * 2
      end

    assert [2, 4, 6, 8] == Enum.take(doubles_stream, 4)
  end

  test "multiple generators" do
    all_combinations_stream =
      streaming x <- [1, 2], y <- [3, 4], z <- [5, 6] do
        {x, y, z}
      end

    all_combinations_list =
      for x <- [1, 2], y <- [3, 4], z <- [5, 6] do
        {x, y, z}
      end

    assert all_combinations_list == Enum.to_list(all_combinations_stream)
  end

  test "mismatches are filtered out" do
    users = [user: "john", admin: "meg", guest: "barbara"]

    stream =
      streaming {type, name} when type != :guest <- users do
        String.upcase(name)
      end

    assert ["JOHN", "MEG"] == Enum.to_list(stream)
  end

  test "generator and filter" do
    even_integers =
      streaming x <- [:a, :b, :c], y <- 1..100, rem(y, 2) == 0 do
        {x, y}
      end

    assert [a: 2, a: 4, a: 6] == Enum.take(even_integers, 3)
  end

  test "multiple filters" do
    even_integers =
      streaming x <- 1..100,
                rem(x, 2) == 0,
                y <- [:a, :b, :c],
                x != y do
        {x, y}
      end

    assert [{2, :a}, {2, :b}, {2, :c}] == Enum.take(even_integers, 3)
  end

  test "uniq" do
    character_stream =
      streaming x <- ~c"ABBA", uniq: true do
        x
      end

    assert ~c"AB" = Enum.to_list(character_stream)
  end
end
