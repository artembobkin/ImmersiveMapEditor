import Testing
import Topology

@Suite struct TopologyTests {
    @Test func theTargetLinks() {
        #expect(TopologyPort.source == "jts 1.20.0")
    }
}
