# Streaming

Syntactic sugar macro for generating streams, very much inspired by [`for`](https://hexdocs.pm/elixir/Kernel.SpecialForms.html#for/1) in Elixir.



`streaming` is lazy and always returns a [`Stream`](https://hexdocs.pm/elixir/Stream.html).

## Examples

Generate a stream of all permutations of x, y, and z.
```elixir
streaming x <- 1..10, y <- 11..20, z <- 21..30 do
  {x, y, z}
end
```

Just like `for`, mismatching values are rejected.
```elixir
users = [user: "john", admin: "meg", guest: "barbara"]

streaming {type, name} when type != :guest <- users do
  String.upcase(name)
end
|> Enum.to_list()

=> ["JOHN", "MEG"]
```

Filter for keeping only even numbers
```elixir
streaming x <- 1..100, rem(y, 2) == 0 do
  x
end
|> Enum.take(3)

=> [2, 4, 6]
```

`uniq` works like expected.
```elixir
streaming x <- ~c"ABBA", uniq: true do
  x + 32
end
|> Enum.to_list()

=> ~c"ab"
```

Infinite stream of multiples of 2 with `unfold`, based on [`Stream.unfold/2`](https://hexdocs.pm/elixir/Stream.html#unfold/2).
```elixir
streaming unfold: 1 do
  n -> {n, n * 2}
end
|> Enum.take(10)

=> [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
```

Sugar for [`Stream.scan/3`](https://hexdocs.pm/elixir/Stream.html#scan/3) is included (but not [`Stream.scan/2`](https://hexdocs.pm/elixir/Stream.html#scan/2))
```elixir
streaming x <- 1..5, scan: 0 do
  acc -> x + acc
end
|> Enum.to_list()

=> [1, 3, 6, 10, 15]
```

Stream values from a resource and close it when the stream ends.
```elixir
streaming resource: StringIO.open("string") |> elem(1) do
  pid ->
    case IO.getn(pid, "", 1) do
      :eof -> {:halt, pid}
      char -> {[char], pid}
    end
after
  pid -> StringIO.close(pid)
end
|> Enum.to_list()

=> ["s", "t", "r", "i", "n", "g"]
```

Transforming data from a resource with an enumerable.
```elixir
streaming i <- 1..100, transform: StringIO.open("string") |> elem(1) do
  pid ->
    case IO.getn(pid, "", 1) do
      :eof -> {:halt, pid}
      char -> {[{i, char}], pid}
    end
after
  pid -> StringIO.close(pid)
end
|> Enum.to_list()

=> [{1, "s"}, {2, "t"}, {3, "r"}, {4, "i"}, {5, "n"}, {6, "g"}]
```

Note that `into` uses [`Stream.into/2`](https://hexdocs.pm/elixir/Stream.html#into/3) and streams values into a collectable _as a side-effect_.
```elixir
{:ok, io_device} = StringIO.open("")
io_stream = IO.stream(io_device, :line)

streaming s <- ["hello", "there"], into: io_stream do
  String.capitalize(s)
end
|> Enum.to_list()

=> ["Hello", "There"]

## Values has been streamed into io_stream as well
StringIO.contents(io_device)

=> {"", "HelloThere"}
```
