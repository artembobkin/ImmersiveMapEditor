/// The failures JTS signals with exceptions that its callers catch, so the
/// port throws them as errors: an assertion that failed (JTS's
/// `AssertionFailedException`), an argument out of a function's domain
/// (`IllegalArgumentException`) and a state an operation cannot go on from
/// (`IllegalStateException`). GEOS derives all of them, with its
/// `TopologyException`, from one runtime error, which the robust overlay
/// catches on its first try; its later tries catch only topology failures.
public struct AssertionFailedException: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String = "") { self.message = message }
    public var description: String { message }
}

public struct IllegalArgumentException: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public struct IllegalStateException: Error, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// JTS's `Assert`, throwing.
public enum Assert {
    public static func isTrue(_ condition: Bool, _ message: @autoclosure () -> String = "") throws {
        if !condition { throw AssertionFailedException(message()) }
    }

    public static func shouldNeverReachHere(_ message: String = "Should never reach here") -> AssertionFailedException {
        AssertionFailedException(message)
    }
}
