/**
A quick-n-dirty way to display a UITableViewController, mostly for debugging
purposes or with rarely-used features.

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
 Can optionally be used to pair list items with custom description strings,
 if setting formatBlock is inconvenient.
*/
public class SimpleListItem<T>: CustomStringConvertible {

    public let representedObject: T
    public let description: String

    public init(_ representedObject: T, description: String) {
        self.representedObject = representedObject
        self.description = description
    }

}

/**
A quick-n-dirty way to display a UITableViewController, mostly for debugging
purposes or with rarely-used features.
*/
public final class SimpleListVC<T>: UITableViewController {

    public init(fetchBlock: @escaping (@escaping (State<T>) -> Void) -> Void) {
        self.fetchBlock = fetchBlock
        super.init(style: UITableViewStyle.plain)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public enum State<T> {
        case loading
        case failed(Error)
        case empty
        case succeeded([T])
    }

    private var state: State<T> = .loading
    private var isUpdateInProgress = false

    public var cellTypes: [String: UITableViewCell.Type] = [
        "item": UITableViewCell.self,
    ]

    public var fetchBlock: (@escaping (State<T>) -> Void) -> Void = { completion in
        completion(.empty)
    }

    public var notificationsToMonitor: [Notification.Name] = []

    public var loadingMessage: String = "Loading..."
    public var emptyMessage: String = "Empty"

    public var formatBlock: (IndexPath, T, UITableView) throws -> UITableViewCell = { indexPath, item, tableView in
        let cell = tableView.dequeueReusableCell(withIdentifier: "item", for: indexPath)
        cell.textLabel!.numberOfLines = 0
        cell.textLabel!.text = String(describing: item)
        return cell
    }

    public var deleteBlock: ((IndexPath, T) -> Bool)? = nil

    public override func viewDidLoad() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "loading")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "failed")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "empty")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "failedChange")
        for (identifier, type) in cellTypes {
            tableView.register(type, forCellReuseIdentifier: identifier)
        }

        tableView.allowsSelection = false

        if deleteBlock != nil && self.navigationItem.rightBarButtonItem == nil {
            self.navigationItem.rightBarButtonItem = self.editButtonItem
        }

        for name in notificationsToMonitor {
            NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: nil)
        }

        update()
    }

    @objc public func update() {
        guard !isUpdateInProgress else {
            return
        }
        isUpdateInProgress = true

        fetchBlock { [weak self] (newState) in
            self?.finishUpdating(newState)
        }
    }

    private func finishUpdating(_ newState: State<T>) {
        isUpdateInProgress = false
        switch newState {
        case let .succeeded(data) where data.isEmpty:
            state = .empty
        default:
            state = newState
        }
        tableView.reloadData()
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch state {
        case .loading, .failed, .empty:
            return 1
        case let .succeeded(data):
            return data.count
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch state {
        case .loading:
            let cell = tableView.dequeueReusableCell(withIdentifier: "loading", for: indexPath)
            cell.textLabel!.text = loadingMessage
            return cell
        case let .failed(error):
            let cell = tableView.dequeueReusableCell(withIdentifier: "failed", for: indexPath)
            cell.textLabel!.text = "Failed: \(String(reflecting: error))"
            return cell
        case .empty:
            let cell = tableView.dequeueReusableCell(withIdentifier: "empty", for: indexPath)
            cell.textLabel!.text = emptyMessage
            return cell
        case let .succeeded(data):
            let item = data[indexPath.row]
            do {
                return try formatBlock(indexPath, item, tableView)
            } catch {
                let cell = tableView.dequeueReusableCell(withIdentifier: "failedChange", for: indexPath)
                cell.textLabel!.text = "Failed: \(String(reflecting: error))"
                return cell
            }
        }
    }

    public override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        switch state {
        case .loading, .failed, .empty:
            return .none
        case .succeeded:
            if deleteBlock == nil {
                return .none
            } else {
                return .delete
            }
        }
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        let isDone: Bool
        switch state {
        case .loading, .failed, .empty:
            isDone = false
        case let .succeeded(data):
            if editingStyle == .delete, let deleteBlock = deleteBlock {
                let item = data[indexPath.row]
                isDone = deleteBlock(indexPath, item)
                if isDone {
                    var newData = data
                    newData.remove(at: indexPath.row)
                    state = .succeeded(newData)
                }
            } else {
                isDone = false
            }
        }

        if isDone {
            tableView.deleteRows(at: [indexPath], with: .bottom)
        } else {
            tableView.reloadData()  // cancel deletion
        }
    }

}
