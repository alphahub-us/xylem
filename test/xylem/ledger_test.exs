defmodule Xylem.LedgerTest do
  use ExUnit.Case, async: true

  alias Xylem.Ledger
  import Decimal, only: [new: 1]

  setup do
    tmp_dir = :os.cmd('mktemp -d') |> List.to_string() |> String.trim() |> String.to_charlist()

    on_exit(fn ->
      with {:ok, files} <- File.ls(tmp_dir) do
        for file <- files, do: File.rm(Path.join(tmp_dir, file))
      end

      :ok = File.rmdir(tmp_dir)
    end)

    {:ok, _} = Ledger.start_link(data_dir: tmp_dir)
    :ok
  end

  test "can set and get funds" do
    assert {:error, :no_funds} = Ledger.get_funds("a")
    :ok = Ledger.set_funds("a", 123.45)
    assert {:ok, new("123.45")} == Ledger.get_funds("a")
    assert {:error, :no_funds} = Ledger.get_funds("b")
  end

  describe "update/2, get_open_position/2, get_position/2" do
    test "can record updates and report net positions for longs" do
      [
        {%{type: :new, side: :buy, symbol: "A"}, {:ok, {new(0), 0}}},
        {%{type: :cancel, side: :buy, symbol: "A"}, {:error, :no_open_position}, {:error, :no_position}},
        {%{type: :new, side: :buy, symbol: "A"}, {:ok, {new(0), 0}}},
        {%{type: :partial, price: 1, qty: 1, side: :buy, symbol: "A"}, {:ok, {new(-1), 1}}},
        {%{type: :fill, price: 1, qty: 1, side: :buy, symbol: "A"}, {:ok, {new(-2), 2}}},
        {%{type: :new, side: :sell, symbol: "A"}, {:ok, {new(-2), 2}}},
        {%{type: :cancel, side: :sell, symbol: "A"}, {:ok, {new(-2), 2}}},
        {%{type: :new, side: :sell, symbol: "A"}, {:ok, {new(-2), 2}}},
        {%{type: :partial, price: 2, qty: 1, side: :sell, symbol: "A"}, {:ok, {new(0), 1}}},
        {%{type: :fill, price: 2, qty: 1, side: :sell, symbol: "A"}, {:error, :no_open_position}, {:ok, {new(2), 0}}},
      ]
      |> Enum.each(fn
        {update, expected} ->
          Ledger.update("a", update)
          assert Ledger.get_open_position("a", "A") == expected
          assert Ledger.get_position("a", "A") == expected
        {update, expected_open, expected} ->
          Ledger.update("a", update)
          assert Ledger.get_open_position("a", "A") == expected_open
          assert Ledger.get_position("a", "A") == expected
      end)
    end
    test "can record updates and report net positions for shorts" do
      [
        {%{type: :new, side: :sell, symbol: "A"}, {:ok, {new(0), 0}}},
        {%{type: :cancel, side: :sell, symbol: "A"}, {:error, :no_open_position}, {:error, :no_position}},
        {%{type: :new, side: :sell, symbol: "A"}, {:ok, {new(0), 0}}},
        {%{type: :partial, price: 1, qty: 1, side: :sell, symbol: "A"}, {:ok, {new(1), -1}}},
        {%{type: :fill, price: 1, qty: 1, side: :sell, symbol: "A"}, {:ok, {new(2), -2}}},
        {%{type: :new, side: :buy, symbol: "A"}, {:ok, {new(2), -2}}},
        {%{type: :cancel, side: :buy, symbol: "A"}, {:ok, {new(2), -2}}},
        {%{type: :new, side: :buy, symbol: "A"}, {:ok, {new(2), -2}}},
        {%{type: :partial, price: 2, qty: 1, side: :buy, symbol: "A"}, {:ok, {new(0), -1}}},
        {%{type: :fill, price: 2, qty: 1, side: :buy, symbol: "A"}, {:error, :no_open_position}, {:ok, {new(-2), 0}}},
      ]
      |> Enum.each(fn
        {update, expected} ->
          Ledger.update("a", update)
          assert Ledger.get_open_position("a", "A") == expected
          assert Ledger.get_position("a", "A") == expected
        {update, expected_open, expected} ->
          Ledger.update("a", update)
          assert Ledger.get_open_position("a", "A") == expected_open
          assert Ledger.get_position("a", "A") == expected
      end)
    end
  end
end
