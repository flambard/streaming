defmodule Streaming.MacroUtils do
  @moduledoc false

  def inject_clause_argument(pattern, block) do
    for {:->, meta, [[arg], body]} <- block do
      arglist =
        case arg do
          {:when, meta, [var, condition]} -> [{:when, meta, [pattern, var, condition]}]
          arg -> [pattern, arg]
        end

      {:->, meta, [arglist, body]}
    end
  end

  def vars_from_binary_pattern(pattern) do
    pattern
    |> vars_from_binary_pattern(MapSet.new())
    |> MapSet.to_list()
  end

  def vars_from_binary_pattern(pattern, vars) do
    case pattern do
      {:<<>>, _meta, patterns} -> Enum.reduce(patterns, vars, &vars_from_binary_pattern(&1, &2))
      {:"::", _meta, [lhs, _type]} -> vars_from_binary_pattern(lhs, vars)
      {:when, _meta, [lhs, _condition]} -> vars_from_binary_pattern(lhs, vars)
      {_name, _meta, module} = var when is_atom(module) -> MapSet.put(vars, var)
      _other -> vars
    end
  end

  def unarrow_bitstring_generator({:<<>>, _, fields}) do
    {bindings, [{:<-, _, [last_binding, input]}]} = Enum.split(fields, -1)
    binary_pattern = quote do: <<unquote_splicing(bindings), unquote(last_binding)>>
    {binary_pattern, input}
  end
end
