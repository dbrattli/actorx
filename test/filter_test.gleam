//// Tests for filter operators

import actorx
import actorx/types.{type Notification, Observer, OnCompleted, OnError, OnNext}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// ============================================================================
// Test utilities (message-based collection for actor-based operators)
// ============================================================================

fn message_observer(subj: Subject(Notification(a))) -> types.Observer(a) {
  Observer(notify: fn(n) { process.send(subj, n) })
}

fn collect_messages(
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

// ============================================================================
// filter tests
// ============================================================================

pub fn filter_keeps_matching_elements_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6])
    |> actorx.filter(fn(x) { x > 3 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([4, 5, 6])
  completed |> should.be_true()
}

pub fn filter_all_pass_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.filter(fn(_) { True })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
}

pub fn filter_none_pass_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.filter(fn(_) { False })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn filter_empty_source_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.filter(fn(x) { x > 0 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn filter_even_numbers_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> actorx.filter(fn(x) { x % 2 == 0 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([2, 4, 6, 8, 10])
}

pub fn filter_chained_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> actorx.filter(fn(x) { x > 3 })
    |> actorx.filter(fn(x) { x < 8 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([4, 5, 6, 7])
}

// ============================================================================
// take tests
// ============================================================================

pub fn take_first_n_elements_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn take_zero_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take(0)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn take_more_than_available_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take(10)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn take_exact_count_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn take_from_empty_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.take(5)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn take_one_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take(1)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1])
  completed |> should.be_true()
}

pub fn take_with_interval_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  // This is the key test - take with async source
  let observable =
    actorx.interval(20)
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 200)
  values |> should.equal([0, 1, 2])
  completed |> should.be_true()
}

// ============================================================================
// skip tests
// ============================================================================

pub fn skip_first_n_elements_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.skip(2)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([3, 4, 5])
  completed |> should.be_true()
}

pub fn skip_zero_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.skip(0)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
}

pub fn skip_more_than_available_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.skip(10)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn skip_exact_count_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.skip(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn skip_from_empty_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.skip(5)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn skip_all_but_one_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.skip(4)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([5])
}

// ============================================================================
// take_while tests
// ============================================================================

pub fn take_while_condition_true_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take_while(fn(x) { x < 4 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn take_while_always_true_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take_while(fn(_) { True })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
}

pub fn take_while_always_false_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take_while(fn(_) { False })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn take_while_empty_source_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.take_while(fn(x) { x > 0 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn take_while_first_fails_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([5, 4, 3, 2, 1])
    |> actorx.take_while(fn(x) { x < 5 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

// ============================================================================
// skip_while tests
// ============================================================================

pub fn skip_while_condition_true_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.skip_while(fn(x) { x < 3 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([3, 4, 5])
  completed |> should.be_true()
}

pub fn skip_while_always_true_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.skip_while(fn(_) { True })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn skip_while_always_false_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.skip_while(fn(_) { False })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
}

pub fn skip_while_empty_source_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.skip_while(fn(x) { x > 0 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn skip_while_first_fails_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([5, 4, 3, 2, 1])
    |> actorx.skip_while(fn(x) { x < 5 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  // First element (5) doesn't satisfy < 5, so we start emitting immediately
  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([5, 4, 3, 2, 1])
}

// ============================================================================
// distinct_until_changed tests
// ============================================================================

pub fn distinct_until_changed_removes_consecutive_dupes_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 1, 2, 2, 2, 3, 1, 1])
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3, 1])
  completed |> should.be_true()
}

pub fn distinct_until_changed_all_different_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3, 4, 5])
}

pub fn distinct_until_changed_all_same_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([2, 2, 2, 2, 2])
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([2])
}

pub fn distinct_until_changed_empty_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn distinct_until_changed_single_value_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.single(42)
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([42])
}

pub fn distinct_until_changed_alternating_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 1, 2, 1, 2])
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  // All values are distinct from their predecessor
  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 1, 2, 1, 2])
}

// ============================================================================
// choose tests
// ============================================================================

pub fn choose_filters_and_maps_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.choose(fn(x) {
      case x % 2 == 0 {
        True -> Some(x * 10)
        False -> None
      }
    })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([20, 40])
  completed |> should.be_true()
}

pub fn choose_all_some_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.choose(fn(x) { Some(x * 100) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([100, 200, 300])
}

pub fn choose_all_none_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.choose(fn(_) { None })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn choose_empty_source_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable: actorx.Observable(Int) =
    actorx.empty()
    |> actorx.choose(fn(x) { Some(x) })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

// ============================================================================
// take_last tests
// ============================================================================

pub fn take_last_returns_last_n_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take_last(2)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([4, 5])
  completed |> should.be_true()
}

pub fn take_last_zero_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take_last(0)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn take_last_more_than_available_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take_last(10)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn take_last_exact_count_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.take_last(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn take_last_from_empty_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.empty()
    |> actorx.take_last(5)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([])
  completed |> should.be_true()
}

pub fn take_last_one_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take_last(1)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([5])
}

// ============================================================================
// Combined operator tests
// ============================================================================

pub fn map_and_filter_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.map(fn(x) { x * 2 })
    |> actorx.filter(fn(x) { x > 4 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([6, 8, 10])
  completed |> should.be_true()
}

pub fn filter_map_take_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> actorx.filter(fn(x) { x % 2 == 0 })
    |> actorx.map(fn(x) { x * 10 })
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, completed, _) = collect_messages(result_subject, 100)
  values |> should.equal([20, 40, 60])
  completed |> should.be_true()
}

pub fn skip_then_take_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> actorx.skip(3)
    |> actorx.take(4)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([4, 5, 6, 7])
}

pub fn take_while_then_map_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take_while(fn(x) { x < 4 })
    |> actorx.map(fn(x) { x * 10 })

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([10, 20, 30])
}

pub fn distinct_then_take_test() {
  let result_subject: Subject(Notification(Int)) = process.new_subject()

  let observable =
    actorx.from_list([1, 1, 2, 2, 3, 3, 4, 4, 5, 5])
    |> actorx.distinct_until_changed()
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, message_observer(result_subject))

  let #(values, _, _) = collect_messages(result_subject, 100)
  values |> should.equal([1, 2, 3])
}
