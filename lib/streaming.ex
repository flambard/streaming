defmodule Streaming do
  @moduledoc false

  alias Streaming.MacroUtils

  defmacro streaming(args, block) when is_list(args) do
    {generators_and_filters, options} = Enum.split_while(args, &(not option?(&1)))
    expand_streaming(generators_and_filters, options, block)
  end

  ###
  ### Aesthetics
  ###

  defmacro streaming(arg, block) do
    if Keyword.keyword?(arg) do
      expand_streaming([], arg, block)
    else
      expand_streaming([arg], [], block)
    end
  end

  defmacro streaming(arg1, arg2, block) do
    if Keyword.keyword?(arg2) do
      expand_streaming([arg1], arg2, block)
    else
      expand_streaming([arg1, arg2], [], block)
    end
  end

  defmacro streaming(arg1, arg2, arg3, block) do
    if Keyword.keyword?(arg3) do
      expand_streaming([arg1, arg2], arg3, block)
    else
      expand_streaming([arg1, arg2, arg3], [], block)
    end
  end

  defmacro streaming(arg1, arg2, arg3, arg4, block) do
    if Keyword.keyword?(arg4) do
      expand_streaming([arg1, arg2, arg3], arg4, block)
    else
      expand_streaming([arg1, arg2, arg3, arg4], [], block)
    end
  end

  ###
  ### Private functions
  ###

  defp expand_streaming(generators_and_filters, options, block) do
    {simple_options, special_options} = Keyword.split(options, [:uniq, :into])

    generators_and_filters
    |> expand_streaming_body(special_options, block)
    |> expand_optional_uniq(simple_options)
    |> expand_optional_into(simple_options)
  end

  defp expand_streaming_body(generators_and_filters, [{:unfold, init}], block) do
    [do: do_block] = block

    outer_generators = group_filters_with_generators(generators_and_filters)
    inner_block = expand_unfold(init, do_block)

    for {generator, filters} <- outer_generators, reduce: inner_block do
      block ->
        generator
        |> expand_generator(filters, block)
        |> expand_concat()
    end
  end

  defp expand_streaming_body(generators_and_filters, [{:resource, resource}], block) do
    [do: do_block, after: after_block] = block

    outer_generators = group_filters_with_generators(generators_and_filters)
    inner_block = expand_resource(resource, do_block, after_block)

    for {generator, filters} <- outer_generators, reduce: inner_block do
      block ->
        generator
        |> expand_generator(filters, block)
        |> expand_concat()
    end
  end

  defp expand_streaming_body(generators_and_filters, options, block) do
    {:ok, do_block} = Keyword.fetch(block, :do)

    [{inner_generator, filters} | outer_generators] =
      group_filters_with_generators(generators_and_filters)

    inner_block =
      case options do
        [transform: init] ->
          after_block = Keyword.get(do_block, :after)
          {pattern, input} = expand_feeding_generator(inner_generator, filters)
          expand_transform(input, pattern, init, do_block, after_block)

        [scan: init] ->
          {pattern, input} = expand_feeding_generator(inner_generator, filters)
          expand_scan(input, pattern, init, do_block)

        [] ->
          expand_generator(inner_generator, filters, do_block)
      end

    for {generator, filters} <- outer_generators, reduce: inner_block do
      block ->
        generator
        |> expand_generator(filters, block)
        |> expand_concat()
    end
  end

  defp expand_feeding_generator({:<<>>, _, _} = bitstring_generator, filters) do
    {binary_pattern, input} = MacroUtils.unarrow_bitstring_generator(bitstring_generator)
    vars = MacroUtils.vars_from_binary_pattern(binary_pattern)

    {vars, expand_bitstring_generator(input, binary_pattern, filters, vars)}
  end

  defp expand_feeding_generator({:<-, _, [pattern, input]}, filters) do
    filtered_input =
      input
      |> expand_pattern_filter(pattern)
      |> expand_filters(pattern, filters)

    {pattern, filtered_input}
  end

  defp expand_generator({:<<>>, _, _} = generator, filters, do_block) do
    {binary_pattern, input} = MacroUtils.unarrow_bitstring_generator(generator)
    expand_bitstring_generator(input, binary_pattern, filters, do_block)
  end

  defp expand_generator({:<-, _, [pattern, input]}, filters, do_block) do
    expand_mapping_generator(input, pattern, filters, do_block)
  end

  defp expand_mapping_generator(input, pattern, filters, block) do
    input
    |> expand_pattern_filter(pattern)
    |> expand_filters(pattern, filters)
    |> expand_map(pattern, block)
  end

  defp expand_bitstring_generator(input, pattern, filters, block) do
    {:<<>>, _, vars} = pattern
    rest = Macro.unique_var(:rest, __MODULE__)
    underscore_rest = Macro.unique_var(:_rest, __MODULE__)
    body = expand_bitstring_generator_body(filters, block)

    quote do
      Stream.resource(
        fn -> unquote(input) end,
        fn
          <<unquote_splicing(vars), unquote(rest)::binary>> -> {unquote(body), unquote(rest)}
          <<unquote(rest)::binary>> -> {:halt, unquote(rest)}
        end,
        fn <<unquote(underscore_rest)::binary>> -> :ok end
      )
    end
  end

  defp expand_bitstring_generator_body([], block) do
    [block]
  end

  defp expand_bitstring_generator_body(filters, block) do
    conditions = expand_conditions(filters)

    quote do
      if unquote(conditions) do
        [unquote(block)]
      else
        []
      end
    end
  end

  defp expand_filters(input, _pattern, []) do
    input
  end

  defp expand_filters(input, pattern, filters) do
    filter_body = expand_conditions(filters)

    quote do
      unquote(input)
      |> Stream.filter(fn unquote(pattern) -> unquote(filter_body) end)
    end
  end

  defp expand_conditions([filter | more_filters]) do
    for f <- more_filters, reduce: filter do
      other_filters -> quote do: unquote(other_filters) && unquote(f)
    end
  end

  defp expand_pattern_filter(input, pattern) do
    quote generated: true do
      unquote(input)
      |> Stream.filter(&match?(unquote(pattern), &1))
    end
  end

  defp expand_map(input, pattern, block) do
    quote do
      unquote(input)
      |> Stream.map(fn unquote(pattern) -> unquote(block) end)
    end
  end

  defp expand_unfold(init, block) do
    next_fun = {:fn, [], block}

    quote do
      Stream.unfold(unquote(init), unquote(next_fun))
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
    reducer_fun = {:fn, [], MacroUtils.inject_clause_argument(pattern, block)}

    quote generated: true do
      unquote(input)
      |> Stream.transform(unquote(init), unquote(reducer_fun))
    end
  end

  defp expand_transform(input, pattern, init, block, after_block) do
    start_fun = quote do: fn -> unquote(init) end
    reducer_fun = {:fn, [], MacroUtils.inject_clause_argument(pattern, block)}
    after_fun = {:fn, [], after_block}

    quote generated: true do
      unquote(input)
      |> Stream.transform(unquote(start_fun), unquote(reducer_fun), unquote(after_fun))
    end
  end

  defp expand_scan(input, pattern, init, block) do
    scanner_fun = {:fn, [], MacroUtils.inject_clause_argument(pattern, block)}

    quote generated: true do
      unquote(input)
      |> Stream.scan(unquote(init), unquote(scanner_fun))
    end
  end

  defp expand_concat(input) do
    quote do
      unquote(input)
      |> Stream.concat()
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

  defp group_filters_with_generators([{:<<>>, _, _} = bitstring_generator | rest], acc) do
    {filters, more} = Enum.split_while(rest, &(not generator?(&1)))
    group_filters_with_generators(more, [{bitstring_generator, filters} | acc])
  end

  defp generator?({:<<>>, _, fields}) do
    fields |> List.last() |> generator?()
  end

  defp generator?(arg) do
    match?({:<-, _, [_, _]}, arg)
  end

  defp option?(arg) do
    match?({_key, _value}, arg)
  end
end
