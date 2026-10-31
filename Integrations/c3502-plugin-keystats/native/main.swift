import Foundation
import Darwin
import CoreGraphics
import ApplicationServices

func emit(_ value: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { exit(70) }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
}
func status(_ value: String) { emit(["schemaVersion": 1, "kind": "status", "state": value]) }

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    let values = Aggregates()
    for _ in 0..<3 { values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 10)]) }
    values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 10), HelperPayloadFields.isAutoRepeat: true])
    values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 1)])
    values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 3)])
    values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 25), HelperPayloadFields.buttonNumber: 2])
    values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 5), HelperPayloadFields.locationX: 0, HelperPayloadFields.locationY: 0])
    values.forward(payload: [HelperPayloadFields.type: NSNumber(value: 5), HelperPayloadFields.locationX: 3, HelperPayloadFields.locationY: 4])
    precondition(values.keyPresses == 3 && values.leftClicks == 1 && values.rightClicks == 1 && values.middleClicks == 1)
    precondition(values.mouseDistancePoints == 5)
    precondition(values.snapshot.count == 9)
    emit(values.snapshot)
    exit(0)
}
guard arguments.isEmpty || arguments == ["--request-permission"] || arguments == ["--diagnose"] else {
    fputs("Usage: KeyStatsC3502Collector [--request-permission | --self-test | --diagnose]\n", stderr)
    exit(64)
}
if arguments == ["--diagnose"] {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    emit(["accessibility": AXIsProcessTrusted(), "listenEvents": CGPreflightListenEventAccess(),
          "sessionOnConsole": session["kCGSSessionOnConsoleKey"] as? Bool ?? false,
          "screenLocked": session["CGSSessionScreenIsLocked"] as? Bool ?? false])
    exit(0)
}
// Listen-only capture has a separate TCC permission on current macOS.
// AX trust alone can allow creation of a tap that never delivers input.
if !CGPreflightListenEventAccess() {
    if arguments == ["--request-permission"] { _ = CGRequestListenEventAccess() }
    status("inputMonitoringDenied")
    exit(78)
}
let tap = EventTapController()
if !tap.isAccessibilityGranted() {
    if arguments == ["--request-permission"] { tap.promptAccessibilityTrust() }
    status("permissionDenied")
    exit(77)
}
let aggregates = Aggregates()
guard tap.start(sink: aggregates) == HelperErrorCode.none else {
    status("tapFailed")
    exit(71)
}
status("monitoring")
emit(aggregates.snapshot)
let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in emit(aggregates.snapshot) }
func stop() {
    timer.invalidate()
    tap.stop()
    exit(0)
}
// Parent closes its pipe on disposal; no orphaned background collector.
let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
input.setEventHandler {
    var byte: UInt8 = 0
    if Darwin.read(STDIN_FILENO, &byte, 1) <= 0 { stop() }
}
input.resume()
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
signal(SIGPIPE, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler { stop() }
termination.resume()
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { stop() }
interrupt.resume()
RunLoop.main.run()
