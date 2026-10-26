import Foundation

@main
struct AppleMixerMathTest {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition {
                print("FAIL: \(message)")
                exit(1)
            }
        }
        func near(_ a: Double, _ b: Double) -> Bool {
            abs(a - b) < 1e-9
        }

        let split = AppleMixerMath.gains(
            mode: "split",
            curve: "linear",
            seconds: 0,
            period: 60,
            contrast: 1,
            phase: 0,
            microHz: 0,
            depth: 0,
            swapped: false
        )
        check(
            near(split.aLeft, 1) && near(split.aRight, 0)
                && near(split.bLeft, 0) && near(split.bRight, 1),
            "split keeps A left and B right"
        )

        let orbit = AppleMixerMath.gains(
            mode: "orbit",
            curve: "linear",
            seconds: 15,
            period: 60,
            contrast: 1,
            phase: 0,
            microHz: 0,
            depth: 0,
            swapped: false
        )
        check(
            near(orbit.aLeft, 0) && near(orbit.aRight, 1)
                && near(orbit.bLeft, 1) && near(orbit.bRight, 0),
            "orbit exchanges languages across ears"
        )
        let opposite = AppleMixerMath.gains(
            mode: "orbit",
            curve: "linear",
            seconds: 45,
            period: 60,
            contrast: 1,
            phase: 0,
            microHz: 0,
            depth: 0,
            swapped: false
        )
        check(
            near(opposite.aLeft, 1) && near(opposite.aRight, 0)
                && near(opposite.bLeft, 0) && near(opposite.bRight, 1),
            "half-cycle reversal"
        )

        for mode in ["split", "orbit", "mono", "together"] {
            for curve in ["equal-power", "linear"] {
                for contrast in [1.0, 2.5, 5.0] {
                    for index in 0..<4_000 {
                        let gains = AppleMixerMath.gains(
                            mode: mode,
                            curve: curve,
                            seconds: Double(index) * 0.017,
                            period: 2,
                            contrast: contrast,
                            phase: 73,
                            microHz: 1.7,
                            depth: 0.5,
                            swapped: false
                        )
                        for value in [
                            gains.aLeft, gains.aRight, gains.bLeft, gains.bRight,
                        ] {
                            check(
                                value.isFinite && value >= -1e-10 && value <= 1 + 1e-10,
                                "finite bounded gains"
                            )
                        }
                        check(
                            gains.aLeft + gains.bLeft <= 1 + 1e-10
                                && gains.aRight + gains.bRight <= 1 + 1e-10,
                            "no clipping with correlated full-scale sources"
                        )
                        if mode == "mono" {
                            check(
                                near(gains.aLeft, gains.aRight)
                                    && near(gains.bLeft, gains.bRight),
                                "centered mono"
                            )
                        }
                        if mode == "together" {
                            check(
                                near(gains.aLeft, 0.5) && near(gains.aRight, 0.5)
                                    && near(gains.bLeft, 0.5)
                                    && near(gains.bRight, 0.5),
                                "fixed simultaneous blend"
                            )
                        }
                    }
                }
            }
        }

        let swapped = AppleMixerMath.gains(
            mode: "split",
            curve: "equal-power",
            seconds: 0,
            period: 60,
            contrast: 1,
            phase: 0,
            microHz: 0,
            depth: 0,
            swapped: true
        )
        check(
            near(swapped.aLeft, 0) && near(swapped.aRight, 1)
                && near(swapped.bLeft, 1) && near(swapped.bRight, 0),
            "swapped ears"
        )
        check(AppleMixerMath.secondaryPosition(10, -100) == 0, "negative offset boundary")
        check(AppleMixerMath.secondaryPosition(1000, 500) == 1500, "positive offset semantics")
        check(AppleMixerMath.correctedSpeed(2, drift: 100) < 2, "ahead B slows")
        check(AppleMixerMath.correctedSpeed(2, drift: -100) > 2, "late B speeds up")
        check(AppleMixerMath.correctedSpeed(2, drift: 0) == 2, "aligned B unchanged")
        print("PASS: \(checks) Apple mixer and synchronization assertions")
    }
}
