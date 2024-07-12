defmodule ScanTest do
  use ExUnit.Case
  import Streaming

  ## Example from Stream.scan/3 documentation for comparison
  #
  # stream = Stream.scan(1..5, 0, &(&1 + &2))
  # Enum.to_list(stream)
  # => [1, 3, 6, 10, 15]
  #

  test "scan" do
    stream =
      streaming x <- 1..5, scan: 0 do
        acc -> x + acc
      end

    assert [1, 3, 6, 10, 15] == Enum.to_list(stream)
  end

  test "scan with bitstring generator" do
    stream =
      streaming <<x::binary-size(2) <- "string">>, scan: [] do
        acc -> [x | acc]
      end

    expected = [["st"], ["ri", "st"], ["ng", "ri", "st"]]
    assert expected == Enum.to_list(stream)
  end
end
