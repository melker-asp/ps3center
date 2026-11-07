import PS3Kit
import SwiftUI

/// The review before "Update All", as DESIGN.md describes: the updates in groups with check
/// boxes and sizes, what is left out and why, and a white button that says exactly what happens.
struct UpdateReviewView: View {
    @Environment(ConsoleStore.self) private var console
    @Environment(AppsStore.self) private var apps
    @Environment(\.dismiss) private var dismiss
    let plan: AppsStore.UpdatePlan
    /// False when rendered for a snapshot: ImageRenderer cannot draw scroll views.
    var scrolls = true
    @State private var excluded: Set<String> = []
    @State private var archiveMissing: Bool

    @MainActor
    init(plan: AppsStore.UpdatePlan, scrolls: Bool = true) {
        self.plan = plan
        self.scrolls = scrolls
        _archiveMissing = State(initialValue: !Snapshot.usesFixtures && MirrorRoot.resolve() == nil)
    }

    private var chosen: [AppStatus] { plan.installs.filter { !excluded.contains($0.id) } }
    private var total: Int64 { chosen.reduce(0) { $0 + ($1.assetSize ?? 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Update Apps")
                .font(.ui(.display, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("The packages are downloaded from GitHub and installed one at a time. A copy is archived in _Installed/Packages.")
                .font(.ui(.body))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 6)
                .padding(.bottom, 12)

            Group {
                if scrolls {
                    ScrollView { groups }.scrollIndicators(.hidden)
                } else {
                    groups
                }
            }
            .frame(maxHeight: 300)

            Divider().overlay(Theme.cardStroke).padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 8) {
                fact("To download", Format.bytes(total))
                if let free = console.snapshot?.freeBytes {
                    fact("Free on the PS3", Format.bytes(free), warn: free < total * 2)
                }
                ForEach(notices, id: \.self) { notice in
                    Text(notice)
                        .font(.ui(.footnote))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if archiveMissing {
                    HStack(spacing: 10) {
                        Text("The app can't find the PS3 folder where packages are archived.")
                            .font(.ui(.footnote))
                            .foregroundStyle(Theme.hot)
                        Spacer()
                        Button("Choose Folder…") {
                            apps.chooseMirrorFolder()
                            archiveMissing = MirrorRoot.resolve() == nil
                        }
                        .buttonStyle(PillButtonStyle(tint: Theme.hot))
                    }
                }
            }

            Spacer(minLength: 16)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button(mainTitle) {
                    apps.updateAll(chosen, from: plan)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle())
                .disabled(chosen.isEmpty || archiveMissing)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 580, height: 660, alignment: .topLeading)
        .background(Theme.base)
    }

    private var mainTitle: String {
        switch chosen.count {
        case 0: return "Nothing Selected"
        case 1: return "Update \(chosen[0].name)"
        default: return "Install \(chosen.count) Updates"
        }
    }

    /// What happens on the way, in the order it matters: a game that makes the queue wait, the
    /// steps a package needs afterwards (webMAN's installer), and apps that are untested here.
    private var notices: [String] {
        var lines: [String] = []
        if let snapshot = console.snapshot, snapshot.isGameRunning {
            lines.append("\(snapshot.mountedGameName ?? "A game") is running. The installs start once you quit the game.")
        }
        for status in chosen {
            if let note = status.note { lines.append("\(status.name): \(note)") }
            if status.compatibility.verdict == .untested { lines.append("\(status.name): \(status.compatibility.summary).") }
        }
        return lines
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(CatalogEntry.Category.allCases, id: \.self) { category in
                let rows = plan.installs.filter { $0.category == category }
                if !rows.isEmpty {
                    groupTitle(category.label)
                    ForEach(rows, id: \.id) { row($0) }
                }
            }
            if !plan.skipped.isEmpty {
                groupTitle("Skipped")
                ForEach(plan.skipped) { skippedRow($0) }
            }
        }
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.ui(.caption, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func row(_ status: AppStatus) -> some View {
        let on = !excluded.contains(status.id)
        return Button {
            if on { excluded.insert(status.id) } else { excluded.remove(status.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.ui(.title3))
                    .foregroundStyle(on ? Theme.accent : Theme.tertiaryText)
                AppIcon(image: apps.icons[status.id], name: status.name, category: status.category,
                        symbol: AppRow.symbols[status.id], size: CGSize(width: 48, height: 27))
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.name)
                        .font(.ui(.callout, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(status.installed ?? "?").foregroundStyle(Theme.secondaryText)
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
                        Text(status.latestForDisplay ?? "?").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                    .font(.ui(.footnote, design: .rounded))
                }
                Spacer()
                Text(status.assetSize.map(Format.bytes) ?? "–")
                    .font(.ui(.body))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func skippedRow(_ skip: AppsStore.UpdatePlan.Skip) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.circle")
                .font(.ui(.headline))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 17)
            Text(skip.status.name)
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Text(AppsStore.versionChange(skip.status))
                .font(.ui(.footnote, design: .rounded))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(skip.reason)
                .font(.ui(.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .help(skip.status.note ?? skip.reason)
    }

    private func fact(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(label).font(.ui(.body)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.ui(.body, weight: .semibold))
                .foregroundStyle(warn ? Theme.hot : Theme.primaryText)
                .monospacedDigit()
        }
    }
}

/// The report after "Update All": Done, Failed and Skipped, with the reason
/// right-aligned in grey. Stays above the list until it is closed.
struct UpdateReportCard: View {
    let report: AppsStore.UpdateReport
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.ui(.headline))
                    .foregroundStyle(report.failed.isEmpty ? Theme.good : Theme.warm)
                Text(title)
                    .font(.ui(.headline, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(Format.time(report.finished))
                    .font(.ui(.footnote))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(CircleIconButtonStyle(size: 28))
                    .iconLabel("Close the report")
            }
            .padding(.bottom, 6)
            group("Done", report.done, symbol: "checkmark", color: Theme.good, detail: Theme.secondaryText)
            group("Failed", report.failed, symbol: "xmark", color: Theme.hot, detail: Theme.hotText)
            group("Skipped", report.skipped, symbol: "minus", color: Theme.tertiaryText, detail: Theme.tertiaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var title: String {
        let done = report.done.count
        let tried = done + report.failed.count
        if report.failed.isEmpty { return done == 1 ? "1 app updated" : "\(done) apps updated" }
        return "\(done) of \(tried) apps updated"
    }

    @ViewBuilder
    private func group(_ title: String, _ lines: [AppsStore.UpdateReport.Line], symbol: String, color: Color, detail: Color) -> some View {
        if !lines.isEmpty {
            Text("\(title.uppercased())  \(lines.count)")
                .font(.ui(.caption, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(lines) { line in
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.ui(.caption, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 16)
                    Text(line.name)
                        .font(.ui(.body, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 16)
                    Text(line.detail)
                        .font(.ui(.footnote))
                        .foregroundStyle(detail)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(line.detail)
                }
                .padding(.vertical, 3)
            }
        }
    }
}
