# Midmar Trainer for iPhone

A native SwiftUI version of the Midmar Mile trainer. It builds the same coached plan as the web app, reads the swims your Apple Watch records from Apple Health, and sends planned workouts to the Workout app on your watch.

## What it does

- **Plan**: builds from your longest non-stop swim, a timed swim, your swim days (1 to 4 a week), pool length and race date. Starts today unless you pick another date.
- **Apple Watch in**: Pool Swim and Open Water Swim workouts from Health tick off the matching session, record the time, pick out your longest continuous set, and time your trial for you on time-trial days. Swims that don't land near a planned day show up under "Swims to sort".
- **Apple Watch out**: "Send to Apple Watch" on a workout opens Apple's preview so you can add it to the Workout app, with each set as a step and timed rests. The Plan tab can schedule this week and next in one go.
- **Your changes**: mark done, skip, move to any free day, edit sets, edit results.
- **Progress**: target paces from your timed swims, predicted race time, weekly distance, longest non-stop swim chart, milestones.

## Run it on your iPhone

1. Open `ios/MidmarTrainer.xcodeproj` in Xcode 16 or later.
2. Select the **MidmarTrainer** target, then **Signing & Capabilities**, and pick your Personal Team. If Xcode says the bundle ID is taken, change `com.camjones.midmartrainer` to something unique.
3. Plug in your iPhone (iOS 18 or later), choose it as the run destination, and press Run.
4. On the phone, allow Apple Health access when asked, then open Setup.

With a free Apple ID the app stops opening after 7 days. Run it again from Xcode to renew it. Your data stays on the phone between installs.

## Tests

`MidmarTrainerTests` covers the plan builder, edits and moves, swim matching and set detection. GitHub Actions builds the app and runs them on every push that touches `ios/`.
