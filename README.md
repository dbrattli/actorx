# ActorX for Gleam

[![Package Version](https://img.shields.io/hexpm/v/actorx)](https://hex.pm/packages/actorx)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/actorx/)

ActorX - Reactive Extensions for Gleam using BEAM actors. A reactive programming library that composes BEAM actors for building asynchronous, event-driven applications.

This is a port of [FSharp.Control.AsyncRx](https://github.com/dbrattli/AsyncRx) to Gleam, targeting the Erlang/BEAM runtime.

## Installation

```sh
gleam add actorx@1
```

## Example

```gleam
import actorx
import actorx/types.{Observer}
import gleam/io
import gleam/int

pub fn main() {
  // Create an observable pipeline
  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> actorx.filter(fn(x) { x % 2 == 0 })  // Keep even numbers
    |> actorx.map(fn(x) { x * 10 })          // Multiply by 10
    |> actorx.take(3)                        // Take first 3

  // Create an observer
  let observer = Observer(
    on_next: fn(x) { io.println("Value: " <> int.to_string(x)) },
    on_error: fn(err) { io.println("Error: " <> err) },
    on_completed: fn() { io.println("Done!") },
  )

  // Subscribe
  let _disposable = actorx.subscribe(observable, observer)
  // Output:
  // Value: 20
  // Value: 40
  // Value: 60
  // Done!
}
```

## Builder Pattern with `use`

ActorX supports Gleam's `use` keyword for monadic composition, similar to F#'s computation expressions:

```gleam
import actorx
import actorx/builder.{bind, return}

pub fn example() {
  use x <- bind(actorx.single(10))
  use y <- bind(actorx.single(20))
  use z <- bind(actorx.from_list([1, 2, 3]))
  return(x + y + z)
}
// Emits: 31, 32, 33 then completes
```

## Core Concepts

### Observable

An `Observable(a)` represents a push-based stream of values of type `a`. Observables are lazy - they don't produce values until subscribed to.

### Observer

An `Observer(a)` receives notifications from an Observable:

- `on_next(a)` - Called for each value
- `on_error(String)` - Called on error (terminal)
- `on_completed()` - Called when complete (terminal)

The Rx contract guarantees: `OnNext* (OnError | OnCompleted)?`

### Disposable

A `Disposable` represents a subscription that can be cancelled. Call `dispose()` to unsubscribe and release resources.

## Available Operators

### Creation

| Operator | Description |
|----------|-------------|
| `single(value)` | Emit single value, then complete |
| `empty()` | Complete immediately |
| `never()` | Never emit, never complete |
| `fail(error)` | Error immediately |
| `from_list(items)` | Emit all items from list |
| `defer(factory)` | Create observable lazily on subscribe |

### Transform

| Operator | Description |
|----------|-------------|
| `map(source, fn)` | Transform each element |
| `flat_map(source, fn)` | Map to observables, merge results |
| `concat_map(source, fn)` | Map to observables, concatenate in order |

### Filter

| Operator | Description |
|----------|-------------|
| `filter(source, predicate)` | Keep elements matching predicate |
| `take(source, n)` | Take first N elements |
| `skip(source, n)` | Skip first N elements |
| `take_while(source, predicate)` | Take while predicate is true |
| `skip_while(source, predicate)` | Skip while predicate is true |
| `choose(source, fn)` | Filter + map via Option |
| `distinct_until_changed(source)` | Skip consecutive duplicates |
| `take_until(source, other)` | Take until other observable emits |
| `take_last(source, n)` | Emit last N elements on completion |

### Builder (for `use` syntax)

| Function | Description |
|----------|-------------|
| `bind(source, fn)` | FlatMap for `use` syntax |
| `return(value)` | Lift value into observable |
| `map_over(source, fn)` | Map for `use` syntax |
| `filter_with(source, fn)` | Filter for `use` syntax |
| `for_each(list, fn)` | Iterate list, concat results |

## Design

### Why Gleam + BEAM?

The original F# AsyncRx uses `MailboxProcessor` (actors) to:

1. Serialize notifications (no concurrent observer calls)
2. Enforce Rx grammar
3. Manage state safely

Gleam on BEAM is a natural fit because:

- BEAM has native lightweight processes (actors)
- OTP provides battle-tested actor primitives
- Millions of concurrent subscriptions are feasible
- Supervision trees for fault tolerance

### Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Observable │────▶│  Operator   │────▶│  Observer   │
│   (source)  │     │  (transform)│     │  (sink)     │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                    ┌──────┴──────┐
                    │ State Actor │
                    │ (for take,  │
                    │  skip, etc) │
                    └─────────────┘
```

Each stateful operator can use an actor to maintain state safely across async boundaries.

### Current Implementation

The current version uses Erlang's process dictionary for mutable state, which works correctly for **synchronous observables** (like `from_list`). This approach:

- Is simple and performant for sync sources
- Avoids actor overhead for simple cases
- Works within a single process context

### Safe Observer

The `safe_observer` module provides Rx grammar enforcement:

- Tracks "stopped" state
- Ignores events after terminal
- Calls disposal on terminal events

## Roadmap

### Phase 1: Core Operators (Current)

- [x] Basic types (Observable, Observer, Disposable, Notification)
- [x] Creation operators (single, empty, never, fail, from_list, defer)
- [x] Transform operators (map, flat_map, concat_map)
- [x] Filter operators (filter, take, skip, take_while, distinct_until_changed, etc.)
- [x] Safe observer with Rx grammar enforcement
- [x] Builder module with `use` keyword support
- [x] Test suite

### Phase 2: Actor-Based Async

- [ ] Full actor-based `safe_observer` using `gleam_otp`
- [ ] `interval` and `timer` operators
- [ ] `debounce` and `throttle` operators
- [ ] `delay` operator
- [ ] Proper async disposal

### Phase 3: Combining Operators

- [ ] `merge` - Merge multiple observables
- [ ] `combine_latest` - Combine latest values
- [ ] `with_latest_from` - Sample with latest
- [ ] `zip` - Pair elements by index

### Phase 4: Advanced Features

- [ ] `Subject` - Hot observable / multicast
- [ ] `share` / `publish` - Share subscriptions
- [ ] `retry` / `catch` - Error handling
- [ ] `scan` / `reduce` - Aggregation
- [ ] `group_by` - Grouped streams
- [ ] Back-pressure support

### Phase 5: Integration

- [ ] Process-based mapper (`map_process`)
- [ ] Supervision integration
- [ ] Telemetry/metrics

## Development

```sh
gleam build  # Build the project
gleam test   # Run the tests
```

## License

MIT

## Related Projects

- [FSharp.Control.AsyncRx](https://github.com/dbrattli/AsyncRx) - Original F# implementation
- [Reaxive](https://github.com/alfert/reaxive) - ReactiveX for Elixir
- [GenStage](https://github.com/elixir-lang/gen_stage) - Elixir's demand-driven streams
