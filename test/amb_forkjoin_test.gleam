//// Tests for amb/race, fork_join, distinct, and timeout

import actorx
import actorx/types.{type Notification}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleeunit/should
import test_utils.{collect_messages, message_observer}

// ============================================================================
// amb / race tests
// ============================================================================

pub fn amb_first_to_emit_wins_test() {
  let result: Subject(Notification(String)) = process.new_subject()

  let source =
    actorx.amb([
      actorx.timer(100) |> actorx.map(fn(_) { "slow" }),
      actorx.timer(30) |> actorx.map(fn(_) { "fast" }),
      actorx.timer(200) |> actorx.map(fn(_) { "slowest" }),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 300)

  // Fast should win
  values |> should.equal(["fast"])
  completed |> should.be_true()
}

pub fn amb_sync_first_wins_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.amb([
      actorx.from_list([1, 2, 3]),
      actorx.from_list([4, 5, 6]),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  // First source wins (1, 2, 3)
  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn amb_empty_list_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source = actorx.amb([])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([])
  completed |> should.be_true()
}

pub fn amb_single_source_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source = actorx.amb([actorx.from_list([1, 2, 3])])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
}

pub fn race_is_alias_for_amb_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.race([
      actorx.from_list([1, 2]),
      actorx.from_list([3, 4]),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([1, 2])
  completed |> should.be_true()
}

pub fn amb_error_from_winner_propagates_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.amb([
      actorx.fail("error"),
      actorx.timer(100) |> actorx.map(fn(_) { 1 }),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 150)

  values |> should.equal([])
  completed |> should.be_false()
  errors |> should.equal(["error"])
}

// ============================================================================
// fork_join tests
// ============================================================================

pub fn fork_join_basic_test() {
  let result: Subject(Notification(List(Int))) = process.new_subject()

  let source =
    actorx.fork_join([
      actorx.from_list([1, 2, 3]),
      actorx.from_list([4, 5]),
      actorx.single(6),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  // Should get last values from each: [3, 5, 6]
  values |> should.equal([[3, 5, 6]])
  completed |> should.be_true()
}

pub fn fork_join_empty_list_test() {
  let result: Subject(Notification(List(Int))) = process.new_subject()

  let source = actorx.fork_join([])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([[]])
  completed |> should.be_true()
}

pub fn fork_join_single_source_test() {
  let result: Subject(Notification(List(Int))) = process.new_subject()

  let source = actorx.fork_join([actorx.from_list([1, 2, 3])])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([[3]])
  completed |> should.be_true()
}

pub fn fork_join_async_test() {
  let result: Subject(Notification(List(Int))) = process.new_subject()

  let source =
    actorx.fork_join([
      actorx.timer(50) |> actorx.map(fn(_) { 1 }),
      actorx.timer(30) |> actorx.map(fn(_) { 2 }),
      actorx.timer(70) |> actorx.map(fn(_) { 3 }),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 200)

  // All complete, emit [1, 2, 3]
  values |> should.equal([[1, 2, 3]])
  completed |> should.be_true()
}

pub fn fork_join_empty_source_errors_test() {
  let result: Subject(Notification(List(Int))) = process.new_subject()

  let source =
    actorx.fork_join([
      actorx.from_list([1, 2]),
      actorx.empty(),
      actorx.from_list([3]),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 100)

  // Empty source causes error
  values |> should.equal([])
  completed |> should.be_false()
  list.length(errors) |> should.equal(1)
}

pub fn fork_join_error_propagates_test() {
  let result: Subject(Notification(List(Int))) = process.new_subject()

  let source =
    actorx.fork_join([
      actorx.from_list([1, 2]),
      actorx.fail("oops"),
      actorx.from_list([3]),
    ])

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 100)

  values |> should.equal([])
  completed |> should.be_false()
  errors |> should.equal(["oops"])
}

// ============================================================================
// distinct tests
// ============================================================================

pub fn distinct_basic_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.from_list([1, 2, 1, 3, 2, 4, 1])
    |> actorx.distinct()

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([1, 2, 3, 4])
  completed |> should.be_true()
}

pub fn distinct_all_unique_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.distinct()

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([1, 2, 3, 4, 5])
  completed |> should.be_true()
}

pub fn distinct_all_same_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.from_list([1, 1, 1, 1, 1])
    |> actorx.distinct()

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([1])
  completed |> should.be_true()
}

pub fn distinct_empty_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  let source =
    actorx.empty()
    |> actorx.distinct()

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, _) = collect_messages(result, 100)

  values |> should.equal([])
  completed |> should.be_true()
}

pub fn distinct_vs_distinct_until_changed_test() {
  let result1: Subject(Notification(Int)) = process.new_subject()
  let result2: Subject(Notification(Int)) = process.new_subject()

  let source = actorx.from_list([1, 2, 2, 1, 3, 3])

  // distinct filters ALL duplicates
  let _ =
    source
    |> actorx.distinct()
    |> actorx.subscribe(message_observer(result1))

  // distinct_until_changed only filters consecutive duplicates
  let _ =
    source
    |> actorx.distinct_until_changed()
    |> actorx.subscribe(message_observer(result2))

  let #(values1, _, _) = collect_messages(result1, 100)
  let #(values2, _, _) = collect_messages(result2, 100)

  // distinct: 1, 2, 3 (all unique)
  values1 |> should.equal([1, 2, 3])

  // distinct_until_changed: 1, 2, 1, 3 (consecutive only)
  values2 |> should.equal([1, 2, 1, 3])
}

// ============================================================================
// timeout tests
// ============================================================================

pub fn timeout_no_timeout_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  // Fast emissions should not timeout
  let source =
    actorx.interval(20)
    |> actorx.take(3)
    |> actorx.timeout(100)

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 200)

  values |> should.equal([0, 1, 2])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn timeout_triggers_error_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  // Source that takes too long
  let source =
    actorx.timer(200)
    |> actorx.map(fn(_) { 1 })
    |> actorx.timeout(50)

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 150)

  values |> should.equal([])
  completed |> should.be_false()
  list.length(errors) |> should.equal(1)
}

pub fn timeout_resets_on_emission_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  // Emissions every 30ms with 50ms timeout - should not timeout
  let source =
    actorx.interval(30)
    |> actorx.take(4)
    |> actorx.timeout(50)

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 250)

  // Should complete without timeout
  values |> should.equal([0, 1, 2, 3])
  completed |> should.be_true()
  errors |> should.equal([])
}

pub fn timeout_sync_source_test() {
  let result: Subject(Notification(Int)) = process.new_subject()

  // Sync source completes before timeout
  let source =
    actorx.from_list([1, 2, 3])
    |> actorx.timeout(1000)

  let _ = actorx.subscribe(source, message_observer(result))

  let #(values, completed, errors) = collect_messages(result, 100)

  values |> should.equal([1, 2, 3])
  completed |> should.be_true()
  errors |> should.equal([])
}
