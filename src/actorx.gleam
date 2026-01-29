//// ActorX - Reactive Extensions for Gleam using BEAM actors
////
//// A reactive programming library that composes BEAM actors for
//// building asynchronous, event-driven applications.
////
//// ## Example
////
//// ```gleam
//// import actorx
//// import actorx/types.{Observer}
////
//// pub fn main() {
////   let observable =
////     actorx.from_list([1, 2, 3, 4, 5])
////     |> actorx.map(fn(x) { x * 2 })
////     |> actorx.filter(fn(x) { x > 4 })
////
////   let observer = Observer(
////     on_next: fn(x) { io.println(int.to_string(x)) },
////     on_error: fn(err) { io.println("Error: " <> err) },
////     on_completed: fn() { io.println("Done!") },
////   )
////
////   actorx.subscribe(observable, observer)
//// }
//// ```

import actorx/create
import actorx/filter
import actorx/transform
import actorx/types
import gleam/option

// ============================================================================
// Re-export types
// ============================================================================

pub type Observable(a) =
  types.Observable(a)

pub type Observer(a) =
  types.Observer(a)

pub type Disposable =
  types.Disposable

pub type Notification(a) =
  types.Notification(a)

// ============================================================================
// Subscribe helper
// ============================================================================

/// Subscribe an observer to an observable.
pub fn subscribe(
  observable: types.Observable(a),
  observer: types.Observer(a),
) -> types.Disposable {
  let types.Observable(subscribe_fn) = observable
  subscribe_fn(observer)
}

// ============================================================================
// Creation operators
// ============================================================================

/// Create an observable from a subscribe function.
pub fn create(
  subscribe_fn: fn(types.Observer(a)) -> types.Disposable,
) -> types.Observable(a) {
  create.create(subscribe_fn)
}

/// Create an observable that emits a single value then completes.
pub fn single(value: a) -> types.Observable(a) {
  create.single(value)
}

/// Create an observable that completes immediately without emitting.
pub fn empty() -> types.Observable(a) {
  create.empty()
}

/// Create an observable that never emits and never completes.
pub fn never() -> types.Observable(a) {
  create.never()
}

/// Create an observable that errors immediately.
pub fn fail(error: String) -> types.Observable(a) {
  create.fail(error)
}

/// Create an observable from a list of values.
pub fn from_list(items: List(a)) -> types.Observable(a) {
  create.from_list(items)
}

/// Create an observable that calls a factory function on each subscription.
pub fn defer(factory: fn() -> types.Observable(a)) -> types.Observable(a) {
  create.defer(factory)
}

// ============================================================================
// Transform operators
// ============================================================================

/// Transform each element using a mapper function.
pub fn map(
  source: types.Observable(a),
  mapper: fn(a) -> b,
) -> types.Observable(b) {
  transform.map(source, mapper)
}

/// Project each element to an observable and flatten.
pub fn flat_map(
  source: types.Observable(a),
  mapper: fn(a) -> types.Observable(b),
) -> types.Observable(b) {
  transform.flat_map(source, mapper)
}

/// Project each element to an observable and concatenate in order.
pub fn concat_map(
  source: types.Observable(a),
  mapper: fn(a) -> types.Observable(b),
) -> types.Observable(b) {
  transform.concat_map(source, mapper)
}

// ============================================================================
// Filter operators
// ============================================================================

/// Filter elements based on a predicate.
pub fn filter(
  source: types.Observable(a),
  predicate: fn(a) -> Bool,
) -> types.Observable(a) {
  filter.filter(source, predicate)
}

/// Take the first N elements.
pub fn take(source: types.Observable(a), count: Int) -> types.Observable(a) {
  filter.take(source, count)
}

/// Skip the first N elements.
pub fn skip(source: types.Observable(a), count: Int) -> types.Observable(a) {
  filter.skip(source, count)
}

/// Take elements while predicate returns True.
pub fn take_while(
  source: types.Observable(a),
  predicate: fn(a) -> Bool,
) -> types.Observable(a) {
  filter.take_while(source, predicate)
}

/// Skip elements while predicate returns True.
pub fn skip_while(
  source: types.Observable(a),
  predicate: fn(a) -> Bool,
) -> types.Observable(a) {
  filter.skip_while(source, predicate)
}

/// Filter and map in one operation.
pub fn choose(
  source: types.Observable(a),
  chooser: fn(a) -> option.Option(b),
) -> types.Observable(b) {
  filter.choose(source, chooser)
}

/// Emit only when value changes from previous.
pub fn distinct_until_changed(
  source: types.Observable(a),
) -> types.Observable(a) {
  filter.distinct_until_changed(source)
}

/// Take elements until another observable emits.
pub fn take_until(
  source: types.Observable(a),
  other: types.Observable(b),
) -> types.Observable(a) {
  filter.take_until(source, other)
}

/// Take the last N elements (emitted on completion).
pub fn take_last(source: types.Observable(a), count: Int) -> types.Observable(a) {
  filter.take_last(source, count)
}

// ============================================================================
// Utility
// ============================================================================

/// Create an empty disposable.
pub fn empty_disposable() -> types.Disposable {
  types.empty_disposable()
}
