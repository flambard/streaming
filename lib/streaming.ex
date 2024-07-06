defmodule Streaming do
  @moduledoc false

  defmacro streaming({:<-, _, [_, _]} = generator, do: block) do
    quote do
      streaming [unquote(generator)] do
        unquote(block)
      end
    end
  end

  defmacro streaming(args, do: block) do
    {generators_and_filters, options} = Enum.split_while(args, &(not option?(&1)))
    [bottom_generator | more_generators] = group_filters_with_generators(generators_and_filters)

    inner_block = expand_bottom_generator(bottom_generator, block)

    for generator <- more_generators, reduce: inner_block do
      block -> expand_generator(generator, block)
    end
    |> expand_optional_uniq(options)
  end

  ###
  ### Private functions
  ###

  defp expand_bottom_generator({{:<-, _, [pattern, generator_expression]}, filters}, block) do
    filtered_expression = expand_filters(filters, pattern, generator_expression)

    quote do
      unquote(filtered_expression)
      |> Stream.map(fn unquote(pattern) -> unquote(block) end)
    end
  end

  defp expand_generator({{:<-, _, [pattern, generator_expression]}, filters}, block) do
    filtered_expression = expand_filters(filters, pattern, generator_expression)

    quote do
      unquote(filtered_expression)
      |> Stream.flat_map(fn unquote(pattern) -> unquote(block) end)
    end
  end

  defp expand_filters(filters, pattern, generator_expression) do
    pattern_filtered =
      quote generated: true do
        unquote(generator_expression)
        |> Stream.filter(&match?(unquote(pattern), &1))
      end

    for filter <- filters, reduce: pattern_filtered do
      expression ->
        quote do
          unquote(expression)
          |> Stream.filter(fn unquote(pattern) -> unquote(filter) end)
        end
    end
  end

  defp expand_optional_uniq(stream, options) do
    if Keyword.get(options, :uniq) == true do
      quote do
        unquote(stream)
        |> Stream.uniq()
      end
    else
      stream
    end
  end

  defp group_filters_with_generators(generators_and_filters) do
    group_filters_with_generators(generators_and_filters, [])
  end

  defp group_filters_with_generators([], acc) do
    acc
  end

  defp group_filters_with_generators([{:<-, _, [_, _]} = generator | rest], acc) do
    {filters, more} = Enum.split_while(rest, &(not generator?(&1)))
    group_filters_with_generators(more, [{generator, filters} | acc])
  end

  defp generator?(arg) do
    match?({:<-, _, [_, _]}, arg)
  end

  defp option?(arg) do
    match?({_key, _value}, arg)
  end
end
