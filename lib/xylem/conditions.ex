defmodule Xylem.Conditions do

  use GenServer

  @me __MODULE__

  alias Decimal, as: D

  # API

  def start_link(args), do: GenServer.start_link(@me, args, name: @me)

  def add(order, condition), do: call({:add, order, condition})

  def add(order, condition, wait) do
    cast({:add, order, condition, wait, self()})
  end

  def remove(order), do: call({:remove, order})

  def check_off(bot, condition_type), do: call({:check_off, bot, condition_type})

  def get(symbol), do: call({:get, symbol})

  defp call(args), do: GenServer.call(@me, args)
  defp cast(args) ,do: GenServer.cast(@me, args)

  # GenServer callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:add, order, condition}, _from, state) do
    {:reply, :ok, add_condition(state, order, condition)}
  end

  def handle_call({:remove, order}, _from, state) do
    {condition, state} = remove_condition(state, order)
    if is_reference(condition), do: Process.cancel_timer(condition)
    {:reply, condition, state}
  end

  def handle_call({:check_off, bot, condition_type}, _from, state) do
    {passing_conditions, state} = pop_passing_conditions(state, bot, condition_type)
    {:reply, passing_conditions, state}
  end

  def handle_call({:get, symbol}, _from, state) do
    {:reply, Map.get(state, symbol), state}
  end

  @impl true
  def handle_cast({:add, order, condition, wait, from}, state) do
    ref = Process.send_after(self(), {:add, order, condition, from}, wait)
    {:noreply, add_condition(state, order, ref)}
  end


  @impl true
  def handle_info({:add, order, condition, from}, state) do
    send(from, {:condition_added, order, condition})
    {:noreply, add_condition(state, order, condition)}
  end

  defp add_condition(state, %{id: id, symbol: symbol}, condition) do
    put_in(state, [Access.key(symbol, %{}), Access.key(id)], condition)
  end

  defp remove_condition(state, %{id: id, symbol: symbol}) do
    pop_in(state, [symbol, id])
  end

  defp pop_passing_conditions(state, bot, {:price, symbol, price}) do
    case Map.get(state, symbol) do
      nil ->
        {{:ok, []}, state}
      conditions ->
        {passing, failing} = Enum.split_with(conditions, &passes_check?(&1, bot, price))
        passing = Enum.map(passing, fn {id, {_, action}} -> {id, action} end)
        {{:ok, passing}, put_in(state, [symbol], Enum.into(failing, %{}))}
    end
  end

  defp pop_passing_conditions(state, _, _), do: {{:error, :invalid_condition}, state}

  defp passes_check?(condition, bot, price) do
    [& !is_reference(elem(&1, 1)), &belongs_to?(&1, bot), &passes_threshold?(&1, price)]
    |> Enum.all?(& &1.(condition))
  end

  defp belongs_to?({"xylem-" <> rest, _}, bot), do: bot == hd String.split(rest, "-")

  defp passes_threshold?({_id, {{:gt, threshold}, _}}, price), do: D.gt?(price, threshold)
  defp passes_threshold?({_id, {{:lt, threshold}, _}}, price), do: D.lt?(price, threshold)
end
