import TileKit

/// tilepipeline: the pipeline's commands from the command line (TileKit's
/// PipelineCommand, which documents them).
@main
enum TilePipelineCommand {
    static func main() {
        PipelineCommand.run(Array(CommandLine.arguments.dropFirst()))
    }
}
