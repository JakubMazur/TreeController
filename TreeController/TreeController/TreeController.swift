//
//  TreeController.swift
//  TreeController
//
//  Created by Artem Shimanski on 06.03.17.
//  Copyright © 2017 Artem Shimanski. All rights reserved.
//

import UIKit
import CoreData

public enum ChangeType {
	case insert
	case delete
	case move
	case update
}

public enum TransitionStyle {
	case none
	case reload
	case reconfigure
}

extension Array where Element: TreeNode {
	
	func changes(from: Array<Element>, handler: (_ oldIndex: Index?, _ newIndex: Index?, _ changeType: ChangeType) -> Void) {
		let to = self
		var arr = from
		
		var removed = IndexSet()
		var inserted = IndexSet()
		var updated = [(Int, Int)]()
		var moved = [(Int, Int)]()
		
		var j = 0
		for (i, v) in from.enumerated() {
			if to.count <= j || to[j] != v {
				arr.remove(at: i - removed.count)
				removed.insert(i)
			}
			else {
				updated.append((i, j))
				j += 1
			}
		}
		
		for (i, v) in to.enumerated() {
			if arr.count <= i || arr[i] != v {
				inserted.insert(i)
				arr.insert(v, at: i)
			}
		}
		
		for i in removed {
			let obj = from[i]
			for j in inserted {
				if obj == to[j] {
					removed.remove(i)
					inserted.remove(j)
					if i != j {
						moved.append((i, j))
					}
					else {
						updated.append((i, j))
					}
				}
			}
		}
		if !removed.isEmpty {
			removed.reversed().forEach {handler($0, nil, .delete)}
		}
		if !inserted.isEmpty {
			inserted.forEach {handler(nil, $0, .insert)}
		}
		if !moved.isEmpty {
			moved.reversed().forEach {handler($0.0, $0.1, .move)}
		}
		if !updated.isEmpty {
			updated.forEach {handler($0.0, $0.1, .update)}
		}
		
		/*let to = self
		var arr = from
		
		for (i, v) in from.enumerated().reversed() {
			if to.index(of: v) == nil {
				handler(i, nil, .delete)
				arr.remove(at: i)
			}
		}
		
		var moves = Set<Int>()
		
		for i in indices {
			guard !moves.contains(i) else {continue}
			let obj = to[i]
			if let j = arr[i..<arr.count].index(of: obj) {
				let k = from.index(of: obj)!
				
				if j != i {
					handler(k, i, .move)
					moves.insert(k)
				}
				let obj2 = from[k]
				if obj !== obj2 {
					handler(k, i, .update)
				}
				
			}
			else {
				handler(nil, i, .insert)
				arr.insert(obj, at: i)
			}
		}*/
	}
	
	mutating func remove(at: IndexSet) {
		for i in at.reversed() {
			self.remove(at: i)
		}
	}
}

open class TreeNode: NSObject {
	open var cellIdentifier: String?
	open func configure(cell: UITableViewCell) -> Void {
		cell.indentationLevel = indentationLevel
	}
	
	public init(cellIdentifier: String? = nil) {
		self.cellIdentifier = cellIdentifier
		super.init()
	}
	
	private var _children: [TreeNode]?
	public var children: [TreeNode] {
		get {
			if _children == nil {
				loadChildren()
				if _children == nil {
					_children = []
				}
			}
			return _children!
		}
		
		set {
			let from = _children
			let to = newValue
			for a in to {
				if let i = from?.index(of: a), let b = from?[i] {
					a.isExpanded = b.isExpanded
					a.isSelected = b.isSelected
					a.estimatedHeight = b.estimatedHeight
				}
			}
			
			if from != nil, let treeController = treeController, let index = flatIndex {
				let size = self.size
				_children = to
				let range = index..<(index + size)
				treeController.replaceNodes(at: range, with: flattened)
			}
			else {
				_children = to
			}
			for child in from ?? [] {
				child.parent = nil
			}
			for child in to {
				child.parent = self
			}
		}
	}
	
	public weak var parent: TreeNode?
	public weak var treeController: TreeController? {
		get {
			return _treeController ?? parent?.treeController
		}
		set {
			_treeController = newValue
		}
	}
	
	open var isExpandable: Bool {
		return true
	}
	
	private var removeRange: CountableRange<Int>?
	open var isExpanded: Bool = true {
		willSet {
			guard treeController != nil else {return}
			guard isExpanded else {return}
			guard newValue != isExpanded else {return}
			guard let flatIndex = flatIndex else {return}
			
			var range = flatIndex..<(flatIndex + size)
			if isViewable {
				range = (range.lowerBound + 1) ..< range.upperBound
			}
			self.removeRange = range
		}
		didSet {
			if let range = removeRange {
				treeController?.removeNodes(at: range)
				self.removeRange = nil
			}
			
			guard let treeController = treeController else {return}
			guard oldValue != isExpanded else {return}
			
			if let cell = treeController.cell(for: self) as? Expandable {
				cell.setExpanded(isExpanded, animated: true)
			}
			
			guard isExpanded else {return}
			guard var flatIndex = flatIndex else {return}
			
			var array = flattened
			if isViewable {
				flatIndex += 1
				array = Array(array[1..<array.count])
			}
			
			treeController.insertNodes(array, at: flatIndex)
		}
	}
	
	fileprivate var _isSelected: Bool = false
	open var isSelected: Bool {
		get {
			return _isSelected
		}
		set {
			_isSelected = newValue
			if newValue {
				treeController?.selectCell(for: self, animated: true, scrollPosition: .none)
			}
			else {
				treeController?.deselectCell(for: self, animated: true)
			}
		}
	}

	open func transitionStyle(from node: TreeNode) -> TransitionStyle {
		return .none
	}
	
	open func loadChildren() {
		
	}
	
	private weak var _treeController: TreeController?
	fileprivate var isViewable: Bool {
		return cellIdentifier != nil
	}
	fileprivate var estimatedHeight: CGFloat?
	
	fileprivate var flatIndex: Int?
	
	fileprivate var size: Int {
		var size = isViewable ? 1 : 0
		if !isExpandable || isExpanded || !isViewable {
			for child in children {
				size += child.size
			}
		}
		return size
	}
	
	fileprivate var flattened: [TreeNode] {
		
		if !isExpandable || isExpanded || !isViewable {
			
			var array = [TreeNode]()
			if isViewable {
				array.append(self)
			}
			
			for child in children {
				array.append(contentsOf: child.flattened)
			}
			
			return array
		}
		else if isViewable {
			return [self]
		}
		else {
			return []
		}
	}
	
	fileprivate var indentationLevel: Int {
		return parent?.isViewable == true ? parent!.indentationLevel + 1 : parent?.indentationLevel ?? 0
	}
}

@objc public protocol TreeControllerDelegate: UIScrollViewDelegate {
	@objc optional func treeController(_ treeController: TreeController, configureCell cell: UITableViewCell, withNode node: TreeNode) -> Void
	@objc optional func treeController(_ treeController: TreeController, editActionsForNode node: TreeNode) -> [UITableViewRowAction]?
	@objc optional func treeController(_ treeController: TreeController, editingStyleForNode node: TreeNode) -> UITableViewCellEditingStyle
	@objc optional func treeController(_ treeController: TreeController, didSelectCellWithNode node: TreeNode) -> Void
	@objc optional func treeController(_ treeController: TreeController, didDeselectCellWithNode node: TreeNode) -> Void
	@objc optional func treeController(_ treeController: TreeController, didExpandCellWithNode node: TreeNode) -> Void
	@objc optional func treeController(_ treeController: TreeController, didCollapseCellWithNode node: TreeNode) -> Void
	@objc optional func treeController(_ treeController: TreeController, accessoryButtonTappedWithNode node: TreeNode) -> Void
	@objc optional func treeController(_ treeController: TreeController, commit editingStyle: UITableViewCellEditingStyle, forNode node: TreeNode) -> Void
	
	@objc optional func treeControllerDidUpdateContent(_ treeController: TreeController) -> Void
}

@objc public protocol Expandable {
	func setExpanded(_ expanded: Bool, animated: Bool) -> Void
}

open class TreeController: NSObject, UITableViewDelegate, UITableViewDataSource {
	
	public var content: TreeNode? {
		didSet {
			oldValue?.treeController = nil
			content?.treeController = self
			let to = content?.flattened
			if oldValue == nil || !UIView.areAnimationsEnabled {
				flattened = to ?? []
				updateIndexes()
				tableView?.reloadData()
			}
			else {
				replaceNodes(at: 0..<flattened.count, with: to ?? [])
			}
			delegate?.treeControllerDidUpdateContent?(self)
		}
	}
	
	@IBOutlet public weak var tableView: UITableView?
	@IBOutlet public weak var delegate: TreeControllerDelegate?
	
	private var flattened: [TreeNode] = []

	public func cell(for node: TreeNode) -> UITableViewCell? {
		guard let index = node.flatIndex else {return nil}
		let indexPath = IndexPath(row: index, section: 0)
		return tableView?.cellForRow(at: indexPath)
	}
	
	public func node(for cell: UITableViewCell) -> TreeNode? {
		guard let indexPath = tableView?.indexPath(for: cell) else {return nil}
		return flattened[indexPath.row]
	}
	
	public func indexPath(for node: TreeNode) -> IndexPath? {
		guard let index = node.flatIndex else {return nil}
		return IndexPath(row: index, section: 0)
	}
	
	public func reloadCells(for nodes: [TreeNode], with animation: UITableViewRowAnimation = .fade) {
		let indexPaths = nodes.flatMap({$0.flatIndex == nil ? nil : IndexPath(row: $0.flatIndex!, section:0)})
		if (indexPaths.count > 0) {
			tableView?.reloadRows(at: indexPaths, with: animation)
		}
	}

	public func deselectCell(for node: TreeNode, animated: Bool) {
		node._isSelected = false
		guard let index = node.flatIndex else {return}
		let indexPath = IndexPath(row: index, section: 0)
		tableView?.deselectRow(at: indexPath, animated: animated)
	}
	
	public func selectCell(for node: TreeNode, animated: Bool, scrollPosition: UITableViewScrollPosition) {
		node._isSelected = true
		guard let index = node.flatIndex else {return}
		let indexPath = IndexPath(row: index, section: 0)
		tableView?.selectRow(at: indexPath, animated: animated, scrollPosition: scrollPosition)
	}
	
	
	private var updatesCounter: Int = 0
	
	public func beginUpdates() {
		if UIView.areAnimationsEnabled {
			tableView?.beginUpdates()
		}
		updatesCounter += 1
	}
	
	public func endUpdates() {
		if UIView.areAnimationsEnabled {
			tableView?.endUpdates()
		}
		updatesCounter -= 1
		if updatesCounter == 0 {
			if !UIView.areAnimationsEnabled {
				tableView?.reloadData()
			}
			delegate?.treeControllerDidUpdateContent?(self)
		}
	}

	
	//MARK: - UITableViewDataSource
	
	public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return flattened.count
	}
	
	public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let node = flattened[indexPath.row]
		let cell = tableView.dequeueReusableCell(withIdentifier: node.cellIdentifier!, for: indexPath)
		cell.indentationLevel = node.indentationLevel
		
		if let cell = cell as? Expandable {
			cell.setExpanded(node.isExpanded, animated: false)
		}
		
		node.configure(cell: cell)
		delegate?.treeController?(self, configureCell: cell, withNode: node)
		return cell
	}
	
	public func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}
	
	public func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		let node = flattened[indexPath.row]
		delegate?.treeController?(self, commit: editingStyle, forNode: node)
	}
	
	//MARK: - UITableViewDelegate
	
	public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let node = flattened[indexPath.row]
		if node.isExpandable {
			node.isExpanded = !node.isExpanded
		}
		node._isSelected = true
		delegate?.treeController?(self, didSelectCellWithNode: node)
	}
	
	public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
		let node = flattened[indexPath.row]
		if node.isExpandable && ((tableView.allowsMultipleSelection && !tableView.isEditing) || (tableView.allowsMultipleSelectionDuringEditing && tableView.isEditing))  {
			node.isExpanded = !node.isExpanded
		}
		node._isSelected = false
		delegate?.treeController?(self, didDeselectCellWithNode: node)
	}
	
	public func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
		let node = flattened[indexPath.row]
		delegate?.treeController?(self, accessoryButtonTappedWithNode: node)
	}
	
	
	public func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
		let node = flattened[indexPath.row]
		return delegate?.treeController?(self, editActionsForNode: node)
	}
	
	public func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
		let node = flattened[indexPath.row]
		return delegate?.treeController?(self, editingStyleForNode: node) ?? (self.tableView(tableView, editActionsForRowAt: indexPath) != nil ? .delete : .none)
	}
	
	public func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		return self.tableView(tableView, editingStyleForRowAt: indexPath) != .none
	}
	
	public func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
		let node = flattened[indexPath.row]
		if let estimatedHeight = node.estimatedHeight {
			return estimatedHeight
		}
		else {
			return tableView.estimatedRowHeight > 0 ? tableView.estimatedRowHeight : UITableViewAutomaticDimension
		}
	}
	
	public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
		let node = flattened[indexPath.row]
		node.estimatedHeight = cell.bounds.size.height
	}
	
	//MARK: - UIScrollViewDelegate
	
	public func scrollViewDidScroll(_ scrollView: UIScrollView) {
		delegate?.scrollViewDidScroll?(scrollView)
	}
	
	public func scrollViewDidZoom(_ scrollView: UIScrollView) {
		delegate?.scrollViewDidZoom?(scrollView)
	}
	
	
	public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		delegate?.scrollViewWillBeginDragging?(scrollView)
	}
	
	public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
		delegate?.scrollViewWillEndDragging?(scrollView, withVelocity: velocity, targetContentOffset: targetContentOffset)
	}
	
	public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		delegate?.scrollViewDidEndDragging?(scrollView, willDecelerate: decelerate)
	}
	
	public func scrollViewWillBeginDecelerating(_ scrollView: UIScrollView) {
		delegate?.scrollViewWillBeginDecelerating?(scrollView)
	}
	
	public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		delegate?.scrollViewDidEndDecelerating?(scrollView)
	}
	
	public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
		delegate?.scrollViewDidEndScrollingAnimation?(scrollView)
	}
	
	public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return delegate?.viewForZooming?(in: scrollView)
	}
	
	public func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
		delegate?.scrollViewWillBeginZooming?(scrollView, with: view)
	}
	
	public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
		delegate?.scrollViewDidEndZooming?(scrollView, with: view, atScale: scale)
	}
	
	public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
		return delegate?.scrollViewShouldScrollToTop?(scrollView) ?? true
	}
	
	public func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
		delegate?.scrollViewDidScrollToTop?(scrollView)
	}

	
	
	//MARK: - Private
	
	fileprivate func removeNodes(at range: CountableRange<Int>) {
		for node in flattened[range] {
			node.flatIndex = nil
		}
		flattened.removeSubrange(range)
		updateIndexes()
		
		if UIView.areAnimationsEnabled {
			tableView?.deleteRows(at: range.map({IndexPath(row: $0, section: 0)}), with: .fade)
		}
		else {
			tableView?.reloadData()
		}
	}
	
	fileprivate func insertNodes(_ nodes: [TreeNode], at index: Int) {
		flattened.insert(contentsOf: nodes, at: index)
		updateIndexes()
		let range = index..<(index + nodes.count)
		
		if UIView.areAnimationsEnabled {
			tableView?.insertRows(at: range.map({IndexPath(row: $0, section: 0)}), with: .fade)
		}
		else {
			tableView?.reloadData()
		}
		
		for (i, node) in flattened[range].enumerated() {
			if node.isSelected {
				tableView?.selectRow(at: IndexPath(row: range.lowerBound + i, section: 0), animated: false, scrollPosition: .none)
			}
		}
	}
	
	fileprivate func replaceNodes(at range: CountableRange<Int>, with nodes: [TreeNode]) {
		beginUpdates()

		let from = Array(flattened[range])
		for node in from {
			node.flatIndex = nil
		}
		
		flattened.replaceSubrange(range, with: nodes)
		
		let start = range.lowerBound
		var selections = [IndexPath]()
		
		let animation = UIView.areAnimationsEnabled ? UITableViewRowAnimation.fade : .none
		
		if UIView.areAnimationsEnabled {
			nodes.changes(from: from) { (old, new, type) in
				switch type {
				case .insert:
					let indexPath = IndexPath(row: start + new!, section: 0)
					if nodes[new!].isSelected {
						selections.append(indexPath)
					}
					tableView?.insertRows(at: [indexPath], with: animation)
				case .delete:
					tableView?.deleteRows(at: [IndexPath(row: start + old!, section: 0)], with: animation)
				case .move:
					//				tableView?.moveRow(at: IndexPath(row: start + old!, section: 0), to: IndexPath(row: start + new!, section: 0))
					let indexPath = IndexPath(row: start + new!, section: 0)
					if nodes[new!].isSelected {
						selections.append(indexPath)
					}
					
					tableView?.deleteRows(at: [IndexPath(row: start + old!, section: 0)], with: animation)
					tableView?.insertRows(at: [indexPath], with: animation)
				case .update:
					let indexPath = IndexPath(row: start + old!, section: 0)
					let a = from[old!]
					let b = nodes[new!]
					if b.isSelected {
						selections.append(indexPath)
					}
					
					switch b.transitionStyle(from: a) {
					case .reload:
						tableView?.reloadRows(at: [indexPath], with: animation)
						break
					case .reconfigure:
						if let cell = tableView?.cellForRow(at: indexPath) {
							b.configure(cell: cell)
						}
					//tableView?.reloadRows(at: [indexPath], with: .none)
					default:
						break
					}
				}
			}
		}
		else {
			tableView?.reloadData()
		}
		
		updateIndexes()
		endUpdates()
		for indexPath in selections {
			tableView?.selectRow(at: indexPath, animated: false, scrollPosition: .none)
		}
	}
	
	fileprivate func updateIndexes() {
		guard let content = content else {return}
		var index: Int = 0
		func update(_ node: TreeNode) {
			node.flatIndex = index
			if node.isViewable {
				index += 1
			}
			
			if !node.isExpandable || node.isExpanded || !node.isViewable {
				for child in node.children {
					update(child)
				}
			}
		}
		update(content)
	}

}


class FetchedResultsNode<ResultType: NSFetchRequestResult>: TreeNode, NSFetchedResultsControllerDelegate {
	let resultsController: NSFetchedResultsController<ResultType>
	let sectionNode: FetchedResultsSectionNode<ResultType>.Type?
	let objectNode: FetchedResultsObjectNode<ResultType>.Type
	
	init(resultsController: NSFetchedResultsController<ResultType>, sectionNode: FetchedResultsSectionNode<ResultType>.Type? = nil, objectNode: FetchedResultsObjectNode<ResultType>.Type) {
		self.resultsController = resultsController
		self.sectionNode = sectionNode
		self.objectNode = objectNode
		super.init()
		if resultsController.fetchRequest.resultType == .managedObjectResultType || resultsController.fetchRequest.resultType == .managedObjectResultType {
			resultsController.delegate = self
		}
	}
	
	override func loadChildren() {
		try? resultsController.performFetch()
		if let sectionNode = self.sectionNode {
			children = resultsController.sections?.map {sectionNode.init(section: $0, objectNode: self.objectNode)} ?? []
		}
		else {
			children = resultsController.fetchedObjects?.flatMap {objectNode.init(object: $0)} ?? []
		}
	}
	
	private struct Update {
		var insertSection: [Int: TreeNode] = [:]
		var deleteSection = IndexSet()
		var insertObject: [IndexPath: TreeNode] = [:]
		var deleteObject = [IndexPath]()
		var moveObject: [IndexPath: IndexPath] = [:]
		var update: [IndexPath: Any] = [:]
	}
	private var update: Update?
	
	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
//		guard objectNode != nil else {return}
		self.update = Update()
		treeController?.beginUpdates()
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
		guard update != nil else {return}
		guard let sectionNode = self.sectionNode else {return}
		switch type {
		case .insert:
			update?.insertSection[sectionIndex] = sectionNode.init(section: sectionInfo, objectNode: self.objectNode)
//			children.insert(sectionNode.init(section: sectionInfo, objectNode: self.objectNode), at: sectionIndex)
		case .delete:
			update?.deleteSection.insert(sectionIndex)
//			children.remove(at: sectionIndex)
		default:
			break
		}
	}
	
	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
		guard update != nil else {return}
//		guard self.sectionNode == nil else {return}
		switch type {
		case .insert:
			update?.insertObject[newIndexPath!] = objectNode.init(object: anObject as! ResultType)
//			children.insert(objectNode.init(object: anObject as! ResultType), at: newIndexPath!.row)
		case .delete:
			update?.deleteObject.append(indexPath!)
//			children.remove(at: indexPath!.row)
		case .move:
			update?.deleteObject.append(indexPath!)
			update?.insertObject[newIndexPath!] = objectNode.init(object: anObject as! ResultType)
//			update?.moveObject[indexPath]
//			children.remove(at: indexPath!.row)
//			children.insert(objectNode.init(object: anObject as! ResultType), at: newIndexPath!.row)
		case .update:
			update?.update[newIndexPath!] = anObject
//			children[newIndexPath!.row] = objectNode.init(object: anObject as! ResultType)
		}
	}
	
	
	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		guard let update = update else {return}
		
		if sectionNode == nil {
			for i in update.deleteObject.sorted(by: > ) {
				children.remove(at: i.row)
			}
			for (i, value) in update.insertObject.sorted(by: {$0.key < $1.key}) {
				children.insert(value, at: i.row)
			}
		}
		else {
			if !update.deleteSection.isEmpty {
				children.remove(at: update.deleteSection)
			}
			for i in update.insertSection.sorted(by: {$0.key < $1.key}) {
				children.insert(i.value, at: i.key)
			}
			for i in update.deleteObject.sorted(by: > ) {
				children[i.section].children.remove(at: i.row)
			}
			for (i, value) in update.insertObject.sorted(by: {$0.key < $1.key}) {
				children[i.section].children.insert(value, at: i.row)
			}
		}
		
		treeController?.endUpdates()
		self.update = nil
	}
}

class FetchedResultsSectionNode<ResultType: NSFetchRequestResult> : TreeNode {
	let section: NSFetchedResultsSectionInfo
	let objectNode: FetchedResultsObjectNode<ResultType>.Type
	required init(section: NSFetchedResultsSectionInfo, objectNode: FetchedResultsObjectNode<ResultType>.Type) {
		self.objectNode = objectNode
		self.section = section
		super.init()
	}
	
	override func loadChildren() {
		children = section.objects?.flatMap {objectNode.init(object: $0 as! ResultType)} ?? []
	}
	
	override var hashValue: Int {
		return section.name.hashValue ^ section.numberOfObjects.hashValue
	}
	
	override func isEqual(_ object: Any?) -> Bool {
		return (object as? FetchedResultsSectionNode<ResultType>)?.hashValue == hashValue
	}
}

class FetchedResultsObjectNode<ResultType: NSFetchRequestResult>: TreeNode {
	let object: ResultType
	
	required init(object: ResultType) {
		self.object = object
		super.init()
	}
	
	override var hashValue: Int {
		return object.hash
	}
	
	override func isEqual(_ object: Any?) -> Bool {
		return (object as? FetchedResultsObjectNode<ResultType>)?.hashValue == hashValue
	}
	
}
