import AppKit

private let mappingPanelColor = NSColor(red: 0.09, green: 0.11, blue: 0.15, alpha: 0.92)
private let mappingDividerColor = NSColor(red: 1, green: 1, blue: 1, alpha: 0.06)
private let mappingSecondaryText = NSColor.white.withAlphaComponent(0.55)

final class GamepadConfigView: NSView {
    struct ButtonSlot {
        let key: String
        let actionKey: String?
        let title: String
        let group: String
        let trailingText: String?
    }

    private struct GroupDescriptor {
        let title: String
        let subtitle: String
        let slotKeys: [String]
        let footer: String?
    }

    private let slots: [ButtonSlot] = [
        ButtonSlot(key: "lt", actionKey: nil, title: "LT / L2", group: "shoulders", trailingText: "Preset Prompts"),
        ButtonSlot(key: "rt", actionKey: nil, title: "RT / R2", group: "shoulders", trailingText: "Preset Prompts"),
        ButtonSlot(key: "lb", actionKey: "lb", title: "LB / L1", group: "shoulders", trailingText: nil),
        ButtonSlot(key: "rb", actionKey: "rb", title: "RB / R1", group: "shoulders", trailingText: nil),
        ButtonSlot(key: "a", actionKey: "a", title: "A / Cross", group: "face", trailingText: nil),
        ButtonSlot(key: "b", actionKey: "b", title: "B / Circle", group: "face", trailingText: nil),
        ButtonSlot(key: "x", actionKey: "x", title: "X / Square", group: "face", trailingText: nil),
        ButtonSlot(key: "y", actionKey: "y", title: "Y / Triangle", group: "face", trailingText: nil),
        ButtonSlot(key: "dpadUp", actionKey: "dpadUp", title: "D-pad Up", group: "nav", trailingText: nil),
        ButtonSlot(key: "dpadDown", actionKey: "dpadDown", title: "D-pad Down", group: "nav", trailingText: nil),
        ButtonSlot(key: "dpadLeft", actionKey: "dpadLeft", title: "D-pad Left", group: "nav", trailingText: nil),
        ButtonSlot(key: "dpadRight", actionKey: "dpadRight", title: "D-pad Right", group: "nav", trailingText: nil),
        ButtonSlot(key: "start", actionKey: "start", title: "Start / Menu", group: "system", trailingText: nil),
        ButtonSlot(key: "select", actionKey: "select", title: "Select / View", group: "system", trailingText: nil),
        ButtonSlot(key: "stickL", actionKey: "stickClick", title: "L3 / R3 Press", group: "system", trailingText: nil),
        ButtonSlot(key: "stickR", actionKey: "stickClick", title: "L3 / R3 Press", group: "system", trailingText: nil),
    ]

    private let groups: [GroupDescriptor] = [
        GroupDescriptor(
            title: "Shoulders",
            subtitle: "Trigger modifiers and bumper actions",
            slotKeys: ["lt", "rt", "lb", "rb"],
            footer: "LT and RT stay managed in Preset Prompts."
        ),
        GroupDescriptor(
            title: "Face Buttons",
            subtitle: "Primary action buttons",
            slotKeys: ["a", "b", "x", "y"],
            footer: nil
        ),
        GroupDescriptor(
            title: "Navigation",
            subtitle: "Directional controls",
            slotKeys: ["dpadUp", "dpadDown", "dpadLeft", "dpadRight"],
            footer: nil
        ),
        GroupDescriptor(
            title: "System & Sticks",
            subtitle: "Menu buttons and stick press action",
            slotKeys: ["start", "select", "stickL"],
            footer: "L3 and R3 share the same runtime action."
        ),
    ]

    private var slotActions: [String: ButtonAction] = [:]
    private var popupByActionKey: [String: NSPopUpButton] = [:]
    private var groupCards: [MappingGroupCardView] = []

    override var isFlipped: Bool { true }

    init(frame: NSRect, mapping: ButtonMapping) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear

        slotActions = [
            "a": mapping.buttonActions.a,
            "b": mapping.buttonActions.b,
            "x": mapping.buttonActions.x,
            "y": mapping.buttonActions.y,
            "lb": mapping.buttonActions.lb,
            "rb": mapping.buttonActions.rb,
            "start": mapping.buttonActions.start,
            "select": mapping.buttonActions.select,
            "stickClick": mapping.buttonActions.stickClick,
            "dpadUp": mapping.buttonActions.dpadUp,
            "dpadDown": mapping.buttonActions.dpadDown,
            "dpadLeft": mapping.buttonActions.dpadLeft,
            "dpadRight": mapping.buttonActions.dpadRight,
        ]

        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutCards()
    }

    private func buildUI() {
        popupByActionKey.removeAll()
        groupCards.removeAll()

        for descriptor in groups {
            let rows = descriptor.slotKeys.compactMap { slot(for: $0) }.map(buildRow)
            let card = MappingGroupCardView(
                title: descriptor.title,
                subtitle: descriptor.subtitle,
                footer: descriptor.footer,
                rows: rows
            )
            addSubview(card)
            groupCards.append(card)
        }
    }

    private func layoutCards() {
        guard groupCards.count == 4 else { return }

        let gap: CGFloat = 18
        let columnWidth = (bounds.width - gap) / 2
        let rowHeightTop = max(groupCards[0].preferredHeight, groupCards[1].preferredHeight)
        let rowHeightBottom = max(groupCards[2].preferredHeight, groupCards[3].preferredHeight)

        groupCards[0].frame = NSRect(x: 0, y: 0, width: columnWidth, height: rowHeightTop)
        groupCards[1].frame = NSRect(x: columnWidth + gap, y: 0, width: columnWidth, height: rowHeightTop)
        groupCards[2].frame = NSRect(x: 0, y: rowHeightTop + gap, width: columnWidth, height: rowHeightBottom)
        groupCards[3].frame = NSRect(x: columnWidth + gap, y: rowHeightTop + gap, width: columnWidth, height: rowHeightBottom)
    }

    private func buildRow(for slot: ButtonSlot) -> MappingActionRowView {
        if let actionKey = slot.actionKey {
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.font = NSFont.systemFont(ofSize: 12)
            for action in ButtonAction.allCases {
                popup.addItem(withTitle: action.rawValue)
            }
            popup.selectItem(withTitle: slotActions[actionKey]?.rawValue ?? ButtonAction.none.rawValue)
            popup.target = self
            popup.action = #selector(actionPopupChanged(_:))
            popup.identifier = NSUserInterfaceItemIdentifier(rawValue: actionKey)
            popupByActionKey[actionKey] = popup
            return MappingActionRowView(title: slot.title, popup: popup)
        }

        return MappingActionRowView(title: slot.title, detail: slot.trailingText ?? "")
    }

    @objc private func actionPopupChanged(_ sender: NSPopUpButton) {
        guard let actionKey = sender.identifier?.rawValue,
              let title = sender.titleOfSelectedItem,
              let action = ButtonAction.allCases.first(where: { $0.rawValue == title }) else { return }
        slotActions[actionKey] = action
    }

    private func slot(for key: String) -> ButtonSlot? {
        slots.first(where: { $0.key == key })
    }

    func actionForSlot(_ key: String) -> ButtonAction {
        switch key {
        case "stickL", "stickR":
            return slotActions["stickClick"] ?? .none
        default:
            guard let slot = slot(for: key), let actionKey = slot.actionKey else { return .none }
            return slotActions[actionKey] ?? .none
        }
    }
}

private final class MappingGroupCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(labelWithString: "")
    private let rows: [MappingActionRowView]
    let preferredHeight: CGFloat

    override var isFlipped: Bool { true }

    init(title: String, subtitle: String, footer: String?, rows: [MappingActionRowView]) {
        self.rows = rows
        let footerHeight: CGFloat = footer == nil ? 0 : 24
        self.preferredHeight = 64 + CGFloat(rows.count) * 38 + CGFloat(max(rows.count - 1, 0)) * 8 + footerHeight + 18
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = mappingPanelColor.cgColor
        layer?.cornerRadius = 18
        layer?.borderWidth = 1
        layer?.borderColor = mappingDividerColor.cgColor

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        addSubview(titleLabel)

        subtitleLabel.stringValue = subtitle
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = mappingSecondaryText
        addSubview(subtitleLabel)

        footerLabel.stringValue = footer ?? ""
        footerLabel.font = NSFont.systemFont(ofSize: 11)
        footerLabel.textColor = mappingSecondaryText
        footerLabel.isHidden = footer == nil
        addSubview(footerLabel)

        rows.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()

        titleLabel.frame = NSRect(x: 16, y: 16, width: bounds.width - 32, height: 18)
        subtitleLabel.frame = NSRect(x: 16, y: 36, width: bounds.width - 32, height: 14)

        var y: CGFloat = 60
        for row in rows {
            row.frame = NSRect(x: 12, y: y, width: bounds.width - 24, height: 38)
            y += 46
        }

        if !footerLabel.isHidden {
            footerLabel.frame = NSRect(x: 16, y: bounds.height - 26, width: bounds.width - 32, height: 14)
        }
    }
}

private final class MappingActionRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let popup: NSPopUpButton?

    override var isFlipped: Bool { true }

    init(title: String, popup: NSPopUpButton) {
        self.popup = popup
        super.init(frame: .zero)
        commonInit(title: title)
        addSubview(popup)
    }

    init(title: String, detail: String) {
        self.popup = nil
        super.init(frame: .zero)
        commonInit(title: title)
        detailLabel.stringValue = detail
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func commonInit(title: String) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
        layer?.cornerRadius = 11

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        addSubview(titleLabel)

        detailLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingMiddle
    }

    override func layout() {
        super.layout()

        titleLabel.frame = NSRect(x: 14, y: 9, width: 160, height: 18)
        if let popup {
            popup.frame = NSRect(x: bounds.width - 186, y: 5, width: 172, height: 28)
        } else {
            detailLabel.frame = NSRect(x: bounds.width - 150, y: 10, width: 136, height: 16)
        }
    }
}
