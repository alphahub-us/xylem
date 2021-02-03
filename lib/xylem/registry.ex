defmodule Xylem.Registry do
  @moduledoc """
  Registry for Xylem processes. It's a simple wrapper around Registry.
  """

  @me __MODULE__

  def child_spec(_), do: Registry.child_spec(keys: :unique, name: @me)

  @doc """
  Register a process via the Registry module.
  """
  @spec register(atom, module) :: {:ok, pid} | {:error, {:already_registered, pid}}
  def register(name, module), do: Registry.register(@me, name, module)

  @doc """
  Find the process with the given name via the Registry.
  """
  @spec lookup(atom) :: {pid, module} | nil
  def lookup(name) do
    Registry.lookup(@me, name)
    |> case do
      [match] -> match
      _ -> nil
    end
  end
end
