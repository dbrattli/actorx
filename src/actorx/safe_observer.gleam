//// Safe Observer - Observer wrapper that enforces Rx grammar
////
//// The safe_observer wraps a downstream observer and:
//// 1. Enforces Rx grammar: OnNext* (OnError | OnCompleted)?
//// 2. Disposes resources on terminal events
//// 3. Ignores messages after terminal event
////
//// Note: For full actor-based implementation with message serialization,
//// use gleam_otp actors. This module provides a simpler synchronous version.

import actorx/types.{
  type Disposable, type Notification, type Observer, Disposable, Observer,
  OnCompleted, OnError, OnNext,
}

/// Wrap an observer with Rx grammar enforcement.
///
/// Returns an Observer that:
/// - Forwards OnNext until a terminal event
/// - Calls disposal on terminal events
/// - Ignores all events after terminal
pub fn wrap(observer: Observer(a), disposable: Disposable) -> Observer(a) {
  let Observer(on_next, on_error, on_completed) = observer
  let Disposable(dispose) = disposable

  // Use Erlang process dictionary for stopped state
  let stopped_ref = make_ref(0)

  Observer(
    on_next: fn(x) {
      case get_ref(stopped_ref) {
        0 -> on_next(x)
        _ -> Nil
      }
    },
    on_error: fn(err) {
      case get_ref(stopped_ref) {
        0 -> {
          set_ref(stopped_ref, 1)
          dispose()
          on_error(err)
        }
        _ -> Nil
      }
    },
    on_completed: fn() {
      case get_ref(stopped_ref) {
        0 -> {
          set_ref(stopped_ref, 1)
          dispose()
          on_completed()
        }
        _ -> Nil
      }
    },
  )
}

/// Create an observer from a notification handler function,
/// wrapped with Rx grammar enforcement.
pub fn from_notify(
  notify: fn(Notification(a)) -> Nil,
  disposable: Disposable,
) -> Observer(a) {
  let observer =
    Observer(
      on_next: fn(x) { notify(OnNext(x)) },
      on_error: fn(err) { notify(OnError(err)) },
      on_completed: fn() { notify(OnCompleted) },
    )
  wrap(observer, disposable)
}

// Mutable reference helpers using Erlang process dictionary

@external(erlang, "erlang", "put")
fn erlang_put(key: a, value: b) -> c

@external(erlang, "erlang", "get")
fn erlang_get(key: a) -> b

@external(erlang, "erlang", "make_ref")
fn erlang_make_ref() -> a

fn make_ref(initial: Int) -> a {
  let ref = erlang_make_ref()
  erlang_put(ref, initial)
  ref
}

fn get_ref(ref: a) -> Int {
  erlang_get(ref)
}

fn set_ref(ref: a, value: Int) -> Nil {
  erlang_put(ref, value)
  Nil
}
