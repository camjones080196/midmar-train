import Foundation

/// Effort zones. Each sets a target pace as a multiple of threshold pace per 100 m.
enum Zone: String, Codable, CaseIterable, Identifiable {
    case easy, steady, thr, fast, max

    var id: String { rawValue }
    static let editable: [Zone] = [.easy, .steady, .thr, .fast]

    var name: String {
        switch self {
        case .easy: "Easy"
        case .steady: "Steady"
        case .thr: "Threshold"
        case .fast: "Fast"
        case .max: "Best effort"
        }
    }

    var factor: Double {
        switch self {
        case .easy: 1.10
        case .steady: 1.04
        case .thr: 1.00
        case .fast: 0.94
        case .max: 0.97
        }
    }

    /// 1 to 4, for the effort pips
    var level: Int {
        switch self {
        case .easy: 1
        case .steady: 2
        case .thr: 3
        case .fast, .max: 4
        }
    }

    var cue: String {
        switch self {
        case .easy: "Relaxed. You could chat at the wall."
        case .steady: "Controlled, with rhythmic breathing."
        case .thr: "Hard but repeatable."
        case .fast: "Strong, just short of a sprint."
        case .max: "As fast as you can hold evenly."
        }
    }
}

enum StepKind: String, Codable, CaseIterable {
    case wu, drill, main, cd, race

    var title: String {
        switch self {
        case .wu: "Warm up"
        case .drill: "Drill"
        case .main: "Main set"
        case .cd: "Cool down"
        case .race: "Race"
        }
    }
}

enum SessionType: String, Codable, CaseIterable {
    case tech, skills, strength, build, thr, pyr, speed, easy, long, tt, race

    var name: String {
        switch self {
        case .tech: "Technique"
        case .skills: "Open-water skills"
        case .strength: "Strength"
        case .build: "Intervals"
        case .thr: "Threshold"
        case .pyr: "Pyramid"
        case .speed: "Speed"
        case .easy: "Easy"
        case .long: "Long swim"
        case .tt: "Time trial"
        case .race: "Race"
        }
    }

    var why: String {
        switch self {
        case .tech: "Smooth technique makes every metre cheaper. Swim these slowly and think about one thing at a time."
        case .skills: "The race is in a dam with no walls, lane lines or black line. These sets practise the skills that save the most time out there: sighting, turning without a wall, and starting from the water."
        case .strength: "Kick and pull sets build the strength in your arms and legs separately, so your stroke holds together late in the Mile."
        case .build: "Short repeats with rest let you cover more distance than you could non-stop. That builds your base."
        case .thr: "Threshold reps teach you to hold a strong pace without fading. Swim every rep at the same speed."
        case .pyr: "A pyramid mixes distances so you practise pacing. Start controlled and keep the long middle swim steady."
        case .speed: "Short, fast reps sharpen your feel for the water and make your steady pace feel easier."
        case .easy: "Easy metres build endurance without tiring you out for the long swim."
        case .long: "The long swim is the heart of the plan. It builds the endurance and the confidence to cover 1.6 km."
        case .tt: "A timed swim shows where your fitness is and sets your target paces for the next block."
        case .race: "This is what the plan was for. Start steady, find clear water, and build through the second half."
        }
    }
}

enum Catalog {
    static let drills: [(name: String, how: String)] = [
        ("Side-kick drill", "Kick on your side with the lower arm out front and your face down. Roll to breathe."),
        ("Catch-up drill", "One arm waits out front until the other hand touches it."),
        ("Fingertip drag", "Drag your fingertips along the surface on each recovery to keep your elbows high."),
        ("6-kick switch", "Six kicks on one side, one stroke, then six kicks on the other side."),
        ("Breathe every 3", "Breathe on every third stroke so you use both sides."),
        ("Sighting practice", "Lift your eyes forward every sixth stroke, then roll to breathe.")
    ]

    static let feel = ["Easy", "Comfy", "Solid", "Hard", "All out"]
    static let openWaterGoal = 4
    static let raceDistance = 1600

    static let raceTips: [(title: String, body: String)] = [
        ("Breathe both sides", "Breathe every 3 strokes when you can. Exhale fully underwater so you are not holding your breath."),
        ("Sight the buoy", "Every 6 to 8 strokes, lift your eyes forward, find the next buoy, then roll to breathe. Practise this in every open-water swim."),
        ("Start wide", "Mass starts are rough. Start to the side or near the back and find clear water before you settle into your pace."),
        ("If it gets hard", "Roll onto your back and float until your breathing settles. Raise an arm if you need help."),
        ("Swim open water before race day", "Aim for at least four swims in a dam or the sea, always with a buddy. Swimming straight without a wall takes practice."),
        ("Nothing new on the day", "Use the same goggles and the same routine you trained with.")
    ]
}
