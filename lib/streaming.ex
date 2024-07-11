defmodule Streaming do
  @moduledoc false

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

    [{{:<-, _, [pattern, input]}, filters} | more_generators] =
      group_filters_with_generators(generators_and_filters)

    filtered_input =
      input
      |> expand_pattern_filter(pattern)
      |> expand_filters(pattern, filters)

    inner_block =
      cond do
        init = Keyword.get(options, :transform) ->
          after_block = Keyword.get(block, :after)

          filtered_input
          |> expand_transform(pattern, init, do_block, after_block)

        init = Keyword.get(options, :scan) ->
          filtered_input
          |> expand_scan(pattern, init, do_block)

        true ->
          filtered_input
          |> expand_mapping_generator(pattern, do_block)
      end

    for {{:<-, _, [pattern, input]}, filters} <- more_generators, reduce: inner_block do
      block ->
        input
        |> expand_pattern_filter(pattern)
        |> expand_filters(pattern, filters)
        |> expand_mapping_generator(pattern, block)
        |> expand_concat()
    end
    |> expand_optional_uniq(options)
    |> expand_optional_into(options)
  end

  defp expand_mapping_generator(input, pattern, block) do
    quote do
      unquote(input)
      |> Stream.map(fn unquote(pattern) -> unquote(block) end)
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
