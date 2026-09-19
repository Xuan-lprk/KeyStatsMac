import Cocoa
import SwiftUI

/// Native sheet shell; no observers, live stats queries or changes to the parent AppKit window.
final class AppDetailViewController: NSViewController {
    private let snapshot: AppDetailPresentation
    private let icon: NSImage

    init(snapshot: AppDetailPresentation, icon: NSImage) {
        self.snapshot = snapshot
        self.icon = icon
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let host = NSHostingController(rootView: AppDetailView(snapshot: snapshot, icon: icon) { [weak self] in
            guard let self else { return }
            // The presenter owns the sheet and must clear its presentation state.
            self.presentingViewController?.dismiss(self)
        })
        addChild(host)
        view = NSView(frame: NSRect(x: 0, y: 0, width: 820, height: 690))
        preferredContentSize = view.frame.size
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

private struct AppDetailView: View {
    let snapshot: AppDetailPresentation
    let icon: NSImage
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var entered = false
    @State private var ranksVisible = false
    @State private var rowsVisible = false
    @State private var started = false

    private let accents: [Color] = [.blue, .green, .orange]
    private func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    var body: some View {
        VStack(spacing: 16) {
            hero
            VStack(alignment: .leading, spacing: 5) {
                Text(text("appDetail.profile")).font(.title3.weight(.semibold))
                Text(text("appDetail.explanation")).font(.callout).foregroundStyle(.secondary)
                Text(text("appDetail.independent")).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .top, spacing: 12) {
                ForEach(snapshot.cards.indices, id: \.self) { index in
                    card(snapshot.cards[index], index: index)
                }
            }
            breakdown
            HStack {
                Spacer()
                Button(text("appStats.breakdown.close"), action: close)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            guard !started else { return }
            started = true
            entered = true
            guard !reduceMotion else {
                ranksVisible = true
                rowsVisible = true
                return
            }
            // Finite entrance only; SwiftUI cancels these waits when the sheet disappears.
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                try Task.checkCancellation()
                ranksVisible = true
                try await Task.sleep(nanoseconds: 520_000_000)
                try Task.checkCancellation()
                rowsVisible = true
            } catch { }
        }
        .onChange(of: reduceMotion) { enabled in
            if enabled {
                entered = true
                ranksVisible = true
                rowsVisible = true
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 6) {
            ZStack {
                if !reduceTransparency {
                    HStack(spacing: -18) {
                        ForEach(accents.indices, id: \.self) { index in
                            Circle().fill(accents[index].opacity(0.15)).frame(width: 58, height: 48)
                        }
                    }
                    .blur(radius: 20)
                    .opacity(entered ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: entered)
                    .accessibilityHidden(true)
                }
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 64, height: 64)
                    .scaleEffect(reduceMotion || entered ? 1 : 0.84)
                    .opacity(reduceMotion || entered ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.65), value: entered)
                    .accessibilityHidden(true)
            }.frame(height: 68)
            VStack(spacing: 4) {
                Text(snapshot.appName).font(.title2.weight(.semibold))
                    .lineLimit(1).truncationMode(.middle).help(snapshot.appName)
                Text(snapshot.rangeTitle).font(.callout).foregroundStyle(.secondary)
                Text(snapshot.metadata).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .opacity(reduceMotion || entered ? 1 : 0)
            .offset(y: reduceMotion || entered ? 0 : 10)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.08), value: entered)
        }.frame(maxWidth: .infinity)
    }

    private func card(_ item: AppDetailPresentation.Card, index: Int) -> some View {
        let accent = accents[index]
        return VStack(alignment: .leading, spacing: 8) {
            Label(item.title, systemImage: item.symbol).font(.headline).foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(item.rankText).font(.system(size: 29, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if item.score != nil {
                    Text(text("appDetail.percentile")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let score = item.score {
                rankTrack(score: score, accent: accent, visible: reduceMotion || ranksVisible)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(Double(index) * 0.06),
                               value: ranksVisible)
            } else {
                Text(item.caption).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 16, alignment: .leading)
            }
            Text(item.evidence).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.reference).font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .padding(14)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .controlBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 16).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.045))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(contrast == .increased ? Color.primary : accent.opacity(0.22),
                          lineWidth: contrast == .increased ? 1.5 : 0.75))
        .shadow(color: Color.black.opacity(reduceTransparency ? 0 : 0.05), radius: 7, y: 3)
        .opacity(reduceMotion || entered ? 1 : 0)
        .offset(y: reduceMotion || entered ? 0 : 16)
        .scaleEffect(reduceMotion || entered ? 1 : 0.96)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)
            .delay(0.14 + Double(index) * 0.08), value: entered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityText)
    }

    private func rankTrack(score: Double, accent: Color, visible: Bool) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 8)
            ZStack(alignment: .leading) {
                Capsule().fill(contrast == .increased ? Color.secondary : accent.opacity(0.14))
                    .frame(height: 4)
                Capsule().fill(accent).frame(width: visible ? width * score + 4 : 0, height: 4)
                Circle().fill(accent).frame(width: 8, height: 8)
                    .offset(x: visible ? width * score : 0)
            }.frame(height: 12)
        }.frame(height: 12).accessibilityHidden(true)
    }

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(text("section.keyBreakdown")).font(.headline)
                Spacer()
                Text(snapshot.breakdownSummary).font(.caption).foregroundStyle(.secondary)
            }
            if let notice = snapshot.breakdownNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(text("appStats.breakdown.key"))
                Spacer()
                Text(text("appStats.breakdown.count"))
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(snapshot.rows.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 16) {
                            Text(row.label).lineLimit(1).truncationMode(.middle).help(row.label)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            GeometryReader { geometry in
                                Capsule().fill(Color.blue.opacity(contrast == .increased ? 0.8 : 0.22))
                                    .frame(width: geometry.size.width
                                           * (reduceMotion || rowsVisible || index >= 2 ? row.usage : 0), height: 4)
                                    .frame(maxHeight: .infinity)
                                    .animation(reduceMotion || index >= 2 ? nil
                                        : .easeOut(duration: 0.3).delay(Double(index) * 0.025), value: rowsVisible)
                            }.frame(width: 130).accessibilityHidden(true)
                            Text(row.count).monospacedDigit().frame(minWidth: 66, alignment: .trailing)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 8).frame(height: 30)
                        .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : Color.clear)
                        .accessibilityElement(children: .combine)
                    }
                }
            }.frame(maxHeight: .infinity)
        }
        .opacity(reduceMotion || rowsVisible ? 1 : 0)
        .offset(y: reduceMotion || rowsVisible ? 0 : 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: rowsVisible)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
