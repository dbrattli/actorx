//// Core types for AsyncRx - Async Reactive Extensions for Gleam
////
//// This module defines the fundamental types for reactive programming:
//// - Notification: The atoms of the Rx grammar (OnNext, OnError, OnCompleted)
//// - Disposable: Resource cleanup handle
//// - Observer: Receives notifications from an observable
//// - Observable: Source of asynchronous events

/// Notification represents the three types of events in the Rx grammar:
/// OnNext* (OnError | OnCompleted)?
pub type Notification(a) {
  OnNext(a)
  OnError(String)
  OnCompleted
}

/// Disposable represents a resource that can be cleaned up.
/// Call the dispose function to release resources and unsubscribe.
pub type Disposable {
  Disposable(dispose: fn() -> Nil)
}

/// Create an empty disposable that does nothing when disposed.
pub fn empty_disposable() -> Disposable {
  Disposable(dispose: fn() { Nil })
}

/// Combine multiple disposables into one.
/// When disposed, all inner disposables are disposed.
pub fn composite_disposable(disposables: List(Disposable)) -> Disposable {
  Disposable(dispose: fn() {
    dispose_all(disposables)
  })
}

fn dispose_all(disposables: List(Disposable)) -> Nil {
  case disposables {
    [] -> Nil
    [Disposable(dispose), ..rest] -> {
      dispose()
      dispose_all(rest)
    }
  }
}

/// Observer receives notifications from an Observable.
///
/// The Rx contract guarantees:
/// - on_next may be called zero or more times
/// - on_error or on_completed is called at most once (terminal)
/// - No calls occur after a terminal event
pub type Observer(a) {
  Observer(
    on_next: fn(a) -> Nil,
    on_error: fn(String) -> Nil,
    on_completed: fn() -> Nil,
  )
}

/// Create an observer from notification handler function.
pub fn observer_from_notify(notify: fn(Notification(a)) -> Nil) -> Observer(a) {
  Observer(
    on_next: fn(x) { notify(OnNext(x)) },
    on_error: fn(err) { notify(OnError(err)) },
    on_completed: fn() { notify(OnCompleted) },
  )
}

/// Observable is a source of asynchronous events.
/// Subscribe with an Observer to receive notifications.
pub type Observable(a) {
  Observable(subscribe: fn(Observer(a)) -> Disposable)
}

/// AsyncObserver wraps an Observer where callbacks may involve
/// sending messages to processes (async in BEAM terms).
pub type AsyncObserver(a) {
  AsyncObserver(
    on_next: fn(a) -> Nil,
    on_error: fn(String) -> Nil,
    on_completed: fn() -> Nil,
  )
}
