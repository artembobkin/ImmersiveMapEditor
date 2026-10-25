/// The version of what `tilepipeline` takes and says (its commands, their
/// arguments, its @progress lines). The editor runs the `tilepipeline`
/// beside it and checks this against its own, both built from this file: a
/// pipeline built before a change of either would take the editor's
/// commands wrong. Raise it with every such change.
public enum PipelineInterface {
    /// 2: a tile's own folder (seed Z X Y, migrate, bake), @progress lines.
    public static let version = 2
}
