//// Error handling operators for ActorX
////
//// These operators handle errors in observable sequences:
//// - retry: Resubscribe on error up to N times
//// - catch: Switch to fallback observable on error

import actorx/types.{
  type Observable, type Observer, Disposable, Observable, Observer, OnCompleted,
  OnError, OnNext,
}
import gleam/erlang/process.{type Subject}

// ============================================================================
// retry - Resubscribe on error
// ============================================================================

/// Messages for the retry actor
type RetryMsg(a) {
  RetryNext(a)
  RetryError(String)
  RetryCompleted
  RetryDispose
}

/// Resubscribes to the source observable when an error occurs,
/// up to the specified number of retries.
///
/// ## Example
/// ```gleam
/// // Retry up to 3 times on error
/// flaky_observable
/// |> retry(3)
/// ```
pub fn retry(source: Observable(a), max_retries: Int) -> Observable(a) {
  Observable(subscribe: fn(observer: Observer(a)) {
    let Observer(downstream) = observer

    // Create control channel
    let control_ready: Subject(Subject(RetryMsg(a))) = process.new_subject()

    // Spawn actor to manage retry state
    process.spawn(fn() {
      let control: Subject(RetryMsg(a)) = process.new_subject()
      process.send(control_ready, control)
      retry_loop(control, downstream, source, max_retries, 0)
    })

    // Get control subject
    let control = case process.receive(control_ready, 1000) {
      Ok(s) -> s
      Error(_) -> panic as "Failed to create retry actor"
    }

    // Initial subscription
    subscribe_with_retry(source, control)

    Disposable(dispose: fn() {
      process.send(control, RetryDispose)
      Nil
    })
  })
}

fn subscribe_with_retry(source: Observable(a), control: Subject(RetryMsg(a))) {
  let source_observer =
    Observer(notify: fn(n) {
      case n {
        OnNext(x) -> process.send(control, RetryNext(x))
        OnError(e) -> process.send(control, RetryError(e))
        OnCompleted -> process.send(control, RetryCompleted)
      }
    })

  let Observable(subscribe) = source
  let _ = subscribe(source_observer)
  Nil
}

fn retry_loop(
  control: Subject(RetryMsg(a)),
  downstream: fn(types.Notification(a)) -> Nil,
  source: Observable(a),
  max_retries: Int,
  retry_count: Int,
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select(control)

  case process.selector_receive_forever(selector) {
    RetryNext(x) -> {
      downstream(OnNext(x))
      retry_loop(control, downstream, source, max_retries, retry_count)
    }
    RetryError(e) -> {
      case retry_count < max_retries {
        True -> {
          // Retry: resubscribe to source
          subscribe_with_retry(source, control)
          retry_loop(control, downstream, source, max_retries, retry_count + 1)
        }
        False -> {
          // Max retries reached, propagate error
          downstream(OnError(e))
          Nil
        }
      }
    }
    RetryCompleted -> {
      downstream(OnCompleted)
      Nil
    }
    RetryDispose -> Nil
  }
}

// ============================================================================
// catch - Switch to fallback on error
// ============================================================================

/// Messages for the catch actor
type CatchMsg(a) {
  CatchNext(a)
  CatchError(String)
  CatchCompleted
  CatchDispose
  // Fallback messages - errors from fallback propagate, not caught again
  FallbackNext(a)
  FallbackError(String)
  FallbackCompleted
}

/// On error, switches to a fallback observable returned by the handler.
/// Also known as `catch_error` or `on_error_resume_next`.
///
/// ## Example
/// ```gleam
/// // On error, emit a default value
/// risky_observable
/// |> catch(fn(_error) { single(default_value) })
/// ```
pub fn catch(
  source: Observable(a),
  handler: fn(String) -> Observable(a),
) -> Observable(a) {
  Observable(subscribe: fn(observer: Observer(a)) {
    let Observer(downstream) = observer

    // Create control channel
    let control_ready: Subject(Subject(CatchMsg(a))) = process.new_subject()

    // Spawn actor to manage state
    process.spawn(fn() {
      let control: Subject(CatchMsg(a)) = process.new_subject()
      process.send(control_ready, control)
      catch_loop(control, downstream, handler)
    })

    // Get control subject
    let control = case process.receive(control_ready, 1000) {
      Ok(s) -> s
      Error(_) -> panic as "Failed to create catch actor"
    }

    // Subscribe to source
    let source_observer =
      Observer(notify: fn(n) {
        case n {
          OnNext(x) -> process.send(control, CatchNext(x))
          OnError(e) -> process.send(control, CatchError(e))
          OnCompleted -> process.send(control, CatchCompleted)
        }
      })

    let Observable(subscribe) = source
    let source_disp = subscribe(source_observer)

    Disposable(dispose: fn() {
      let Disposable(dispose_source) = source_disp
      dispose_source()
      process.send(control, CatchDispose)
      Nil
    })
  })
}

fn catch_loop(
  control: Subject(CatchMsg(a)),
  downstream: fn(types.Notification(a)) -> Nil,
  handler: fn(String) -> Observable(a),
) -> Nil {
  let selector =
    process.new_selector()
    |> process.select(control)

  case process.selector_receive_forever(selector) {
    CatchNext(x) -> {
      downstream(OnNext(x))
      catch_loop(control, downstream, handler)
    }
    CatchError(e) -> {
      // Switch to fallback observable
      let fallback = handler(e)
      let fallback_observer =
        Observer(notify: fn(n) {
          case n {
            // Fallback emissions use different message types
            OnNext(x) -> process.send(control, FallbackNext(x))
            OnError(err) -> process.send(control, FallbackError(err))
            OnCompleted -> process.send(control, FallbackCompleted)
          }
        })

      let Observable(subscribe_fallback) = fallback
      let _ = subscribe_fallback(fallback_observer)

      // Continue loop to handle fallback emissions
      catch_loop(control, downstream, handler)
    }
    CatchCompleted -> {
      downstream(OnCompleted)
      Nil
    }
    CatchDispose -> Nil
    // Fallback messages - forward directly, don't catch errors
    FallbackNext(x) -> {
      downstream(OnNext(x))
      catch_loop(control, downstream, handler)
    }
    FallbackError(e) -> {
      // Propagate fallback errors downstream (to be caught by outer catch if any)
      downstream(OnError(e))
      Nil
    }
    FallbackCompleted -> {
      downstream(OnCompleted)
      Nil
    }
  }
}
