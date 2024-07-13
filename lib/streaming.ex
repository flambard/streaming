defmodule Streaming do
  @moduledoc """
  Stream comprehensions allows you to quickly create streams with a tidy syntax.
  """
  alias Streaming.MacroUtils

  defmacro streaming(args, block) when is_list(args) do
    {generators_and_filters, options} = Enum.split_while(args, &(not option?(&1)))
    expand_streaming(generators_and_filters, options, block)
  end

  ###
  ### Aesthetics
  ###

  defmacro streaming(arg, block) do
    expand_streaming([arg], block)
  end

  defmacro streaming(arg1, arg2, block) do
    expand_streaming([arg1, arg2], block)
  end

  defmacro streaming(arg1, arg2, arg3, block) do
    expand_streaming([arg1, arg2, arg3], block)
  end

  defmacro streaming(arg1, arg2, arg3, arg4, block) do
    expand_streaming([arg1, arg2, arg3, arg4], block)
  end

  ###
  ### Private functions
  ###

  defp expand_streaming(args, block) do
    {generators, [options]} = Enum.split(args, -1)

    if Keyword.keyword?(options) do
      expand_streaming(generators, options, block)
    else
      expand_streaming(args, [], block)
    end
  end

  defp expand_streaming(generators_and_filters, options, block) do
    {simple_options, special_options} = Keyword.split(options, [:uniq, :into])

    {outer_generators, inner_block} =
      generators_and_filters
      |> group_filters_with_generators()
      |> expand_inner_body(special_options, block)

    outer_generators
    |> expand_outer_generators(inner_block)
    |> expand_optional_uniq(simple_options)
    |> expand_optional_into(simple_options)
  end

  defp expand_inner_body(generators, [unfold: init], do: do_block) do
    {generators, expand_unfold(init, do_block)}
  end

  defp expand_inner_body(generators, [resource: resource], do: do_block, after: after_block) do
    {generators, expand_resource(resource, do_block, after_block)}
  end

  defp expand_inner_body([{generator, filters} | generators], [transform: init], block) do
    {:ok, do_block} = Keyword.fetch(block, :do)
    after_block = Keyword.get(do_block, :after, nil)
    {pattern, input} = expand_feeding_generator(generator, filters)
    {generators, expand_transform(input, pattern, init, do_block, after_block)}
  end

  defp expand_inner_body([{generator, filters} | generators], [scan: init], do: do_block) do
    {pattern, input} = expand_feeding_generator(generator, filters)
    {generators, expand_scan(input, pattern, init, do_block)}
  end

  defp expand_inner_body([{generator, filters} | generators], [], do: do_block) do
    {generators, expand_generator(generator, filters, do_block)}
  end

  defp expand_feeding_generator({:<<>>, _, _} = bitstring_generator, filters) do
    {binary_pattern, input} = MacroUtils.unarrow_bitstring_generator(bitstring_generator)
    var_list = MacroUtils.vars_from_binary_pattern(binary_pattern)
    {var_list, expand_bitstring_generator(input, binary_pattern, filters, var_list)}
  end

  defp expand_feeding_generator({:<-, _, [pattern, input]}, filters) do
    {pattern, expand_filter(input, pattern, filters)}
  end

  defp expand_outer_generators(generators, inner_block) do
    for {generator, filters} <- generators, reduce: inner_block do
      block ->
        generator
        |> expand_generator(filters, block)
        |> expand_concat()
    end
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
    |> expand_filter(pattern, filters)
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

  defp expand_filter(input, pattern, filters) do
    filter_body = expand_conditions(filters)

    quote generated: true do
      unquote(input)
      |> Stream.filter(fn
        unquote(pattern) -> unquote(filter_body)
        _ -> false
      end)
    end
  end

  defp expand_conditions([]) do
    true
  end

  defp expand_conditions([filter | more_filters]) do
    for f <- more_filters, reduce: filter do
      other_filters -> quote do: unquote(other_filters) && unquote(f)
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
    match?({:<-, _, [_, _]}, List.last(fields))
  end

  defp generator?(arg) do
    match?({:<-, _, [_, _]}, arg)
  end

  defp option?(arg) do
    match?({_key, _value}, arg)
  end
end
