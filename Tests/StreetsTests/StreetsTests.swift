import Testing
import Streets

@Suite struct StreetsTests {
    @Test func theTargetsLink() {
        #expect(StreetsPort.source == "osm2streets fc119c4")
    }
}
