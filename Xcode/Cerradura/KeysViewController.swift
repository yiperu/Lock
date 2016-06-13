//
//  KeysViewController.swift
//  Lock
//
//  Created by Alsey Coleman Miller on 4/23/16.
//  Copyright © 2016 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import CoreBluetooth
import CoreLock
import GATT

final class KeysViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate, AsyncProtocol {
    
    // MARK: - IB Outlets
    
    @IBOutlet weak var tableView: UITableView!
    
    // MARK: - Properties
    
    private lazy var fetchedResultsController: NSFetchedResultsController = {
        
        let fetchRequest = NSFetchRequest(entityName: LockCache.entityName)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: LockCache.Property.name.rawValue, ascending: true)]
        
        let controller = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: Store.shared.managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        
        return controller
    }()
    
    internal lazy var queue: dispatch_queue_t = dispatch_queue_create("\(self.dynamicType) Internal Queue", DISPATCH_QUEUE_SERIAL)
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let _ = LockManager.shared.state.observe(stateChanged)
        
        fetchedResultsController.delegate = self
        tableView.dataSource = self
        tableView.delegate = self
        
        try! fetchedResultsController.performFetch()
    }
    
    // MARK: - Methods
    
    private func stateChanged(_ state: CBCentralManagerState) {
        
        mainQueue {
            
            self.tableView.setEditing(false, animated: true)
        }
    }
    
    private func item(at indexPath: NSIndexPath) -> LockCache {
        
        let managedObject = fetchedResultsController.object(at: indexPath) as! NSManagedObject
        
        let lock = LockCache(managedObject: managedObject)
        
        return lock
    }
    
    private func configure(cell: KeyTableViewCell, at indexPath: NSIndexPath) {
        
        let lock = item(at: indexPath)
        
        let permissionImage: UIImage
        
        let permissionText: String
        
        switch lock.permission {
            
        case .owner:
            
            permissionImage = UIImage(named: "permissionBadgeOwner")!
            
            permissionText = "Owner"
            
        case .admin:
            
            permissionImage = UIImage(named: "permissionBadgeAdmin")!
            
            permissionText = "Admin"
            
        case .anytime:
            
            permissionImage = UIImage(named: "permissionBadgeAnytime")!
            
            permissionText = "Anytime"
            
        case let .scheduled(schedule):
            
            permissionImage = UIImage(named: "permissionBadgeScheduled")!
            
            permissionText = "Scheduled" // FIXME
        }
        
        cell.lockNameLabel.text = lock.name
        
        cell.permissionImageView.image = permissionImage
        
        cell.permissionLabel.text = permissionText
    }
    
    // MARK: - UITableViewDatasource
    
    @objc func numberOfSections(in tableView: UITableView) -> Int {
        
        return 1
    }
    
    @objc func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return fetchedResultsController.fetchedObjects?.count ?? 0
    }
    
    @objc func tableView(_ tableView: UITableView, cellForRowAt indexPath: NSIndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: KeyTableViewCell.resuseIdentifier, for: indexPath) as! KeyTableViewCell
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: NSIndexPath) -> [UITableViewRowAction]? {
        
        var actions = [UITableViewRowAction]()
        
        let lockCache = self.item(at: indexPath)
        
        let delete = UITableViewRowAction(style: UITableViewRowActionStyle.destructive, title: "Delete") {
            
            assert($0.1 == indexPath)
            
            let alert = UIAlertController(title: NSLocalizedString("Confirmation", comment: "DeletionConfirmation"),
                                          message: "Are you sure you want to delete this key?",
                                          preferredStyle: UIAlertControllerStyle.alert)
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: "Delete"), style: UIAlertActionStyle.destructive, handler: { (UIAlertAction) in
                
                Store.shared.remove(lockCache.identifier)
                
                alert.dismiss(animated: true, completion: nil)
            }))
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel"), style: UIAlertActionStyle.`default`, handler: { (UIAlertAction) in
                
                alert.dismiss(animated: true, completion: nil)
            }))
            
           self.present(alert, animated: true, completion: nil)
        }
        
        actions.append(delete)
        
        let unlock = UITableViewRowAction(style: UITableViewRowActionStyle.normal, title: "Unlock") { (action, index) in
            
            let key = Store.shared[key: lockCache.identifier]!
            
            print("Unlocking \"\(lockCache.name)\"...")
            
            tableView.setEditing(false, animated: true)
            
            self.async {
                
                do { try LockManager.shared.unlock(lockCache.identifier, key: key) }
                    
                catch { mainQueue { self.showErrorAlert("Could not unlock. (\(error))") }; return }
                
                print("Successfully unlocked \"\(lockCache.name)\"")
            }
        }
        
        // validate permission for unlocking
        if case let .scheduled(schedule) = lockCache.permission where schedule.valid() {
            
            actions.append(unlock)
            
        } else {
            
            actions.append(unlock)
        }
        
        let newKey = UITableViewRowAction(style: UITableViewRowActionStyle.normal, title: "New key") { (action, index) in
            
            tableView.setEditing(false, animated: true)
            
            let navigationController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "newKeyNavigationStack") as! UINavigationController
            
            let destinationViewController = navigationController.viewControllers.first! as! NewKeySelectPermissionViewController
            
            destinationViewController.lockIdentifier = lockCache.identifier
            
            self.present(navigationController, animated: true, completion: nil)
        }
        
        newKey.backgroundColor = UIColor.green()
        
        // Bluetooth must be on and only Admin and Owner can create keys
        if LockManager.shared.state.value == .poweredOn
            && (lockCache.permission == .owner || lockCache.permission == .admin) {
            
            actions.append(newKey)
        }
        
        return actions
    }
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    @objc func controllerWillChangeContent(_ controller: NSFetchedResultsController) {
        
        tableView.beginUpdates()
    }
    
    @objc func controllerDidChangeContent(_ controller: NSFetchedResultsController) {
        
        tableView.endUpdates()
    }
    
    @objc func controller(_ controller: NSFetchedResultsController,
                          didChange anObject: AnyObject,
                          at indexPath: NSIndexPath?,
                          for type: NSFetchedResultsChangeType,
                          newIndexPath: NSIndexPath?) {
        
        sleep(1)
        
        switch type {
            
        case .insert:
            
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
            
        case .delete:
            
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
            
        case .update:
            
            if let indexPath = indexPath {
                
                if let cell = tableView.cellForRow(at: indexPath) as? KeyTableViewCell {
                    
                    self.configure(cell: cell, at: indexPath)
                }
            }
            
        case .move:
            
            if let indexPath = indexPath {
                
                if let newIndexPath = newIndexPath {
                    
                    tableView.deleteRows(at: [indexPath], with: .automatic)
                    tableView.insertRows(at: [newIndexPath], with: .automatic)
                }
            }
        }
    }
}

// MARK: - Supporting Types

final class KeyTableViewCell: UITableViewCell {
    
    static let resuseIdentifier = "KeyTableViewCell"
    
    @IBOutlet weak var permissionImageView: UIImageView!
    
    @IBOutlet weak var lockNameLabel: UILabel!
    
    @IBOutlet weak var permissionLabel: UILabel!
}
