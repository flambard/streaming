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
end
