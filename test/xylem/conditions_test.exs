defmodule Xylem.ConditionsTest do

  use ExUnit.Case, async: true

  alias Xylem.Conditions

  setup do
    {:ok, _} = Conditions.start_link(:ok)
    :ok
  end

  test "can add and evaluate conditions" do
    order = %{id: "xylem-a-1", symbol: "A"}
    condition = {{:gt, Decimal.new("101")}, :noop}
    Conditions.add(order, condition)
    assert {:ok, [{"xylem-a-1", :noop}]} = Conditions.check_off("a", {:price, "A", Decimal.new("101.10")})
    assert %{} == Conditions.get("A")
  end

  test "can remove conditions" do
    order = %{id: "xylem-a-1", symbol: "A"}
    condition = {{:gt, Decimal.new("101")}, :noop}
    Conditions.add(order, condition)
    assert ^condition = Conditions.remove(order)
    assert %{} == Conditions.get("A")
  end

  test "can add conditions with a wait time" do
    order = %{id: "xylem-a-1", symbol: "A"}
    condition = {{:gt, Decimal.new("101")}, :noop}
    condition_type = {:price, "A", Decimal.new("101.10")}
    :ok = Conditions.add(order, condition, 50)
    assert {:ok, []} = Conditions.check_off("a", condition_type)
    assert_receive {:condition_added, ^order, ^condition}, 100
    assert {:ok, [{"xylem-a-1", :noop}]} = Conditions.check_off("a", condition_type)
    assert %{} == Conditions.get("A")
  end

  test "can remove conditions with a wait time before the wait time expires" do
    order = %{id: "xylem-a-1", symbol: "A"}
    condition = {{:gt, Decimal.new("101")}, :noop}
    :ok = Conditions.add(order, condition, 1000)
    ref = Conditions.remove(order)
    assert is_reference(ref)
    assert %{} == Conditions.get("A")
  end

  test "checks don't return conditions that apply to different bots or symbols" do
    orders = [
      %{id: "xylem-a-1", symbol: "A"},
      %{id: "xylem-a-1", symbol: "B"},
      %{id: "xylem-b-1", symbol: "A"}
    ]
    condition = {{:gt, Decimal.new("101")}, :noop}
    Enum.each(orders, &Conditions.add(&1, condition))
    assert {:ok, [{"xylem-a-1", :noop}]} = Conditions.check_off("a", {:price, "A", Decimal.new("101.10")})
    assert map_size(Conditions.get("A")) == 1
    assert map_size(Conditions.get("B")) == 1
  end
end
