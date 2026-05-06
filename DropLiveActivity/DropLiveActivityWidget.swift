import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - App Group image loader (Widget-side)
// Reads profile images cached by the main app via LiveActivityImageCache.

private enum LAImageHelper {
    static func image(filename: String) -> UIImage? {
        guard !filename.isEmpty else { return nil }
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.dennis.drops")
        else { return nil }
        let fileURL = base
            .appendingPathComponent("la_avatars")
            .appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Entry Point

@main
struct DropLiveActivityWidgetBundle: WidgetBundle {
    var body: some Widget { DropLiveActivityWidget() }
}

struct DropLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DropLiveActivityAttributes.self) { context in
            DropBannerView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading)  { ExpandedLeading(context: context) }
                DynamicIslandExpandedRegion(.trailing) { ExpandedTrailing(context: context) }
                DynamicIslandExpandedRegion(.bottom)   { ExpandedBottom(context: context) }
            } compactLeading: {
                CompactLeading(context: context)
            } compactTrailing: {
                CompactTrailing(context: context)
            } minimal: {
                Text(context.attributes.activityEmoji).font(.system(size: 14))
            }
        }
    }
}

// MARK: - Compact

private struct CompactLeading: View {
    let context: ActivityViewContext<DropLiveActivityAttributes>
    var body: some View {
        HStack(spacing: 3) {
            Text(context.attributes.activityEmoji).font(.system(size: 14))
            Text("\(context.state.participantCount)/\(context.state.maxParticipants)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.leading, 4)
    }
}

private struct CompactTrailing: View {
    let context: ActivityViewContext<DropLiveActivityAttributes>
    var body: some View {
        HStack(spacing: 2) {
            if !context.state.onTheWayEmojis.isEmpty {
                Text(context.state.onTheWayEmojis[0]).font(.system(size: 11))
                if let eta = context.state.onTheWayETAs.first {
                    Text("~\(eta)m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.trailing, 4)
    }
}

// MARK: - Expanded: Leading

private struct ExpandedLeading: View {
    let context: ActivityViewContext<DropLiveActivityAttributes>
    var body: some View {
        HStack(spacing: 8) {
            Text(context.attributes.activityEmoji)
                .font(.system(size: 28))
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.activityName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                if !context.state.locationTitle.isEmpty {
                    Text(context.state.locationTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 2)
    }
}

// MARK: - Expanded: Trailing

private struct ExpandedTrailing: View {
    let context: ActivityViewContext<DropLiveActivityAttributes>
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11))
                Text("\(context.state.participantCount)/\(context.state.maxParticipants)")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                isFull ? Color.orange.opacity(0.25) : Color.white.opacity(0.12),
                in: Capsule()
            )
            .overlay(Capsule().stroke(
                isFull ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 1))

            if let eta = context.state.onTheWayETAs.first {
                Text("~\(eta) Min")
                    .font(.system(size: 11))
                    .foregroundStyle(.green.opacity(0.8))
            }
        }
        .padding(.trailing, 4)
    }

    private var isFull: Bool { context.state.participantCount >= context.state.maxParticipants }
}

// MARK: - Expanded: Bottom

private struct ExpandedBottom: View {
    let context: ActivityViewContext<DropLiveActivityAttributes>
    var body: some View {
        VStack(spacing: 6) {
            if !context.state.arrivedEmojis.isEmpty {
                HStack(spacing: 6) {
                    Text("Vor Ort")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 46, alignment: .leading)
                    PersonAvatarRow(
                        emojis:     context.state.arrivedEmojis,
                        names:      context.state.arrivedNames,
                        filenames:  context.state.arrivedImageFilenames,
                        max: 5
                    )
                    Spacer()
                }
            }
            if !context.state.onTheWayEmojis.isEmpty {
                HStack(spacing: 6) {
                    Text("Unterwegs")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.green.opacity(0.7))
                        .frame(width: 46, alignment: .leading)
                    ForEach(Array(zip(context.state.onTheWayEmojis,
                                     context.state.onTheWayETAs).prefix(3).enumerated()),
                            id: \.offset) { _, pair in
                        HStack(spacing: 2) {
                            Text(pair.0).font(.system(size: 13))
                            Text("~\(pair.1)m")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

// MARK: - Avatar Cell (einzelne Person: Bild + Name)

private struct AvatarCell: View {
    let emoji:    String
    let name:     String
    let filename: String

    private var loadedImage: UIImage? { LAImageHelper.image(filename: filename) }
    private var firstName: String { name.components(separatedBy: " ").first ?? name }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 30, height: 30)
                if let img = loadedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                } else {
                    Text(emoji)
                        .font(.system(size: 15))
                }
            }
            .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))

            Text(firstName)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .frame(maxWidth: 34)
        }
    }
}

// MARK: - Avatar Row (Vor Ort — zeigt bis zu max Personen)

private struct PersonAvatarRow: View {
    let emojis:    [String]
    let names:     [String]
    let filenames: [String]
    let max: Int

    private var persons: [(emoji: String, name: String, filename: String)] {
        let count = min(emojis.count, max)
        return (0..<count).map { i in
            (emoji:    i < emojis.count    ? emojis[i]    : "",
             name:     i < names.count     ? names[i]     : "",
             filename: i < filenames.count ? filenames[i] : "")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(persons.enumerated()), id: \.offset) { _, person in
                AvatarCell(emoji: person.emoji, name: person.name, filename: person.filename)
            }
            if emojis.count > max {
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 30, height: 30)
                        Text("+\(emojis.count - max)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Text("").font(.system(size: 8))
                }
            }
        }
    }
}

// MARK: - Lock Screen Banner

private struct DropBannerView: View {
    let context: ActivityViewContext<DropLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Kopfzeile ────────────────────────────────────────────
            HStack(spacing: 10) {
                Text(context.attributes.activityEmoji)
                    .font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(context.attributes.activityName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    // Adresse — komplett anzeigen, mehrzeilig wenn nötig
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 2)
                        Text(context.state.locationTitle.isEmpty
                             ? "Standort wird geladen …"
                             : context.state.locationTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer()

                // Teilnehmer-Zähler rechts oben
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                    Text("\(context.state.participantCount)/\(context.state.maxParticipants)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1), in: Capsule())
            }

            // ── Trennlinie ────────────────────────────────────────────
            if !context.state.arrivedEmojis.isEmpty || !context.state.onTheWayEmojis.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
            }

            // ── Vor Ort — Avatar-Spalten mit Namen ───────────────────
            if !context.state.arrivedEmojis.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Label("Vor Ort", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 68, alignment: .leading)
                        .padding(.top, 5)

                    PersonAvatarRow(
                        emojis:    context.state.arrivedEmojis,
                        names:     context.state.arrivedNames,
                        filenames: context.state.arrivedImageFilenames,
                        max: 5
                    )

                    Spacer()
                }
            }

            // ── Unterwegs ────────────────────────────────────────────
            if !context.state.onTheWayEmojis.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(zip3(context.state.onTheWayEmojis,
                                      context.state.onTheWayNames,
                                      context.state.onTheWayETAs).prefix(3).enumerated()),
                            id: \.offset) { _, triple in
                        HStack(spacing: 8) {
                            // Avatar
                            Text(triple.0)
                                .font(.system(size: 16))
                                .frame(width: 30, height: 30)
                                .background(Color.green.opacity(0.15), in: Circle())

                            // Name + "ist unterwegs"
                            VStack(alignment: .leading, spacing: 1) {
                                Text(triple.1)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text("ist unterwegs")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.45))
                            }

                            Spacer()

                            // ETA
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("~\(triple.2)")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.green)
                                Text("Min")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// Hilfsfunktion zip für 3 Arrays
private func zip3<A, B, C>(_ a: [A], _ b: [B], _ c: [C]) -> [(A, B, C)] {
    let count = min(a.count, b.count, c.count)
    return (0..<count).map { (a[$0], b[$0], c[$0]) }
}

// MARK: - Preview Data

#if DEBUG
extension DropLiveActivityAttributes {
    static var preview: DropLiveActivityAttributes {
        DropLiveActivityAttributes(
            activityName: "Kaffee",
            activityEmoji: "☕️",
            dropID: UUID().uuidString,
            isHost: true
        )
    }
}

extension DropLiveActivityAttributes.ContentState {
    static var previewActive: DropLiveActivityAttributes.ContentState {
        .init(participantCount: 3, maxParticipants: 5,
              expiresAt: Date().addingTimeInterval(45 * 60),
              locationTitle: "Café Luitpold, Odeonsplatz",
              arrivedEmojis: ["🧑‍💻", "👩‍🦰"],
              arrivedNames:  ["Dennis", "Sarah"],
              arrivedImageFilenames: ["", ""],
              onTheWayEmojis: ["🧔"],
              onTheWayETAs: [8],
              onTheWayNames: ["Jonas"])
    }
    static var previewMultiple: DropLiveActivityAttributes.ContentState {
        .init(participantCount: 4, maxParticipants: 6,
              expiresAt: Date().addingTimeInterval(30 * 60),
              locationTitle: "Viktualienmarkt",
              arrivedEmojis: ["🧑‍💻", "👩‍🦰", "🧕"],
              arrivedNames:  ["Dennis", "Sarah", "Leyla"],
              arrivedImageFilenames: ["", "", ""],
              onTheWayEmojis: ["🧔", "👨‍🎤"],
              onTheWayETAs: [5, 12],
              onTheWayNames: ["Jonas", "Lena"])
    }
    static var previewNoOne: DropLiveActivityAttributes.ContentState {
        .init(participantCount: 1, maxParticipants: 5,
              expiresAt: Date().addingTimeInterval(60 * 60),
              locationTitle: "Marienplatz",
              arrivedEmojis: ["😎"],
              arrivedNames:  ["Dennis"],
              arrivedImageFilenames: [""],
              onTheWayEmojis: [],
              onTheWayETAs: [],
              onTheWayNames: [])
    }
}

private struct PreviewHelper: View {
    let state: DropLiveActivityAttributes.ContentState
    var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.88))
                .overlay(BannerStandalone(attrs: .preview, state: state))
                .padding()
        }
    }
}

private struct BannerStandalone: View {
    let attrs: DropLiveActivityAttributes
    let state: DropLiveActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(attrs.activityEmoji).font(.system(size: 30))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(attrs.activityName).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    HStack(spacing: 4) {
                        Image(systemName: "mappin").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        Text(state.locationTitle.isEmpty ? "Standort wird geladen …" : state.locationTitle)
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill").font(.system(size: 10))
                    Text("\(state.participantCount)/\(state.maxParticipants)").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.white.opacity(0.1), in: Capsule())
            }
            if !state.arrivedEmojis.isEmpty || !state.onTheWayEmojis.isEmpty {
                Divider().overlay(Color.white.opacity(0.1))
            }
            if !state.arrivedEmojis.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Label("Vor Ort", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                        .frame(width: 68, alignment: .leading).padding(.top, 5)
                    PersonAvatarRow(
                        emojis:    state.arrivedEmojis,
                        names:     state.arrivedNames,
                        filenames: state.arrivedImageFilenames,
                        max: 5
                    )
                    Spacer()
                }
            }
            if !state.onTheWayEmojis.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(zip3(state.onTheWayEmojis, state.onTheWayNames, state.onTheWayETAs).enumerated()), id: \.offset) { _, t in
                        HStack(spacing: 8) {
                            Text(t.0).font(.system(size: 16)).frame(width: 30, height: 30)
                                .background(Color.green.opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.1).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                Text("ist unterwegs").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("~\(t.2)").font(.system(size: 15, weight: .bold)).foregroundStyle(.green)
                                Text("Min").font(.system(size: 9)).foregroundStyle(.green.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

#Preview("Aktiv + 1 unterwegs")  { PreviewHelper(state: .previewActive) }
#Preview("Mehrere unterwegs")    { PreviewHelper(state: .previewMultiple) }
#Preview("Nur ich da")           { PreviewHelper(state: .previewNoOne) }
#endif
