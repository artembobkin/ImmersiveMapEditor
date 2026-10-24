/// The longest line across points: the extremes in x, else in y.
func computeMaximumLine(_ pts: [Coordinate], _ factory: GeometryFactory) -> LineString {
    var ptMinX: Coordinate?, ptMaxX: Coordinate?, ptMinY: Coordinate?, ptMaxY: Coordinate?
    for p in pts {
        if ptMinX == nil || p.x < ptMinX!.x { ptMinX = p }
        if ptMaxX == nil || p.x > ptMaxX!.x { ptMaxX = p }
        if ptMinY == nil || p.y < ptMinY!.y { ptMinY = p }
        if ptMaxY == nil || p.y > ptMaxY!.y { ptMaxY = p }
    }
    var p0 = ptMinX!, p1 = ptMaxX!
    if p0.x == p1.x {
        p0 = ptMinY!
        p1 = ptMaxY!
    }
    return factory.createLineString([p0, p1])
}
