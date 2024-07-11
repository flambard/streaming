defmodule BitstringTest do
  use ExUnit.Case
  import Streaming

  test "bitstring generator" do
    pixels = <<213, 45, 132, 64, 76, 32, 76, 0, 0, 234, 32, 15>>

    pixel_stream =
      streaming <<r::8, g::8, b::8 <- pixels>> do
        {r, g, b}
      end

    expected = [{213, 45, 132}, {64, 76, 32}, {76, 0, 0}, {234, 32, 15}]
    assert expected == Enum.to_list(pixel_stream)
  end

  test "bitstring generator with leftover byte" do
    pixels = <<213, 45, 132, 64, 76, 32, 76, 0, 0, 234, 32, 15, 34>>

    pixel_stream =
      streaming <<r::8, g::8, b::8 <- pixels>> do
        {r, g, b}
      end

    expected = [{213, 45, 132}, {64, 76, 32}, {76, 0, 0}, {234, 32, 15}]
    assert expected == Enum.to_list(pixel_stream)
  end

  test "another bitstring" do
    bitstring = <<1, "I", 6, "really", 4, "love", 6, "stream", 14, "comprehensions", 1, "!">>

    message_stream =
      streaming <<message_length::integer, message::binary-size(message_length) <- bitstring>> do
        message
      end

    expected = ["I", "really", "love", "stream", "comprehensions", "!"]
    assert expected == Enum.to_list(message_stream)
  end

  test "bitstring generator with filters" do
    stream =
      streaming <<x <- "hello">>, 103 < x, x < 109 do
        x - 32
      end

    assert ~c"HLL" == Enum.to_list(stream)
  end

  test "bitstring generator with outer mapper generator" do
    stream =
      streaming key <- [:a, :b], <<value::16 <- "heja">> do
        {key, value}
      end

    expected = [a: 26725, a: 27233, b: 26725, b: 27233]
    assert expected == Enum.to_list(stream)
  end
end
