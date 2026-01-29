//// Tests for error handling operators (retry, catch)
////
//// Based on RxPY test patterns for comprehensive coverage.

import actorx
import actorx/types.{type Notification, OnCompleted, OnNext}
import gleam/erlang/process.{type Subject}
import gleeunit/should
import test_utils.{collect_messages, collect_notifications, message_observer}

// ============================================================================
// retry tests
// ============================================================================

pub fn retry_no_error_completes_normally_test() {
  // RxPY: test_retry_observable_basic
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.retry(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn retry_max_retries_then_error_test() {
  // RxPY: test_retry_observable_retry_count_basic
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  // Always fails - should retry twice then propagate error
  let observable =
    actorx.fail("Always fails")
    |> actorx.retry(2)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([])
  completed |> should.be_false()
  errors |> should.equal(["Always fails"])
}

pub fn retry_zero_retries_propagates_immediately_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Immediate fail")
    |> actorx.retry(0)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([])
  completed |> should.be_false()
  errors |> should.equal(["Immediate fail"])
}

pub fn retry_empty_source_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.retry(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn retry_single_value_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.single(42)
    |> actorx.retry(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([42])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn retry_with_timer_test() {
  // Test retry with async source
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.timer(20)
    |> actorx.retry(2)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _errors) = collect_messages(result_subject, 100)

  values |> should.equal([0])
  completed |> should.be_true()
}

pub fn retry_partial_then_error_resubscribes_test() {
  // RxPY: test_retry_observable_error - values emitted, then error, then retry
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  // Track subscription count
  let count_subject: Subject(Int) = process.new_subject()

  let observable =
    actorx.defer(fn() {
      process.send(count_subject, 1)
      // First subscription: emit 1, 2 then error
      // Second subscription: succeed
      actorx.create(fn(observer) {
        actorx.on_next(observer, 1)
        actorx.on_next(observer, 2)
        // Check how many times we've subscribed
        let selector =
          process.new_selector()
          |> process.select(count_subject)
        case drain_subject(selector, 0) {
          1 -> actorx.on_error(observer, "First try fails")
          _ -> actorx.on_completed(observer)
        }
        actorx.empty_disposable()
      })
    })
    |> actorx.retry(2)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _errors) = collect_messages(result_subject, 100)

  // First attempt: 1, 2, error -> retry
  // Second attempt: 1, 2, complete
  values |> should.equal([1, 2, 1, 2])
  completed |> should.be_true()
}

fn drain_subject(selector, count: Int) -> Int {
  case process.selector_receive(selector, 1) {
    Ok(_) -> drain_subject(selector, count + 1)
    Error(_) -> count
  }
}

// ============================================================================
// catch tests
// ============================================================================

pub fn catch_no_error_passes_through_test() {
  // RxPY: test_catch_no_errors
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.catch(fn(_) { actorx.single(99) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_error_switches_to_fallback_test() {
  // RxPY: test_catch_error
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Oops")
    |> actorx.catch(fn(_) { actorx.single(42) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([42])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_error_with_fallback_list_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Error")
    |> actorx.catch(fn(_) { actorx.from_list([10, 20, 30]) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([10, 20, 30])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_partial_emission_then_error_test() {
  // RxPY: test_catch_error - source emits some values before error
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.create(fn(observer) {
      actorx.on_next(observer, 1)
      actorx.on_next(observer, 2)
      actorx.on_error(observer, "Midway error")
      actorx.empty_disposable()
    })
    |> actorx.catch(fn(_) { actorx.from_list([100, 200]) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([1, 2, 100, 200])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_handler_receives_error_message_test() {
  // RxPY: test_catch_error_specific_caught
  let result_subject: Subject(Notification(String)) = process.new_subject()

  let observable =
    actorx.fail("Custom error")
    |> actorx.catch(fn(err) { actorx.single("Caught: " <> err) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal(["Caught: Custom error"])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_fallback_empty_test() {
  // RxPY: test_catch_empty
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Error")
    |> actorx.catch(fn(_) { actorx.empty() })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_fallback_also_errors_propagates_test() {
  // RxPY: test_catch_error_error
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Error 1")
    |> actorx.catch(fn(_) { actorx.fail("Error 2") })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([])
  completed |> should.be_false()
  errors |> should.equal(["Error 2"])
}

pub fn catch_chained_catches_both_errors_test() {
  // RxPY: test_catch_throw_from_nested_catch
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Error 1")
    |> actorx.catch(fn(_) { actorx.fail("Error 2") })
    |> actorx.catch(fn(_) { actorx.single(999) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([999])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_chained_first_succeeds_test() {
  // RxPY: test_catch_nested_outer_catches
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  // First catch handles the error, second catch is not invoked
  let observable =
    actorx.fail("Error 1")
    |> actorx.catch(fn(_) { actorx.from_list([1, 2, 3]) })
    |> actorx.catch(fn(_) { actorx.single(999) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_with_timer_fallback_test() {
  // Test catch with async fallback
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.fail("Error")
    |> actorx.catch(fn(_) {
      actorx.timer(20)
      |> actorx.map(fn(_) { 42 })
    })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _errors) = collect_messages(result_subject, 100)

  values |> should.equal([42])
  completed |> should.be_true()
}

pub fn catch_preserves_notification_sequence_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.create(fn(observer) {
      actorx.on_next(observer, 1)
      actorx.on_error(observer, "Error")
      actorx.empty_disposable()
    })
    |> actorx.catch(fn(_) {
      actorx.create(fn(observer) {
        actorx.on_next(observer, 2)
        actorx.on_completed(observer)
        actorx.empty_disposable()
      })
    })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let notifications = collect_notifications(result_subject, 100)

  notifications |> should.equal([OnNext(1), OnNext(2), OnCompleted])
}

// ============================================================================
// Combined retry + catch tests
// ============================================================================

pub fn retry_then_catch_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  // Retry twice, then fall back to default
  let observable =
    actorx.fail("Error")
    |> actorx.retry(2)
    |> actorx.catch(fn(_) { actorx.single(0) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([0])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn catch_then_retry_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  // catch converts error to success, retry sees success
  let observable =
    actorx.fail("Error")
    |> actorx.catch(fn(_) { actorx.single(42) })
    |> actorx.retry(2)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, errors) = collect_messages(result_subject, 100)

  values |> should.equal([42])
  completed |> should.be_true()
  errors |> should.equal([])
}
