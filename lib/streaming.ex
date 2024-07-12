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

  defp expand_streaming([], [{:unfold, init} | options], do: do_block) do
    init
    |> expand_unfold(do_block)
    |> expand_optional_uniq(options)
    |> expand_optional_into(options)
  end

  defp expand_streaming([], [{:resource, resource} | options], do: do_block, after: after_block) do
    resource
    |> expand_resource(do_block, after_block)
    |> expand_optional_uniq(options)
    |> expand_optional_into(options)
  end

  defp expand_streaming(generators_and_filters, options, block) do
    {:ok, do_block} = Keyword.fetch(block, :do)

    [{inner_generator, filters} | more_generators] =
      group_filters_with_generators(generators_and_filters)

    inner_block =
      case inner_generator do
        {:<<>>, _, _} ->
          {binary_pattern, input} = MacroUtils.unarrow_bitstring_generator(inner_generator)

          cond do
            init = Keyword.get(options, :transform) ->
              vars = MacroUtils.vars_from_binary_pattern(binary_pattern)
              after_block = Keyword.get(do_block, :after)

              input
              |> expand_bitstring_generator(binary_pattern, filters, vars)
              |> expand_transform(vars, init, do_block, after_block)

            init = Keyword.get(options, :scan) ->
              vars = MacroUtils.vars_from_binary_pattern(binary_pattern)

              input
              |> expand_bitstring_generator(binary_pattern, filters, vars)
              |> expand_scan(vars, init, do_block)

            true ->
              expand_bitstring_generator(input, binary_pattern, filters, do_block)
          end

        {:<-, _, [pattern, input]} ->
          cond do
            init = Keyword.get(options, :transform) ->
              after_block = Keyword.get(do_block, :after)

              input
              |> expand_pattern_filter(pattern)
              |> expand_filters(pattern, filters)
              |> expand_transform(pattern, init, do_block, after_block)

            init = Keyword.get(options, :scan) ->
              input
              |> expand_pattern_filter(pattern)
              |> expand_filters(pattern, filters)
              |> expand_scan(pattern, init, do_block)

            true ->
              input
              |> expand_mapping_generator(pattern, filters, do_block)
          end
      end

    for {generator, filters} <- more_generators, reduce: inner_block do
      block ->
        case generator do
          {:<<>>, _, _} ->
            {binary_pattern, input} = MacroUtils.unarrow_bitstring_generator(generator)

            input
            |> expand_bitstring_generator(binary_pattern, filters, block)

          {:<-, _, [pattern, input]} ->
            input
            |> expand_mapping_generator(pattern, filters, block)
        end
        |> expand_concat()
    end
    |> expand_optional_uniq(options)
    |> expand_optional_into(options)
  end

  defp expand_mapping_generator(input, pattern, filters, block) do
    input
    |> expand_pattern_filter(pattern)
    |> expand_filters(pattern, filters)
    |> expand_map(pattern, block)
  end

  defp expand_bitstring_generator(input, pattern, filters, block) do
    {:<<>>, _, vars} = pattern
    rest = Macro.unique_var(:acc, __MODULE__)
    body = expand_bitstring_generator_body(filters, block)

    quote do
      Stream.resource(
        fn -> unquote(input) end,
        fn
          <<unquote_splicing(vars), unquote(rest)::binary>> -> {unquote(body), unquote(rest)}
          <<unquote(rest)::binary>> -> {:halt, unquote(rest)}
        end,
        fn <<_rest::binary>> -> :ok end
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
