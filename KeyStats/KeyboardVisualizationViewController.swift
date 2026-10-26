import Cocoa

final class KeyboardVisualizationViewController: NSViewController {
    private let growth = GrowthKeyboardViewController(manager: .shared, startsIn3D: true)
    private let models = NSSegmentedControl()
    private let interaction = NSSegmentedControl()
    private let content = NSView()
    private var surfaces: [Int: MechanicalKeyboardView] = [:]
    private var prefersInteraction = false
    var onPageChanged: ((Bool) -> Void)?
    var showsGrowth: Bool { true }

    override func loadView() {
        view = KeyboardVisualizationCanvasView(frame: NSRect(x: 0, y: 0, width: 1160, height: 780))
        let title = NSTextField(labelWithString: NSLocalizedString("growth.title", comment: ""))
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let subtitle = NSTextField(labelWithString: NSLocalizedString("keyboard.window.subtitle", comment: ""))
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 3
        models.segmentCount = 2
        models.setLabel("Mac", forSegment: 0)
        models.setLabel(NSLocalizedString("keyboard.model.mechanical", comment: ""), forSegment: 1)
        models.selectedSegment = 0
        models.segmentStyle = .rounded
        models.setWidth(66, forSegment: 0); models.setWidth(104, forSegment: 1)
        models.target = self; models.action = #selector(changeModel)
        models.setAccessibilityLabel(NSLocalizedString("growth.mode.choose", comment: ""))
        interaction.segmentCount = 2
        interaction.setLabel(NSLocalizedString("keyboard.mode.growth", comment: ""), forSegment: 0)
        interaction.setLabel(NSLocalizedString("keyboard.interaction", comment: ""), forSegment: 1)
        interaction.selectedSegment = 0; interaction.segmentStyle = .rounded
        interaction.setWidth(86, forSegment: 0); interaction.setWidth(92, forSegment: 1)
        interaction.setAccessibilityLabel(NSLocalizedString("keyboard.mode.choose", comment: ""))
        interaction.target = self; interaction.action = #selector(toggleInteraction)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [heading, spacer, models, interaction])
        header.spacing = 14; header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header); view.addSubview(divider); view.addSubview(content)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            content.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        addChild(growth)
        content.addSubview(growth.view)
        growth.view.frame = content.bounds
        growth.view.autoresizingMask = [.width, .height]
        changeModel()
    }

    @objc private func changeModel() {
        let index = models.selectedSegment
        let usesSurface = prefersInteraction
        if usesSurface && surfaces[index] == nil {
            do {
                let model = try MechanicalKeyboardScene()
                if index == 0 { try model.configureMacModel() }
                else { try model.configureFullModel() }
                let surface = MechanicalKeyboardView(model: model, embedded: true)
                content.addSubview(surface)
                surfaces[index] = surface
            } catch {
                models.selectedSegment = 0; prefersInteraction = false
                NSAlert(error: error).runModal()
                changeModel()
                return
            }
        }
        for (candidate, surface) in surfaces {
            surface.cancel()
            surface.isHidden = !usesSurface || candidate != index
        }
        growth.view.isHidden = usesSurface
        if !usesSurface { growth.setMechanical(index == 1) }
        growth.setPresented(!usesSurface)
        interaction.isEnabled = true
        interaction.selectedSegment = usesSurface ? 1 : 0
        layoutSurfaces()
        if usesSurface, let surface = surfaces[index] {
            surface.nextKeyView = interaction
            models.nextKeyView = surface
            view.window?.makeFirstResponder(surface)
        } else if let focused = view.window?.firstResponder as? NSView,
                  surfaces.values.contains(where: { focused === $0 || focused.isDescendant(of: $0) }) {
            view.window?.makeFirstResponder(interaction)
        }
    }

    @objc private func toggleInteraction() {
        prefersInteraction = interaction.selectedSegment == 1
        changeModel()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSurfaces()
    }

    private func layoutSurfaces() {
        for surface in surfaces.values {
            let scale = max(0.01, min(content.bounds.width / MechanicalKeyboardView.size.width,
                                     content.bounds.height / MechanicalKeyboardView.size.height))
            let size = CGSize(width: MechanicalKeyboardView.size.width * scale,
                              height: MechanicalKeyboardView.size.height * scale)
            surface.frame = CGRect(x: (content.bounds.width - size.width) / 2,
                                   y: (content.bounds.height - size.height) / 2, width: size.width, height: size.height)
            surface.setBoundsSize(MechanicalKeyboardView.size)
        }
    }

    func refreshForPresentation(resetToToday: Bool) {
        _ = view
        growth.setPresented(!growth.view.isHidden)
        growth.refreshData(resetToToday: resetToToday)
    }
}
