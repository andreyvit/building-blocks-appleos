/**
A static UITableView with predefined rows, suitable for settings, service menus
and the like.

This component is part of the Building Blocks initiative. We believe that apps
should be assembled from standardized building blocks like houses, not designed
from scratch like cathedrals. Over time, we want to produce a collection of
composable self-contained building blocks that work well with a number of
standardized internal (app & model) architectures.

To install these building blocks, copy some into your project and check back
for updates regularly. Each component follows semantic versioning. This may seem
like too much work, but we believe the manual approach is appropriately hands-on.

© 2018 Andrey Tarantsov <andrey@tarantsov.com>, published under the MIT license.

- v0.1.0 (2018-11-29): initial release
*/
import Foundation
import UIKit

/**
 Displays a UITableView with predefined rows. Reloads data when it receives one of the specified notifications.
 The rows are independent entities that produce their own table cells and handle user interaction.
*/
public class StaticTableVC: UITableViewController {

    private let rows: [StaticTableRow]
    private let changeNotifications: [Notification.Name]

    private var visibleSections: [StaticTableSection] = []

    public init(_ rows: [StaticTableRow], monitor changeNotifications: [Notification.Name] = []) {
        self.rows = rows
        self.changeNotifications = changeNotifications
        super.init(style: .grouped)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))

        for name in changeNotifications {
            NotificationCenter.default.addObserver(self, selector: #selector(updateSettings), name: name, object: nil)
        }
        updateSettings()
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return visibleSections.count
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection sectionIndex: Int) -> Int {
        let section = visibleSections[sectionIndex]
        return section.rows.count
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection sectionIndex: Int) -> String? {
        let section = visibleSections[sectionIndex]
        return (section.title.isEmpty ? nil : section.title)
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = visibleSections[indexPath.section].rows[indexPath.row]
        return row.cell
    }

    public override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        let controller = visibleSections[indexPath.section].rows[indexPath.row].controller
        if (controller?.isSelectable ?? false) {
            return indexPath
        } else {
            return nil
        }
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let controller = visibleSections[indexPath.section].rows[indexPath.row].controller
        switch (controller?.didSelect() ?? .deselect) {
        case .keepSelected:
            break
        case .deselect:
            tableView.deselectRow(at: indexPath, animated: true)
        case let .push(vc):
            if let navigationController = navigationController {
                navigationController.pushViewController(vc, animated: true)
            } else {
                let nc = UINavigationController(rootViewController: vc)
                tableView.deselectRow(at: indexPath, animated: true)
                present(nc, animated: true, completion: nil)
            }
        case let .present(vc):
            tableView.deselectRow(at: indexPath, animated: true)
            present(vc, animated: true, completion: nil)
        }
    }

    @IBAction private func dismissSelf() {
        dismiss(animated: true, completion: nil)
    }

    private var visibleSettings: [StaticTableRow] = []
    @objc private func updateSettings() {
        for setting in rows {
            setting.update()
        }

        let builder = StaticTableBuilder()
        for setting in rows {
            setting.render(into: builder)
        }
        visibleSections = builder.finish()
        tableView.reloadData()
    }

}

public protocol StaticTableRow {

    func update()

    func render(into builder: StaticTableBuilder)

}

public protocol StaticTableCellController {

    var displaysDisclosureIndicator: Bool { get }

    var isSelectable: Bool { get }

    func didSelect() -> StaticTableCellTapBehavior

}

public enum StaticTableCellTapBehavior {
    case deselect
    case keepSelected
    case push(UIViewController)
    case present(UIViewController)
}

internal protocol UpdatableStaticTableRow: class, StaticTableRow {
    var updateBlock: ((Self) -> Void)? { get set }
}
internal extension UpdatableStaticTableRow {
    func whenUpdating(_ block: @escaping (Self) -> Void) -> Self {
        self.updateBlock = block
        return self
    }
}

internal protocol TappableStaticTableRow: class, StaticTableRow {
    var didTap: (() -> StaticTableCellTapBehavior)? { get set }
    var displaysDisclosureIndicator: Bool { get set }
}
internal extension TappableStaticTableRow {
    func whenTapped(displaysDisclosureIndicator: Bool = true, _ block: @escaping () -> StaticTableCellTapBehavior) -> Self {
        self.displaysDisclosureIndicator = displaysDisclosureIndicator
        self.didTap = block
        return self
    }
}

public final class StaticTableSectionSeparator: StaticTableRow {

    private let title: String

    public init(_ title: String = "") {
        self.title = title
    }

    public func update() {
    }

    public func render(into builder: StaticTableBuilder) {
        builder.startSection(title)
    }
}

public final class ReadonlyValueRow: StaticTableRow, UpdatableStaticTableRow, TappableStaticTableRow, StaticTableCellController {

    public var title: String
    public var value: String
    public var isVisible: Bool = true

    public var updateBlock: ((ReadonlyValueRow) -> Void)?
    public func update() {
        updateBlock?(self)
    }

    public var didTap: (() -> StaticTableCellTapBehavior)?
    public var displaysDisclosureIndicator = true

    public init(_ title: String, value: String = "") {
        self.title = title
        self.value = value
    }

    public func render(into builder: StaticTableBuilder) {
        guard isVisible else { return }

        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel!.text = title
        cell.detailTextLabel!.text = value
        if isSelectable && displaysDisclosureIndicator {
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.selectionStyle = .none
        }
        builder.add(cell, controller: self)
    }

    public var isSelectable: Bool {
        return didTap != nil
    }

    public func didSelect() -> StaticTableCellTapBehavior {
        if let didTap = didTap {
            return didTap()
        } else {
            return .deselect
        }
    }

}

public final class TextRow: StaticTableRow, UpdatableStaticTableRow, TappableStaticTableRow, StaticTableCellController {

    public var text: String

    public var isVisible: Bool {
        get {
            return text != ""
        }
    }

    public var updateBlock: ((TextRow) -> Void)?
    public func update() {
        updateBlock?(self)
    }

    public var didTap: (() -> StaticTableCellTapBehavior)?
    public var displaysDisclosureIndicator = true

    public init(_ text: String = "") {
        self.text = text
    }

    public func render(into builder: StaticTableBuilder) {
        guard isVisible else { return }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel!.numberOfLines = 0
        cell.textLabel!.text = text
        if isSelectable && displaysDisclosureIndicator {
            cell.accessoryType = .disclosureIndicator
        } else {
            cell.selectionStyle = .none
        }
        builder.add(cell, controller: self)
    }

    public var isSelectable: Bool {
        return didTap != nil
    }

    public func didSelect() -> StaticTableCellTapBehavior {
        if let didTap = didTap {
            return didTap()
        } else {
            return .deselect
        }
    }

}

public final class ButtonRow: StaticTableRow, TappableStaticTableRow, StaticTableCellController {

    private let textAlignment: NSTextAlignment

    public var title: String
    public var isVisible: Bool = true

    public var updateBlock: ((ButtonRow) -> Void)?
    public func update() {
        updateBlock?(self)
    }

    public var didTap: (() -> StaticTableCellTapBehavior)?
    public var displaysDisclosureIndicator = true

    public var confirmation: SettingsActionConfirmation?

    public init(_ title: String, textAlignment: NSTextAlignment = .center) {
        self.title = title
        self.textAlignment = textAlignment
    }

    public func render(into builder: StaticTableBuilder) {
        guard isVisible else { return }

        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel!.textAlignment = textAlignment
        cell.textLabel!.text = title
        builder.add(cell, controller: self)
    }

    public func requires(_ confirmation: SettingsActionConfirmation) -> ButtonRow {
        self.confirmation = confirmation
        return self
    }

    public var isSelectable: Bool {
        return true
    }

    public func didSelect() -> StaticTableCellTapBehavior {
        if let didTap = didTap {
            if let confirmation = confirmation {
                let vc = UIAlertController(title: confirmation.message, message: nil, preferredStyle: .alert)
                vc.addAction(UIAlertAction(title: confirmation.actionButtonTitle, style: .default, handler: { (action) in
                    switch didTap() {
                    case .deselect:
                        break // OK
                    default:
                        fatalError("Confirmation button handler must return .deselect")
                    }
                }))
                vc.addAction(UIAlertAction(title: confirmation.cancelButtonTitle, style: .cancel, handler: nil))
                return .present(vc)
            }

            return didTap()
        } else {
            return .deselect
        }
    }

}

public final class ToggleRow: StaticTableRow, UpdatableStaticTableRow {

    public var title: String
    public var isVisible: Bool = true
    public var value: Bool

    public var updateBlock: ((ToggleRow) -> Void)?
    public func update() {
        updateBlock?(self)
    }

    public var didChange: ((Bool) -> Void)?

    public var confirmation: SettingsActionConfirmation?

    public init(_ title: String, value: Bool = false) {
        self.title = title
        self.value = value
    }

    public func whenChanged(_ block: @escaping (Bool) -> Void) -> Self {
        self.didChange = block
        return self
    }

    public func render(into builder: StaticTableBuilder) {
        guard isVisible else { return }

        let controller = ToggleRowController(row: self)
        builder.add(controller.cell, controller: controller)
    }

}
private class ToggleRowController: StaticTableCellController {

    public let row: ToggleRow
    public let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    private let toggle = UISwitch()

    fileprivate init(row: ToggleRow) {
        self.row = row
        cell.textLabel!.text = row.title
        cell.accessoryView = toggle
        toggle.isOn = row.value
        toggle.addTarget(self, action: #selector(toggleDidChange), for: .touchUpInside)
    }

    public var isSelectable: Bool {
        return false
    }

    public var displaysDisclosureIndicator: Bool {
        return false
    }

    public func didSelect() -> StaticTableCellTapBehavior {
        return .deselect
    }

    @objc private func toggleDidChange() {
        row.value = toggle.isOn
        if let didChange = row.didChange {
            return didChange(row.value)
        }
    }

}

public struct SettingsActionConfirmation {
    public var message: String
    public var actionButtonTitle: String
    public var actionButtonStyle: UIAlertActionStyle = .default
    public var cancelButtonTitle: String = "Cancel"

    public init(actionButtonTitle: String, message: String = "Are you sure?") {
        self.actionButtonTitle = actionButtonTitle
        self.message = message
    }
}

public final class StaticTableBuilder {

    private var sections: [StaticTableSection] = []
    private var currentSection = StaticTableSection()

    public func startSection(_ title: String = "") {
        if !currentSection.isEmpty {
            sections.append(currentSection)
        }
        currentSection = StaticTableSection()
        setSectionTitle(title)
    }

    public func setSectionTitle(_ title: String) {
        currentSection.title = title
    }

    public func add(_ cell: UITableViewCell, controller: StaticTableCellController?) {
        currentSection.rows.append(StaticTableCell(cell, controller: controller))
    }

    fileprivate func finish() -> [StaticTableSection] {
        startSection()
        return sections
    }

}

private final class StaticTableSection {

    fileprivate var title: String = ""

    fileprivate var rows: [StaticTableCell] = []

    fileprivate var isEmpty: Bool {
        return rows.isEmpty
    }

}

private final class StaticTableCell {

    fileprivate let cell: UITableViewCell
    fileprivate let controller: StaticTableCellController?

    fileprivate init(_ cell: UITableViewCell, controller: StaticTableCellController?) {
        self.cell = cell
        self.controller = controller
    }

}
