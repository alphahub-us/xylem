defmodule Xylem.LedgerTest do
  use ExUnit.Case, async: true

  alias Xylem.Ledger

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

  describe "process_event/1" do
    test "handles long position" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 1, price: 1},
        %{base_update | type: :fill, qty: 1, price: 1.1},
        %{base_update | side: :sell},
        %{base_update | side: :sell, type: :partial, qty: 1, price: 2},
        %{base_update | side: :sell, type: :fill, qty: 1, price: 2},
      ]

      Enum.each(updates, &Ledger.process_event/1)

      {:ok, {_, positions}} = Ledger.last_position("a", "A")
      assert {Decimal.new("1.9"), 0} == Ledger.accumulate(positions)
    end

    test "handles short position" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        %{base_update | side: :sell},
        %{base_update | side: :sell, type: :partial, qty: 1, price: 2},
        %{base_update | side: :sell, type: :fill, qty: 1, price: 2.1},
        base_update,
        %{base_update | type: :partial, qty: 1, price: 1.5},
        %{base_update | type: :fill, qty: 1, price: 1},
      ]

      Enum.each(updates, &Ledger.process_event/1)

      {:ok, {_, positions}} = Ledger.last_position("a", "A")
      assert {Decimal.new("1.6"), 0} == Ledger.accumulate(positions)
    end

    test "deletes new positions without any fills on cancel" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :cancel}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert {:error, :no_position} = Ledger.last_position("a", "A")
    end

    test "does not delete open positions on cancel" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 1, price: 1},
        %{base_update | type: :fill, qty: 1, price: 1.1},
      ]

      Enum.each(updates, &Ledger.process_event/1)
      {:ok, {_,positions}} = Ledger.last_position("a", "A")

      cancellation = [
        %{base_update | side: :sell},
        %{base_update | side: :sell, type: :cancel}
      ]

      Enum.each(cancellation, &Ledger.process_event/1)

      assert {:ok, {_, ^positions}} = Ledger.last_position("a", "A")
    end

    test "isn't caught up by random other events" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      external_update = %{base_update | id: "other-id"}
      updates = [
        %{base_update | side: :sell},
        %{base_update | side: :sell, type: :partial, qty: 1, price: 2},
        external_update,
        %{base_update | side: :sell, type: :fill, qty: 1, price: 2.1},
        %{external_update | type: :partial, qty: 1, price: 1},
        %{external_update | type: :fill, qty: 1, price: 1},
        %{external_update | side: :sell},
        base_update,
        %{base_update | type: :partial, qty: 1, price: 1.5},
        %{external_update | side: :sell, type: :partial, qty: 1, price: 1},
        %{external_update | side: :sell, type: :fill, qty: 1, price: 1},
        %{base_update | type: :fill, qty: 1, price: 1},
      ]

      Enum.each(updates, &Ledger.process_event/1)

      {:ok, {_, positions}} = Ledger.last_position("a", "A")
      assert {Decimal.new("1.6"), 0} == Ledger.accumulate(positions)
    end

    test "handles multiple positions for the same symbol" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a-1"}
      second_update = %{base_update | id: "xylem-a-2"}
      updates = [
        %{base_update | side: :sell},
        %{base_update | side: :sell, type: :partial, qty: 1, price: 2},
        %{base_update | side: :sell, type: :fill, qty: 1, price: 2.1},
        base_update,
        %{base_update | type: :partial, qty: 1, price: 1.5},
        %{base_update | type: :fill, qty: 1, price: 1},
        second_update,
        %{second_update | type: :partial, qty: 1, price: 1},
        %{second_update | type: :fill, qty: 1, price: 1.1},
        %{second_update | side: :sell},
        %{second_update | side: :sell, type: :partial, qty: 1, price: 2},
        %{second_update | side: :sell, type: :fill, qty: 1, price: 2.1},
      ]

      Enum.each(updates, &Ledger.process_event/1)

      {:ok, {_, positions}} = Ledger.last_position("a", "A")
      assert {Decimal.new("2.0"), 0} == Ledger.accumulate(positions)
    end
  end

  describe "prepare_orders" do
    test "prepares a new order from a long close signal, expected existing shares" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :sell, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 1}]
      updates = [
        base_update,
        %{ base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order] = Ledger.prepare_orders(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a long close signal, fewer shares than expected" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :sell, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order] = Ledger.prepare_orders(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a long close signal, fewer shares than expected with need to break up order" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :sell, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 2, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order, order] = Ledger.prepare_orders(signals, "a", positions)
                              |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a long close signal, more shares than expected" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :sell, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 2}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order] = Ledger.prepare_orders(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a short close signal, same shares as expected" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :buy, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order] = Ledger.prepare_orders(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares new orders for a short close signal, fewer shares than expected" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :buy, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order] = Ledger.prepare_orders(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares new orders for a short close signal, fewer shares than expected with need to break up order " do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :buy, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 2, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order, order] = Ledger.prepare_orders(signals, "a", positions)
                              |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares new orders for a short close signal, more shares than expected" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: Decimal.new("1.5"), side: :buy, weight: Decimal.new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -2}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Ledger.process_event/1)

      assert [order] = Ledger.prepare_orders(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares a new order from an open signal" do
      Ledger.set_funds("a", 1.5)
      signals = [
        %{type: :open, symbol: "A", price: Decimal.new("1.5"), side: :buy, weight: Decimal.new("1.0")}
      ]

      assert [order] = Ledger.prepare_orders(signals, "a", [])
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: Decimal.new("1.5"), symbol: "A", side: :buy, qty: 1}
    end
  end
end
