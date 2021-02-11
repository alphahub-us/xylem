defmodule Xylem.OrdersTest do
  use ExUnit.Case

  alias Xylem.{Orders, Ledger}
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

      Enum.each(updates, &Orders.process_event/1)

      assert {:ok, {new("1.9"), 0}} == Ledger.get_position("a", "A")
      assert {:error, :no_open_position} == Ledger.get_open_position("a", "A")
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

      Enum.each(updates, &Orders.process_event/1)

      assert {:ok, {new("1.6"), 0}} == Ledger.get_position("a", "A")
      assert {:error, :no_open_position} == Ledger.get_open_position("a", "A")
    end

    test "handles multiple positions" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 1, price: 1},
        %{base_update | type: :fill, qty: 1, price: 1.1},
        %{base_update | symbol: "B"},
        %{base_update | symbol: "B", type: :partial, qty: 1, price: 2},
        %{base_update | symbol: "B", type: :fill, qty: 1, price: 2},
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert {:ok, {a_positions, 2}} = Ledger.get_open_position("a", "A")
      assert {:ok, {b_positions, 2}} = Ledger.get_open_position("a", "B")
      assert a_positions != b_positions
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

      Enum.each(updates, &Orders.process_event/1)

      assert {:ok, {new("1.6"), 0}} == Ledger.get_position("a", "A")
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

      Enum.each(updates, &Orders.process_event/1)

      assert {:ok, {new("2.0"), 0}} == Ledger.get_position("a", "A")
    end
  end

  describe "prepare_orders" do
    test "prepares a new order from a long close signal, expected existing shares" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :sell, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 1}]
      updates = [
        base_update,
        %{ base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order] = Orders.prepare(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a long close signal, fewer shares than expected" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :sell, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order] = Orders.prepare(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a long close signal, fewer shares than expected with need to break up order" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :sell, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 2, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order, order] = Orders.prepare(signals, "a", positions)
                              |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a long close signal, more shares than expected" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :sell, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 2}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order] = Orders.prepare(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :sell, qty: 1}
    end

    test "prepares new orders for a short close signal, same shares as expected" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :buy, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order] = Orders.prepare(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares new orders for a short close signal, fewer shares than expected" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :buy, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: 1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order] = Orders.prepare(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares new orders for a short close signal, fewer shares than expected with need to break up order " do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :buy, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -1}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 2, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order, order] = Orders.prepare(signals, "a", positions)
                              |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares new orders for a short close signal, more shares than expected" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :buy, weight: new("1.0")}
      ]
      positions = [%{symbol: "A", qty: -2}]
      updates = [
        base_update,
        %{base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [order] = Orders.prepare(signals, "a", positions)
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "prepares a new order from an open signal" do
      Ledger.set_funds("a", 1.5)
      signals = [
        %{type: :open, symbol: "A", price: new("1.5"), side: :buy, weight: new("1.0")}
      ]

      assert [order] = Orders.prepare(signals, "a", [])
                       |> Enum.map(&Map.take(&1, [:price, :symbol, :side, :qty]))
      assert order == %{price: new("1.5"), symbol: "A", side: :buy, qty: 1}
    end

    test "does not prepare any close orders if there's no open account position" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      signals = [
        %{type: :close, symbol: "A", price: new("1.5"), side: :sell, weight: new("1.0")}
      ]
      updates = [
        base_update,
        %{ base_update | type: :fill, qty: 1, price: 1}
      ]

      Enum.each(updates, &Orders.process_event/1)

      assert [] == Orders.prepare(signals, "a", [])
    end
  end

  describe "remaining_qty/1" do
    test "works with no current position" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      Orders.process_event(base_update)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :buy, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 5
    end
    test "works with partially-filled open long positions" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2}
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :buy, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 3
    end
    test "works with partially-filled open short positions" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2}
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :sell, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 3
    end
    test "works with filled open long position, no close position" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2},
        %{base_update | type: :fill, qty: 3}
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :sell, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 5
    end
    test "works with filled open short position, no close position" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2},
        %{base_update | type: :fill, qty: 3}
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :buy, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 5
    end
    test "works with partially-filled close long positions" do
      base_update = %{type: :new, side: :buy, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2},
        %{base_update | type: :fill, qty: 3},
        %{base_update | side: :sell},
        %{base_update | side: :sell, type: :partial, qty: 2},
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :sell, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 3
    end
    test "works with partially-filled close short positions" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2},
        %{base_update | type: :fill, qty: 3},
        %{base_update | side: :buy},
        %{base_update | side: :buy, type: :partial, qty: 2},
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :buy, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 3
    end
    test "works with fully-filled position" do
      base_update = %{type: :new, side: :sell, qty: 0, price: 0, symbol: "A", id: "xylem-a"}
      updates = [
        base_update,
        %{base_update | type: :partial, qty: 2},
        %{base_update | type: :fill, qty: 3},
        %{base_update | side: :buy},
        %{base_update | side: :buy, type: :partial, qty: 2},
        %{base_update | side: :buy, type: :fill, qty: 3},
      ]
      Enum.each(updates, &Orders.process_event/1)

      order = %{id: "xylem-a", symbol: "A", qty: 5, side: :buy, price: new("1.0")}
      assert Orders.get_remaining_qty(order) == 0
    end
  end
end
