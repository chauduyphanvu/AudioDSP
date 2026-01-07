import XCTest
@testable import AudioDSP

final class DSPTests: XCTestCase {

    func testDbToLinear() {
        XCTAssertEqual(dbToLinear(0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(dbToLinear(-20), 0.1, accuracy: 0.001)
        XCTAssertEqual(dbToLinear(-6), 0.501, accuracy: 0.01)
        XCTAssertEqual(dbToLinear(6), 1.995, accuracy: 0.01)
    }

    func testLinearToDb() {
        XCTAssertEqual(linearToDb(1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(linearToDb(0.1), -20.0, accuracy: 0.1)
        XCTAssertEqual(linearToDb(0.5), -6.02, accuracy: 0.1)
        XCTAssertTrue(linearToDb(0.0).isFinite)
    }

    func testStereoPeak() {
        XCTAssertEqual(stereoPeak(0.5, 0.3), 0.5)
        XCTAssertEqual(stereoPeak(-0.8, 0.3), 0.8)
        XCTAssertEqual(stereoPeak(0.3, -0.9), 0.9)
    }

    func testBiquadCoefficients() {
        let coeffs = BiquadCoefficients.calculate(
            type: .peak(gainDb: 6),
            sampleRate: 48000,
            frequency: 1000,
            q: 1.0
        )

        // Coefficients should be reasonable values
        XCTAssertTrue(coeffs.b0.isFinite)
        XCTAssertTrue(coeffs.b1.isFinite)
        XCTAssertTrue(coeffs.b2.isFinite)
        XCTAssertTrue(coeffs.a1.isFinite)
        XCTAssertTrue(coeffs.a2.isFinite)
    }

    func testBiquadProcess() {
        let coeffs = BiquadCoefficients.calculate(
            type: .peak(gainDb: 0),
            sampleRate: 48000,
            frequency: 1000,
            q: 1.0
        )

        let biquad = Biquad(coefficients: coeffs)

        // With 0dB gain, output should approximately equal input after settling
        for _ in 0..<1000 {
            _ = biquad.process(1.0)
        }

        let output = biquad.process(1.0)
        XCTAssertEqual(output, 1.0, accuracy: 0.01)
    }

    func testGainEffect() {
        let gain = Gain(gainDb: 6)

        let (outL, outR) = gain.process(left: 0.5, right: 0.5)

        // 6dB gain should approximately double the signal
        XCTAssertEqual(outL, 0.5 * dbToLinear(6), accuracy: 0.01)
        XCTAssertEqual(outR, 0.5 * dbToLinear(6), accuracy: 0.01)
    }

    func testCompressorNoCompression() {
        let compressor = Compressor(sampleRate: 48000)

        // Set threshold very high so no compression happens
        compressor.setParameter(0, value: 0)

        // Feed a small signal
        for _ in 0..<1000 {
            _ = compressor.process(left: 0.1, right: 0.1)
        }

        // Gain reduction should be minimal
        XCTAssertEqual(compressor.gainReductionDb, 0, accuracy: 0.1)
    }

    func testStereoWidener() {
        let widener = StereoWidener()

        // Width = 1 should be unity
        widener.setParameter(0, value: 1.0)
        let (outL, outR) = widener.process(left: 0.5, right: 0.3)
        XCTAssertEqual(outL, 0.5, accuracy: 0.001)
        XCTAssertEqual(outR, 0.3, accuracy: 0.001)

        // Width = 0 should collapse to mono
        widener.setParameter(0, value: 0.0)
        let (monoL, monoR) = widener.process(left: 1.0, right: 0.0)
        XCTAssertEqual(monoL, monoR, accuracy: 0.001)
    }

    func testDSPChain() {
        let chain = DSPChain.createDefault(sampleRate: 48000)

        // Process some samples
        for _ in 0..<1000 {
            _ = chain.process(left: 0.5, right: 0.5)
        }

        // Should have valid levels
        let (inL, inR) = chain.inputLevels
        let (outL, outR) = chain.outputLevels

        XCTAssertTrue(inL >= 0)
        XCTAssertTrue(inR >= 0)
        XCTAssertTrue(outL >= 0)
        XCTAssertTrue(outR >= 0)
    }

    func testEnvelopeFollowerAttackRelease() {
        let env = EnvelopeFollower(sampleRate: 44100, mode: .attackRelease)

        XCTAssertEqual(env.current, 0.0)

        // Feed constant signal
        for _ in 0..<4410 {
            _ = env.process(1.0)
        }

        // Should approach 1.0
        XCTAssertGreaterThan(env.current, 0.9)
    }

    func testEnvelopeFollowerInstantAttack() {
        let env = EnvelopeFollower(sampleRate: 44100, mode: .instantAttack)

        XCTAssertEqual(env.current, 1.0)

        // Instant attack should immediately follow downward
        let result = env.process(0.5)
        XCTAssertEqual(result, 0.5, accuracy: 0.001)
    }
}
