import SwiftUI

// MARK: - Anime Workout Plan Data Model

struct AnimeWorkoutPlan: Identifiable {
    let id: String                          // stable string key stored on Profile
    let character: String
    let anime: String
    let tagline: String                     // short flavour line
    let description: String
    let difficulty: PlanDifficulty
    let accentColor: Color
    let iconSymbol: String                  // SF Symbol
    let weeklySchedule: [DayPlan]           // 7 entries, index 0 = Monday
    let nutrition: PlanNutrition
    /// Which biological sex this program is designed for. nil = unisex.
    let targetGender: PlayerGender?

    // MARK: - Difficulty
    enum PlanDifficulty: String {
        case beginner     = "Beginner"
        case intermediate = "Intermediate"
        case advanced     = "Advanced"
        case elite        = "Elite"

        var color: Color {
            switch self {
            case .beginner:     return .green
            case .intermediate: return .blue
            case .advanced:     return .orange
            case .elite:        return .red
            }
        }
    }

    // MARK: - Day Plan
    struct DayPlan {
        let dayName: String          // "Monday", "Tuesday", etc.
        let focus: String            // e.g. "Push", "Rest", "Full Body"
        let isRest: Bool
        let exercises: [PlannedExercise]
        let questTitle: String       // override quest title for today
        let questDetails: String
        let xpReward: Int
    }

    // MARK: - Individual Exercise in a Plan
    struct PlannedExercise {
        let name: String
        let sets: Int
        let reps: String             // "10", "10-12", "Max", "100"
        let restSeconds: Int
        let notes: String
    }

    // MARK: - Nutrition
    struct PlanNutrition {
        let dailyCalories: Int
        let proteinGrams: Int
        let carbGrams: Int
        let fatGrams: Int
        let waterGlasses: Int
        let mealPrepTips: [String]   // 3-4 actionable tips
        let avoidList: [String]      // foods to avoid on this plan
    }
}

// MARK: - All Plans

enum AnimeWorkoutPlans {

    static let all: [AnimeWorkoutPlan] = [
        saitama, goku, levi, rockLee, endeavor,
        asta, rudeus, deku, maki, starsAndStripes
    ]

    static func plan(id: String) -> AnimeWorkoutPlan? {
        all.first { $0.id == id }
    }

    // MARK: - Saitama (One Punch Man)
    // The legendary 100/100/100/10km routine — deceptively simple, brutally consistent.
    static let saitama = AnimeWorkoutPlan(
        id: "saitama",
        character: "Saitama",
        anime: "One Punch Man",
        tagline: "Become so strong it stops being fun.",
        description: "100 push-ups, 100 sit-ups, 100 squats, and a 10 km run — every single day, no days off. Simple, merciless, and the reason Saitama lost his hair. Pure bodyweight volume.",
        difficulty: .beginner,
        accentColor: .yellow,
        iconSymbol: "bolt.fill",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Full Body",
                isRest: false,
                exercises: [
                    .init(name: "Push-Ups",      sets: 10, reps: "10",  restSeconds: 30, notes: "Chest to floor, full lockout"),
                    .init(name: "Sit-Ups",        sets: 10, reps: "10",  restSeconds: 30, notes: "Hands behind head, full crunch"),
                    .init(name: "Bodyweight Squat",sets: 10, reps: "10",  restSeconds: 30, notes: "Below parallel, drive through heels"),
                    .init(name: "Running",        sets: 1,  reps: "10 km", restSeconds: 0,  notes: "Steady pace, no stopping"),
                ],
                questTitle: "Saitama Protocol — Day 1",
                questDetails: "100 push-ups. 100 sit-ups. 100 squats. 10 km run. No AC. No heater. No excuses.",
                xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Full Body",
                isRest: false,
                exercises: [
                    .init(name: "Push-Ups",       sets: 10, reps: "10",   restSeconds: 30, notes: ""),
                    .init(name: "Sit-Ups",         sets: 10, reps: "10",   restSeconds: 30, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 10, reps: "10",   restSeconds: 30, notes: ""),
                    .init(name: "Running",         sets: 1,  reps: "10 km", restSeconds: 0,  notes: ""),
                ],
                questTitle: "Saitama Protocol — Day 2",
                questDetails: "Same as yesterday. Same as tomorrow. Consistency is the secret weapon.",
                xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Full Body", isRest: false,
                exercises: [
                    .init(name: "Push-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Sit-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Running", sets: 1, reps: "10 km", restSeconds: 0, notes: ""),
                ],
                questTitle: "Saitama Protocol — Day 3",
                questDetails: "The hero who does it anyway. Complete the protocol.",
                xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Full Body", isRest: false,
                exercises: [
                    .init(name: "Push-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Sit-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Running", sets: 1, reps: "10 km", restSeconds: 0, notes: ""),
                ],
                questTitle: "Saitama Protocol — Day 4", questDetails: "Day 4. Still going.", xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Full Body", isRest: false,
                exercises: [
                    .init(name: "Push-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Sit-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Running", sets: 1, reps: "10 km", restSeconds: 0, notes: ""),
                ],
                questTitle: "Saitama Protocol — Day 5", questDetails: "Five days straight. Weekend means nothing.", xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Full Body", isRest: false,
                exercises: [
                    .init(name: "Push-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Sit-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Running", sets: 1, reps: "10 km", restSeconds: 0, notes: ""),
                ],
                questTitle: "Saitama Protocol — Day 6", questDetails: "No days off. That's the whole point.", xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Full Body", isRest: false,
                exercises: [
                    .init(name: "Push-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Sit-Ups", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 10, reps: "10", restSeconds: 30, notes: ""),
                    .init(name: "Running", sets: 1, reps: "10 km", restSeconds: 0, notes: ""),
                ],
                questTitle: "Saitama Protocol — Day 7", questDetails: "Seven days. One week down. Start again tomorrow.", xpReward: 150
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 2200,
            proteinGrams: 140,
            carbGrams: 270,
            fatGrams: 60,
            waterGlasses: 10,
            mealPrepTips: [
                "Batch cook rice and chicken at the start of the week",
                "Keep boiled eggs on hand for fast protein between sessions",
                "Eat a banana + peanut butter 30 min before the run",
                "Hydrate aggressively — 10 km daily dehydrates fast",
            ],
            avoidList: ["Alcohol", "Fried food", "Energy drinks", "Processed snacks"]
        ),
        targetGender: .male
    )

    // MARK: - Goku (Dragon Ball Z)
    // High volume compound lifts, massive calorie surplus, train to failure.
    static let goku = AnimeWorkoutPlan(
        id: "goku",
        character: "Goku",
        anime: "Dragon Ball Z",
        tagline: "Push past your limits. Every. Single. Day.",
        description: "Goku trains under 100x gravity. We'll start lighter. Heavy compound lifts, high volume, high frequency. Massive caloric surplus to fuel muscle growth. Built for someone who refuses to stay at their current level.",
        difficulty: .advanced,
        accentColor: .orange,
        iconSymbol: "flame.fill",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Chest & Triceps", isRest: false,
                exercises: [
                    .init(name: "Bench Press",       sets: 5, reps: "5",    restSeconds: 180, notes: "Work up to 5RM — push past last week"),
                    .init(name: "Incline Dumbbell Press", sets: 4, reps: "8-10", restSeconds: 90, notes: "Control the negative"),
                    .init(name: "Dips",              sets: 4, reps: "Max",  restSeconds: 90,  notes: "Add weight when >15 reps"),
                    .init(name: "Tricep Pushdown",   sets: 3, reps: "12",   restSeconds: 60,  notes: "Full extension at bottom"),
                ],
                questTitle: "Power Level Training — Push Day",
                questDetails: "Chest and triceps. 5 sets of bench. Match or beat last week's weight. Failure is not an option unless you're at absolute failure.",
                xpReward: 150
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Back & Biceps", isRest: false,
                exercises: [
                    .init(name: "Deadlift",        sets: 5, reps: "5",    restSeconds: 180, notes: "Full hip hinge, neutral spine"),
                    .init(name: "Pull-Ups",        sets: 4, reps: "Max",  restSeconds: 90,  notes: "Dead hang start"),
                    .init(name: "Barbell Row",     sets: 4, reps: "8",    restSeconds: 90,  notes: "Chest to bench, pull to hip"),
                    .init(name: "Barbell Curl",    sets: 3, reps: "10",   restSeconds: 60,  notes: "No swinging"),
                ],
                questTitle: "Power Level Training — Pull Day",
                questDetails: "Deadlifts open. Pull-ups to failure. Back must be destroyed by the end.",
                xpReward: 150
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Legs", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 5, reps: "5",    restSeconds: 180, notes: "Below parallel, brace hard"),
                    .init(name: "Romanian Deadlift",sets: 4, reps: "8",   restSeconds: 90,  notes: "Hinge until hamstring stretch"),
                    .init(name: "Leg Press",       sets: 4, reps: "10-12",restSeconds: 90,  notes: "Full range, no locking out"),
                    .init(name: "Calf Raise",      sets: 4, reps: "15",   restSeconds: 60,  notes: "Pause at top"),
                ],
                questTitle: "Power Level Training — Leg Day",
                questDetails: "Legs are 70% of your power. Squats first, heavy. No skipping.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Shoulders & Core", isRest: false,
                exercises: [
                    .init(name: "Overhead Press",  sets: 5, reps: "5",    restSeconds: 180, notes: "Strict — no leg drive"),
                    .init(name: "Lateral Raise",   sets: 4, reps: "12",   restSeconds: 60,  notes: "Lead with elbows"),
                    .init(name: "Face Pull",       sets: 3, reps: "15",   restSeconds: 60,  notes: "External rotation at end"),
                    .init(name: "Plank",           sets: 3, reps: "60s",  restSeconds: 60,  notes: "Squeeze glutes, breathe"),
                ],
                questTitle: "Power Level Training — Shoulders", questDetails: "Shoulders and core. OHP is the king. Five heavy sets.", xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Full Body Power", isRest: false,
                exercises: [
                    .init(name: "Power Clean",     sets: 5, reps: "3",    restSeconds: 180, notes: "Explosive pull from floor"),
                    .init(name: "Front Squat",     sets: 4, reps: "5",    restSeconds: 120, notes: "Elbows high, upright torso"),
                    .init(name: "Push Press",      sets: 4, reps: "5",    restSeconds: 120, notes: "Dip and drive"),
                    .init(name: "Farmer's Carry",  sets: 3, reps: "40 m", restSeconds: 90,  notes: "Heavy, shoulders packed"),
                ],
                questTitle: "Power Level Training — Full Power",
                questDetails: "Full body power day. Power cleans, front squats, push press. This is what Gravity Chamber prep looks like.",
                xpReward: 180
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Active Recovery", isRest: false,
                exercises: [
                    .init(name: "Running",         sets: 1, reps: "5 km", restSeconds: 0, notes: "Easy pace — conversational"),
                    .init(name: "Stretching",      sets: 1, reps: "20 min", restSeconds: 0, notes: "Full body mobility flow"),
                ],
                questTitle: "Recovery Run", questDetails: "Active recovery. 5 km easy + full stretch. Saiyans recover fast because they work at it.", xpReward: 80
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day — Recharge", questDetails: "Even Goku sleeps. Eat your meals, hydrate, and prepare for next week.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 3500,
            proteinGrams: 220,
            carbGrams: 420,
            fatGrams: 90,
            waterGlasses: 12,
            mealPrepTips: [
                "Prep 6 meals per day — eat every 2.5–3 hours to fuel volume training",
                "Post-workout: 60g fast carbs (white rice/banana) + 50g protein shake immediately",
                "Pre-bed: cottage cheese or Greek yogurt for slow-release casein protein",
                "Batch cook 1.5 kg chicken breast and 2 kg rice on Sunday",
            ],
            avoidList: ["Calorie deficit", "Skipping meals", "Alcohol", "Low-carb eating on heavy training days"]
        ),
        targetGender: .male
    )

    // MARK: - Levi Ackerman (Attack on Titan)
    // Calisthenics, agility drills, grip strength — the ODM gear demands it.
    static let levi = AnimeWorkoutPlan(
        id: "levi",
        character: "Levi Ackerman",
        anime: "Attack on Titan",
        tagline: "Humanity's strongest soldier doesn't rest.",
        description: "Captain Levi's power comes from explosive calisthenics, iron grip strength, and razor-sharp agility. No barbell required — bodyweight mastery, sprints, and core work. Small but lethal.",
        difficulty: .intermediate,
        accentColor: .gray,
        iconSymbol: "figure.fencing",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Upper Body Pull & Grip", isRest: false,
                exercises: [
                    .init(name: "Pull-Ups",        sets: 5, reps: "Max",  restSeconds: 90, notes: "Full dead hang, chin over bar"),
                    .init(name: "Towel Pull-Ups",  sets: 3, reps: "8",    restSeconds: 90, notes: "Drape towel over bar for grip"),
                    .init(name: "Archer Rows",     sets: 4, reps: "8 each", restSeconds: 60, notes: "One-arm assisted row"),
                    .init(name: "Dead Hang",       sets: 3, reps: "60s",  restSeconds: 60, notes: "ODM gear requires iron grip"),
                ],
                questTitle: "Survey Corps Training — Grip & Pull",
                questDetails: "ODM gear is useless without grip strength. Pull-ups to failure, towel rows, dead hang. Your hands must not let go.",
                xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Legs & Agility", isRest: false,
                exercises: [
                    .init(name: "Pistol Squat",    sets: 4, reps: "5 each", restSeconds: 90, notes: "Assist with TRX if needed"),
                    .init(name: "Box Jump",        sets: 4, reps: "8",    restSeconds: 60,  notes: "Maximum height, soft landing"),
                    .init(name: "Sprint Intervals",sets: 6, reps: "30s on / 30s off", restSeconds: 0, notes: "All out effort each rep"),
                    .init(name: "Lateral Bounds",  sets: 3, reps: "10 each", restSeconds: 60, notes: "Stick the landing"),
                ],
                questTitle: "Survey Corps Training — Agility",
                questDetails: "Speed and explosive power. Titans are bigger than you — you win by being faster. Sprint intervals, box jumps, pistol squats.",
                xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Core & Rotation", isRest: false,
                exercises: [
                    .init(name: "L-Sit",           sets: 4, reps: "20s",  restSeconds: 60, notes: "Parallel bars or floor"),
                    .init(name: "Dragon Flag",     sets: 3, reps: "6",    restSeconds: 90, notes: "Control entire descent"),
                    .init(name: "Russian Twist",   sets: 3, reps: "20",   restSeconds: 60, notes: "Weighted — rotate fully"),
                    .init(name: "Ab Wheel Rollout",sets: 3, reps: "10",   restSeconds: 60, notes: "Hips stay high"),
                ],
                questTitle: "Survey Corps Training — Core",
                questDetails: "ODM gear pivots from your core. L-sits, dragon flags, rotational work. The mid-section must be armour.",
                xpReward: 130
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Push & Shoulder Stability", isRest: false,
                exercises: [
                    .init(name: "Handstand Push-Up", sets: 4, reps: "5", restSeconds: 90, notes: "Wall assisted — work toward freestanding"),
                    .init(name: "Ring Dips",         sets: 4, reps: "8", restSeconds: 90, notes: "Control the rings — no flare"),
                    .init(name: "Pike Push-Up",      sets: 3, reps: "12",restSeconds: 60, notes: "Hips high, nose to floor"),
                    .init(name: "Plank Shoulder Tap",sets: 3, reps: "20",restSeconds: 60, notes: "Hips level, no rotation"),
                ],
                questTitle: "Survey Corps Training — Push",
                questDetails: "Shoulder strength and stability. Handstand push-ups and ring dips. Control is strength.",
                xpReward: 130
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Full Body Circuit", isRest: false,
                exercises: [
                    .init(name: "Burpee",          sets: 5, reps: "10",  restSeconds: 60,  notes: "Explosive jump at top"),
                    .init(name: "Pull-Ups",        sets: 5, reps: "8",   restSeconds: 60,  notes: ""),
                    .init(name: "Push-Ups",        sets: 5, reps: "15",  restSeconds: 60,  notes: ""),
                    .init(name: "Squat Jump",      sets: 5, reps: "10",  restSeconds: 60,  notes: ""),
                ],
                questTitle: "Survey Corps Training — Combat Circuit",
                questDetails: "Full body circuit. 5 rounds. This is the conditioning that keeps soldiers alive on the field.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Long Run", isRest: false,
                exercises: [
                    .init(name: "Running", sets: 1, reps: "8 km", restSeconds: 0, notes: "Steady state — simulate patrol"),
                ],
                questTitle: "Patrol Route", questDetails: "8 km patrol. Steady pace. This is what keeping humanity safe costs.", xpReward: 100
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Rest. Clean your equipment. Prepare mentally for the week ahead.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 2600,
            proteinGrams: 170,
            carbGrams: 300,
            fatGrams: 75,
            waterGlasses: 10,
            mealPrepTips: [
                "Lean protein at every meal — chicken, fish, eggs",
                "Complex carbs pre-workout: oats or sweet potato 1 hour before",
                "Post-workout shake within 20 min of finishing",
                "Keep snacks portable — nuts, jerky, protein bars for active days",
            ],
            avoidList: ["Heavy meals before training", "Alcohol", "High-fat pre-workout meals", "Sugary drinks"]
        ),
        targetGender: .male
    )

    // MARK: - Rock Lee (Naruto)
    // Pure hard work. Weights on legs, endless reps, no shortcuts.
    static let rockLee = AnimeWorkoutPlan(
        id: "rock-lee",
        character: "Rock Lee",
        anime: "Naruto",
        tagline: "If you can't use ninjutsu, work harder than anyone who can.",
        description: "Rock Lee was born without ninjutsu ability but became an elite through sheer effort. This plan is pure volume — calisthenics, weighted reps, and endurance work. No talent required, only will.",
        difficulty: .intermediate,
        accentColor: .green,
        iconSymbol: "figure.martial.arts",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Legs — The Foundation", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 5, reps: "20",  restSeconds: 90,  notes: "High rep — build endurance base"),
                    .init(name: "Lunge",           sets: 4, reps: "20 each", restSeconds: 60, notes: "Weighted if possible"),
                    .init(name: "Calf Raise",      sets: 5, reps: "30",  restSeconds: 45,  notes: "Weighted — Rock Lee's calves are legendary"),
                    .init(name: "Jump Rope",       sets: 1, reps: "10 min", restSeconds: 0, notes: "Fast footwork"),
                ],
                questTitle: "Taijutsu Foundation — Leg Day",
                questDetails: "Rock Lee's speed came from leg training that others refused to do. 500 squats is the goal eventually. Start with 100 today.",
                xpReward: 150
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Push Endurance", isRest: false,
                exercises: [
                    .init(name: "Push-Ups",        sets: 10, reps: "20", restSeconds: 45,  notes: "200 total — rest as needed"),
                    .init(name: "Diamond Push-Ups",sets: 4,  reps: "15", restSeconds: 60,  notes: "Tricep focus"),
                    .init(name: "Dips",            sets: 4,  reps: "Max",restSeconds: 90,  notes: "Full range"),
                    .init(name: "Handstand Hold",  sets: 3,  reps: "20s",restSeconds: 60,  notes: "Wall support — build shoulder endurance"),
                ],
                questTitle: "Taijutsu Foundation — Push Day",
                questDetails: "200 push-ups. Broken into sets. Dips to failure. If Rock Lee can do 500 with leg weights, you can do 200.",
                xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Running & Core", isRest: false,
                exercises: [
                    .init(name: "Running",         sets: 1, reps: "10 km", restSeconds: 0, notes: "Steady pace"),
                    .init(name: "Sit-Ups",         sets: 5, reps: "40",   restSeconds: 45, notes: ""),
                    .init(name: "Leg Raise",       sets: 4, reps: "20",   restSeconds: 45, notes: "Lower ab focus"),
                ],
                questTitle: "Taijutsu Foundation — Endurance Run",
                questDetails: "10 km run followed by core work. Speed is distance first. Build the base.",
                xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Full Body Volume", isRest: false,
                exercises: [
                    .init(name: "Pull-Ups",        sets: 5, reps: "Max",  restSeconds: 90, notes: ""),
                    .init(name: "Bodyweight Squat", sets: 5, reps: "30",  restSeconds: 60, notes: ""),
                    .init(name: "Push-Ups",        sets: 5, reps: "25",   restSeconds: 60, notes: ""),
                    .init(name: "Burpee",          sets: 3, reps: "20",   restSeconds: 90, notes: "Full extension at top"),
                ],
                questTitle: "Taijutsu Foundation — Volume Circuit",
                questDetails: "Full body circuit. Pull-ups, squats, push-ups, burpees. High volume = high adaptation.",
                xpReward: 150
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Legs — Heavy", isRest: false,
                exercises: [
                    .init(name: "Weighted Squat",  sets: 5, reps: "10",  restSeconds: 120, notes: "Rock Lee trained with weights on legs — honour that"),
                    .init(name: "Single-Leg Deadlift", sets: 4, reps: "10 each", restSeconds: 90, notes: "Balance and hamstring strength"),
                    .init(name: "Box Jump",        sets: 4, reps: "10",  restSeconds: 60,  notes: "Maximum height"),
                    .init(name: "Sprint",          sets: 6, reps: "100m",restSeconds: 90,  notes: "All out effort"),
                ],
                questTitle: "Taijutsu Foundation — Heavy Legs",
                questDetails: "Weighted squats. Sprint intervals. The Eight Inner Gates don't open for free.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Skill & Flexibility", isRest: false,
                exercises: [
                    .init(name: "Jump Rope",       sets: 3, reps: "5 min", restSeconds: 60, notes: "Work on speed and rhythm"),
                    .init(name: "Stretching",      sets: 1, reps: "30 min", restSeconds: 0, notes: "Full body — focus on hip flexors and hamstrings"),
                    .init(name: "Balance Work",    sets: 3, reps: "60s each side", restSeconds: 30, notes: "Single leg balance, eyes closed"),
                ],
                questTitle: "Taijutsu Foundation — Skill Day",
                questDetails: "Jump rope, flexibility, balance. Martial arts isn't just strength — it's precision.",
                xpReward: 90
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Rest. Even Guy-sensei rests. Eat well and recover.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 2800,
            proteinGrams: 160,
            carbGrams: 360,
            fatGrams: 70,
            waterGlasses: 10,
            mealPrepTips: [
                "High carb days on Mon/Thu/Fri to fuel heavy leg sessions",
                "Rice balls (onigiri) are a great portable carb source for between sessions",
                "Eat within 30 min of training — body is primed for nutrients",
                "Miso soup provides electrolytes lost during long runs",
            ],
            avoidList: ["Processed sugar", "Alcohol", "Heavy fat meals before training", "Skipping post-workout nutrition"]
        ),
        targetGender: .male
    )

    // MARK: - Endeavor (My Hero Academia)
    // Raw strength + conditioning. Pro hero training. No mercy.
    static let endeavor = AnimeWorkoutPlan(
        id: "endeavor",
        character: "Endeavor",
        anime: "My Hero Academia",
        tagline: "The number one hero doesn't take shortcuts.",
        description: "Enji Todoroki became the world's number one hero through relentless strength training and conditioning. Heavy barbell work, high-intensity intervals, and iron discipline. This plan is not for the soft.",
        difficulty: .elite,
        accentColor: .red,
        iconSymbol: "flame.fill",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Max Strength — Lower", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 5, reps: "3",   restSeconds: 240, notes: "Work up to 3RM — maximum weight"),
                    .init(name: "Romanian Deadlift",sets: 4, reps: "6",   restSeconds: 120, notes: "Heavy — hamstring tension throughout"),
                    .init(name: "Leg Press",       sets: 4, reps: "8",   restSeconds: 90,  notes: "High load"),
                    .init(name: "Sprint",          sets: 8, reps: "200m",restSeconds: 90,  notes: "Max effort — simulate quirk activation"),
                ],
                questTitle: "Pro Hero Protocol — Max Lower",
                questDetails: "5×3 squats at near-max. Eight 200m sprints. This is what the number one hero's legs are built from.",
                xpReward: 200
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Max Strength — Upper", isRest: false,
                exercises: [
                    .init(name: "Bench Press",     sets: 5, reps: "3",   restSeconds: 240, notes: "Near-max load"),
                    .init(name: "Weighted Pull-Up",sets: 5, reps: "5",   restSeconds: 120, notes: "Add weight on belt"),
                    .init(name: "Overhead Press",  sets: 4, reps: "5",   restSeconds: 120, notes: "Strict — no leg drive"),
                    .init(name: "Barbell Row",     sets: 4, reps: "6",   restSeconds: 90,  notes: "Heavy — maintain flat back"),
                ],
                questTitle: "Pro Hero Protocol — Max Upper",
                questDetails: "Bench, weighted pull-ups, OHP, rows. Five heavy sets each. Endeavor trained this way for 20 years.",
                xpReward: 190
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "HIIT Conditioning", isRest: false,
                exercises: [
                    .init(name: "Battle Rope",     sets: 5, reps: "30s on / 30s off", restSeconds: 0, notes: "Full effort every round"),
                    .init(name: "Kettlebell Swing",sets: 5, reps: "20",  restSeconds: 60, notes: "Hip drive — explosive"),
                    .init(name: "Box Jump",        sets: 4, reps: "10",  restSeconds: 60, notes: "Max height"),
                    .init(name: "Sled Push",       sets: 4, reps: "20m", restSeconds: 90, notes: "Heavy load"),
                ],
                questTitle: "Pro Hero Protocol — HIIT Conditioning",
                questDetails: "Conditioning circuit. Battle ropes, kettlebell swings, box jumps, sled. Pro heroes need both strength AND endurance.",
                xpReward: 180
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Hypertrophy — Push", isRest: false,
                exercises: [
                    .init(name: "Incline Bench Press", sets: 4, reps: "8-10", restSeconds: 90, notes: ""),
                    .init(name: "Dumbbell Shoulder Press", sets: 4, reps: "10", restSeconds: 90, notes: ""),
                    .init(name: "Lateral Raise",   sets: 4, reps: "15",  restSeconds: 60, notes: ""),
                    .init(name: "Tricep Dips",     sets: 4, reps: "Max", restSeconds: 90, notes: "Add weight"),
                ],
                questTitle: "Pro Hero Protocol — Push Hypertrophy", questDetails: "Volume push day. Incline press, shoulder press, laterals, dips. Build the size that backs up the strength.", xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Hypertrophy — Pull & Legs", isRest: false,
                exercises: [
                    .init(name: "Deadlift",        sets: 4, reps: "8",   restSeconds: 120, notes: "Moderate weight — focus on form"),
                    .init(name: "Pull-Ups",        sets: 4, reps: "Max", restSeconds: 90,  notes: ""),
                    .init(name: "Leg Curl",        sets: 4, reps: "12",  restSeconds: 60,  notes: ""),
                    .init(name: "Barbell Curl",    sets: 3, reps: "12",  restSeconds: 60,  notes: ""),
                ],
                questTitle: "Pro Hero Protocol — Pull & Legs", questDetails: "Deadlifts moderate, pull-ups to failure, leg curls, curls. Balanced strength.", xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Active Recovery + Run", isRest: false,
                exercises: [
                    .init(name: "Running", sets: 1, reps: "6 km", restSeconds: 0, notes: "Moderate pace"),
                    .init(name: "Stretching", sets: 1, reps: "20 min", restSeconds: 0, notes: ""),
                ],
                questTitle: "Recovery Run", questDetails: "6 km run. Full body stretch. Recovery is training.", xpReward: 90
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Mandatory rest. Eat, sleep, recover. The number one hero doesn't burn out.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 3800,
            proteinGrams: 240,
            carbGrams: 440,
            fatGrams: 100,
            waterGlasses: 14,
            mealPrepTips: [
                "6 meals per day minimum — body can't sustain elite output on 3 meals",
                "1g protein per lb bodyweight is the floor, not the ceiling",
                "Pre-workout: white rice + chicken 90 min before lifting",
                "Creatine monohydrate 5g daily — non-negotiable for this intensity",
            ],
            avoidList: ["Alcohol", "Calorie deficit", "Skipping meals", "Low protein days", "Junk food on heavy training days"]
        ),
        targetGender: .male
    )

    // MARK: - Asta (Black Clover)
    // Born with zero magic — built pure physical dominance. Massive volume, anti-magic sword training.
    static let asta = AnimeWorkoutPlan(
        id: "asta",
        character: "Asta",
        anime: "Black Clover",
        tagline: "No magic? No problem. Outwork everyone.",
        description: "Asta has no magic in a world of magic users. He compensated with a body built through relentless physical training — arguably the most physically gifted human in the series. Pure grind, zero shortcuts.",
        difficulty: .advanced,
        accentColor: .purple,
        iconSymbol: "bolt.fill",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Anti-Magic Strength", isRest: false,
                exercises: [
                    .init(name: "Deadlift",        sets: 5, reps: "5",   restSeconds: 180, notes: "Build the base — Asta swings a giant black sword"),
                    .init(name: "Farmer's Carry",  sets: 4, reps: "40m", restSeconds: 90,  notes: "As heavy as possible — grip and total body"),
                    .init(name: "Atlas Stone (Sandbag)", sets: 4, reps: "5", restSeconds: 120, notes: "Simulate heavy sword lifting"),
                    .init(name: "Push-Ups",        sets: 4, reps: "30",  restSeconds: 60,  notes: "High volume — warm down"),
                ],
                questTitle: "Black Bull Training — Sword Strength",
                questDetails: "Asta swings a sword larger than his body. Deadlifts, carries, sandbag work. Build the grip and back to match.",
                xpReward: 170
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Speed & Reaction", isRest: false,
                exercises: [
                    .init(name: "Sprint",          sets: 8, reps: "50m", restSeconds: 60,  notes: "Explosive start every rep"),
                    .init(name: "Lateral Shuffle", sets: 4, reps: "10m each way", restSeconds: 45, notes: "Quick feet"),
                    .init(name: "Plyometric Push-Up", sets: 4, reps: "10", restSeconds: 60, notes: "Clap at top"),
                    .init(name: "Jump Squat",      sets: 4, reps: "15",  restSeconds: 60,  notes: "Explosive — land soft"),
                ],
                questTitle: "Black Bull Training — Speed Drill",
                questDetails: "Speed and agility. Asta closes distance on mages before they can cast. Sprint work, lateral drills, explosive plyos.",
                xpReward: 150
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Endurance — The Grind", isRest: false,
                exercises: [
                    .init(name: "Running",         sets: 1, reps: "12 km", restSeconds: 0, notes: "Moderate pace — simulate mountain training"),
                    .init(name: "Pull-Ups",        sets: 5, reps: "Max",   restSeconds: 90, notes: "After the run — when tired"),
                    .init(name: "Sit-Ups",         sets: 5, reps: "30",    restSeconds: 45, notes: ""),
                ],
                questTitle: "Black Bull Training — Endurance Run",
                questDetails: "12 km run then pull-ups. Asta trained in the mountains with no breaks. Match the effort.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Upper Body Power", isRest: false,
                exercises: [
                    .init(name: "Bench Press",     sets: 5, reps: "5",   restSeconds: 180, notes: "Heavy — press like you're pushing a sword through armour"),
                    .init(name: "Weighted Dips",   sets: 4, reps: "8",   restSeconds: 90,  notes: ""),
                    .init(name: "One-Arm Dumbbell Row", sets: 4, reps: "10 each", restSeconds: 60, notes: "Heavy — unilateral like sword swings"),
                    .init(name: "Chin-Ups",        sets: 4, reps: "Max", restSeconds: 90,  notes: "Supinated grip"),
                ],
                questTitle: "Black Bull Training — Upper Power",
                questDetails: "Heavy bench, weighted dips, one-arm rows, chin-ups. Upper body power that supports the Anti-Magic sword.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Full Body Circuit", isRest: false,
                exercises: [
                    .init(name: "Thruster",        sets: 5, reps: "10",  restSeconds: 90,  notes: "Barbell squat to press — full body"),
                    .init(name: "Pull-Ups",        sets: 5, reps: "10",  restSeconds: 60,  notes: ""),
                    .init(name: "Burpee",          sets: 5, reps: "10",  restSeconds: 60,  notes: ""),
                    .init(name: "Kettlebell Swing",sets: 4, reps: "20",  restSeconds: 60,  notes: "Hip explosion"),
                ],
                questTitle: "Black Bull Training — Circuit Day",
                questDetails: "Five-round circuit. Thrusters, pull-ups, burpees, swings. No magic needed — just will.",
                xpReward: 170
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Grip & Forearm Finisher", isRest: false,
                exercises: [
                    .init(name: "Dead Hang",       sets: 5, reps: "Max time", restSeconds: 60, notes: "Until failure"),
                    .init(name: "Wrist Roller",    sets: 3, reps: "3 up+down", restSeconds: 60, notes: ""),
                    .init(name: "Running",         sets: 1, reps: "5 km", restSeconds: 0, notes: "Easy pace"),
                ],
                questTitle: "Black Bull Training — Grip Day", questDetails: "Grip training and a short run. Asta's grip is what keeps the anti-magic sword in hand.", xpReward: 100
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Rest and eat. You earned it. Prepare for next week's grind.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 3200,
            proteinGrams: 200,
            carbGrams: 390,
            fatGrams: 80,
            waterGlasses: 11,
            mealPrepTips: [
                "Asta grew up eating simple food — rice, beans, eggs. Keep it whole and consistent",
                "High carb days Tuesday/Wednesday/Friday to fuel sprint and endurance work",
                "Protein shake immediately post-workout on every training day",
                "Prep meals in bulk — Asta never stopped training to worry about food",
            ],
            avoidList: ["Alcohol", "Processed food", "Low carb on sprint days", "Skipping post-workout meals"]
        ),
        targetGender: .male
    )

    // MARK: - Rudeus Greyrat (Mushoku Tensei / Jobless Reincarnation)
    // Mage who became a complete fighter — magic endurance, mobility, intelligent training.
    static let rudeus = AnimeWorkoutPlan(
        id: "rudeus",
        character: "Rudeus Greyrat",
        anime: "Mushoku Tensei",
        tagline: "A second chance. Use it better.",
        description: "Rudeus reincarnated and chose to build the body he never had. Intelligent progressive overload, mobility work, and well-rounded conditioning. This is the plan for someone starting over and doing it right.",
        difficulty: .beginner,
        accentColor: .blue,
        iconSymbol: "wand.and.stars",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Foundation — Lower Body", isRest: false,
                exercises: [
                    .init(name: "Goblet Squat",    sets: 4, reps: "12",  restSeconds: 90, notes: "Learn the pattern first — depth and form"),
                    .init(name: "Romanian Deadlift",sets: 3, reps: "10",  restSeconds: 90, notes: "Light — feel the hinge"),
                    .init(name: "Walking Lunge",   sets: 3, reps: "12 each", restSeconds: 60, notes: ""),
                    .init(name: "Calf Raise",      sets: 3, reps: "15",  restSeconds: 45, notes: ""),
                ],
                questTitle: "Second Life Directive — Lower Foundation",
                questDetails: "Rudeus built from scratch with knowledge of what works. Goblet squats, RDLs, lunges. Learn the patterns before adding load.",
                xpReward: 110
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Foundation — Upper Body", isRest: false,
                exercises: [
                    .init(name: "Push-Ups",        sets: 4, reps: "15",  restSeconds: 60, notes: "Perfect form — slow down"),
                    .init(name: "Dumbbell Row",    sets: 4, reps: "12",  restSeconds: 60, notes: "Support with bench"),
                    .init(name: "Dumbbell Shoulder Press", sets: 3, reps: "12", restSeconds: 60, notes: ""),
                    .init(name: "Resistance Band Pull-Apart", sets: 3, reps: "15", restSeconds: 45, notes: "Rear delt health"),
                ],
                questTitle: "Second Life Directive — Upper Foundation",
                questDetails: "Upper body with dumbbells and bodyweight. Build the connective tissue right — Rudeus learned from Roxy not to rush.",
                xpReward: 110
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Cardio & Mobility", isRest: false,
                exercises: [
                    .init(name: "Running",         sets: 1, reps: "4 km", restSeconds: 0, notes: "Easy conversational pace"),
                    .init(name: "Yoga Flow",       sets: 1, reps: "20 min", restSeconds: 0, notes: "Full body mobility"),
                    .init(name: "Core Circuit",    sets: 3, reps: "30s each", restSeconds: 30, notes: "Plank, bird dog, dead bug"),
                ],
                questTitle: "Second Life Directive — Recovery Run",
                questDetails: "Easy run and mobility. Rudeus studied magic every day — study movement the same way.",
                xpReward: 100
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Progressive Lower", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 4, reps: "8",   restSeconds: 120, notes: "Add weight from Monday's goblet squat"),
                    .init(name: "Deadlift",        sets: 3, reps: "5",   restSeconds: 120, notes: "Introductory load — focus on form"),
                    .init(name: "Step-Up",         sets: 3, reps: "10 each", restSeconds: 60, notes: "Weighted if possible"),
                ],
                questTitle: "Second Life Directive — Progressive Lower",
                questDetails: "Progress from Monday. Add weight to the squat. Try your first real deadlift. Small consistent gains.",
                xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Progressive Upper", isRest: false,
                exercises: [
                    .init(name: "Dumbbell Bench Press", sets: 4, reps: "10", restSeconds: 90, notes: "Progress from push-ups"),
                    .init(name: "Lat Pulldown",    sets: 4, reps: "10",  restSeconds: 90,  notes: "Or band-assisted pull-ups"),
                    .init(name: "Arnold Press",    sets: 3, reps: "10",  restSeconds: 60,  notes: "Full rotation"),
                    .init(name: "Bicep Curl",      sets: 3, reps: "12",  restSeconds: 45,  notes: ""),
                ],
                questTitle: "Second Life Directive — Progressive Upper",
                questDetails: "Step up from Tuesday. Dumbbell bench, lat pulldown, shoulder work. Progress is the whole point.",
                xpReward: 120
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Adventure Day", isRest: false,
                exercises: [
                    .init(name: "Hiking or Long Walk", sets: 1, reps: "60 min", restSeconds: 0, notes: "Real world movement — Rudeus explored the world"),
                    .init(name: "Stretching",      sets: 1, reps: "15 min", restSeconds: 0, notes: ""),
                ],
                questTitle: "Second Life — Explore", questDetails: "Get outside. Walk, hike, explore. The world is your training ground.", xpReward: 80
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Study, plan, recover. Rudeus always used rest to reflect and improve. Do the same.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 2200,
            proteinGrams: 140,
            carbGrams: 270,
            fatGrams: 65,
            waterGlasses: 8,
            mealPrepTips: [
                "Beginner plan — focus on whole foods first: chicken, rice, vegetables",
                "Don't overthink it: protein + carbs + fat at each meal",
                "Meal prep 3 days at a time — manageable and builds the habit",
                "Track your food for the first 2 weeks to calibrate portions",
            ],
            avoidList: ["Skipping breakfast", "Eating under 1500 calories", "Excessive alcohol", "Ultra-processed food"]
        ),
        targetGender: .male
    )

    // MARK: - Deku / Izuku Midoriya (My Hero Academia)
    // One For All recipient — started from zero, built a base before the power arrived.
    static let deku = AnimeWorkoutPlan(
        id: "deku",
        character: "Izuku Midoriya (Deku)",
        anime: "My Hero Academia",
        tagline: "Smash through every limit.",
        description: "Deku trained his frail body from scratch to receive One For All. All Might gave him 10 months of beach-cleaning hell. This plan honours that — total body conditioning starting from nothing and building toward everything.",
        difficulty: .intermediate,
        accentColor: .green,
        iconSymbol: "figure.run",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Beach Training — Carry & Lift", isRest: false,
                exercises: [
                    .init(name: "Sandbag Carry",   sets: 5, reps: "30m", restSeconds: 90,  notes: "Simulate beach trash — heavy awkward load"),
                    .init(name: "Tire Flip",        sets: 4, reps: "8",   restSeconds: 120, notes: "Or heavy sandbag clean"),
                    .init(name: "Push-Ups",         sets: 5, reps: "20",  restSeconds: 60,  notes: ""),
                    .init(name: "Running",          sets: 1, reps: "5 km",restSeconds: 0,   notes: "Beach run if possible"),
                ],
                questTitle: "All Might's Protocol — Beach Day 1",
                questDetails: "Deku cleaned a beach by hand in 10 months. Carries, flips, runs. Build the vessel that can hold power.",
                xpReward: 150
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Upper Body Strength", isRest: false,
                exercises: [
                    .init(name: "Pull-Ups",        sets: 5, reps: "Max",  restSeconds: 90, notes: "Deku started unable to do one — every rep counts"),
                    .init(name: "Push-Ups",        sets: 5, reps: "25",   restSeconds: 60, notes: ""),
                    .init(name: "Dumbbell Row",    sets: 4, reps: "12",   restSeconds: 60, notes: ""),
                    .init(name: "Tricep Dip",      sets: 4, reps: "15",   restSeconds: 60, notes: ""),
                ],
                questTitle: "All Might's Protocol — Upper Body",
                questDetails: "Pull-ups to failure, push volume, rows, dips. Midoriya's arms needed to throw Detroit Smashes. Build them.",
                xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Legs & Core", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 5, reps: "15",  restSeconds: 90, notes: "High rep — base building"),
                    .init(name: "Box Jump",        sets: 4, reps: "10",  restSeconds: 60, notes: "One For All starts with explosion"),
                    .init(name: "Hanging Knee Raise", sets: 4, reps: "15", restSeconds: 60, notes: ""),
                    .init(name: "Plank",           sets: 3, reps: "60s", restSeconds: 60, notes: ""),
                ],
                questTitle: "All Might's Protocol — Legs & Core", questDetails: "Legs and core. Deku's kicks needed to be as powerful as his punches. High rep squats and explosive jumps.", xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Endurance Run", isRest: false,
                exercises: [
                    .init(name: "Running",         sets: 1, reps: "8 km", restSeconds: 0, notes: "Build the aerobic engine"),
                    .init(name: "Walking Lunge",   sets: 3, reps: "20 each", restSeconds: 60, notes: "Post run — legs still working"),
                ],
                questTitle: "All Might's Protocol — Run",
                questDetails: "8 km run. Deku ran every morning. The aerobic base is what lets you keep fighting when others stop.",
                xpReward: 130
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Full Power Circuit", isRest: false,
                exercises: [
                    .init(name: "Deadlift",        sets: 4, reps: "8",   restSeconds: 120, notes: ""),
                    .init(name: "Bench Press",     sets: 4, reps: "8",   restSeconds: 90,  notes: ""),
                    .init(name: "Pull-Ups",        sets: 4, reps: "Max", restSeconds: 90,  notes: ""),
                    .init(name: "Sprint",          sets: 5, reps: "100m",restSeconds: 90,  notes: "All out — 100% effort"),
                ],
                questTitle: "All Might's Protocol — Full Power",
                questDetails: "Compound lifts and sprints. This is the capstone of the week. 100% effort on every rep.",
                xpReward: 180
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Flexibility & Recovery", isRest: false,
                exercises: [
                    .init(name: "Yoga Flow",       sets: 1, reps: "30 min", restSeconds: 0, notes: "Full body"),
                    .init(name: "Light Running",   sets: 1, reps: "3 km",   restSeconds: 0, notes: "Easy pace"),
                ],
                questTitle: "Recovery Day", questDetails: "Mobility and light run. Deku studies heroes on rest days. Study your own body today.", xpReward: 80
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Rest and reflect. Write down what you'll improve next week. Midoriya always had his notebook.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 2700,
            proteinGrams: 165,
            carbGrams: 330,
            fatGrams: 72,
            waterGlasses: 10,
            mealPrepTips: [
                "Katsudon (pork cutlet rice bowl) is Deku's favourite meal — use it as a reward meal post heavy session",
                "High carb before beach training days — you need fuel for carries and runs",
                "Post-workout: 40g protein + 60g carbs within 45 min",
                "Don't skip breakfast — Deku trained mornings, fuel accordingly",
            ],
            avoidList: ["Skipping meals", "Alcohol during training phases", "Low protein days", "Excessive junk food"]
        ),
        targetGender: .male
    )

    // MARK: - Maki Zenin (Jujutsu Kaisen)
    // Zero cursed energy — compensated with supernatural physical training and weapon mastery.
    static let maki = AnimeWorkoutPlan(
        id: "maki",
        character: "Maki Zenin",
        anime: "Jujutsu Kaisen",
        tagline: "No cursed energy. Just pure, terrifying strength.",
        description: "Maki has almost no cursed energy in a world where sorcerers fight with it. She overpowered that limitation through physical training that makes her body itself a weapon. Lean, explosive, powerful, relentless.",
        difficulty: .advanced,
        accentColor: .pink,
        iconSymbol: "figure.gymnastics",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Explosive Power", isRest: false,
                exercises: [
                    .init(name: "Power Clean",     sets: 5, reps: "3",   restSeconds: 180, notes: "Explosive pull — Maki's attacks come from total body power"),
                    .init(name: "Box Jump",        sets: 4, reps: "8",   restSeconds: 90,  notes: "Max height"),
                    .init(name: "Broad Jump",      sets: 4, reps: "6",   restSeconds: 90,  notes: "Maximum horizontal distance"),
                    .init(name: "Sprint",          sets: 6, reps: "30m", restSeconds: 60,  notes: "Acceleration focus"),
                ],
                questTitle: "Zenin Clan Override — Power Day",
                questDetails: "Maki's power is pure explosive speed and strength. Power cleans, jumps, broad jumps, sprints. Cursed energy is irrelevant.",
                xpReward: 170
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Upper Body Strength", isRest: false,
                exercises: [
                    .init(name: "Bench Press",     sets: 5, reps: "5",   restSeconds: 180, notes: "Heavy — pushing strength"),
                    .init(name: "Weighted Pull-Up",sets: 5, reps: "5",   restSeconds: 120, notes: "Add weight on belt"),
                    .init(name: "Overhead Press",  sets: 4, reps: "6",   restSeconds: 90,  notes: "Strict press"),
                    .init(name: "Face Pull",       sets: 3, reps: "15",  restSeconds: 60,  notes: "Rotator cuff health for weapon work"),
                ],
                questTitle: "Zenin Clan Override — Upper Strength",
                questDetails: "Bench, weighted pull-ups, OHP. Maki's upper body controls cursed tools that would cripple others.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Legs & Agility", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 5, reps: "5",   restSeconds: 180, notes: "Heavy — strength base"),
                    .init(name: "Single-Leg Box Jump", sets: 4, reps: "6 each", restSeconds: 90, notes: ""),
                    .init(name: "Lateral Sprint",  sets: 5, reps: "5m each way", restSeconds: 45, notes: "Reaction drills"),
                    .init(name: "Cossack Squat",   sets: 3, reps: "8 each", restSeconds: 60, notes: "Hip mobility for combat stance"),
                ],
                questTitle: "Zenin Clan Override — Legs & Agility",
                questDetails: "Squat heavy, single-leg explosive work, lateral movement. Maki changes direction faster than cursed spirits can react.",
                xpReward: 160
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Core & Anti-Rotation", isRest: false,
                exercises: [
                    .init(name: "Ab Wheel Rollout",sets: 4, reps: "10",  restSeconds: 60, notes: "Full extension if possible"),
                    .init(name: "Pallof Press",    sets: 3, reps: "12 each", restSeconds: 60, notes: "Anti-rotation for weapon control"),
                    .init(name: "Dragon Flag",     sets: 3, reps: "5",   restSeconds: 90, notes: "Full control on descent"),
                    .init(name: "Turkish Get-Up",  sets: 3, reps: "3 each", restSeconds: 90, notes: "Total body control + core"),
                ],
                questTitle: "Zenin Clan Override — Core",
                questDetails: "Anti-rotation core work. Maki handles cursed weapons with total body control. This is why.",
                xpReward: 140
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Combat Conditioning", isRest: false,
                exercises: [
                    .init(name: "Burpee",          sets: 5, reps: "10",  restSeconds: 60,  notes: "Full extension every rep"),
                    .init(name: "Kettlebell Swing",sets: 5, reps: "15",  restSeconds: 60,  notes: "Hip drive"),
                    .init(name: "Battle Rope",     sets: 4, reps: "30s", restSeconds: 45,  notes: "Alternating waves"),
                    .init(name: "Pull-Ups",        sets: 4, reps: "Max", restSeconds: 90,  notes: ""),
                ],
                questTitle: "Zenin Clan Override — Combat Conditioning",
                questDetails: "Conditioning circuit. This is what fighting multiple grade-1 curses without energy feels like. Survive it.",
                xpReward: 170
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Skills & Mobility", isRest: false,
                exercises: [
                    .init(name: "Handstand Practice", sets: 5, reps: "30s", restSeconds: 60, notes: "Balance and shoulder strength"),
                    .init(name: "Flexibility Flow",sets: 1, reps: "25 min", restSeconds: 0, notes: "Hip flexors, hamstrings, thoracic"),
                    .init(name: "Running",         sets: 1, reps: "4 km", restSeconds: 0,  notes: "Easy pace"),
                ],
                questTitle: "Zenin Clan Override — Skills Day", questDetails: "Handstand practice, mobility, run. Combat skill requires total body awareness.", xpReward: 90
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Rest. Maki's body is her only tool. Protect it and let it recover.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 2800,
            proteinGrams: 175,
            carbGrams: 320,
            fatGrams: 80,
            waterGlasses: 10,
            mealPrepTips: [
                "Lean protein every meal — fish, chicken, eggs, Greek yogurt",
                "Anti-inflammatory focus: berries, leafy greens, olive oil — reduce soreness for daily training",
                "Pre-workout: banana + protein bar 45 min before sessions",
                "Omega-3 supplement daily — joint health for high-impact training",
            ],
            avoidList: ["Alcohol", "High sugar foods", "Heavy meals within 2 hours of training", "Skipping recovery meals"]
        ),
        targetGender: .female
    )

    // MARK: - Stars and Stripes (My Hero Academia)
    // World's number 2 hero — military-grade conditioning, peak athletic performance.
    static let starsAndStripes = AnimeWorkoutPlan(
        id: "stars-and-stripes",
        character: "Stars and Stripes",
        anime: "My Hero Academia",
        tagline: "American hero. Military discipline. Zero compromise.",
        description: "Cathleen Bate — Stars and Stripes — was the world's second-ranked hero, trained under All Might. Military-grade conditioning, aerial combat focus, strength and endurance combined at the absolute highest level. Elite tier only.",
        difficulty: .elite,
        accentColor: .blue,
        iconSymbol: "star.fill",
        weeklySchedule: [
            AnimeWorkoutPlan.DayPlan(
                dayName: "Monday", focus: "Military Strength — Lower", isRest: false,
                exercises: [
                    .init(name: "Squat",           sets: 6, reps: "3",   restSeconds: 240, notes: "Competition-style — max load"),
                    .init(name: "Jump Squat",      sets: 5, reps: "5",   restSeconds: 120, notes: "Loaded — 30% of squat max"),
                    .init(name: "Walking Lunge",   sets: 4, reps: "20 each", restSeconds: 90, notes: "Weighted"),
                    .init(name: "Sprint",          sets: 10, reps: "100m", restSeconds: 60, notes: "Military quick — all out"),
                ],
                questTitle: "Hero Commission Protocol — Lower Power",
                questDetails: "Military lower body. 6×3 max squats, loaded jumps, 10 sprints. Stars and Stripes combined brute strength with flight speed.",
                xpReward: 220
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Tuesday", focus: "Military Strength — Upper", isRest: false,
                exercises: [
                    .init(name: "Bench Press",     sets: 6, reps: "3",   restSeconds: 240, notes: "Max load"),
                    .init(name: "Weighted Pull-Up",sets: 6, reps: "5",   restSeconds: 120, notes: "Heavy belt"),
                    .init(name: "Overhead Press",  sets: 5, reps: "5",   restSeconds: 120, notes: "Strict military press"),
                    .init(name: "Barbell Row",     sets: 4, reps: "6",   restSeconds: 90,  notes: "Heavy"),
                ],
                questTitle: "Hero Commission Protocol — Upper Power",
                questDetails: "Maximum upper body strength. Bench, pull-ups, strict OHP, rows. Six working sets on the main lifts.",
                xpReward: 210
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Wednesday", focus: "Aerial Conditioning (HIIT)", isRest: false,
                exercises: [
                    .init(name: "Box Jump",        sets: 6, reps: "8",   restSeconds: 60,  notes: "Max height every rep"),
                    .init(name: "Battle Rope",     sets: 5, reps: "45s", restSeconds: 45,  notes: "All out"),
                    .init(name: "Sled Push",       sets: 5, reps: "20m", restSeconds: 90,  notes: "Max load"),
                    .init(name: "Assault Bike",    sets: 1, reps: "20 min", restSeconds: 0, notes: "Push hard last 5 min"),
                ],
                questTitle: "Hero Commission Protocol — Aerial HIIT",
                questDetails: "High-intensity conditioning. Box jumps, battle ropes, sled, assault bike. Flight ability requires elite cardiovascular capacity.",
                xpReward: 200
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Thursday", focus: "Hypertrophy + Core", isRest: false,
                exercises: [
                    .init(name: "Incline Bench Press", sets: 5, reps: "8", restSeconds: 90, notes: ""),
                    .init(name: "Dumbbell Row",    sets: 5, reps: "10",  restSeconds: 90,  notes: "Heavy"),
                    .init(name: "Dragon Flag",     sets: 4, reps: "6",   restSeconds: 90,  notes: "Controlled negative"),
                    .init(name: "Hanging Leg Raise", sets: 4, reps: "12", restSeconds: 60, notes: ""),
                ],
                questTitle: "Hero Commission Protocol — Hypertrophy",
                questDetails: "Volume push/pull and heavy core. Build the size behind the strength.", xpReward: 180
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Friday", focus: "Total Body Power", isRest: false,
                exercises: [
                    .init(name: "Power Clean",     sets: 5, reps: "3",   restSeconds: 180, notes: "Explosive — generate maximum force"),
                    .init(name: "Push Press",      sets: 5, reps: "5",   restSeconds: 120, notes: "Dip and drive — overhead power"),
                    .init(name: "Trap Bar Deadlift", sets: 5, reps: "5", restSeconds: 120, notes: "Or straight bar"),
                    .init(name: "Sprint",          sets: 6, reps: "200m",restSeconds: 90,  notes: "All out"),
                ],
                questTitle: "Hero Commission Protocol — Total Power",
                questDetails: "Olympic-style power day. Power cleans, push press, trap bar pulls, sprints. This is what second-ranked hero output looks like.",
                xpReward: 220
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Saturday", focus: "Long Run + Mobility", isRest: false,
                exercises: [
                    .init(name: "Running",         sets: 1, reps: "10 km", restSeconds: 0, notes: "Moderate to hard pace — not easy"),
                    .init(name: "Stretching",      sets: 1, reps: "20 min", restSeconds: 0, notes: "Full body"),
                ],
                questTitle: "Hero Commission Protocol — Endurance Run",
                questDetails: "10 km run at pace. Stars and Stripes had the endurance to fight Shigaraki at full power. Build it.",
                xpReward: 130
            ),
            AnimeWorkoutPlan.DayPlan(
                dayName: "Sunday", focus: "Rest", isRest: true, exercises: [],
                questTitle: "Rest Day", questDetails: "Mandatory. Elite recovery is elite training. Sleep, eat, prepare.", xpReward: 30
            ),
        ],
        nutrition: AnimeWorkoutPlan.PlanNutrition(
            dailyCalories: 4000,
            proteinGrams: 250,
            carbGrams: 480,
            fatGrams: 110,
            waterGlasses: 14,
            mealPrepTips: [
                "Military-style meal prep: 7 days of food prepped on Sunday, zero excuses mid-week",
                "Carb cycle: higher carbs Mon/Tue/Wed/Fri (training days), lower on Thu/Sat",
                "1.2g protein per lb bodyweight — non-negotiable at this intensity",
                "Creatine + beta-alanine pre-workout, protein + fast carbs immediately post",
            ],
            avoidList: ["Alcohol", "Calorie deficit on heavy training days", "Processed food", "Inadequate sleep", "Skipping any meal"]
        ),
        targetGender: .female
    )
}
