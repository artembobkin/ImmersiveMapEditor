/// muv-osm's `Lifecycle` (`lifecycle.rs`): proposed, under construction,
/// disused and the like, and how a feature's key is read with its
/// lifecycle in OSM's three ways (`highway=construction` with
/// `construction=*`, the prefix `razed:highway=*`, and `abandoned=yes`).
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public enum Lifecycle: Int, SimpleEnum, Sendable {
    case proposed, planned, construction, normal, disused, abandoned, ruins, razed, demolished, destroyed, removed

    public static let rustNames = ["Proposed", "Planned", "Construction", "Normal", "Disused", "Abandoned", "Ruins", "Razed",
                            "Demolished", "Destroyed", "Removed"]
    public static let osmNames = makeOsmNames([.normal: []])

    /// `Lifecycle::from_osm(tags, key)`: the lifecycle, the key's value
    /// parsed by `parse`, and the key's node. Nil when the key is not there
    /// in any of the three forms.
    static func fromOsm<V>(_ tags: Tag, _ key: String, _ parse: (String) -> V?) -> (Lifecycle, V?, Tag)? {
        guard let base = tags.get(key), let baseVal = base.value else {
            // The prefix method.
            for (lifecycleStr, lifecycleBase) in tags.subtags() {
                guard let lifecycle = fromOsmStr(lifecycleStr), let base = lifecycleBase.get(key),
                      let value = base.value else { continue }
                return (lifecycle, parse(value), base)
            }
            return nil
        }
        if let lifecycle = fromOsmStr(baseVal) {
            // The value method.
            return (lifecycle, tags.getValue(baseVal).flatMap(parse), base)
        }
        // The yes method.
        var lifecycle = Lifecycle.normal
        for (lifecycleStr, value) in tags.subtags() {
            guard let v = value.value, boolFromOsmStr(v) ?? false else { continue }
            if let l = fromOsmStr(lifecycleStr) {
                lifecycle = l
                break
            }
        }
        return (lifecycle, parse(baseVal), base)
    }
}
