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
      streaming [x <- [1, 2], y <- [3, 4], z <- [5, 6]] do
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
      streaming [x <- [:a, :b, :c], y <- 1..100, rem(y, 2) == 0] do
        {x, y}
      end

    assert [a: 2, a: 4, a: 6] == Enum.take(even_integers, 3)
  end

  test "multiple filters" do
    even_integers =
      streaming [
        x <- 1..100,
        rem(x, 2) == 0,
        y <- [:a, :b, :c],
        x != y
      ] do
        {x, y}
      end

    assert [{2, :a}, {2, :b}, {2, :c}] == Enum.take(even_integers, 3)
  end

  test "uniq" do
    character_stream =
      streaming [x <- ~c"ABBA", uniq: true] do
        x
      end

    assert ~c"AB" = Enum.to_list(character_stream)
  end

  ## Example from Stream.resource/3 documentation for comparison
  #
  # Stream.resource(
  #   fn ->
  #     {:ok, pid} = StringIO.open("string")
  #     pid
  #   end,
  #   fn pid ->
  #     case IO.getn(pid, "", 1) do
  #       :eof -> {:halt, pid}
  #       char -> {[char], pid}
  #     end
  #   end,
  #   fn pid -> StringIO.close(pid) end
  # )
  # |> Enum.to_list()
  #

  test "resource" do
    character_stream =
      streaming resource: StringIO.open("string") |> elem(1) do
        pid ->
          case IO.getn(pid, "", 1) do
            :eof -> {:halt, pid}
            char -> {[char], pid}
          end
      after
        pid -> StringIO.close(pid)
      end

    assert ["s", "t", "r", "i", "n", "g"] == Enum.to_list(character_stream)
  end

  test "resource with multiple clauses" do
    character_stream =
      streaming resource: StringIO.open("string") do
        {:ok, pid} ->
          {[], pid}

        pid ->
          case IO.getn(pid, "", 1) do
            :eof -> {:halt, pid}
            char -> {[char], pid}
          end
      after
        pid -> StringIO.close(pid)
      end

    assert ["s", "t", "r", "i", "n", "g"] == Enum.to_list(character_stream)
  end

  ## Example from Stream.transform/3 documentation for comparison
  #
  # enum = 1001..9999
  # n = 3
  #
  # stream =
  #   Stream.transform(enum, 0, fn i, acc ->
  #     if acc < n, do: {[i], acc + 1}, else: {:halt, acc}
  #   end)
  #
  # Enum.to_list(stream)
  # [1001, 1002, 1003]
  #

  test "transform" do
    enum = 1001..9999
    n = 3

    stream =
      streaming [i <- enum, transform: 0] do
        acc -> if acc < n, do: {[i], acc + 1}, else: {:halt, acc}
      end

    assert [1001, 1002, 1003] == Enum.to_list(stream)
  end

  test "transform with multiple generators" do
    stream =
      streaming [x <- 1..3, y <- 4..6, transform: 0] do
        acc -> if acc < 2, do: {[x, y], acc + 1}, else: {:halt, acc}
      end

    expected = [1, 4, 1, 5, 2, 4, 2, 5, 3, 4, 3, 5]
    assert expected == Enum.to_list(stream)
  end

  test "transform with filter" do
    enum = 1001..9999
    n = 3

    stream =
      streaming [i <- enum, rem(i, 2) == 0, transform: 0] do
        acc -> if acc < n, do: {[i], acc + 1}, else: {:halt, acc}
      end

    assert [1002, 1004, 1006] == Enum.to_list(stream)
  end

  test "transform with multiple clauses" do
    enum = 1001..9999
    n = 3

    stream =
      streaming [i <- enum, transform: 0] do
        acc when acc < n -> {[i], acc + 1}
        acc -> {:halt, acc}
      end

    assert [1001, 1002, 1003] == Enum.to_list(stream)
  end
end
