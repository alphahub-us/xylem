# Xylem

**xylem** [ zi-lem ] *noun*
1. A vascular tissue in land plants primarily responsible for the distribution
   of water and minerals taken up by the roots; also the primary component of
   wood.

AlphaHub's automated trader. Responsible for handling new signals, turning them to orders, and distributing them where needed. Stores funds and position state for logging and order creation.

## Configuration

To get started, create a file in the `config` folder called `default.config.exs` and add your configuration to it. It should look like the following:

```elixir
import Config

config :xylem,
  ledger: [data_dir: "/path/to/cubdb/folder"],
  venues: %{
    "venue:my_venue" => {
      Xylem.Venue.Alpaca,
      credentials: %{id: "alpaca_api_key_id", secret: "alpaca_api_key_secret"},
      environment: "paper" # or "live"
    },
  },
  data: %{
    "polygon" => {
      Xylem.Data.Polygon,
      credentials: %{api_key: "my_api_key"},
    },
  },
  signals: %{
    "alphahub" => {
      Xylem.Signal.AlphaHub,
      credentials: %{email: "my@email.com", password: "my_password"},
      ids: [14, 16, 17] # or any IDs you want to subscribe to
    },
  },
  bots: %{
    "my_bot" => {
      Xylem.Bot.Production,
      venue: "venue:my_venue",
      data: "polygon",
      signal: {"alphahub", id: 17}, # Xylem.Signal.IEx
      log_path: "/path/to/csv/log.csv"
    },
  }
```

At this point, all you'll need to do is run it with `iex -S mix`.

## General Commands

### Check the funds balance of `my_bot`

```elixir
iex(1)> Xylem.Ledger.get_funds("my_bot")
{:ok, #Decimal<41035.39>}
```

### Update the funds balance of `my_bot`

```elixir
iex(1)> Xylem.Ledger.set_funds("my_bot", 10000.0) # This needs to be a float
:ok
```

### get position history for `my_bot`

```elixir
iex(1)> Xylem.Ledger.history("my_bot") # full history
[{}, {}, ...]
iex(1)> Xylem.Ledger.history("my_bot") |> Enum.take(2) # last two positions held
[{}, {}]
```

### get funds history for `my_bot`

```elixir
iex(1)> Xylem.Ledger.history("my_bot", :funds) # full history
[{}, {}, ...]
iex(1)> Xylem.Ledger.history("my_bot", :funds) |> Enum.take(2) # last two
[{}, {}]
```

### adding events manually

This is in case the websockets listener misses some venue updates

Venue events are maps which have the following keys:

- `id (string)`: a unique ID for the order in question. Should be generated with `Xylem.Orders.generate_id/1` if not given. This is how the Ledger determines which bot's history to update. You can see an example ID in the code snippet below.
- `price (Decimal)`: the price of the order. Can be `nil` for new market orders.
- `symbol (string)`: stock symbol that the order is acting on.
- `type (atom)`: the event type. Can be one of the following: `:new`, `:partial`, `:fill`, or `:cancel`.
- `side (atom)`: the trade side. Can be `:buy` or `:sell`.
- `qty (integer)`: the order quantity

```elixir
iex(1)> id = Xylem.Orders.generate_id("my_bot")
"xylem-my_bot-9d2c-fa5c86e29aec"
iex(2)> events = [
...(2)> %{id: id, price: Decimal.new("123.45"), symbol: "ABC", type: :new, side: :buy, qty: 2},
...(2)> %{id: id, price: Decimal.new("123.45"), symbol: "ABC", type: :partial, side: :buy, qty: 1},
...(2)> %{id: id, price: Decimal.new("123.45"), symbol: "ABC", type: :fill, side: :buy, qty: 1}
...(2)> ]
[
  %{
    id: "xylem-my_bot-9d2c-fa5c86e29aec",
    price: #Decimal<123.45>,
    qty: 2,
    side: :buy,
    symbol: "ABC",
    type: :new
  },
  %{
    id: "xylem-my_bot-9d2c-fa5c86e29aec",
    price: #Decimal<123.45>,
    qty: 1,
    side: :buy,
    symbol: "ABC",
    type: :partial
  },
  %{
    id: "xylem-my_bot-9d2c-fa5c86e29aec",
    price: #Decimal<123.45>,
    qty: 1,
    side: :buy,
    symbol: "ABC",
    type: :fill
  }
]
iex(3)> Enum.each(events, &Xylem.Orders.process_event/1)
:ok
```

### making manual orders

In case you want to manually create new orders, i.e. a venue drops the automated order for some reason and you need to re-submit it later.

Orders are maps which have the following keys:

- `id (string)`: a unique ID for the order. Should be generated with `Xylem.Orders.generate_id/1` if not given. You can see an example ID in the code snippet below.
- `price (Decimal)`: the price of the order. Can be `nil` market orders.
- `symbol (string)`: stock symbol that the order is acting on.
- `side (atom)`: the order side. Can be `:buy` or `:sell`.
- `qty (integer)`: the order quantity

```elixir
iex(1)> id = Xylem.Orders.generate_id("my_bot")
"xylem-my_bot-9d2c-fa5c86e29aec"
iex(2)> order = %{id: id, price: Decimal.new("123.45"), symbol: "ABC", side: :buy, qty: 2}
%{
  id: "xylem-my_bot-9d2c-fa5c86e29aec",
  price: #Decimal<123.45>,
  qty: 2,
  side: :buy,
  symbol: "ABC"
}
iex(3)> Xylem.Venue.submit_order("venue:my_venue", order, type: :limit) # can also be :market
{:ok, %{...}}
```

### cancelling orders

In case you want to cancel an existing order. You'll need the ID for the order you want to cancel.

```elixir
iex(1)> id = "xylem-my_bot-9d2c-fa5c86e29aec" # or whatever your order ID is
"xylem-my_bot-9d2c-fa5c86e29aec"
iex(2)> Xylem.Venue.cancel_order("venue:my_venue", %{id: id})
:ok
```

### checking a venue's open positions

```elixir
iex(1)> Xylem.Venue.get_positions("venue:my_venue")
[
  %{qty: -67, symbol: "PYPL"}, # negative numbers indicate short position
  %{qty: 150, symbol: "NTES"},
  %{qty: 34, symbol: "NFLX"}
]
```

## Venues

### Alpaca

Connects to an Alpaca account, then listens to order updates over websockets.

### IEx

Allows you to broadcast "order updates" from the IEx console. Mostly used for testing.

The order updates should take the same form as shown in the "adding events manually" section above

```elixir
iex(1)> id = Xylem.Orders.generate_id("my_bot")
"xylem-my_bot-9d2c-fa5c86e29aec"
iex(2)> event = %{id: id, price: Decimal.new("123.45"), symbol: "ABC", type: :new, side: :buy, qty: 2}
%{
  id: "xylem-my_bot-9d2c-fa5c86e29aec",
  price: #Decimal<123.45>,
  qty: 2,
  side: :buy,
  symbol: "ABC",
  type: :new
}
iex(3)> Xylem.Venue.update(event)
:ok
```

## Signals

### AlphaHub

Connects to AlphaHub's WebSockets server, then listens for new signals.

### IEx

Allows you to broadcast "signals" from the IEx console. Mostly used for testing.

If you want to simulate AlphaHub signals, its a list of maps containing the following fields:

- `type (atom)`: `:open` or `:close`
- `symbol (string)`
- `side (atom)`: `:buy` or `:sell`
- `weight (Decimal)`: how much of the provided funds to allocate towards a given signal
- `price (Decimal)`: desired order price

```elixir
iex(1)> signals = [%{type: :open, symbol: "ABC", side: :buy, weight: Decimal.new("1"), price: Decimal.new("123.45")}]
[
  %{
    type: :open,
    symbol: "ABC",
    side: :buy,
    weight: #Decimal<1>,
    price: #Decimal<123.45>
  }
]
iex(2)> Xylem.Signal.IEx.submit(signals)
:ok
```

## Data

### Polygon

Connects to Polygon, allowing you to subscribe to tickers and receive price updates via WebSockets.

### IEx

Allows you to broadcast "data" from the IEx console. Mostly used for testing.
