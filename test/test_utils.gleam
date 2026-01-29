//// Shared test utilities for ActorX tests
////
//// Provides utilities for testing ActorX observables:
//// - Process dictionary refs for sync tests
//// - Message-based collection for async/actor-based tests
//// - Observer factories
//// - Assertion helpers

import actorx/types.{
  type Notification, type Observer, Observer, OnCompleted, OnError, OnNext,
}
import gleam/erlang/process.{type Subject}
import gleam/list

// ============================================================================
// Erlang process dictionary FFI for test state
// ============================================================================

@external(erlang, "erlang", "put")
pub fn erlang_put(key: a, value: b) -> c

@external(erlang, "erlang", "get")
pub fn erlang_get(key: a) -> b

@external(erlang, "erlang", "make_ref")
pub fn erlang_make_ref() -> a

// ============================================================================
// Reference helpers for collecting test results
// ============================================================================

/// Create a reference to an empty list for collecting values
pub fn make_list_ref() -> a {
  let ref = erlang_make_ref()
  erlang_put(ref, [])
  ref
}

/// Get the current list from a reference
pub fn get_list_ref(ref: a) -> List(b) {
  erlang_get(ref)
}

/// Append a value to a list reference
pub fn append_to_ref(ref: a, value: b) -> Nil {
  let current: List(b) = erlang_get(ref)
  erlang_put(ref, list.append(current, [value]))
  Nil
}

/// Create a reference to a boolean value
pub fn make_bool_ref(initial: Bool) -> a {
  let ref = erlang_make_ref()
  erlang_put(ref, initial)
  ref
}

/// Get the current boolean from a reference
pub fn get_bool_ref(ref: a) -> Bool {
  erlang_get(ref)
}

/// Set a boolean reference value
pub fn set_bool_ref(ref: a, value: Bool) -> Nil {
  erlang_put(ref, value)
  Nil
}

/// Create a reference to an integer value
pub fn make_int_ref(initial: Int) -> a {
  let ref = erlang_make_ref()
  erlang_put(ref, initial)
  ref
}

/// Get the current integer from a reference
pub fn get_int_ref(ref: a) -> Int {
  erlang_get(ref)
}

/// Set an integer reference value
pub fn set_int_ref(ref: a, value: Int) -> Nil {
  erlang_put(ref, value)
  Nil
}

/// Increment an integer reference
pub fn incr_int_ref(ref: a) -> Nil {
  let current: Int = erlang_get(ref)
  erlang_put(ref, current + 1)
  Nil
}

// ============================================================================
// Test observer factories
// ============================================================================

/// Create a test observer that collects Int results
pub fn test_observer(
  results_ref: a,
  completed_ref: b,
  errors_ref: c,
) -> Observer(Int) {
  Observer(notify: fn(n) {
    case n {
      OnNext(x) -> append_to_ref(results_ref, x)
      OnError(err) -> append_to_ref(errors_ref, err)
      OnCompleted -> set_bool_ref(completed_ref, True)
    }
  })
}

/// Create a test observer that collects String results
pub fn test_string_observer(
  results_ref: a,
  completed_ref: b,
  errors_ref: c,
) -> Observer(String) {
  Observer(notify: fn(n) {
    case n {
      OnNext(x) -> append_to_ref(results_ref, x)
      OnError(err) -> append_to_ref(errors_ref, err)
      OnCompleted -> set_bool_ref(completed_ref, True)
    }
  })
}

/// Create a test observer that collects notifications in order
pub fn notification_observer(notifications_ref: a) -> Observer(Int) {
  Observer(notify: fn(n) { append_to_ref(notifications_ref, n) })
}

/// Get collected notifications from a reference
pub fn get_notifications(ref: a) -> List(Notification(Int)) {
  erlang_get(ref)
}

/// Sleep for the specified number of milliseconds.
/// Useful for testing async operators.
pub fn wait_ms(ms: Int) -> Nil {
  process.sleep(ms)
}

// ============================================================================
// Message-based collection for actor-based operators
// ============================================================================

/// Result type for collected messages
pub type CollectedMessages(a) {
  CollectedMessages(values: List(a), completed: Bool, errors: List(String))
}

/// Create an observer that sends notifications via message passing.
/// Use with collect_messages for testing actor-based operators.
pub fn message_observer(subj: Subject(Notification(a))) -> Observer(a) {
  Observer(notify: fn(n) { process.send(subj, n) })
}

/// Collect messages from a subject until completion, error, or timeout.
/// Returns tuple of (values, completed, errors).
pub fn collect_messages(
  subj: Subject(Notification(a)),
  timeout_ms: Int,
) -> #(List(a), Bool, List(String)) {
  collect_messages_loop(subj, timeout_ms, [], False, [])
}

fn collect_messages_loop(
  subj: Subject(Notification(a)),
  timeout_ms: Int,
  values: List(a),
  completed: Bool,
  errors: List(String),
) -> #(List(a), Bool, List(String)) {
  let selector =
    process.new_selector()
    |> process.select(subj)

  case process.selector_receive(selector, timeout_ms) {
    Ok(OnNext(x)) ->
      collect_messages_loop(
        subj,
        timeout_ms,
        list.append(values, [x]),
        completed,
        errors,
      )
    Ok(OnCompleted) -> #(values, True, errors)
    Ok(OnError(e)) -> #(values, completed, list.append(errors, [e]))
    Error(_) -> #(values, completed, errors)
  }
}

/// Collect all notifications (including type) from a subject.
/// Useful for testing exact notification sequences.
pub fn collect_notifications(
  subj: Subject(Notification(a)),
  timeout_ms: Int,
) -> List(Notification(a)) {
  collect_notifications_loop(subj, timeout_ms, [])
}

fn collect_notifications_loop(
  subj: Subject(Notification(a)),
  timeout_ms: Int,
  notifications: List(Notification(a)),
) -> List(Notification(a)) {
  let selector =
    process.new_selector()
    |> process.select(subj)

  case process.selector_receive(selector, timeout_ms) {
    Ok(n) -> {
      let new_list = list.append(notifications, [n])
      case n {
        OnCompleted -> new_list
        OnError(_) -> new_list
        OnNext(_) -> collect_notifications_loop(subj, timeout_ms, new_list)
      }
    }
    Error(_) -> notifications
  }
}

/// Create a new subject for message collection and return both
/// the subject and an observer connected to it.
pub fn make_test_subject() -> #(Subject(Notification(a)), Observer(a)) {
  let subj = process.new_subject()
  #(subj, message_observer(subj))
}

// ============================================================================
// Subscription tracking
// ============================================================================

/// Track subscription and disposal for testing lifecycle.
pub type SubscriptionRecord {
  SubscriptionRecord(subscribed: Bool, disposed: Bool, dispose_count: Int)
}

/// Create refs for tracking subscription lifecycle.
pub fn make_subscription_tracker() -> #(a, b, c) {
  let subscribed = make_bool_ref(False)
  let disposed = make_bool_ref(False)
  let dispose_count = make_int_ref(0)
  #(subscribed, disposed, dispose_count)
}
