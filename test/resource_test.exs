defmodule ResourceTest do
  use ExUnit.Case
  import Streaming

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

  test "resource with uniq and into" do
    {:ok, io_device} = StringIO.open("")
    io_stream = IO.stream(io_device, :line)

    character_stream =
      streaming resource: StringIO.open("Elixir") |> elem(1), into: io_stream, uniq: true do
        pid ->
          case IO.getn(pid, "", 1) do
            :eof -> {:halt, pid}
            char -> {[char], pid}
          end
      after
        pid -> StringIO.close(pid)
      end

    assert {"", ""} == StringIO.contents(io_device)
    assert ["E", "l", "i", "x", "r"] == Enum.to_list(character_stream)
    assert {"", "Elixr"} == StringIO.contents(io_device)
  end

  test "resource with outer generator" do
    character_stream =
      streaming string <- ["yes", "but", "no"], resource: StringIO.open(string) |> elem(1) do
        pid ->
          case IO.getn(pid, "", 1) do
            :eof -> {:halt, pid}
            char -> {[char], pid}
          end
      after
        pid -> StringIO.close(pid)
      end

    expected = ["y", "e", "s", "b", "u", "t", "n", "o"]
    assert expected == Enum.to_list(character_stream)
  end
end
