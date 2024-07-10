defmodule TransformTest do
  use ExUnit.Case
  import Streaming

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
      streaming i <- enum, transform: 0 do
        acc -> if acc < n, do: {[i], acc + 1}, else: {:halt, acc}
      end

    assert [1001, 1002, 1003] == Enum.to_list(stream)
  end

  test "transform with multiple generators" do
    stream =
      streaming x <- 1..3, y <- 4..6, transform: 0 do
        acc -> if acc < 2, do: {[x, y], acc + 1}, else: {:halt, acc}
      end

    expected = [1, 4, 1, 5, 2, 4, 2, 5, 3, 4, 3, 5]
    assert expected == Enum.to_list(stream)
  end

  test "transform with filter" do
    enum = 1001..9999
    n = 3

    stream =
      streaming i <- enum, rem(i, 2) == 0, transform: 0 do
        acc -> if acc < n, do: {[i], acc + 1}, else: {:halt, acc}
      end

    assert [1002, 1004, 1006] == Enum.to_list(stream)
  end

  test "transform with multiple clauses" do
    enum = 1001..9999
    n = 3

    stream =
      streaming i <- enum, transform: 0 do
        acc when acc < n -> {[i], acc + 1}
        acc -> {:halt, acc}
      end

    assert [1001, 1002, 1003] == Enum.to_list(stream)
  end

  test "transform with after-clause" do
    tuple_stream =
      streaming i <- 1..100, transform: StringIO.open("string") |> elem(1) do
        pid ->
          case IO.getn(pid, "", 1) do
            :eof -> {:halt, pid}
            char -> {[{i, char}], pid}
          end
      after
        pid -> StringIO.close(pid)
      end

    expected = [{1, "s"}, {2, "t"}, {3, "r"}, {4, "i"}, {5, "n"}, {6, "g"}]
    assert expected == Enum.to_list(tuple_stream)
  end
end
