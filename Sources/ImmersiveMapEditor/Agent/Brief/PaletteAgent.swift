import Foundation

/// The palette agent's brief: the prompt of one session started in the data
/// folder's `agent/palette/` that makes a palette fit a city, through the
/// palette tools (`PaletteMCP`), copied by the Palettes tab (the user,
/// 2026-11-22: a palette for one's own city made with an agent).
enum PaletteAgent {
    /// The prompt for the palette `name` made for `city`, a copy of `from`
    /// when there is no palette of that name yet.
    static func prompt(name: String, city: String, from: String) -> String {
        """
        You make the palette "\(name)" of a map editor fit \(city): the colours its 3D map tiles and landmark models are \
        painted with. Work through the palette tools (the MCP server "palette") only: do not run commands or edit files.
        1. Call list_palettes. If "\(name)" is not there, create_palette it from "\(from)".
        2. Call get_palette and show_palette for it: what each colour paints, and how they look together.
        3. Look at the city: city_photos at three or four points of it, the old centre, an ordinary residential street, a \
        newer district, and what you know of its buildings and their materials.
        4. Set the colours with set_colours: the walls (plaster_a, plaster_b, plaster_c, brick, modern, box) as the city's \
        ordinary facades, roof and roof_flat as its roofs seen from above, the landmark colours as the materials of its \
        landmarks, adding the city's own as lm_<material> (lm_terracotta, lm_limestone) where none fits. The style stays \
        what it is: a calm, light ground of ordinary buildings with the colour left to the landmarks, every colour a little \
        softer than in a photo, and the colours of one group far enough apart to tell from afar. Leave the roads, the \
        markings and the props alone unless the city's clearly differ.
        5. Look at the palette set_colours draws after each change beside the photos, and correct it: two or three rounds.
        6. Report in a few lines what you set and why. The user chooses in the editor which tiles use the palette.
        """
    }
}
