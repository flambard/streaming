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

    {{:<-, _, [pattern, generator_input]}, filters} = bottom_generator

    inner_block =
      expand_filters(filters, pattern, generator_input)
      |> expand_bottom_generator(pattern, block)

    for generator <- more_generators, reduce: inner_block do
      block ->
        {{:<-, _, [pattern, generator_input]}, filters} = generator

        expand_filters(filters, pattern, generator_input)
        |> expand_generator(pattern, block)
    end
    |> expand_optional_uniq(options)
  end

  defmacro streaming([resource: resource], do: block, after: after_block) do
    next_fun = expand_block_with_resource(block)
    after_fun = expand_block_with_resource(after_block)

    quote do
      Stream.resource(fn -> unquote(resource) end, unquote(next_fun), unquote(after_fun))
    end
  end

  ###
  ### Private functions
  ###

  defp expand_bottom_generator(filtered_expression, pattern, block) do
    quote do
      unquote(filtered_expression)
      |> Stream.map(fn unquote(pattern) -> unquote(block) end)
    end
  end

  defp expand_generator(filtered_expression, pattern, block) do
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

  defp expand_block_with_resource(clauses) do
    {:fn, [], clauses}
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
