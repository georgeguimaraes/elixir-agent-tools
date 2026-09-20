defmodule Pretty do
  @moduledoc """
  JSON encoder with two-space indentation, matching `json.dumps(..., indent=2)`.

  Objects may be given as `{:obj, [{key, value}]}` to pin the emitted key order.
  Plain maps are emitted with their keys sorted so output stays deterministic.
  """

  def encode(value), do: enc(value, 0)

  defp enc(nil, _), do: "null"
  defp enc(true, _), do: "true"
  defp enc(false, _), do: "false"
  defp enc(v, _) when is_binary(v), do: JSON.encode!(v)
  defp enc(v, _) when is_atom(v), do: JSON.encode!(Atom.to_string(v))
  defp enc(v, _) when is_integer(v), do: Integer.to_string(v)
  defp enc(v, _) when is_float(v), do: float(v)
  defp enc({:obj, []}, _), do: "{}"

  defp enc({:obj, pairs}, indent) do
    body =
      Enum.map_join(pairs, ",\n", fn {k, v} ->
        pad(indent + 1) <> JSON.encode!(to_string(k)) <> ": " <> enc(v, indent + 1)
      end)

    "{\n" <> body <> "\n" <> pad(indent) <> "}"
  end

  defp enc([], _), do: "[]"

  defp enc(list, indent) when is_list(list) do
    body = Enum.map_join(list, ",\n", fn v -> pad(indent + 1) <> enc(v, indent + 1) end)
    "[\n" <> body <> "\n" <> pad(indent) <> "]"
  end

  defp enc(tuple, indent) when is_tuple(tuple), do: enc(Tuple.to_list(tuple), indent)

  defp enc(map, indent) when is_map(map) do
    enc({:obj, Enum.sort_by(map, fn {k, _} -> to_string(k) end)}, indent)
  end

  defp pad(indent), do: String.duplicate("  ", indent)

  defp float(v) do
    if v == Float.round(v) and abs(v) < 1.0e16 do
      :erlang.float_to_binary(v, decimals: 1)
    else
      to_string(v)
    end
  end
end
