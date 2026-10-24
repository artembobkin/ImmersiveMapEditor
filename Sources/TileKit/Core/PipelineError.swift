import Foundation

/// An error of the pipeline, said in words.
public struct PipelineError: Error, CustomStringConvertible {
    public let description: String
    public init(_ s: String) { description = s }
}
