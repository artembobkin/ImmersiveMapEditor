import Foundation
import Geometry

/// The recipe's format and the style, in the words the landmarks' agent
/// reads them (get_landmark gives it): every word of a recipe, what the
/// generator makes of it, and the rules a recipe is refused by.
extension LandmarkRecipe {
    /// The format and the style, as the landmarks' agent is told them.
    public static let guide = """
    THE RECIPE (recipe.json): a stylized low-poly model of the landmark, in one cartoon style shared by every landmark of the map. \
    You choose the words below; the generator builds the geometry, so keep to them. Places are metres east (x) and north (y) of the \
    landmark's centre, heights metres above the ground. Every colour is one of the palette's landmark colours by name: \
    \(colourList).

    {"version": 1,
     "masses": [{"id": "portico-base", "outline": "way/123"  (an OSM element of the landmark: its outer ring)
                   or "polygon": [[x, y], ...]  (a ring of your own, for a volume OSM does not draw),
                 "base": 0, "top": 23, "colour": "lm_cream",
                 "plinth": {"height": 1.5, "depth": 0.15, "colour": "lm_stone"},
                 "cornice": {"height": 0.8, "depth": 0.4, "colour": "lm_white"},
                 "windows": {"storeys": 3, "spacing": 3.5, "width": 1.4, "height": 2.4, "arched": false},
                 "doors": [{"at": [x, y], "width": 2.4, "height": 4, "depth": 0.6, "arched": true, "portal": 0.35, "colour": "lm_dark"},
                           {"at": [x, y], "sill": 9, "width": 1.6, "height": 2.8, "arched": true, "glass": true}],
                 "pilasters": {"spacing": 3.5, "width": 1.0, "depth": 0.3, "colour": "lm_white"},
                 "bands": {"height": 0.3, "depth": 0.15, "colour": "lm_white"},
                 "roof": {"shape": "flat|gabled|skillion|hipped|mansard|vault|pyramidal|dome|onion|spire", "height": 6, "colour": "lm_stone",
                          "overhang": 0.6, "parapet": 1.0}}],
     "features": [{"kind": "colonnade", "from": [x, y], "to": [x, y], "base": 1.5, "height": 15, "columns": 8, "radius": 0.7, "colour": "lm_white"},
                  {"kind": "pediment", "from": [x, y], "to": [x, y], "base": 18, "height": 4, "depth": 2, "colour": "lm_cream"},
                  {"kind": "statue", "shape": "quadriga", "at": [x, y], "heading": 180, "base": 23, "pedestal": 1, "height": 5, "width": 8, "colour": "lm_dark"},
                  {"kind": "box", "polygon": [[x, y], ...], "base": 0, "top": 2, "colour": "lm_stone"},
                  {"kind": "steps", "from": [x, y], "to": [x, y], "depth": 4, "height": 1.5, "count": 5, "colour": "lm_stone"}]}

    - A wall is one wall. A building's walls are its OSM outline, and every stretch of them belongs to one mass: no two \
    masses may run along the same wall (a part drawn as its own polygon beside the outline's mass would put two grids \
    of windows on one wall; the build refuses it). A building of parts with different heights, windows or roofs is one \
    outline cut into them: a part is the outline with `cuts` (a straight line through it, from and to, and a point on \
    the side to `keep`; several cuts for a corner part), and the rest of the outline is the outline `minus` those parts' \
    ids. The parts meet on the cut and the generator joins them. An outline is one ring around the whole block, its \
    courtyards and all: where the parts enclose a courtyard open to the sky (get_landmark names each, with its ring and \
    its floor: the ground, or the roof of the podium its garden lies on), what is under it ends at the floor, the \
    wings around it are masses cut from the outline, one a side, each `minus` the ones before it where they overlap at \
    the corners, and no mass rises over the courtyard (the build refuses one). A `polygon` of its own is only for what OSM has no \
    outline of (a tower on the roof, a dome's drum, a porch), and it must stand clear of the outline's walls or on its \
    own. The model is one shell: every mass and shape is a closed solid, and all of them are united. Masses that touch \
    must overlap: a tower sinks half a metre into its base, never with a slot between them (the generator sinks a \
    corner that stands on or near a neighbour's wall into it, but do not count on it). A mass is a prism of its outline from base to top, its walls in its colour, with an optional plinth and cornice band \
    standing proud, windows storey by storey on every wall long enough, and a roof on its top. A window is a recess cut \
    into the wall (the map's style): reveals and glass in tones of the wall, a light sill, and a surround, jambs and a \
    lintel standing a little proud, in `windows.colour` (lm_white unless given; `"surround": false` for a plain modern \
    wall). A cornice is drawn as a profile of three steps up and out. Give windows only to a mass that \
    reads as storeys of windows, with the storeys and spacing the photos show. A window that the rows cannot place (one \
    between pilasters, a single large window, a window of its own above a door) is a door with a `sill` (metres above \
    the plinth's top): cut in at that place, glass at its back, as the rows' windows are; from 10 m² (a shop front, a glazed \
    arch, a glass wall between piers) its back is the map's glass, lm_glass, which reads as glass from afar where a wall's dark tone reads as a hole. A door is an entrance cut into the wall \
    nearest its `at` (a point on or by that wall), from the ground up through the plinth, deeper than a window, its leaf at \
    the back (glass when `glass` is true, a glazed entrance) and a portal standing proud around it: every building has its entrances where the photos show them. \
    A plinth is a blind base, 3 m at most. A ground floor of its own colour, a rusticated or granite base with its shop fronts, \
    arches or windows, is a mass of its own from the ground to its top, with its windows and doors, and the body a mass \
    from there up on the same outline, its base at the ground floor's top, the generator makes them touch and joins them (the build refuses a \
    taller plinth: a building on 8 m of blind wall stands on a pedestal). Pilasters are vertical strips standing \
    proud of the walls (between the windows when they share the spacing); bands are string courses at the storey lines. \
    Give every size as the building has it: the generator draws the map's caricature itself, every cornice, band, pilaster, \
    portal, parapet and recess at least about half a metre to a metre, and windows a little larger, so a detail reads from afar. \
    A pitched roof has eaves 0.6 m beyond the walls with a fascia (`overhang` to change); a flat roof always gets a \
    parapet with a light rim (give `parapet` its height when the photos show a taller one). A flat roof's colour is the \
    map's own roof grey, lm_roof: leave it out unless satellite_view reads a colour of its own off the imagery (lm_green \
    or lm_dark_green green, lm_red red; a dark metal roof is lm_stone, never lm_dark, which reads as a hole from above); a pitched roof's colour is what the imagery reads (lm_stone grey \
    metal too), given for every mass: never a guess. A historic building never ends in a bare flat cap: a parapet, a balustrade of shapes, or a \
    pitched roof with its eaves, so the roof reads as a volume of its own. Gabled, skillion (one slope, \
    rising across the short side), hipped and mansard roofs rise over the outline's smallest rectangle (the ridge along its long side); dome, onion, spire and pyramidal draw the \
    outline in to a point, so give them a round or square outline. A vault is a barrel vault along the outline's long side, `height` high (half its width unless given): in lm_glass a glazed vault with its ribs and rails, as the galleries of a passage or a station hall. A glass roof is always a vault, never gabled or flat planes of lm_glass, which read as blue slabs. A roof's height defaults to the outline's size.
    - A statue is a sculpture by its shape: figure (a standing person), horse, quadriga (a chariot drawn by four horses, \
    as over a theatre's portico), equestrian (a rider on a horse), obelisk, cross (a church's), star (a tower's or a store's), flame (a \
    monument's gilded tip), crescent (a crescent with a star in it, a mosque's, open at the top, on a pole). It faces \
    `heading` (a compass bearing: 0 north, 90 east, 180 south), stands at `at` on `base` (the top of the mass or pediment \
    under it) with an optional `pedestal`, `height` tall and about `width` wide. Use it for the sculpture that makes the \
    building recognisable, nothing else. Figures, horses and chariots are drawn as round solids with real silhouettes, a star faceted with a ridge along each ray, a cross with flared ends and the ball at its foot, \
    and a statue with `"emphasis": true` is drawn larger than life and finer, with more sides to its round solids. \
    A monument (get_landmark says so: a landmark of a point, its ring the plot round it, not a wall) has no masses: its \
    pedestal is a box, a cylinder, a prism or a loft shape standing on the ground, the figure on it a statue feature where \
    one fits (figure, equestrian, obelisk, cross, star, flame) and otherwise shapes assembled (a loft or a sweep for a body, \
    cylinders for booms and barrels, thin boxes for blades, wings and plates, spheres), at its real size from the photos \
    and OSM's height, facing the heading the photos and the satellite view show.
    - Where these words do not describe the building, model it yourself from shapes, as many as it takes:
      "shapes": [
       {"kind": "box", "at": [x, y], "base": 0, "size": [along, across, up], "heading": 0, "pitch": 0, "colour": "lm_stone"},
       {"kind": "cylinder", "at": [x, y], "base": 0, "radius": 1, "radius_top": 1, "height": 10, "segments": 16, "colour": "lm_white"},
       {"kind": "cone", "at": [x, y], "base": 30, "radius": 3, "height": 6, "segments": 8, "colour": "lm_green"},
       {"kind": "sphere", "at": [x, y], "base": 30, "radius": 2, "segments": 12, "colour": "lm_gold"},
       {"kind": "dome", "at": [x, y], "base": 30, "radius": 6, "segments": 16, "colour": "lm_green"},
       {"kind": "prism", "polygon": [[x, y], ...] or "outline": "way/123", "holes": [[[x, y], ...]], "base": 0, "top": 5, "colour": "lm_cream"},
       {"kind": "loft", "radius": 4, "segments": 16, or "polygon"/"outline", "base": 30, "profile": [[1, 0], [1.2, 0.5], [0.8, 3], [0, 5]], "colour": "lm_green"},
       {"kind": "text", "text": "ЦУМ", "at": [x, y], "base": 30, "height": 3, "depth": 0.4, "heading": 180, "colour": "lm_red"},
       {"kind": "ring", "at": [x, y], "base": 30, "radius": 2.5, "depth": 0.3, "heading": 180, "segments": 24, "colour": "lm_dark"}]
      A text is its letters in a bold sans face, any script, upright and facing `heading`, `height` tall (the capitals) \
    and `depth` thick, centred on `at`, their feet on `base`: only for solid letters that really stand on the building \
    (on its roof or its cornice, on a frame of boxes), at their real size; a shop's signboard, a banner or an \
    advertisement is not modelled. \
    A ring stands upright on its base, its face toward `heading`, `radius` to the middle of its `depth`-thick \
    band (a star in a ring: the ring and a statue of shape star at the same place, the star's height twice the radius). \
    Emphasis, `"emphasis": true`, is for what stands free on or before the building and makes it recognisable from afar, \
    the one or two things a person points at: a sculpture or a finial, a statue feature (a figure, a horse, a quadriga, an \
    obelisk, a cross, a star) or a ring or a sphere shape (a star's ring, a ball finial). The generator draws it a size up \
    about its foot, so it stays on what carries it (a star on its pole on the spire's tip). Nothing else is ever emphasised, \
    in any city: the building's own body, a tower, a dome, a cone, a drum, a portico, a platform, a box, lettering, is given its \
    real size in the recipe and drawn at it, emphasis on it ignored and said back with the build. The caricature of the body comes from the \
    generator itself. \
      A shape stands at `at` (its centre in plan) on `base`, `heading` turns it (0 north, 90 east), `pitch` tips its top \
    forward (a cylinder with pitch 90 lies along its heading: a beam). A sphere stands on its base; a dome is a half \
    sphere, flat side down. A loft draws its ring toward its centre ring by ring, [scale, rise] from the base up: a drum \
    with a moulding, a vase, an onion, a tapering tower. `"repeat": {"count": 6, "step": [3.5, 0, 0]}` makes copies along \
    a step (metres east, north, up); `"around": {"count": 8, "centre": [x, y]}` makes copies turned around a point. Shapes \
    are solids: let them overlap, or sink one a little into what it stands on, rather than share a face exactly. Nothing \
    cuts a hole: an opening is a prism with holes, or a loft. An upright box or a prism takes `doors` and `windows` as a mass \
    does (a podium with its entrances, a porch, a wing OSM does not draw): an entrance is always a recess cut into the wall \
    with its leaf at the back and a portal around it, never a dark plate laid on the wall. An upright cylinder with `windows` is a \
    round bay (a tower's rounded corner, a glazed bay of flats) with a ribbon of windows a storey between its parapets, \
    its posts in `windows.colour`: a bay the photos show glazed is never a plain drum. Few large shapes before many \
    small ones, and 8 to 16 segments.
    - A colonnade stands along the line from `from` to `to`, its columns evenly spaced, a beam on top. A pediment is a triangle \
    over the line, reaching `depth` to the line's right (looking from `from` to `to`): put it on a facade's line with the \
    outside on the right. Steps rise from the ground at `depth` to the right of the line up to `height` at the line.
    - The style: few large shapes over many small ones; the silhouette, proportions, the main colours and the few details \
    that make the building recognisable from a distance (a portico, a dome, a tower, a quadriga, a glass curtain wall, a \
    spire). The building can be of any kind and age: a church (drums with domes or onions, a cross on top), a tower (a tent \
    roof, a star), a palace, a station, a department store, a modern block of glass and stone (a mass in lm_glass with no \
    windows is a curtain wall), a monument (a pedestal and a statue). Every mass, box or cylinder in lm_glass or \
    lm_sky_glass is glazed by the generator: a band at every storey and mullions every 1.5 m (`mullions` to change) in \
    `frame` (lm_dark unless given), so a curtain wall, a glass rotunda (an upright cylinder) or a glazed bay (a box \
    sunk 10 cm into the wall) reads as glass in a frame, never as a solid block. Model what is there. No textures, no fine \
    ornament. Windows only where the building reads as storeys of windows. Every model of the map looks of one family.
    - Everything is physical, as a building is, even where no photo shows it: steps lead up to a landing (a box or a \
    mass at their top height) that reaches the wall and the doors, the floor the portico's columns stand on; a colonnade \
    stands on a stylobate (a box) and carries its beam; a statue stands on a pedestal, a pediment or a roof; a balcony has \
    a floor; nothing floats and nothing ends in the air.
    - Use the OSM outlines where they are good. OSM heights can be wrong: trust the photos, and say so. A height differs \
    within one outline only where a photo shows a step in the roofline or OSM has parts of their own heights: the \
    satellite view tells roof colours and plan, never height, and a lighter patch of roof is not a lower wing (the one \
    height it shows is the shadow's length). An outline of one OSM height with no parts is one height, wing and all.
    """
}
