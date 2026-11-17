import SwiftUI

struct RaceView: View {
    @Environment(TrainerStore.self) private var store

    var body: some View {
        let range = Paces.raceRange(thr: store.thr)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card {
                    Eyebrow(text: "Race day in your plan")
                    Text(Days.withYear(store.plan.race)).font(.display(44))
                    Text("Midmar Dam, KwaZulu-Natal. The Mile is 1.6 km, which is \(Catalog.raceDistance / store.plan.pool) lengths of a \(store.plan.pool) m pool. The 2027 event runs on 13 and 14 February, so check your entry confirmation for the day and wave you swim.")
                        .foregroundStyle(Palette.muted)
                    Link("Event details at midmarmile.com", destination: URL(string: "https://midmarmile.com/")!)
                }
                Card {
                    Text("Pacing plan").font(.display(22))
                    if let range {
                        let mid = (range.lo + range.hi) / 2
                        (Text("\(Int((range.lo / 60).rounded())) to \(Int((range.hi / 60).rounded()))").font(.display(44))
                         + Text(" min predicted").font(.display(20, weight: .semibold)).foregroundColor(Palette.muted))
                        Text("Swim the first quarter a little slower than this, then hold your rhythm. Checkpoints at an even pace:")
                            .font(.system(size: 14)).foregroundStyle(Palette.muted)
                        HStack(spacing: 0) {
                            ForEach([400, 800, 1200, 1600], id: \.self) { d in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Fmt.time(mid * Double(d) / 1600)).font(.display(22)).monospacedDigit()
                                    Text(Fmt.dist(d)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                if d != 1600 { Divider() }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
                    } else {
                        Text("Add a timed swim on the Progress tab to see a predicted race time and checkpoints for every 400 m.")
                            .font(.system(size: 14)).foregroundStyle(Palette.muted)
                    }
                }
                Card {
                    Text("Race notes").font(.display(22))
                    ForEach(Catalog.raceTips, id: \.title) { tip in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tip.title).font(.display(20))
                            Text(tip.body).font(.system(size: 15)).foregroundStyle(Palette.muted)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("If you have a heart or breathing condition, check with a doctor before you step up your training.")
                    .font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
            .padding(16)
        }
        .background(Palette.bg)
        .navigationTitle("Race")
    }
}
