//// Tests for ActorX - Reactive Extensions for Gleam using BEAM actors

import actorx
import actorx/types.{type Observer, Observer}
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

// ============================================================================
// Test utilities using Erlang process dictionary for state
// ============================================================================

@external(erlang, "erlang", "put")
fn erlang_put(key: a, value: b) -> c

@external(erlang, "erlang", "get")
fn erlang_get(key: a) -> b

@external(erlang, "erlang", "make_ref")
fn erlang_make_ref() -> a

fn make_list_ref() -> a {
  let ref = erlang_make_ref()
  erlang_put(ref, [])
  ref
}

fn get_list_ref(ref: a) -> List(b) {
  erlang_get(ref)
}

fn append_to_ref(ref: a, value: b) -> Nil {
  let current: List(b) = erlang_get(ref)
  erlang_put(ref, list.append(current, [value]))
  Nil
}

fn make_bool_ref(initial: Bool) -> a {
  let ref = erlang_make_ref()
  erlang_put(ref, initial)
  ref
}

fn get_bool_ref(ref: a) -> Bool {
  erlang_get(ref)
}

fn set_bool_ref(ref: a, value: Bool) -> Nil {
  erlang_put(ref, value)
  Nil
}

/// Create a test observer that collects results
fn test_observer(
  results_ref: a,
  completed_ref: b,
  errors_ref: c,
) -> Observer(Int) {
  Observer(
    on_next: fn(x) { append_to_ref(results_ref, x) },
    on_error: fn(err) { append_to_ref(errors_ref, err) },
    on_completed: fn() { set_bool_ref(completed_ref, True) },
  )
}

// ============================================================================
// Creation operator tests
// ============================================================================

pub fn single_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable = actorx.single(42)
  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([42])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn empty_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable = actorx.empty()
  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn from_list_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable = actorx.from_list([1, 2, 3, 4, 5])
  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([1, 2, 3, 4, 5])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn fail_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors: a = make_list_ref()

  let observable = actorx.fail("test error")
  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([])
  get_bool_ref(completed) |> should.equal(False)
  let errs: List(String) = get_list_ref(errors)
  errs |> should.equal(["test error"])
}

// ============================================================================
// Transform operator tests
// ============================================================================

pub fn map_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.map(fn(x) { x * 10 })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([10, 20, 30])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn map_chained_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3])
    |> actorx.map(fn(x) { x * 10 })
    |> actorx.map(fn(x) { x + 1 })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([11, 21, 31])
  get_bool_ref(completed) |> should.equal(True)
}

// ============================================================================
// Filter operator tests
// ============================================================================

pub fn filter_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6])
    |> actorx.filter(fn(x) { x > 3 })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([4, 5, 6])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn take_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([1, 2, 3])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn skip_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.skip(2)

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([3, 4, 5])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn take_while_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take_while(fn(x) { x < 4 })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([1, 2, 3])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn distinct_until_changed_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 1, 2, 2, 2, 3, 1, 1])
    |> actorx.distinct_until_changed()

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([1, 2, 3, 1])
  get_bool_ref(completed) |> should.equal(True)
}

// ============================================================================
// Combined operator tests
// ============================================================================

pub fn map_and_filter_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.map(fn(x) { x * 2 })
    |> actorx.filter(fn(x) { x > 4 })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([6, 8, 10])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn filter_map_take_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    |> actorx.filter(fn(x) { x % 2 == 0 })
    |> actorx.map(fn(x) { x * 10 })
    |> actorx.take(3)

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([20, 40, 60])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn choose_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.choose(fn(x) {
      case x % 2 == 0 {
        True -> Some(x * 10)
        False -> None
      }
    })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([20, 40])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn take_last_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  let observable =
    actorx.from_list([1, 2, 3, 4, 5])
    |> actorx.take_last(2)

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([4, 5])
  get_bool_ref(completed) |> should.equal(True)
}

// ============================================================================
// Builder tests - `use` keyword support
// ============================================================================

import actorx/builder.{bind, filter_with, for_each, map_over, return}

pub fn builder_simple_bind_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // use x <- bind(source) desugars to bind(source, fn(x) { ... })
  let observable = {
    use x <- bind(actorx.single(42))
    return(x * 2)
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([84])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_chained_bind_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // Multiple binds - like F#'s let! x = ... let! y = ...
  let observable = {
    use x <- bind(actorx.single(10))
    use y <- bind(actorx.single(20))
    return(x + y)
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([30])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_flatmap_behavior_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // bind with from_list creates flatMap behavior
  // For each x in [1,2,3], emit x+10
  let observable = {
    use x <- bind(actorx.from_list([1, 2, 3]))
    return(x + 10)
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([11, 12, 13])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_nested_flatmap_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // Cartesian product: [1,2] x [10,20] = [11,21,12,22]
  let observable = {
    use x <- bind(actorx.from_list([1, 2]))
    use y <- bind(actorx.from_list([10, 20]))
    return(x + y)
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([11, 21, 12, 22])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_map_over_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // map_over is like map but with use syntax
  let observable = {
    use x <- map_over(actorx.from_list([1, 2, 3]))
    x * 100
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([100, 200, 300])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_filter_with_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // filter_with is like filter but with use syntax
  let observable = {
    use x <- filter_with(actorx.from_list([1, 2, 3, 4, 5]))
    x > 2
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([3, 4, 5])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_for_each_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // for_each is like F#'s for in computation expressions
  let observable = for_each([1, 2, 3], fn(x) { actorx.single(x * 10) })

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  get_list_ref(results) |> should.equal([10, 20, 30])
  get_bool_ref(completed) |> should.equal(True)
}

pub fn builder_complex_composition_test() {
  let results = make_list_ref()
  let completed = make_bool_ref(False)
  let errors = make_list_ref()

  // Complex composition combining bind, map, and filter
  let observable = {
    use x <- bind(actorx.from_list([1, 2, 3, 4, 5]))
    use y <- bind(actorx.single(10))
    case x % 2 == 0 {
      True -> return(x * y)
      False -> builder.empty()
    }
  }

  let _ = actorx.subscribe(observable, test_observer(results, completed, errors))

  // Only even numbers (2, 4) multiplied by 10
  get_list_ref(results) |> should.equal([20, 40])
  get_bool_ref(completed) |> should.equal(True)
}
