defmodule IntoTest do
  use ExUnit.Case
  import Streaming

  test "into" do
    {:ok, io_device} = StringIO.open("")
    io_stream = IO.stream(io_device, :line)

    stream =
      streaming s <- ["hello", "there"], into: io_stream do
        String.capitalize(s)
      end

    assert {"", ""} == StringIO.contents(io_device)
    assert ["Hello", "There"] == Enum.to_list(stream)
    assert {"", "HelloThere"} == StringIO.contents(io_device)
  end
end
