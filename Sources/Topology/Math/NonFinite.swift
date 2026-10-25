import Darwin

/// GEOS 3.13's failure on a non-finite coordinate in its orientation test.
///
/// GEOS's `CGAlgorithmsDD::orientationIndex` throws when the tested point
/// has a NaN or infinite ordinate (and `signOfDet2x2` on any non-finite
/// value); JTS computes on. The port's predicates do not throw (making them
/// throw would change every caller), so the throw is emulated: the
/// predicate raises a flag of the current thread and computes on, and each
/// place where GEOS would catch or report the exception runs its body in
/// `scope`, which turns a raised flag into the error GEOS throws. What the
/// port computes between the raise and the scope's end is discarded, as
/// GEOS unwinds it. Only non-finite input reaches this.
public enum NonFinite {
    static let message = "CGAlgorithmsDD::orientationIndex encountered NaN/Inf numbers"

    private static let key: pthread_key_t = {
        var k = pthread_key_t()
        pthread_key_create(&k, nil)
        return k
    }()

    /// Raises the flag (the predicate's throw).
    static func raise() {
        trace?()
        pthread_setspecific(key, UnsafeRawPointer(bitPattern: 1))
    }

    /// Called at each raise, when set (a test's probe).
    nonisolated(unsafe) public static var trace: (() -> Void)?

    static var isRaised: Bool { pthread_getspecific(key) != nil }

    private static func set(_ raised: Bool) { pthread_setspecific(key, raised ? UnsafeRawPointer(bitPattern: 1) : nil) }

    /// Runs `body` and tells whether a non-finite coordinate reached the
    /// orientation test inside it, for a computation that cannot go on past
    /// GEOS's throw (its result is discarded by the enclosing scope). The
    /// flag stays raised when it was raised inside or before.
    static func watch<T>(_ body: () -> T) -> (result: T, raised: Bool) {
        let outer = isRaised
        if outer { set(false) }
        let result = body()
        let raised = isRaised
        set(outer || raised)
        return (result, raised)
    }

    /// Runs `body`; if a non-finite coordinate reached the orientation test
    /// inside it, throws GEOS's error instead of its result or error.
    public static func scope<T>(_ body: () throws -> T) throws -> T {
        let outer = isRaised
        if outer { set(false) }
        let result = Result { try body() }
        let raised = isRaised
        set(outer)
        if raised { throw IllegalArgumentException(message) }
        return try result.get()
    }
}
