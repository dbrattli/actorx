//// Transform operators for ActorX
////
//// These operators transform the elements of an observable sequence:
//// - map: Apply a function to each element
//// - flat_map: Map to observables and flatten

import actorx/types.{type Observable, type Observer, Observable, Observer}

/// Returns an observable whose elements are the result of invoking
/// the mapper function on each element of the source.
pub fn map(source: Observable(a), mapper: fn(a) -> b) -> Observable(b) {
  Observable(subscribe: fn(observer: Observer(b)) {
    let Observer(on_next, on_error, on_completed) = observer

    let upstream_observer =
      Observer(
        on_next: fn(x) { on_next(mapper(x)) },
        on_error: on_error,
        on_completed: on_completed,
      )

    let Observable(subscribe) = source
    subscribe(upstream_observer)
  })
}

/// Projects each element of an observable sequence into an observable
/// sequence and merges the resulting observable sequences.
pub fn flat_map(
  source: Observable(a),
  mapper: fn(a) -> Observable(b),
) -> Observable(b) {
  Observable(subscribe: fn(observer: Observer(b)) {
    let Observer(on_next, on_error, on_completed) = observer

    // Simple implementation: subscribe to each inner immediately
    let upstream_observer =
      Observer(
        on_next: fn(x) {
          let inner_observable = mapper(x)
          let Observable(inner_subscribe) = inner_observable

          let inner_observer =
            Observer(
              on_next: on_next,
              on_error: on_error,
              on_completed: fn() { Nil },
            )

          let _inner_disp = inner_subscribe(inner_observer)
          Nil
        },
        on_error: on_error,
        on_completed: on_completed,
      )

    let Observable(subscribe) = source
    subscribe(upstream_observer)
  })
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
