/// The tag sets of the MuvLanes oracle tests: written by hand, one or more
/// per feature of Muv's lane reading, and drawn at random from a
/// vocabulary of the lane keys and their typical (and odd) values.

import Foundation

enum MuvTagSets {
    private static func t(_ s: String) -> [(String, String)] {
        s.split(separator: " ").map { kv in
            let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], parts[1].replacingOccurrences(of: "_SP_", with: " "))
        }
    }

    /// Space-separated `key=value` pairs; `_SP_` in a value is a space.
    static let handWritten: [[(String, String)]] = [
        // Classes and defaults.
        "highway=residential", "highway=primary", "highway=secondary", "highway=tertiary", "highway=unclassified",
        "highway=motorway", "highway=motorway_link", "highway=trunk", "highway=trunk_link", "highway=primary_link",
        "highway=service", "highway=service service=parking_aisle", "highway=living_street", "highway=pedestrian",
        "highway=footway", "highway=footway footway=sidewalk", "highway=cycleway", "highway=path", "highway=steps",
        "highway=track", "highway=busway", "highway=steps ramp:wheelchair=yes", "highway=steps ramp:bicycle=yes",
        "highway=steps ramp=yes", "highway=steps ramp:luggage=automatic ramp=yes", "highway=steps ramp:stroller=yes",
        "highway=path bicycle=designated foot=designated segregated=yes",
        "highway=path bicycle=designated foot=designated segregated=no",
        "highway=cycleway oneway=yes foot=permissive segregated=yes",
        "highway=cycleway is_sidepath=yes", "highway=residential motorroad=yes",
        "highway=residential bicycle_road=yes", "highway=residential cyclestreet=yes",
        "highway=footway public_transport=platform",
        "highway=construction construction=residential", "highway=construction construction=primary lanes=4",
        "highway=primary construction=yes", "highway=residential disused=yes abandoned=yes",
        // Lane counts and directions.
        "highway=primary lanes=4", "highway=primary lanes=3", "highway=primary lanes=5 lanes:backward=2",
        "highway=primary lanes=3 lanes:forward=2", "highway=primary lanes=1", "highway=primary lanes=100",
        "highway=primary lanes=0", "highway=primary lanes=+3", "highway=primary lanes=-1", "highway=primary lanes=2.5",
        "highway=primary lanes=6 lanes:forward=3 lanes:backward=2 lanes:both_ways=1",
        "highway=primary lanes=3 lanes:both_ways=1", "highway=secondary centre_turn_lane=yes",
        "highway=secondary center_turn_lane=yes lanes=3", "highway=residential priority=forward",
        "highway=primary oneway=yes lanes=3", "highway=primary oneway=-1 lanes=2", "highway=primary oneway=reversible lanes=2",
        "highway=primary oneway=alternating", "highway=primary oneway=no", "highway=primary oneway=yes oneway:bicycle=no",
        "highway=residential oneway=yes oneway:bus=no lanes=2 lanes:forward=1 lanes:backward=1",
        "highway=primary oneway=yes oneway:conditional=no_SP_@_SP_(Mo-Fr_SP_07:00-19:00)",
        "highway=residential junction=roundabout", "highway=residential junction=circular lanes=2",
        "highway=primary oneway=yes lanes=3 placement=right_of:1", "highway=primary lanes=3 placement=middle_of:2",
        "highway=primary lanes=3 lanes:backward=2 placement:backward=middle_of:2",
        "highway=primary lanes=2 placement:forward=middle_of:2", "highway=primary lanes=4 placement:forward=left_of:1",
        "highway=primary lanes=4 placement=transition",
        // Per-lane keys.
        "highway=secondary_link oneway=yes lanes=2 turn:lanes=left|right",
        "highway=primary lanes=4 turn:lanes:forward=left|through;right turn:lanes:backward=through|through;left",
        "highway=primary oneway=yes lanes=3 turn:lanes=slight_left|slight_right|merge_to_left",
        "highway=primary oneway=yes lanes=3 turn:lanes=sharp_left|sharp_right|reverse",
        "highway=primary oneway=yes lanes=2 turn:lanes=none|",
        "highway=primary oneway=yes lanes=3 turn:lanes=left|through",
        "highway=primary lanes=4 turn:lanes:forward=left|through|right",
        "highway=primary turn=left", "highway=primary turn:forward=through turn:backward=through",
        "highway=primary oneway=yes lanes=2 change:lanes=not_right|no",
        "highway=primary oneway=yes lanes=2 width:lanes=3.5|3", "highway=primary oneway=yes lanes=2 surface:lanes=asphalt|sett",
        "highway=primary oneway=yes lanes=2 smoothness:lanes=good|bad",
        "highway=primary lanes=4 bus:lanes:forward=no|designated", "highway=primary lanes=4 psv:lanes:backward=designated|yes",
        "highway=residential lanes=4 lanes:bus:forward=1", "highway=primary lanes=4 lanes:psv=2",
        "highway=secondary bus:lanes:forward=no|yes bus:lanes:backward=no|yes bus:lanes:forward:conditional=(yes|designated)_SP_@_SP_(Mo-Fr_SP_06:00-09:00) bus:lanes:backward:conditional=(yes|designated)_SP_@_SP_(Mo-Fr_SP_14:00-18:00)",
        "highway=primary oneway=yes lanes=3 hgv:lanes=no|yes|yes bus:lanes=yes|designated",
        "highway=primary oneway=yes lanes=2 vehicle:lanes=yes|no bicycle:lanes=yes|designated",
        "highway=primary oneway=yes lanes=3 access:lanes=yes|no|yes",
        "highway=primary oneway=yes lanes=2 maxspeed:lanes=60|80", "highway=primary oneway=yes lanes=2 maxheight:lanes=3|4",
        "highway=primary oneway=yes lanes=2 maxweight:lanes=3.5|7.5 maxwidth:lanes=2|3 maxlength:lanes=10|20",
        "highway=primary oneway=yes lanes=2 maxdraught:lanes=1|2 maxdraught=3",
        "highway=primary oneway=yes lanes=2 overtaking:lanes=no|yes",
        "highway=primary oneway=yes lanes=2 priority_road:lanes=yes|designated",
        "highway=primary oneway=yes lanes=2 minspeed:lanes=40|60",
        // Access.
        "highway=residential access=no bicycle=designated", "highway=footway access=permissive", "highway=cycleway access=yes",
        "highway=residential access=private", "highway=residential motor_vehicle=no", "highway=residential vehicle=destination",
        "highway=residential hgv=no goods=delivery", "highway=residential bus=designated psv=yes",
        "highway=service access=customers", "highway=primary foot=no bicycle=no",
        "highway=residential tricycle=no auto_rickshaw=yes", "highway=residential Bus=no bus=yes",
        "highway=residential BICYCLE=no", "highway=residential ski=yes ski:nordic=no hazmat=no hazmat:water=yes hazmat:C=no",
        "highway=residential access:conditional=no_SP_@_SP_(22:00-06:00)",
        "highway=residential motor_vehicle:conditional=no_SP_@_SP_(Mo-Fr_SP_07:00-19:00;_SP_Sa_SP_08:00-14:00)",
        "highway=residential hgv:conditional=no_SP_@_SP_(weight_SP_>_SP_7.5) bus:conditional=yes_SP_@_SP_wet",
        "highway=residential access:forward=no access:backward=yes", "highway=residential bicycle:backward=yes oneway=yes",
        "highway=residential motorcar:forward=no", "highway=residential access=agricultural;forestry",
        // Speeds.
        "highway=primary maxspeed=60", "highway=primary maxspeed=30_SP_mph", "highway=primary maxspeed=walk",
        "highway=primary maxspeed=RU:urban", "highway=primary maxspeed=DE:zone30", "highway=primary maxspeed=DE:zone:30",
        "highway=primary maxspeed=FR:rural", "highway=primary maxspeed=none", "highway=primary maxspeed=signals",
        "highway=primary maxspeed=50_SP_km/h", "highway=primary maxspeed=50kmh", "highway=primary maxspeed=10_SP_knots",
        "highway=primary maxspeed:type=FR:rural maxspeed=100", "highway=motorway maxspeed=10",
        "highway=primary maxspeed:type=RU:rural", "highway=primary source:maxspeed=RU:urban",
        "highway=primary zone:maxspeed=DE:30 zone:traffic=DE:urban", "highway=primary maxspeed:source=GB:nsl_single",
        "highway=primary maxspeed=70_SP_mph maxspeed:conditional=65_SP_mph_SP_@_SP_((sunset+01:30)-(sunrise-01:30))",
        "highway=primary maxspeed=100 maxspeed:conditional=60_SP_@_SP_(22:00-05:00_SP_AND_SP_weight>7.5)",
        "highway=primary maxspeed=30 maxspeed:conditional=20_SP_@_SP_(Sa,Su_SP_\"weekend_SP_);\")",
        "highway=primary maxspeed=90 maxspeed:conditional=80_SP_@_SP_wet)", "highway=primary maxspeed:forward=60 maxspeed:backward=40",
        "highway=primary maxspeed:hgv=60 maxspeed:bus=70", "highway=primary maxspeed:hgv:conditional=50_SP_@_SP_wet",
        "highway=primary minspeed=40", "highway=motorway minspeed=60 maxspeed=130", "highway=living_street maxspeed=20",
        "highway=service maxspeed=10", "highway=pedestrian maxspeed=walk",
        "highway=motorway maxspeed:conditional=100_SP_@_SP_(06:00-22:00);_SP_80_SP_@_SP_snow",
        // Conditions of every kind.
        "highway=residential maxweight=3.5 maxweight:conditional=7.5_SP_@_SP_(Mo-Fr_SP_07:00-19:00);_SP_12_SP_@_SP_wet",
        "highway=residential maxweight=3.5_SP_t maxaxleload=10 maxlength=12 maxwidth=2.5 maxheight=4.0",
        "highway=residential maxheight=12'6\" maxwidth=7'", "highway=residential maxheight=default maxwidth=below_default",
        "highway=residential maxweight=5000_SP_kg maxweight:hgv=7.5 maxlength=40_SP_ft",
        "highway=residential hgv:conditional=no_SP_@_SP_(length>12)_SP_AND_SP_(axles>=3)",
        "highway=residential bus:conditional=designated_SP_@_SP_(Mo-Fr_SP_06:00-09:00,16:00-19:00)",
        "highway=residential access:conditional=destination_SP_@_SP_(stay_SP_<_SP_2_SP_hours)",
        "highway=residential access:conditional=no_SP_@_SP_(winter);_SP_yes_SP_@_SP_(summer)",
        "highway=residential vehicle:conditional=no_SP_@_SP_(trailer);_SP_no_SP_@_SP_caravan;_SP_no_SP_@_SP_articulated",
        "highway=residential vehicle:conditional=no_SP_@_SP_(occupants<2) hov:conditional=designated_SP_@_SP_(seats>=7)",
        "highway=residential vehicle:conditional=no_SP_@_SP_(wheels=2) access:conditional=delivery_SP_@_SP_customers",
        "highway=residential vehicle:conditional=no_SP_@_SP_(emptyweight>3) goods:conditional=no_SP_@_SP_(weightcapacity>2)",
        "highway=residential hgv:conditional=no_SP_@_SP_(trailers>1) hgv:lanes:conditional=no|yes_SP_@_SP_wet",
        "highway=residential access:conditional=no_SP_@_SP_(Jan-Mar) bus:conditional=yes_SP_@_SP_(2024_SP_Mar_SP_10-Apr_SP_02)",
        "highway=residential access:conditional=no_SP_@_SP_(easter) motorcar:conditional=no_SP_@_SP_(PH)",
        "highway=residential access:conditional=no_SP_@_SP_(Su[1,-1]) hgv:conditional=no_SP_@_SP_(week_SP_01-10/2)",
        "highway=residential access:conditional=no_SP_@_SP_(\"closed_SP_for_SP_works\") bus:conditional=yes_SP_@_SP_(24/7)",
        "highway=residential access:conditional=no_SP_@_SP_(sunrise-sunset) hgv:conditional=no_SP_@_SP_(dawn-dusk)",
        "highway=residential access:conditional=no_SP_@_SP_(10:00-48:30) hgv:conditional=no_SP_@_SP_(10:00-28:00)",
        "highway=residential access:conditional=no_SP_@_SP_(Mo-Fr_SP_08:00-12:00_SP_off) hgv:conditional=no_SP_@_SP_(SH)",
        "highway=residential access:conditional=no_SP_@_SP_(Mo_SP_+1_SP_day) hgv:conditional=no_SP_@_SP_(PH_SP_-1_SP_day)",
        "highway=residential access:conditional=no_SP_@_SP_(Dec_SP_25-26) hgv:conditional=no_SP_@_SP_(2020-2030/2)",
        "highway=residential access:conditional=no_SP_@_SP_(nonsense) hgv:conditional=no_SP_@_SP_() bus:conditional=@_SP_wet",
        "highway=residential access:conditional=no_SP_@_SP_(10:00+) hgv:conditional=no_SP_@_SP_(10:00-12:00/30)",
        "highway=residential access:conditional=no_SP_@_SP_(Mo-Fr_SP_10:00-12:00,14:00-16:00_SP_||_SP_\"call\")",
        // Sidewalks, cycleways, side lanes.
        "highway=residential sidewalk=both", "highway=residential sidewalk=left", "highway=residential sidewalk=right",
        "highway=residential sidewalk=no", "highway=residential sidewalk=separate", "highway=residential sidewalk=yes",
        "highway=residential sidewalk:left=yes sidewalk:right=separate", "highway=residential sidewalk:both=yes",
        "highway=residential sidewalk=both sidewalk:both:surface=paving_stones sidewalk:left:width=2",
        "highway=residential sidewalk=right sidewalk:right:surface=paving_stones sidewalk:right:bicycle=yes sidewalk:right:segregated=no cycleway:right=track cycleway:right:surface=asphalt",
        "highway=residential cycleway:left=track cycleway:left:surface=asphalt cycleway:left:foot=designated cycleway:left:segregated=no sidewalk=left",
        "highway=residential sidewalk=left sidewalk:left:bicycle=yes sidewalk:left:oneway=-1",
        "highway=residential cycleway=lane", "highway=residential cycleway=track", "highway=residential cycleway=opposite_lane oneway=yes",
        "highway=residential cycleway=opposite_track oneway=yes", "highway=residential cycleway=share_busway",
        "highway=residential cycleway:left=lane cycleway:right=track", "highway=residential cycleway:both=lane",
        "highway=residential cycleway:left=opposite_lane cycleway:right=track",
        "highway=residential oneway=yes cycleway:left=track cycleway:left:oneway=no",
        "highway=residential cycleway:left=lane cycleway:left:buffer=0.2 cycleway:right=track cycleway:right:buffer=0.75",
        "highway=residential cycleway:left=opposite_track cycleway:left:oneway=-1 cycleway:left:foot=designated cycleway:left:bicycle=designated cycleway:left:segregated=yes",
        "highway=residential cycleway:left=track cycleway:left:segregated=yes",
        "highway=residential cycleway:right=track cycleway:right:width=2 cycleway:right:surface=asphalt cycleway:right:smoothness=good",
        "highway=secondary lanes:backward=2 cycleway:left=lane cycleway:right=lane cycleway:lanes:forward=lane|no vehicle:lanes:forward=no|yes bicycle:lanes:forward=designated|yes",
        "highway=secondary cycleway:left=lane cycleway:right=lane bicycle:lanes:forward=yes|designated|yes",
        "highway=secondary oneway=yes cycleway:right=lane cycleway:lanes=no|lane|no vehicle:lanes=yes|no|yes bicycle:lanes=no|designated|yes",
        "highway=cycleway oneway=yes cycleway=lane", "highway=cycleway sidewalk=left oneway=yes segregated=yes",
        "highway=footway sidewalk=both", "highway=primary busway=lane", "highway=primary busway:left=lane lanes=4",
        "highway=secondary busway:left=lane bus:lanes:backward=yes|designated", "highway=primary busway=opposite_lane oneway=yes",
        "highway=primary busway:both=lane bus:lanes=yes|designated", "highway=primary busway:right=lane psv:lanes:forward=yes|designated",
        "highway=primary bus_bay=left bus_bay:right=lane", "highway=primary bus_bay=both", "highway=primary bus_bay=right",
        "highway=primary shoulder=both", "highway=primary shoulder=right shoulder:right:width=1.5", "highway=primary shoulder:left=yes",
        // Parking.
        "highway=residential parking:left=lane parking:left:orientation=parallel parking:left:markings=yes parking:left:direction=head_in parking:right=no",
        "highway=residential parking:both=lane parking:left:orientation=parallel parking:right:orientation=diagonal",
        "highway=residential parking:both=lane", "highway=residential parking:lane:both=parallel",
        "highway=residential parking:lane:right=parallel parking:lane:right:parallel=street_side parking:condition:right:maxstay=5_SP_minutes",
        "highway=residential parking:lane:left=diagonal parking:lane:left:diagonal=on_kerb parking:condition:left=ticket",
        "highway=residential parking:lane:right=marked parking:condition:right=residents parking:lane:right:residents=A;B",
        "highway=residential parking:lane:both=perpendicular parking:lane:both:perpendicular=half_on_kerb parking:condition:both=no_stopping",
        "highway=residential parking:lane:right=yes parking:condition:right=free;disc parking:lane:right:capacity=5",
        "highway=residential lanes=2 sidewalk=both parking:left=half_on_kerb", "highway=residential parking:right=on_kerb",
        "highway=residential parking:left=street_side parking:right=lay_by parking:right:width=3",
        "highway=residential parking:right=lane parking:right:capacity=10 parking:right:capacity:disabled=2 parking:right:capacity:women=yes parking:right:capacity:charging=no",
        "highway=residential parking:right=lane parking:right:zone=II;;III parking:right:restriction=no_stopping parking:right:maxstay=2_SP_h",
        "highway=residential parking:right=lane parking:right:access=private parking:right:motorcar=yes parking:right:restriction:conditional=loading_only_SP_@_SP_(Mo-Fr_SP_08:00-12:00)",
        "highway=residential parking:left=shoulder parking:right=yes", "highway=residential parking:right=no parking:left=separate",
        "highway=primary width=8 vehicle:lanes:forward=yes|no bicycle:lanes:forward=yes|designated parking:right=lane parking:right:width=3",
        // Widths and surfaces.
        "highway=primary width=10.5 lanes=3", "highway=primary width:carriageway=7 width=12", "highway=primary est_width=6",
        "highway=primary width=7_SP_m", "highway=primary width=20'", "highway=primary width=wide", "highway=primary width=3.20",
        "highway=residential width=6 sidewalk=both sidewalk:both:width=2", "highway=footway width=3",
        "highway=residential surface=asphalt surface:colour=#f0a smoothness=excellent",
        "highway=residential surface=paving_stones surface:colour=red", "highway=residential surface=concrete:plates",
        "highway=residential surface=earth smoothness=very_bad", "highway=residential surface=unknown smoothness=GOOD",
        "highway=residential surface=sett surface:colour=#123456", "highway=residential surface=asphalt surface:colour=#12",
        "highway=residential surface:forward=asphalt surface:backward=gravel",
        // Overtaking, priority, change, traffic signs.
        "highway=primary overtaking=no", "highway=primary overtaking=caution", "highway=primary overtaking=only_motorcycle",
        "highway=primary overtaking:hgv=no", "highway=primary overtaking:forward=no traffic_sign=DE:277.1",
        "highway=primary traffic_sign=DE:274;DE:277.1", "highway=primary priority_road=designated priority_road:conditional=no_SP_@_SP_wet",
        "highway=primary change=no change:forward=not_left", "highway=primary priority_road=yes_unposted",
        // Railways.
        "railway=light_rail", "railway=rail", "railway=light_rail maxspeed=80 gauge=1435", "railway=rail gauge=1435;1520",
        "railway=rail electrified=contact_line voltage=25000 frequency=50", "railway=light_rail electrified=yes voltage=750",
        "railway=rail loading_gauge:maxheight=5600 loading_gauge:maxwidth=4100 railway:preferred_direction=forward",
        "railway=rail railway:bidirectional=signals", "railway=rail railway:bidirectional=possible railway:preferred_direction=backward",
        "railway=light_rail gauge=standard", "highway=residential railway=tram",
        // Driving side and odd values.
        "highway=primary driving_side=left lanes=3", "highway=primary driving_side=right sidewalk=left",
        "highway=primary lanes=two", "highway=primary lanes:forward=2", "highway=primary lanes:backward=3",
        "highway=primary oneway=yes lanes=2 turn:lanes=left;;through|right", "highway=residential layer=1 bridge=yes",
    ].map(t)

    /// The vocabulary the random sets draw from: a key, and values to pick.
    private static let vocabulary: [(String, [String])] = [
        ("lanes", ["1", "2", "3", "4", "5", "6"]),
        ("lanes:forward", ["1", "2", "3"]), ("lanes:backward", ["1", "2"]), ("lanes:both_ways", ["1"]),
        ("oneway", ["yes", "-1", "no", "reversible"]), ("oneway:bicycle", ["no"]), ("oneway:bus", ["no"]),
        ("sidewalk", ["both", "left", "right", "no", "separate"]), ("sidewalk:left", ["yes", "separate", "no"]),
        ("sidewalk:right", ["yes", "no"]), ("sidewalk:both:surface", ["paving_stones"]),
        ("cycleway", ["lane", "track", "opposite_lane", "share_busway", "no"]),
        ("cycleway:left", ["lane", "track", "opposite_track"]), ("cycleway:right", ["lane", "track"]),
        ("cycleway:both", ["lane"]), ("cycleway:right:segregated", ["yes", "no"]), ("cycleway:left:oneway", ["no", "-1"]),
        ("cycleway:right:buffer", ["0.5"]), ("cycleway:right:width", ["1.5", "2"]),
        ("busway", ["lane"]), ("busway:left", ["lane"]), ("busway:right", ["lane"]),
        ("bus:lanes", ["yes|designated", "designated|yes|yes"]), ("bus:lanes:forward", ["no|designated", "yes|designated"]),
        ("bus:lanes:backward", ["designated|yes"]), ("psv:lanes", ["yes|designated"]), ("psv:lanes:forward", ["yes|designated"]),
        ("hgv:lanes", ["no|yes", "no|yes|yes"]), ("bicycle:lanes", ["no|designated", "yes|designated|yes"]),
        ("vehicle:lanes:forward", ["no|yes", "yes|no"]), ("taxi:lanes", ["yes|no"]), ("motorcar:lanes", ["yes|no|yes"]),
        ("turn:lanes", ["left|through", "left|through|right", "through;right|right", "left|", "none|none"]),
        ("turn:lanes:forward", ["left|through", "through|through;right"]), ("turn:lanes:backward", ["left|through"]),
        ("turn", ["left", "through"]), ("width", ["6", "7.5", "10", "12 m", "20'"]), ("width:lanes", ["3|3.5", "3|3|3"]),
        ("width:carriageway", ["7"]), ("est_width", ["5"]),
        ("maxspeed", ["30", "40", "60", "30 mph", "walk", "RU:urban", "DE:zone30", "none"]), ("maxspeed:type", ["RU:urban", "RU:rural"]),
        ("maxspeed:forward", ["60"]), ("maxspeed:backward", ["40"]), ("maxspeed:hgv", ["50"]), ("maxspeed:lanes", ["60|80"]),
        ("maxspeed:conditional", ["30 @ (Mo-Fr 07:00-19:00)", "50 @ wet", "40 @ (weight>3.5)"]),
        ("minspeed", ["30"]), ("source:maxspeed", ["RU:urban", "RU:living_street"]),
        ("access", ["no", "yes", "private", "destination", "permissive"]), ("motor_vehicle", ["no", "destination"]),
        ("vehicle", ["no"]), ("bicycle", ["yes", "no", "designated", "dismount"]), ("foot", ["yes", "no", "designated"]),
        ("bus", ["yes", "designated"]), ("psv", ["yes"]), ("hgv", ["no", "destination"]), ("motorcar", ["no"]),
        ("tricycle", ["no", "yes"]), ("auto_rickshaw", ["yes", "no"]), ("Bus", ["no"]), ("taxi", ["yes"]),
        ("access:conditional", ["no @ (22:00-06:00)", "delivery @ (Mo-Sa 06:00-11:00)"]),
        ("hgv:conditional", ["no @ (weight > 7.5)"]), ("access:lanes", ["yes|no"]), ("bus:lanes:conditional", ["designated|yes @ (Mo-Fr 07:00-10:00)"]),
        ("parking:left", ["lane", "street_side", "half_on_kerb", "on_kerb", "no"]), ("parking:right", ["lane", "no", "separate"]),
        ("parking:both", ["lane", "no"]), ("parking:left:orientation", ["parallel", "diagonal", "perpendicular"]),
        ("parking:right:orientation", ["diagonal"]), ("parking:lane:both", ["parallel", "no"]),
        ("parking:lane:right", ["diagonal", "marked"]), ("parking:condition:right", ["ticket", "residents", "no_parking"]),
        ("parking:right:capacity", ["4"]), ("parking:right:width", ["2.5"]),
        ("bus_bay", ["left", "right", "both"]), ("shoulder", ["right", "both", "no"]),
        ("surface", ["asphalt", "paving_stones", "sett", "concrete", "gravel"]), ("smoothness", ["good", "bad"]),
        ("surface:lanes", ["asphalt|sett"]), ("segregated", ["yes", "no"]), ("placement", ["right_of:1", "middle_of:1", "transition"]),
        ("placement:forward", ["middle_of:1", "left_of:1"]), ("junction", ["roundabout"]), ("centre_turn_lane", ["yes"]),
        ("overtaking", ["no", "caution"]), ("maxweight", ["3.5", "7.5 t"]), ("maxheight", ["4", "3.8"]),
        ("priority", ["forward"]), ("motorroad", ["yes"]), ("cyclestreet", ["yes"]), ("construction", ["yes"]),
        ("is_sidepath", ["yes"]), ("footway", ["sidewalk", "crossing"]), ("public_transport", ["platform"]),
    ]

    private static let classes = ["residential", "primary", "secondary", "tertiary", "unclassified", "service", "trunk",
                                  "motorway", "living_street", "pedestrian", "footway", "cycleway", "path", "steps",
                                  "track", "busway", "primary_link", "motorway_link"]

    /// `count` sets of a highway class and two to nine keys of the
    /// vocabulary, from a SplitMix64 stream seeded with `seed`.
    static func random(count: Int, seed: UInt64) -> [[(String, String)]] {
        var state = seed
        func next() -> UInt64 {
            state &+= 0x9e37_79b9_7f4a_7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
            z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
            return z ^ (z >> 31)
        }
        func pick(_ n: Int) -> Int { Int(next() % UInt64(n)) }
        var res: [[(String, String)]] = []
        for _ in 0..<count {
            var set: [(String, String)] = [("highway", classes[pick(classes.count)])]
            var keys: Set<String> = ["highway"]
            for _ in 0..<(2 + pick(8)) {
                let (k, values) = vocabulary[pick(vocabulary.count)]
                if keys.insert(k).inserted { set.append((k, values[pick(values.count)])) }
            }
            res.append(set)
        }
        return res
    }
}
