import PS3Kit
import SwiftUI

/// The review before "Uppdatera alla", as DESIGN.md describes: the updates in groups with check
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
            Text("Uppdatera program")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.primaryText)
            Text("Paketen hämtas från GitHub och installeras ett i taget. Kopian arkiveras i _Installerat/Paket.")
                .font(.system(size: 13))
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
                fact("Att hämta", Format.bytes(total))
                if let free = console.snapshot?.freeBytes {
                    fact("Ledigt på PS3:an", Format.bytes(free), warn: free < total * 2)
                }
                ForEach(notices, id: \.self) { notice in
                    Text(notice)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if archiveMissing {
                    HStack(spacing: 10) {
                        Text("Appen hittar inte PS3-mappen där paketen arkiveras.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.hot)
                        Spacer()
                        Button("Välj mapp…") {
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
                Button("Avbryt") { dismiss() }
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
        case 0: return "Inget valt"
        case 1: return "Uppdatera \(chosen[0].name)"
        default: return "Installera \(chosen.count) uppdateringar"
        }
    }

    /// What happens on the way, in the order it matters: a game that makes the queue wait, the
    /// steps a package needs afterwards (webMAN's installer), and apps that are untested here.
    private var notices: [String] {
        var lines: [String] = []
        if let snapshot = console.snapshot, snapshot.isGameRunning {
            lines.append("\(snapshot.mountedGameName ?? "Ett spel") körs. Installationerna börjar när du har avslutat spelet.")
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
                groupTitle("Hoppas över")
                ForEach(plan.skipped) { skippedRow($0) }
            }
        }
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
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
                    .font(.system(size: 17))
                    .foregroundStyle(on ? Theme.accent : Theme.tertiaryText)
                AppIcon(image: apps.icons[status.id], name: status.name, category: status.category,
                        symbol: AppRow.symbols[status.id], size: CGSize(width: 48, height: 27))
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(status.installed ?? "?").foregroundStyle(Theme.secondaryText)
                        Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.tertiaryText)
                        Text(status.latest ?? "?").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                    .font(.system(size: 12, design: .rounded))
                }
                Spacer()
                Text(status.assetSize.map(Format.bytes) ?? "–")
                    .font(.system(size: 13))
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
                .font(.system(size: 15))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 17)
            Text(skip.status.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Text(AppsStore.versionChange(skip.status))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Theme.tertiaryText)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(skip.reason)
                .font(.system(size: 12))
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
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(warn ? Theme.hot : Theme.primaryText)
                .monospacedDigit()
        }
    }
}

/// The report after "Uppdatera alla": Klart, Misslyckades and Hoppade över, with the reason
/// right-aligned in grey. Stays above the list until it is closed.
struct UpdateReportCard: View {
    let report: AppsStore.UpdateReport
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: report.failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(report.failed.isEmpty ? Theme.good : Theme.warm)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(report.finished.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(CircleIconButtonStyle(size: 28))
                    .help("Stäng rapporten")
            }
            .padding(.bottom, 6)
            group("Klart", report.done, symbol: "checkmark", color: Theme.good, detail: Theme.secondaryText)
            group("Misslyckades", report.failed, symbol: "xmark", color: Theme.hot, detail: Theme.hot)
            group("Hoppade över", report.skipped, symbol: "minus", color: Theme.tertiaryText, detail: Theme.tertiaryText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var title: String {
        let done = report.done.count
        let tried = done + report.failed.count
        if report.failed.isEmpty { return done == 1 ? "1 program uppdaterat" : "\(done) program uppdaterade" }
        return "\(done) av \(tried) program uppdaterade"
    }

    @ViewBuilder
    private func group(_ title: String, _ lines: [AppsStore.UpdateReport.Line], symbol: String, color: Color, detail: Color) -> some View {
        if !lines.isEmpty {
            Text("\(title.uppercased())  \(lines.count)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(lines) { line in
                HStack(spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                        .frame(width: 16)
                    Text(line.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 16)
                    Text(line.detail)
                        .font(.system(size: 12))
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
