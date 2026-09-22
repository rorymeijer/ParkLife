import XCTest
@testable import ParkLifeCore

final class MoneyTests: XCTestCase {

    func testEuroConstruction() {
        XCTAssertEqual(Money(euros: 12).cents, 1_200)
        XCTAssertEqual(Money.euros(4.55).cents, 455)
        XCTAssertEqual(Money(cents: -250).description, "-€2.50")
        XCTAssertEqual(Money(cents: 1_205).description, "€12.05")
    }

    func testArithmeticIsExact() {
        var total = Money.zero
        // A thousand small transactions must land exactly, which is the whole reason money is
        // integer cents and not Double.
        for _ in 0..<1_000 {
            total += Money(cents: 7)
        }
        XCTAssertEqual(total.cents, 7_000)
    }

    func testScalingRoundsToNearestCent() {
        XCTAssertEqual(Money(cents: 999).scaled(by: 0.5).cents, 500)
        XCTAssertEqual(Money(cents: 101).scaled(by: 0.3).cents, 30)
    }

    func testSplitSumsBackExactly() {
        let amount = Money(cents: 1_000)
        let parts = amount.split(into: 3)
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts.reduce(0) { $0 + $1.cents }, 1_000)
        XCTAssertEqual(parts.map(\.cents).sorted(), [333, 333, 334])
    }

    func testCodableRoundTrip() throws {
        let value = Money(cents: 123_456)
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(String(data: data, encoding: .utf8), "123456")
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: data), value)
    }
}

final class SeededRandomTests: XCTestCase {

    func testSameSeedProducesSameSequence() {
        var a = SeededRandom(seed: 42)
        var b = SeededRandom(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SeededRandom(seed: 1)
        var b = SeededRandom(seed: 2)
        XCTAssertNotEqual(a.next(), b.next())
    }

    func testUnitRangeIsBounded() {
        var random = SeededRandom(seed: 7)
        for _ in 0..<10_000 {
            let value = random.nextUnit()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    func testIntRangeIsInclusiveAndBounded() {
        var random = SeededRandom(seed: 9)
        var seen = Set<Int>()
        for _ in 0..<2_000 {
            let value = random.nextInt(in: 3...6)
            XCTAssertTrue((3...6).contains(value))
            seen.insert(value)
        }
        XCTAssertEqual(seen, [3, 4, 5, 6])
    }

    func testWeightedIndexIgnoresZeroWeights() {
        var random = SeededRandom(seed: 11)
        for _ in 0..<500 {
            let index = random.weightedIndex([0, 5, 0, 2])
            XCTAssertTrue(index == 1 || index == 3)
        }
        XCTAssertNil(random.weightedIndex([0, 0, 0]))
    }

    func testPoissonMeanIsApproximatelyCorrect() {
        var random = SeededRandom(seed: 3)
        var total = 0
        let samples = 5_000
        for _ in 0..<samples {
            total += random.poisson(mean: 4.0)
        }
        let mean = Double(total) / Double(samples)
        XCTAssertEqual(mean, 4.0, accuracy: 0.25)
    }

    func testStreamsAreIndependent() {
        var streams = RandomStreams(masterSeed: 99)
        let firstWeather = streams.weather.next()
        // Consuming the demand stream must not shift the weather stream.
        var other = RandomStreams(masterSeed: 99)
        _ = other.demand.next()
        _ = other.demand.next()
        XCTAssertEqual(other.weather.next(), firstWeather)
    }
}

final class RunLengthTests: XCTestCase {

    func testRoundTrip() throws {
        let values = [0, 0, 0, 1, 1, 2, 2, 2, 2, 5]
        let encoded = RunLength.encode(values)
        XCTAssertEqual(encoded, [0, 3, 1, 2, 2, 4, 5, 1])
        XCTAssertEqual(try RunLength.decode(encoded, expectedCount: values.count), values)
    }

    func testUniformGridCompressesHard() {
        let values = [Int](repeating: 3, count: 9_216)
        XCTAssertEqual(RunLength.encode(values), [3, 9_216])
    }

    func testEmptyInput() throws {
        XCTAssertEqual(RunLength.encode([]), [])
        XCTAssertEqual(try RunLength.decode([], expectedCount: 0), [])
    }

    func testMalformedPayloadThrows() {
        XCTAssertThrowsError(try RunLength.decode([1, 2, 3], expectedCount: 3))
        XCTAssertThrowsError(try RunLength.decode([1, 99], expectedCount: 3))
    }
}

final class MinHeapTests: XCTestCase {

    func testPopsInOrder() {
        var heap = MinHeap<Int>()
        for value in [5, 3, 9, 1, 7, 1, 0] {
            heap.insert(value)
        }
        var popped: [Int] = []
        while let value = heap.removeMin() {
            popped.append(value)
        }
        XCTAssertEqual(popped, [0, 1, 1, 3, 5, 7, 9])
    }

    func testHeapifyFromArray() {
        var heap = MinHeap([8, 2, 6, 4])
        XCTAssertEqual(heap.min, 2)
        XCTAssertEqual(heap.removeMin(), 2)
        XCTAssertEqual(heap.removeMin(), 4)
        XCTAssertEqual(heap.count, 2)
    }

    func testEmptyHeap() {
        var heap = MinHeap<Int>()
        XCTAssertTrue(heap.isEmpty)
        XCTAssertNil(heap.removeMin())
    }
}

final class FNV1aTests: XCTestCase {

    func testKnownVector() {
        var hasher = FNV1a()
        hasher.combine("hello")
        // FNV-1a 64 of "hello".
        XCTAssertEqual(hasher.hexDigest, "a430d84680aabd0b")
    }

    func testStabilityAcrossRuns() {
        let data = Data("ParkLife".utf8)
        XCTAssertEqual(FNV1a.hash(data), FNV1a.hash(data))
    }

    func testHexIsSixteenCharacters() {
        XCTAssertEqual(FNV1a.hexString(of: 0).count, 16)
        XCTAssertEqual(FNV1a.hexString(of: UInt64.max), "ffffffffffffffff")
    }
}

final class EntityStoreTests: XCTestCase {

    func testInsertLookupAndRemove() {
        var store = EntityStore<Reservation>()
        let reservation = Reservation(
            id: ReservationID(raw: 3),
            groupID: GroupID(raw: 1),
            unitBuildingID: nil,
            requestedDefinitionID: "cottage_basic_4",
            arrival: GameDate(year: 2026, month: 5, day: 1),
            departure: GameDate(year: 2026, month: 5, day: 4),
            adults: 2,
            children: 1,
            packageID: "standard",
            price: Money(euros: 300),
            discount: .zero,
            extras: .zero,
            status: .booked,
            bookedAtTick: 0
        )
        store.insert(reservation)
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store[ReservationID(raw: 3)]?.adults, 2)
        store.modify(ReservationID(raw: 3)) { $0.status = .paid }
        XCTAssertEqual(store[ReservationID(raw: 3)]?.status, .paid)
        XCTAssertNotNil(store.remove(ReservationID(raw: 3)))
        XCTAssertTrue(store.isEmpty)
    }

    func testSwapRemoveKeepsOtherLookupsValid() {
        var store = EntityStore<StaffTask>()
        for raw in 1...5 {
            store.insert(
                StaffTask(
                    id: TaskID(raw: UInt32(raw)),
                    kind: .cleanUnit,
                    target: BuildingID(raw: 1),
                    createdTick: 0,
                    priority: 1,
                    durationMinutes: 10
                )
            )
        }
        store.remove(TaskID(raw: 2))
        XCTAssertEqual(store.count, 4)
        for raw in [1, 3, 4, 5] {
            XCTAssertNotNil(store[TaskID(raw: UInt32(raw))], "id \(raw) should still resolve")
        }
        XCTAssertNil(store[TaskID(raw: 2)])
        XCTAssertEqual(store.sortedIDs.map(\.raw), [1, 3, 4, 5])
    }
}
