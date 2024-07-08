defmodule Streaming do
  @moduledoc false

  defmacro streaming({:<-, _, [_, _]} = generator, do: block) do
    quote do
      streaming [unquote(generator)] do
        unquote(block)
      end
    end
  end

  defmacro streaming([{:resource, resource} | options], do: block, after: after_block) do
    resource
    |> expand_resource(block, after_block)
    |> expand_optional_uniq(options)
    |> expand_optional_into(options)
  end

  defmacro streaming(args, keyword_options) do
    {:ok, block} = Keyword.fetch(keyword_options, :do)

    {generators_and_filters, options} = Enum.split_while(args, &(not option?(&1)))
    [bottom_generator | more_generators] = group_filters_with_generators(generators_and_filters)

    {{:<-, _, [pattern, generator_input]}, filters} = bottom_generator

    filtered_input =
      generator_input
      |> expand_pattern_filter(pattern)
      |> expand_filters(pattern, filters)

    inner_block =
      cond do
        init = Keyword.get(options, :transform) ->
          after_block = Keyword.get(keyword_options, :after)

          filtered_input
          |> expand_transform(pattern, init, block, after_block)

        init = Keyword.get(options, :scan) ->
          filtered_input
          |> expand_scan(pattern, init, block)

        true ->
          ## Normal mapping
          filtered_input
          |> expand_bottom_generator(pattern, block)
      end

    for generator <- more_generators, reduce: inner_block do
      block ->
        {{:<-, _, [pattern, generator_input]}, filters} = generator

        generator_input
        |> expand_pattern_filter(pattern)
        |> expand_filters(pattern, filters)
        |> expand_generator(pattern, block)
    end
    |> expand_optional_uniq(options)
    |> expand_optional_into(options)
  end

  ###
  ### Private functions
  ###

  defp expand_bottom_generator(input, pattern, block) do
    quote do
      unquote(input)
      |> Stream.map(fn unquote(pattern) -> unquote(block) end)
    end
  end

  defp expand_generator(input, pattern, block) do
    quote do
      unquote(input)
      |> Stream.flat_map(fn unquote(pattern) -> unquote(block) end)
    end
  end

  defp expand_filters(input, _pattern, []) do
    input
  end

  defp expand_filters(input, pattern, [filter | more_filters]) do
    filter_body =
      for f <- more_filters, reduce: filter do
        other_filters -> quote do: unquote(other_filters) && unquote(f)
      end

    quote do
      unquote(input)
      |> Stream.filter(fn unquote(pattern) -> unquote(filter_body) end)
    end
  end

  defp expand_pattern_filter(input, pattern) do
    quote generated: true do
      unquote(input)
      |> Stream.filter(&match?(unquote(pattern), &1))
    end
  end

  defp expand_resource(resource, block, after_block) do
    start_fun = quote do: fn -> unquote(resource) end
    next_fun = {:fn, [], block}
    after_fun = {:fn, [], after_block}

    quote do
      Stream.resource(unquote(start_fun), unquote(next_fun), unquote(after_fun))
    end
  end

  defp expand_transform(input, pattern, init, block, nil) do
    reducer_fun = {:fn, [], inject_clause_argument(pattern, block)}

    quote generated: true do
      unquote(input)
      |> Stream.transform(unquote(init), unquote(reducer_fun))
    end
  end

  defp expand_transform(input, pattern, init, block, after_block) do
    start_fun = quote do: fn -> unquote(init) end
    reducer_fun = {:fn, [], inject_clause_argument(pattern, block)}
    after_fun = {:fn, [], after_block}

    quote generated: true do
      unquote(input)
      |> Stream.transform(unquote(start_fun), unquote(reducer_fun), unquote(after_fun))
    end
  end

  defp expand_scan(input, pattern, init, block) do
    scanner_fun = {:fn, [], inject_clause_argument(pattern, block)}

    quote generated: true do
      unquote(input)
      |> Stream.scan(unquote(init), unquote(scanner_fun))
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

  defp expand_optional_into(stream, options) do
    if collectable = Keyword.get(options, :into) do
      quote do
        unquote(stream)
        |> Stream.into(unquote(collectable))
      end
    else
      stream
    end
  end

  defp inject_clause_argument(pattern, block) do
    for {:->, meta, [[arg], body]} <- block do
      arglist =
        case arg do
          {:when, meta, [var, condition]} -> [{:when, meta, [pattern, var, condition]}]
          arg -> [pattern, arg]
        end

      {:->, meta, [arglist, body]}
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
