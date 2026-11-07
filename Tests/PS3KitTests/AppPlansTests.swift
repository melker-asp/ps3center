import Foundation
import Testing
@testable import PS3Kit
import PS3KitFixtures

// "Update All" and the Apps groups, which the app and `ps3 apps update` used to decide each on
// their own, and the smaller rules that had copies in both.

@Test func updateAllInstallsPackagesAndExplainsTheRest() {
    let statuses = Fixtures.appStatuses()
    let plan = UpdatePlan(statuses)
    #expect(plan.installs.allSatisfy { $0.canInstall && $0.state == .updateAvailable && !$0.ignored })
    #expect(plan.installs.contains { $0.id == "apollo" })

    let reasons = Dictionary(uniqueKeysWithValues: plan.skipped.map { ($0.id, $0.status.skip) })
    #expect(reasons["artemis"] == .ignored)
    #expect(reasons["hen"] == .notAutomatic)  // HEN is never installed automatically
    #expect(!plan.skipped.contains { $0.status.canInstall && !$0.status.ignored })
}

@Test func namingAnIgnoredAppIncludesIt() {
    let plan = UpdatePlan(Fixtures.appStatuses(), includingIgnored: true)
    #expect(plan.installs.contains { $0.id == "artemis" })
    #expect(!plan.skipped.contains { $0.status.skip == .ignored })
}

@Test func theGroupsSplitEveryStatusOnce() {
    let statuses = Fixtures.appStatuses()
    let groups = AppGroups(statuses)
    #expect(groups.updates.allSatisfy { $0.isPendingUpdate })
    #expect(groups.ignored.map(\.id) == ["artemis"])
    let all = groups.updates + groups.ignored + groups.current + groups.manual + groups.missing
    #expect(all.count == statuses.count)
    #expect(Set(all.map(\.id)).count == statuses.count)
}

@Test func theBatchLeavesOutWhatFinishedMeanwhileAndReportsEachOutcome() throws {
    let plan = UpdatePlan(Fixtures.appStatuses())
    try #require(plan.installs.count >= 2)
    let (first, second) = (plan.installs[0], plan.installs[1])

    // Both chosen, but the second finished with its own Update button while the review was open.
    let batch = UpdateBatch(plan: plan, chosen: [first, second], pending: [first.id])
    #expect(batch.queued.map(\.id) == [first.id])
    #expect(batch.skipped.first { $0.id == second.id }?.detail == "Already updated")
    #expect(batch.skipped.contains { $0.id == "artemis" && $0.detail == "Ignored" })

    let done = batch.report([first.id: .done])
    #expect(done.done.map(\.id) == [first.id])
    #expect(done.done[0].detail == first.versionChange)
    #expect(batch.report([first.id: .failed("The connection dropped")]).failed.map(\.detail) == ["The connection dropped"])
    #expect(batch.report([:]).skipped.contains { $0.id == first.id && $0.detail == "Didn't run" })

    // Only the first chosen: the second is reported as unchecked.
    let one = UpdateBatch(plan: plan, chosen: [first], pending: [first.id, second.id])
    #expect(one.skipped.first { $0.id == second.id }?.detail == "Unchecked in the review")
}

@Test func browseListsWhatCanBeInstalledIsInstalledOrIsBlocked() {
    for status in Fixtures.appStatuses() {
        #expect(status.isListed == (status.installable || status.installed != nil || status.blocked))
    }
}

@Test func theReviewAndTheQueueGroupRoutesTheSameWay() {
    func route(_ file: String, title: String?) -> Route {
        Route(local: URL(fileURLWithPath: "/m/\(file)"), remote: "/dev_hdd0/PSXISO/\(file)", kind: .psxISO, size: 1, title: title)
    }
    let routes = [route("Spyro.cue", title: "Spyro"), route("GT.iso", title: "GT"), route("Spyro.bin", title: "Spyro")]
    let games = TransferQueue.games(in: routes)
    #expect(games.map(\.title) == ["Spyro", "GT"])
    #expect(games[0].routes.count == 2)
    var queue = TransferQueue()
    #expect(queue.add(routes).map(\.title) == games.map(\.title))
}

@Test func onlyACopiedDiscOnTheConsoleIsCheckedAgainstItsIRD() {
    let ripped = Game(path: "/dev_hdd0/GAMES/Demon's Souls [BLES00932]", title: "Demon's Souls", titleID: "BLES00932", platform: .ps3,
                      isFolder: true)
    let installed = Game(path: "/dev_hdd0/game/NPEB01042", title: "NFS", titleID: "NPEB01042", platform: .ps3, isFolder: true)
    let iso = Game(path: "/dev_hdd0/PS3ISO/GT5.iso", title: "GT5", titleID: "BCES00569", platform: .ps3)
    #expect(ripped.canVerifyWithIRD)
    #expect(!installed.canVerifyWithIRD)
    #expect(!iso.canVerifyWithIRD)
}

@Test func playTimeIsFoundUnderWhicheverNetworkServerWasUsed() {
    var game = Game(path: "/Users/me/Games/PS3ISO/GT5.iso", title: "GT5", titleID: "BCES00569", platform: .ps3)
    game.netPath = "/PS3ISO/GT5.iso"
    var log = PlayLog()
    let record = PlayLog.Record(title: "GT5", seconds: 600, sessions: 1, lastPlayed: Date())
    log.games[NetServer.mountPath(slot: 2, netPath: "/PS3ISO/GT5.iso")] = record
    #expect(log.record(for: game) == record)  // before, only /net0 was looked at
    #expect(NetServer.isNetMount("/net2/PS3ISO/GT5.iso"))
    #expect(!NetServer.isNetMount("/network/x.iso"))
    #expect(!NetServer.isNetMount("/dev_hdd0/PS3ISO/GT5.iso"))
}

@Test func aPlainPS2ISOToHENIsCaughtBeforeSending() {
    let iso = Route(local: URL(fileURLWithPath: "/m/Game.iso"), remote: "/dev_hdd0/PS2ISO/Game.iso", kind: .ps2ISO, size: 1, title: nil)
    let classic = Route(local: URL(fileURLWithPath: "/m/Game [SLES12345].BIN.ENC"), remote: "/dev_hdd0/PS2ISO/Game [SLES12345].BIN.ENC",
                        kind: .ps2ISO, size: 1, title: nil)
    let hen = ConsoleProfile(snapshot: Fixtures.snapshot)
    let cfw = ConsoleProfile(snapshot: Fixtures.cfwSnapshot)
    #expect(PlayCheck.sendsPS2ISOToHEN([iso], console: hen))
    #expect(!PlayCheck.sendsPS2ISOToHEN([classic], console: hen))
    #expect(!PlayCheck.sendsPS2ISOToHEN([iso], console: cfw))
    #expect(!PlayCheck.sendsPS2ISOToHEN([iso], console: nil))
}

@Test func theEstimateUsesTheSpeedNowElseTheMeasurement() {
    #expect(SpeedTest.estimate(bytes: 1_000, rate: 100, measured: Fixtures.speed) == 10)
    #expect(SpeedTest.estimate(bytes: 3_250_000, rate: 0, measured: Fixtures.speed) == 1)
    #expect(SpeedTest.estimate(bytes: 1_000, rate: 0, measured: nil) == nil)
}
