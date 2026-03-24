import Foundation

// MARK: - Built-In Exercise Database
// Offline-first exercise library used as a fallback when the remote API is
// unavailable. Covers Strength, Cardio, Flexibility and Mixed types with
// full instructions, muscle groups, equipment and difficulty ratings.

struct BuiltInExercises {

    // MARK: - Search

    static func search(type: String, query: String) -> [Exercise] {
        let pool = all
        var results: [Exercise]

        // Filter by type first
        if type.isEmpty {
            results = pool
        } else {
            let t = type.lowercased()
            results = pool.filter { ($0.type ?? "").lowercased().contains(t) }
        }

        // Then filter / rank by query
        if query.isEmpty {
            return results
        }
        let q = query.lowercased()
        return results.filter { ex in
            ex.name.lowercased().contains(q) ||
            (ex.muscle ?? "").lowercased().contains(q) ||
            (ex.equipment ?? "").lowercased().contains(q) ||
            (ex.instructions ?? "").lowercased().contains(q)
        }
    }

    // MARK: - Full Database

    static let all: [Exercise] = strength + cardio + flexibility + mixed

    // MARK: Strength

    static let strength: [Exercise] = [
        Exercise(name: "Barbell Back Squat",
                 type: "strength", muscle: "quadriceps",
                 secondaryMuscle: "glutes", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Stand with feet shoulder-width apart, bar resting on upper traps.\n2. Brace core and descend by pushing knees out and hips back.\n3. Lower until thighs are parallel to floor or below.\n4. Drive through heels to return to standing.\n5. Keep chest tall and spine neutral throughout."),

        Exercise(name: "Deadlift",
                 type: "strength", muscle: "back",
                 secondaryMuscle: "hamstrings", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Stand with bar over mid-foot, feet hip-width apart.\n2. Hinge at hips and grip bar just outside legs.\n3. Flatten back, pull slack out of bar.\n4. Push floor away while keeping bar close to body.\n5. Lock hips and knees out at top, then reverse."),

        Exercise(name: "Bench Press",
                 type: "strength", muscle: "chest",
                 secondaryMuscle: "triceps", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Lie on bench, eyes under bar. Grip slightly wider than shoulder-width.\n2. Unrack and lower bar to lower chest with elbows ~75° from torso.\n3. Touch chest lightly and press bar back up in a slight arc.\n4. Keep feet flat, arch natural, and shoulder blades retracted."),

        Exercise(name: "Overhead Press",
                 type: "strength", muscle: "shoulders",
                 secondaryMuscle: "triceps", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Hold bar at collar-bone height, grip just outside shoulders.\n2. Brace abs and glutes. Press bar straight up, head moving back slightly.\n3. Lock out overhead with bar over mid-foot.\n4. Lower controlled back to starting position."),

        Exercise(name: "Romanian Deadlift",
                 type: "strength", muscle: "hamstrings",
                 secondaryMuscle: "back", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Hold barbell at hip height with overhand grip.\n2. Push hips back while keeping bar close to legs.\n3. Lower until hamstrings are fully stretched (typically mid-shin).\n4. Drive hips forward to return to standing."),

        Exercise(name: "Pull-Up",
                 type: "strength", muscle: "back",
                 secondaryMuscle: "biceps", equipment: "pull-up bar",
                 difficulty: "intermediate",
                 instructions: "1. Hang from bar with overhand grip slightly wider than shoulders.\n2. Depress shoulder blades and pull chest toward bar.\n3. Lead with elbows driving down and back.\n4. Clear chin over bar, then lower fully under control."),

        Exercise(name: "Dumbbell Lunges",
                 type: "strength", muscle: "quadriceps",
                 secondaryMuscle: "glutes", equipment: "dumbbell",
                 difficulty: "beginner",
                 instructions: "1. Hold a dumbbell in each hand at your sides.\n2. Step forward with one leg and lower your back knee toward the floor.\n3. Keep front knee over ankle, torso upright.\n4. Push off front foot to return to start. Alternate legs."),

        Exercise(name: "Dumbbell Row",
                 type: "strength", muscle: "back",
                 secondaryMuscle: "biceps", equipment: "dumbbell",
                 difficulty: "beginner",
                 instructions: "1. Place one hand and knee on a bench for support.\n2. Hold dumbbell with free hand, arm extended.\n3. Pull dumbbell to hip, keeping elbow close to body.\n4. Lower with control and repeat."),

        Exercise(name: "Incline Dumbbell Press",
                 type: "strength", muscle: "chest",
                 secondaryMuscle: "shoulders", equipment: "dumbbell",
                 difficulty: "intermediate",
                 instructions: "1. Set bench to 30-45°. Hold dumbbells at chest height.\n2. Press up and slightly inward until arms are nearly extended.\n3. Lower controlled to starting position."),

        Exercise(name: "Bicep Curl",
                 type: "strength", muscle: "biceps",
                 secondaryMuscle: "forearms", equipment: "dumbbell",
                 difficulty: "beginner",
                 instructions: "1. Stand holding dumbbells at sides, palms facing forward.\n2. Curl weights toward shoulders by flexing at elbow.\n3. Squeeze biceps at top, lower slowly."),

        Exercise(name: "Tricep Dip",
                 type: "strength", muscle: "triceps",
                 secondaryMuscle: "chest", equipment: "parallel bars",
                 difficulty: "intermediate",
                 instructions: "1. Grip parallel bars, arms extended, body upright.\n2. Lower by bending elbows to 90° while leaning slightly forward.\n3. Press back to starting position."),

        Exercise(name: "Cable Lateral Raise",
                 type: "strength", muscle: "shoulders",
                 secondaryMuscle: nil, equipment: "cable machine",
                 difficulty: "beginner",
                 instructions: "1. Stand beside cable machine, handle in far hand.\n2. Keep slight bend in elbow, raise arm to shoulder height.\n3. Lower with control. Complete reps then switch sides."),

        Exercise(name: "Leg Press",
                 type: "strength", muscle: "quadriceps",
                 secondaryMuscle: "glutes", equipment: "machine",
                 difficulty: "beginner",
                 instructions: "1. Sit in leg press machine, feet shoulder-width on platform.\n2. Release safety handles. Lower platform until knees are at 90°.\n3. Press through heels to full extension without locking knees."),

        Exercise(name: "Calf Raise",
                 type: "strength", muscle: "calves",
                 secondaryMuscle: nil, equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Stand on edge of step or flat floor.\n2. Rise onto balls of feet as high as possible.\n3. Hold briefly at top, lower heels below step level.\n4. Use dumbbells or machine for added resistance."),

        Exercise(name: "Plank",
                 type: "strength", muscle: "abdominals",
                 secondaryMuscle: "back", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Rest forearms on floor, elbows under shoulders.\n2. Extend legs, toes on floor. Raise hips to form straight line.\n3. Brace abs, glutes and quads. Hold without letting hips sag or rise."),

        Exercise(name: "Push-Up",
                 type: "strength", muscle: "chest",
                 secondaryMuscle: "triceps", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Place hands slightly wider than shoulders, body in a straight line.\n2. Lower chest to floor by bending elbows to ~45° from torso.\n3. Press back to full extension.\n4. Modify by dropping to knees to decrease difficulty."),

        Exercise(name: "Hip Thrust",
                 type: "strength", muscle: "glutes",
                 secondaryMuscle: "hamstrings", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Sit against a bench with bar across hips.\n2. Plant feet hip-width, drive hips up until body forms a straight line.\n3. Squeeze glutes hard at top. Lower with control."),

        Exercise(name: "Face Pull",
                 type: "strength", muscle: "shoulders",
                 secondaryMuscle: "back", equipment: "cable machine",
                 difficulty: "beginner",
                 instructions: "1. Set cable to head height with rope attachment.\n2. Pull rope toward face, flaring elbows high.\n3. External rotate at the end so hands are by ears.\n4. Return slowly."),

        Exercise(name: "Lat Pulldown",
                 type: "strength", muscle: "back",
                 secondaryMuscle: "biceps", equipment: "cable machine",
                 difficulty: "beginner",
                 instructions: "1. Sit at pulldown station, grab wide bar overhand.\n2. Lean slightly back, depress shoulder blades.\n3. Pull bar to upper chest leading with elbows.\n4. Stretch back up slowly."),

        Exercise(name: "Bulgarian Split Squat",
                 type: "strength", muscle: "quadriceps",
                 secondaryMuscle: "glutes", equipment: "dumbbell",
                 difficulty: "intermediate",
                 instructions: "1. Rear foot elevated on bench, front foot ~2 feet forward.\n2. Hold dumbbells at sides. Lower back knee toward floor.\n3. Keep front shin vertical. Drive through front heel to return."),
    ]

    // MARK: Cardio

    static let cardio: [Exercise] = [
        Exercise(name: "Treadmill Run",
                 type: "cardio", muscle: "quadriceps",
                 secondaryMuscle: "calves", equipment: "treadmill",
                 difficulty: "beginner",
                 instructions: "1. Start at a comfortable walking pace to warm up (2 min).\n2. Increase speed to a steady running pace.\n3. Maintain upright posture, relaxed arms, mid-foot strike.\n4. Cool down by reducing speed gradually for the final 2 minutes."),

        Exercise(name: "Cycling",
                 type: "cardio", muscle: "quadriceps",
                 secondaryMuscle: "calves", equipment: "stationary bike",
                 difficulty: "beginner",
                 instructions: "1. Adjust seat so knee has a slight bend at the bottom of the pedal stroke.\n2. Pedal at 60-90 RPM. Adjust resistance to maintain target heart rate.\n3. Keep core slightly engaged and avoid rocking your hips."),

        Exercise(name: "Rowing Machine",
                 type: "cardio", muscle: "back",
                 secondaryMuscle: "legs", equipment: "rowing machine",
                 difficulty: "intermediate",
                 instructions: "1. Sit with feet strapped in, shins vertical, grip handle.\n2. Drive through legs first, then lean back slightly and pull handle to lower ribs.\n3. Reverse: arms away, hinge forward, then bend knees.\n4. Ratio: legs 60%, back 20%, arms 20% of the pull."),

        Exercise(name: "Burpee",
                 type: "cardio", muscle: "quadriceps",
                 secondaryMuscle: "chest", equipment: "bodyweight",
                 difficulty: "intermediate",
                 instructions: "1. Stand, then squat and place hands on floor.\n2. Jump feet back into push-up position. Perform a push-up.\n3. Jump feet to hands, then explosively jump up with arms overhead."),

        Exercise(name: "Jump Rope",
                 type: "cardio", muscle: "calves",
                 secondaryMuscle: "shoulders", equipment: "jump rope",
                 difficulty: "beginner",
                 instructions: "1. Hold handles at hip height, elbows close to body.\n2. Rotate rope with wrists, not arms.\n3. Jump only 1-2cm off the ground and land softly on balls of feet.\n4. Progress to double-unders once basic rhythm is solid."),

        Exercise(name: "Box Jump",
                 type: "cardio", muscle: "quadriceps",
                 secondaryMuscle: "glutes", equipment: "plyo box",
                 difficulty: "intermediate",
                 instructions: "1. Stand in front of box, feet hip-width.\n2. Dip slightly, swing arms, then explosively jump onto the box.\n3. Land softly with knees bent, hips back.\n4. Step (don't jump) back down."),

        Exercise(name: "Battle Ropes",
                 type: "cardio", muscle: "shoulders",
                 secondaryMuscle: "back", equipment: "battle ropes",
                 difficulty: "intermediate",
                 instructions: "1. Stand with slight knee bend, rope in each hand.\n2. Alternate arms in rapid waves or both together.\n3. Maintain upright posture and tight core throughout."),

        Exercise(name: "Stair Climber",
                 type: "cardio", muscle: "glutes",
                 secondaryMuscle: "quadriceps", equipment: "stair climber",
                 difficulty: "beginner",
                 instructions: "1. Step onto machine, hold handrails lightly (not for support).\n2. Maintain steady climbing pace, push through full foot.\n3. Avoid leaning heavily on rails — keep torso upright."),

        Exercise(name: "Sled Push",
                 type: "cardio", muscle: "quadriceps",
                 secondaryMuscle: "chest", equipment: "sled",
                 difficulty: "intermediate",
                 instructions: "1. Load sled with appropriate weight. Stand behind, hands on posts.\n2. Lean forward at ~45° and drive through legs in short, powerful steps.\n3. Maintain low hips and push with both arms extended."),

        Exercise(name: "Mountain Climber",
                 type: "cardio", muscle: "abdominals",
                 secondaryMuscle: "quadriceps", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Start in push-up position, core tight.\n2. Drive one knee toward chest, then quickly switch legs.\n3. Keep hips level and move as fast as controlled form allows."),

        Exercise(name: "Kettlebell Swing",
                 type: "cardio", muscle: "glutes",
                 secondaryMuscle: "back", equipment: "kettlebell",
                 difficulty: "intermediate",
                 instructions: "1. Stand with kettlebell in front, feet shoulder-width.\n2. Hinge at hips to swing bell back between legs.\n3. Drive hips forward explosively to swing bell to shoulder height.\n4. Let it fall back and repeat — it's a hinge, not a squat."),
    ]

    // MARK: Flexibility

    static let flexibility: [Exercise] = [
        Exercise(name: "Standing Hamstring Stretch",
                 type: "stretching", muscle: "hamstrings",
                 secondaryMuscle: nil, equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Stand with feet together. Hinge at hips and reach toward the floor.\n2. Keep a slight bend in knees if needed.\n3. Hold for 30-60 seconds, breathing deeply."),

        Exercise(name: "Hip Flexor Lunge Stretch",
                 type: "stretching", muscle: "quadriceps",
                 secondaryMuscle: "hip flexors", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Kneel on one knee, front foot forward.\n2. Push hips forward until a stretch is felt in the front of the rear hip.\n3. Raise rear arm overhead for a deeper stretch. Hold 30s each side."),

        Exercise(name: "Seated Pigeon Pose",
                 type: "stretching", muscle: "glutes",
                 secondaryMuscle: "hip flexors", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Sit on floor. Place one ankle over the opposite knee.\n2. Flex the raised foot to protect the knee.\n3. Lean forward gently until a deep glute stretch is felt. Hold 45s."),

        Exercise(name: "Doorway Chest Stretch",
                 type: "stretching", muscle: "chest",
                 secondaryMuscle: "shoulders", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Stand in a doorway, arms at 90° against the frame.\n2. Step one foot through and lean forward until chest opens.\n3. Hold 30 seconds, squeeze shoulder blades together gently."),

        Exercise(name: "Cat-Cow",
                 type: "stretching", muscle: "back",
                 secondaryMuscle: "abdominals", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Start on hands and knees, spine neutral.\n2. Inhale: drop belly, lift head and tailbone (Cow).\n3. Exhale: round spine toward ceiling, tuck chin and tailbone (Cat).\n4. Flow for 8-10 slow breaths."),

        Exercise(name: "Child's Pose",
                 type: "stretching", muscle: "back",
                 secondaryMuscle: "shoulders", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Kneel, then sit back onto heels and extend arms forward.\n2. Rest forehead on the floor and relax completely.\n3. Walk hands to one side for a lateral stretch. Hold 60s."),

        Exercise(name: "Thoracic Rotation",
                 type: "stretching", muscle: "back",
                 secondaryMuscle: nil, equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Sit or kneel. Place one hand behind head.\n2. Rotate upper body, pointing elbow toward ceiling.\n3. Only rotate through the thoracic spine, not the lower back.\n4. 10 reps each side."),

        Exercise(name: "Standing Quad Stretch",
                 type: "stretching", muscle: "quadriceps",
                 secondaryMuscle: nil, equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Stand on one leg, pull opposite ankle to glutes.\n2. Keep knees together, stand tall.\n3. Hold a wall for balance if needed. 30s each side."),

        Exercise(name: "Calf Stretch",
                 type: "stretching", muscle: "calves",
                 secondaryMuscle: nil, equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Stand facing a wall, hands on wall.\n2. Step one foot back. Press rear heel flat to floor.\n3. Lean into wall until calf stretches. 30s, then bend rear knee slightly to target soleus."),

        Exercise(name: "Shoulder Cross-Body Stretch",
                 type: "stretching", muscle: "shoulders",
                 secondaryMuscle: "back", equipment: "bodyweight",
                 difficulty: "beginner",
                 instructions: "1. Bring one arm across chest at shoulder height.\n2. Use opposite hand to press gently on the upper arm.\n3. Hold 30s. Repeat on other side."),
    ]

    // MARK: Mixed

    static let mixed: [Exercise] = [
        Exercise(name: "Thruster",
                 type: "mixed", muscle: "quadriceps",
                 secondaryMuscle: "shoulders", equipment: "barbell",
                 difficulty: "intermediate",
                 instructions: "1. Hold barbell at shoulder height, feet shoulder-width.\n2. Squat to parallel, then drive up explosively.\n3. Use the upward momentum to press bar overhead.\n4. Lower bar back to shoulders as you descend into next squat."),

        Exercise(name: "Clean and Press",
                 type: "mixed", muscle: "back",
                 secondaryMuscle: "shoulders", equipment: "barbell",
                 difficulty: "expert",
                 instructions: "1. Deadlift bar to hips, then explosively pull and rotate elbows to catch bar at shoulders.\n2. Dip slightly to receive the bar in the front rack position.\n3. Press bar overhead to full lockout.\n4. Lower under control and repeat."),

        Exercise(name: "Dumbbell Complex",
                 type: "mixed", muscle: "back",
                 secondaryMuscle: "quadriceps", equipment: "dumbbell",
                 difficulty: "intermediate",
                 instructions: "1. Perform 6 dumbbell rows each arm.\n2. Immediately 6 Romanian deadlifts.\n3. Then 6 hang power cleans.\n4. Finally 6 shoulder presses.\n5. Rest 90s and repeat. Don't set dumbbells down within a complex."),

        Exercise(name: "Turkish Get-Up",
                 type: "mixed", muscle: "shoulders",
                 secondaryMuscle: "abdominals", equipment: "kettlebell",
                 difficulty: "intermediate",
                 instructions: "1. Lie with kettlebell pressed overhead in one hand.\n2. Roll to elbow, then to hand, then sweep leg to a lunge position.\n3. Stand fully. Reverse each step back to the floor.\n4. Keep eyes on the weight throughout."),

        Exercise(name: "Sandbag Carry",
                 type: "mixed", muscle: "back",
                 secondaryMuscle: "abdominals", equipment: "sandbag",
                 difficulty: "beginner",
                 instructions: "1. Bear-hug a sandbag at chest height.\n2. Walk for the prescribed distance or time.\n3. Keep core braced and chest tall to protect lower back."),

        Exercise(name: "Wall Ball",
                 type: "mixed", muscle: "quadriceps",
                 secondaryMuscle: "shoulders", equipment: "medicine ball",
                 difficulty: "intermediate",
                 instructions: "1. Hold medicine ball at chest, stand ~1m from wall.\n2. Squat to parallel, then explode up and throw ball to a 10ft target.\n3. Catch on the way down and use the momentum to flow into next squat."),

        Exercise(name: "Farmer's Carry",
                 type: "mixed", muscle: "forearms",
                 secondaryMuscle: "traps", equipment: "dumbbell",
                 difficulty: "beginner",
                 instructions: "1. Pick up heavy dumbbells or kettlebells at sides.\n2. Walk with upright posture, shoulders back, core tight.\n3. Take controlled steps for prescribed distance."),

        Exercise(name: "Renegade Row",
                 type: "mixed", muscle: "back",
                 secondaryMuscle: "chest", equipment: "dumbbell",
                 difficulty: "intermediate",
                 instructions: "1. Start in push-up position holding two dumbbells.\n2. Perform a push-up.\n3. At the top, row one dumbbell to hip while balancing on the other.\n4. Alternate sides each rep."),
    ]
}
