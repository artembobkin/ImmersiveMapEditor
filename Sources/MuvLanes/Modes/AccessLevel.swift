/// muv-osm's `AccessLevel` (`access.rs`): the values of OSM's access keys.
///
/// This Source Code Form is subject to the terms of the Mozilla Public
/// License, v. 2.0. If a copy of the MPL was not distributed with this
/// file, You can obtain one at https://mozilla.org/MPL/2.0/.

public enum AccessLevel: Int, SimpleEnum, Sendable {
    case designated, yes, permissive, discouraged, permit, `private`, no
    case dismount, useSidepath
    case destination, customers
    case delivery, agricultural, forestry, military
    case variable, escape
    case unknown

    public static let rustNames = [
        "Designated", "Yes", "Permissive", "Discouraged", "Permit", "Private", "No",
        "Dismount", "UseSidepath",
        "Destination", "Customers",
        "Delivery", "Agricultural", "Forestry", "Military",
        "Variable", "Escape",
        "Unknown",
    ]
    public static let osmNames = makeOsmNames()
}
