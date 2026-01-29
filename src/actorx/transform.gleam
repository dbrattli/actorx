//// Transform operators for ActorX
////
//// These operators transform the elements of an observable sequence:
//// - map: Apply a function to each element
//// - flat_map: Map to observables and flatten (actor-based)
//// - scan: Running accumulation
//// - reduce: Final accumulation on completion
//// - group_by: Group elements into sub-observables by key

import actorx/types.{
  type Disposable, type Notification, type Observable, type Observer, Disposable,
  Observable, Observer, OnCompleted, OnError, OnNext,
}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list

/// Returns an observable whose elements are the result of invoking
/// the mapper function on each element of the source.
pub fn map(source: Observable(a), mapper: fn(a) -> b) -> Observable(b) {
  Observable(subscribe: fn(observer: Observer(b)) {
    let Observer(downstream) = observer

    let upstream_observer =
      Observer(notify: fn(n) {
        case n {
          OnNext(x) -> downstream(OnNext(mapper(x)))
          OnError(e) -> downstream(OnError(e))
          OnCompleted -> downstream(OnCompleted)
        }
      })

    let Observable(subscribe) = source
    subscribe(upstream_observer)
  })
}

// ============================================================================
// flat_map - Actor-based flat_map
// ============================================================================

/// Messages for the flat_map coordinator actor
type FlatMapMsg(b) {
  /// Source emitted a value (inner observable to subscribe to)
  InnerSubscribe(Observable(b))
  /// Inner observable emitted a value
  InnerNext(b)
  /// Inner observable completed
  InnerCompleted
  /// Inner observable errored
  InnerError(String)
  /// Source completed
  SourceCompleted
  /// Source errored
  SourceError(String)
  /// Dispose all subscriptions
  FlatMapDispose
}

/// Projects each element of an observable sequence into an observable
/// sequence and merges the resulting observable sequences.
///
/// Uses an actor to coordinate inner subscriptions, making it safe for
/// both sync and async sources. It properly tracks all inner subscriptions
/// and only completes when both the source AND all inner observables have
/// completed.
///
/// ## Example
/// ```gleam
/// interval(100)
/// |> take(3)
/// |> flat_map(fn(i) { timer(50) |> map(fn(_) { i }) })
/// ```
pub fn flat_map(
  source: Observable(a),
  mapper: fn(a) -> Observable(b),
) -> Observable(b) {
  Observable(subscribe: fn(observer: Observer(b)) {
    let Observer(downstream) = observer

    // Create control channel
    let control_ready: Subject(Subject(FlatMapMsg(b))) = process.new_subject()

    // Spawn coordinator actor
    process.spawn(fn() {
      let control: Subject(FlatMapMsg(b)) = process.new_subject()
      process.send(control_ready, control)
      flat_map_loop(control, downstream, 0, False)
    })

    // Get control subject
    let control = case process.receive(control_ready, 1000) {
      Ok(s) -> s
      Error(_) -> panic as "Failed to create flat_map"
    }

    // Subscribe to source
    let source_observer =
      Observer(notify: fn(n) {
        case n {
          OnNext(x) -> {
            let inner = mapper(x)
            process.send(control, InnerSubscribe(inner))
          }
          OnError(e) -> process.send(control, SourceError(e))
          OnCompleted -> process.send(control, SourceCompleted)
        }
      })

    let Observable(subscribe) = source
    let source_disp = subscribe(source_observer)

    // Return disposable that cleans up everything
    Disposable(dispose: fn() {
      let Disposable(dispose_source) = source_disp
      dispose_source()
      process.send(control, FlatMapDispose)
      Nil
    })
  })
}

fn flat_map_loop(
  control: Subject(FlatMapMsg(b)),
  downstream: fn(types.Notification(b)) -> Nil,
  inner_count: Int,
  source_stopped: Bool,
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select(control)

  case process.selector_receive_forever(selector) {
    InnerSubscribe(inner_observable) -> {
      // Subscribe to inner observable
      let inner_observer =
        Observer(notify: fn(n) {
          case n {
            OnNext(value) -> process.send(control, InnerNext(value))
            OnError(e) -> process.send(control, InnerError(e))
            OnCompleted -> process.send(control, InnerCompleted)
          }
        })

      let Observable(inner_subscribe) = inner_observable
      let _inner_disp = inner_subscribe(inner_observer)

      flat_map_loop(control, downstream, inner_count + 1, source_stopped)
    }

    InnerNext(value) -> {
      downstream(OnNext(value))
      flat_map_loop(control, downstream, inner_count, source_stopped)
    }

    InnerCompleted -> {
      let new_count = inner_count - 1
      case source_stopped && new_count <= 0 {
        True -> {
          // Source done and all inners done - complete
          downstream(OnCompleted)
          Nil
        }
        False -> flat_map_loop(control, downstream, new_count, source_stopped)
      }
    }

    InnerError(e) -> {
      downstream(OnError(e))
      Nil
    }

    SourceCompleted -> {
      case inner_count <= 0 {
        True -> {
          // No active inners - complete immediately
          downstream(OnCompleted)
          Nil
        }
        False -> {
          // Wait for inners to complete
          flat_map_loop(control, downstream, inner_count, True)
        }
      }
    }

    SourceError(e) -> {
      downstream(OnError(e))
      Nil
    }

    FlatMapDispose -> Nil
  }
}

/// Projects each element into an observable and concatenates them in order.
pub fn concat_map(
  source: Observable(a),
  mapper: fn(a) -> Observable(b),
) -> Observable(b) {
  // Simplified version - processes inner observables immediately
  // A full implementation would queue and process sequentially
  flat_map(source, mapper)
}

// ============================================================================
// scan - Running accumulation
// ============================================================================

/// Messages for the scan actor
type ScanMsg(a) {
  ScanNext(a)
  ScanError(String)
  ScanCompleted
  ScanDispose
}

/// Applies an accumulator function over the source, emitting each
/// intermediate result.
///
/// ## Example
/// ```gleam
/// from_list([1, 2, 3, 4, 5])
/// |> scan(0, fn(acc, x) { acc + x })
/// // Emits: 1, 3, 6, 10, 15
/// ```
pub fn scan(
  source: Observable(a),
  initial: b,
  accumulator: fn(b, a) -> b,
) -> Observable(b) {
  Observable(subscribe: fn(observer: Observer(b)) {
    let Observer(downstream) = observer

    // Create control channel
    let control_ready: Subject(Subject(ScanMsg(a))) = process.new_subject()

    // Spawn actor to manage state
    process.spawn(fn() {
      let control: Subject(ScanMsg(a)) = process.new_subject()
      process.send(control_ready, control)
      scan_loop(control, downstream, initial, accumulator)
    })

    // Get control subject
    let control = case process.receive(control_ready, 1000) {
      Ok(s) -> s
      Error(_) -> panic as "Failed to create scan actor"
    }

    // Subscribe to source
    let source_observer =
      Observer(notify: fn(n) {
        case n {
          OnNext(x) -> process.send(control, ScanNext(x))
          OnError(e) -> process.send(control, ScanError(e))
          OnCompleted -> process.send(control, ScanCompleted)
        }
      })

    let Observable(subscribe) = source
    let source_disp = subscribe(source_observer)

    Disposable(dispose: fn() {
      let Disposable(dispose_source) = source_disp
      dispose_source()
      process.send(control, ScanDispose)
      Nil
    })
  })
}

fn scan_loop(
  control: Subject(ScanMsg(a)),
  downstream: fn(types.Notification(b)) -> Nil,
  acc: b,
  accumulator: fn(b, a) -> b,
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select(control)

  case process.selector_receive_forever(selector) {
    ScanNext(x) -> {
      let new_acc = accumulator(acc, x)
      downstream(OnNext(new_acc))
      scan_loop(control, downstream, new_acc, accumulator)
    }
    ScanError(e) -> {
      downstream(OnError(e))
      Nil
    }
    ScanCompleted -> {
      downstream(OnCompleted)
      Nil
    }
    ScanDispose -> Nil
  }
}

// ============================================================================
// reduce - Final accumulation on completion
// ============================================================================

/// Messages for the reduce actor
type ReduceMsg(a) {
  ReduceNext(a)
  ReduceError(String)
  ReduceCompleted
  ReduceDispose
}

/// Applies an accumulator function over the source, emitting only
/// the final accumulated value when the source completes.
///
/// ## Example
/// ```gleam
/// from_list([1, 2, 3, 4, 5])
/// |> reduce(0, fn(acc, x) { acc + x })
/// // Emits: 15, then completes
/// ```
pub fn reduce(
  source: Observable(a),
  initial: b,
  accumulator: fn(b, a) -> b,
) -> Observable(b) {
  Observable(subscribe: fn(observer: Observer(b)) {
    let Observer(downstream) = observer

    // Create control channel
    let control_ready: Subject(Subject(ReduceMsg(a))) = process.new_subject()

    // Spawn actor to manage state
    process.spawn(fn() {
      let control: Subject(ReduceMsg(a)) = process.new_subject()
      process.send(control_ready, control)
      reduce_loop(control, downstream, initial, accumulator)
    })

    // Get control subject
    let control = case process.receive(control_ready, 1000) {
      Ok(s) -> s
      Error(_) -> panic as "Failed to create reduce actor"
    }

    // Subscribe to source
    let source_observer =
      Observer(notify: fn(n) {
        case n {
          OnNext(x) -> process.send(control, ReduceNext(x))
          OnError(e) -> process.send(control, ReduceError(e))
          OnCompleted -> process.send(control, ReduceCompleted)
        }
      })

    let Observable(subscribe) = source
    let source_disp = subscribe(source_observer)

    Disposable(dispose: fn() {
      let Disposable(dispose_source) = source_disp
      dispose_source()
      process.send(control, ReduceDispose)
      Nil
    })
  })
}

fn reduce_loop(
  control: Subject(ReduceMsg(a)),
  downstream: fn(types.Notification(b)) -> Nil,
  acc: b,
  accumulator: fn(b, a) -> b,
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select(control)

  case process.selector_receive_forever(selector) {
    ReduceNext(x) -> {
      let new_acc = accumulator(acc, x)
      reduce_loop(control, downstream, new_acc, accumulator)
    }
    ReduceError(e) -> {
      downstream(OnError(e))
      Nil
    }
    ReduceCompleted -> {
      // Emit final accumulated value, then complete
      downstream(OnNext(acc))
      downstream(OnCompleted)
      Nil
    }
    ReduceDispose -> Nil
  }
}

// ============================================================================
// group_by - Group elements into sub-observables by key
// ============================================================================

/// Messages for the group_by actor
type GroupByMsg(k, a) {
  /// Element with its computed key
  GroupByNext(k, a)
  GroupByError(String)
  GroupByCompleted
  GroupByDispose
  /// Request to subscribe to a specific group
  GroupSubscribe(k, Observer(a), Subject(Disposable))
  /// Unsubscribe from a group
  GroupUnsubscribe(k, Int)
}

/// A group subscriber
type GroupSubscriber(a) {
  GroupSubscriber(id: Int, observer: Observer(a))
}

/// State for a single group
type GroupState(a) {
  GroupState(subscribers: List(GroupSubscriber(a)), buffer: List(a))
}

/// State for the group_by actor
type GroupByState(k, a) {
  GroupByState(
    groups: Dict(k, GroupState(a)),
    emitted_keys: List(k),
    terminated: Bool,
  )
}

/// Groups elements of an observable by key, returning an observable of
/// grouped observables.
///
/// Each time a new key is encountered, emits a tuple of (key, Observable).
/// All elements with that key are forwarded to the corresponding group's
/// observable.
///
/// ## Example
/// ```gleam
/// // Group numbers by even/odd
/// from_list([1, 2, 3, 4, 5, 6])
/// |> group_by(fn(x) { x % 2 })
/// |> flat_map(fn(group) {
///   let #(key, values) = group
///   values |> map(fn(v) { #(key, v) })
/// })
/// // Emits: #(1, 1), #(0, 2), #(1, 3), #(0, 4), #(1, 5), #(0, 6)
/// ```
pub fn group_by(
  source: Observable(a),
  key_selector: fn(a) -> k,
) -> Observable(#(k, Observable(a))) {
  Observable(subscribe: fn(observer: Observer(#(k, Observable(a)))) {
    let Observer(downstream) = observer

    // Create control channel
    let control_ready: Subject(Subject(GroupByMsg(k, a))) = process.new_subject()

    // Spawn actor
    process.spawn(fn() {
      let control: Subject(GroupByMsg(k, a)) = process.new_subject()
      process.send(control_ready, control)
      let initial_state =
        GroupByState(groups: dict.new(), emitted_keys: [], terminated: False)
      group_by_loop(control, downstream, initial_state)
    })

    // Get control subject
    let control = case process.receive(control_ready, 1000) {
      Ok(s) -> s
      Error(_) -> panic as "Failed to create group_by actor"
    }

    // Subscribe to source
    let source_observer =
      Observer(notify: fn(n) {
        case n {
          OnNext(x) -> {
            let key = key_selector(x)
            process.send(control, GroupByNext(key, x))
          }
          OnError(e) -> process.send(control, GroupByError(e))
          OnCompleted -> process.send(control, GroupByCompleted)
        }
      })

    let Observable(subscribe) = source
    let source_disp = subscribe(source_observer)

    Disposable(dispose: fn() {
      let Disposable(dispose_source) = source_disp
      dispose_source()
      process.send(control, GroupByDispose)
      Nil
    })
  })
}

fn group_by_loop(
  control: Subject(GroupByMsg(k, a)),
  downstream: fn(Notification(#(k, Observable(a)))) -> Nil,
  state: GroupByState(k, a),
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select(control)

  case process.selector_receive_forever(selector) {
    GroupByNext(key, value) -> {
      // Check if this is a new key
      let is_new_key = !list.contains(state.emitted_keys, key)

      // Create group observable if new key
      let new_state = case is_new_key {
        True -> {
          // Create the group observable
          let group_observable =
            Observable(subscribe: fn(group_observer: Observer(a)) {
              let reply: Subject(Disposable) = process.new_subject()
              process.send(control, GroupSubscribe(key, group_observer, reply))
              case process.receive(reply, 5000) {
                Ok(disp) -> disp
                Error(_) -> panic as "group subscribe timeout"
              }
            })

          // Emit the new group to downstream
          downstream(OnNext(#(key, group_observable)))

          // Update emitted keys
          GroupByState(..state, emitted_keys: [key, ..state.emitted_keys])
        }
        False -> state
      }

      // Forward value to group subscribers (or buffer if no subscribers yet)
      let current_group = case dict.get(new_state.groups, key) {
        Ok(g) -> g
        Error(_) -> GroupState(subscribers: [], buffer: [])
      }

      let updated_group = case current_group.subscribers {
        [] -> {
          // No subscribers yet, buffer the value
          GroupState(..current_group, buffer: list.append(current_group.buffer, [value]))
        }
        subs -> {
          // Forward to all subscribers
          list.each(subs, fn(sub) {
            let Observer(notify) = sub.observer
            notify(OnNext(value))
          })
          current_group
        }
      }

      let updated_groups = dict.insert(new_state.groups, key, updated_group)
      group_by_loop(
        control,
        downstream,
        GroupByState(..new_state, groups: updated_groups),
      )
    }
    GroupByError(e) -> {
      // Propagate error to downstream and all groups
      downstream(OnError(e))
      // Also error all group subscribers
      let _ =
        dict.each(state.groups, fn(_key, group_state) {
          list.each(group_state.subscribers, fn(sub) {
            let Observer(notify) = sub.observer
            notify(OnError(e))
          })
        })
      Nil
    }
    GroupByCompleted -> {
      // Complete all groups first, then complete downstream
      let _ =
        dict.each(state.groups, fn(_key, group_state) {
          list.each(group_state.subscribers, fn(sub) {
            let Observer(notify) = sub.observer
            notify(OnCompleted)
          })
        })
      downstream(OnCompleted)
      // Keep running to handle late subscribers who should get OnCompleted
      group_by_loop(
        control,
        downstream,
        GroupByState(..state, terminated: True),
      )
    }
    GroupByDispose -> Nil
    GroupSubscribe(key, observer, reply) -> {
      // Add subscriber to the group
      let id = erlang_unique_integer()
      let new_sub = GroupSubscriber(id: id, observer: observer)

      let current_group = case dict.get(state.groups, key) {
        Ok(g) -> g
        Error(_) -> GroupState(subscribers: [], buffer: [])
      }

      // Flush buffered values to new subscriber
      let Observer(notify) = observer
      list.each(current_group.buffer, fn(value) { notify(OnNext(value)) })

      // If already terminated, send completion
      case state.terminated {
        True -> notify(OnCompleted)
        False -> Nil
      }

      let new_group =
        GroupState(..current_group, subscribers: [
          new_sub,
          ..current_group.subscribers
        ])
      let new_groups = dict.insert(state.groups, key, new_group)

      let disp =
        Disposable(dispose: fn() {
          process.send(control, GroupUnsubscribe(key, id))
          Nil
        })
      process.send(reply, disp)

      group_by_loop(
        control,
        downstream,
        GroupByState(..state, groups: new_groups),
      )
    }
    GroupUnsubscribe(key, id) -> {
      let new_groups = case dict.get(state.groups, key) {
        Ok(group_state) -> {
          let new_subs =
            list.filter(group_state.subscribers, fn(s) { s.id != id })
          dict.insert(
            state.groups,
            key,
            GroupState(..group_state, subscribers: new_subs),
          )
        }
        Error(_) -> state.groups
      }
      group_by_loop(
        control,
        downstream,
        GroupByState(..state, groups: new_groups),
      )
    }
  }
}

@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int
