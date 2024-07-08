defmodule UnfoldTest do
  use ExUnit.Case
  import Streaming

  ## Example from Stream.unfold/2 documentation for comparison
  #
  # Stream.unfold(1, fn
  #   n -> {n, n * 2}
  # end)
  # |> Enum.take(10)
  #
  # => [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
  #

  test "unfold" do
    multiples_stream =
      streaming unfold: 1 do
        n -> {n, n * 2}
      end

    assert [1, 2, 4, 8, 16, 32, 64, 128, 256, 512] == Enum.take(multiples_stream, 10)
  end

  test "unfold with multiple clauses" do
    multiples_stream =
      streaming unfold: 5 do
        0 -> nil
        n -> {n, n - 1}
      end

    assert [5, 4, 3, 2, 1] == Enum.to_list(multiples_stream)
  end
end
