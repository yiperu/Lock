//
//  AppDelegate.swift
//  Cerradura
//
//  Created by Alsey Coleman Miller on 4/16/16.
//  Copyright © 2016 ColemanCDA. All rights reserved.
//

import Foundation
import UIKit
import WatchConnectivity
import CoreSpotlight
import CoreLock
import JSON

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    
    static var shared: AppDelegate { return UIApplication.shared.delegate as! AppDelegate }

    var window: UIWindow?
    
    var active = true
    
    var firstLaunch = false
        
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        // print app info
        print("Launching Cerradura v\(AppVersion) Build \(AppBuild)")
        
        // reset Keychain if first launch
        if Preferences.shared.isAppInstalled == false {
            
            try! Store.shared.keychain.removeAll()
            
            Preferences.shared.isAppInstalled = true
            
            firstLaunch = true
        }
        
        // add NSPersistentStore to Cerradura.Store
        do { try LoadPersistentStore() }
        
        catch {
            
            print("Nuking cache")
            
            try! RemovePersistentStore()
            try! LoadPersistentStore()
            try! Store.shared.keychain.removeAll()
        }
        
        LockManager.shared.log = { print("LockManager: " + $0) }
        
        // Apple Watch support
        if #available(iOS 9.3, *) {
            
            if WCSession.isSupported() {
                
                WatchController.shared.log = { print("WatchController: " + $0) }
                
                WatchController.shared.activate()
            }
        }
        
        // iBeacon
        BeaconController.shared.log = { print("BeaconController: " + $0) }
        BeaconController.shared.start()
        
        // Core Spotlight
        if #available(iOS 9.0, *) {
            
            if CSSearchableIndex.isIndexingAvailable() {
                
                UpdateSpotlight() { (error) in
                    
                    print("Updated SpotLight index")
                    
                    if let error = error { print("Spotlight Error: ", error) }
                }
                
                SpotlightController.shared.log = { print("SpotlightController: " + $0) }
                
                try! SpotlightController.shared.startObserving()
            }
        }
        
        // configure SplitVC
        (self.window!.rootViewController as! UISplitViewController).preferredDisplayMode = .allVisible
        
        // handle url
        if let url = launchOptions?[UIApplicationLaunchOptionsKey.url] as? URL {
            
            guard openURL(url)
                else { return false }
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        
        active = false
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        
        //state = .background
        active = false
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        
        //state = .foreground
        active = true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        active = true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        
        //BeaconController.shared.stop()
    }
    
    func application(_ application: UIApplication, handleOpen url: URL) -> Bool {
        
        return openURL(url)
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        
        print("Continue activity \(userActivity.activityType)")
        
        if #available(iOS 9.0, *) {
            
            guard userActivity.activityType == CSSearchableItemActionType
                else { return false }
            
            guard let identifierString = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                let identifier = UUID(rawValue: identifierString)
                else { return false }
            
            guard let (lockCache, keyData) = Store.shared[identifier]
                else { return false }
            
            print("Selected lock \(identifier) from CoreSpotlight")
            
            async {
                
                do {
                    var foundLock = LockManager.shared[identifier]
                    
                    // scan if not prevously found
                    if foundLock == nil {
                        
                        try LockManager.shared.scan()
                        
                        foundLock = LockManager.shared[identifier]
                    }
                    
                    guard foundLock != nil
                        else { mainQueue { self.window?.rootViewController?.showErrorAlert("Could not unlock. Not in range.") }; return }
                    
                    // wait until other scanning completes
                    while LockManager.shared.scanning.value {
                        
                        sleep(1)
                    }
                    
                    let key = (lockCache.keyIdentifier, keyData)
                    
                    try LockManager.shared.unlock(identifier, key: key)
                }
                
                catch { mainQueue { self.window?.rootViewController?.showErrorAlert("Could not unlock. \(error)") }; return }
            }
            
            return true
            
        } else {
            
            return false
        }
    }
}

private extension AppDelegate {
    
    func openURL(_ url: URL) -> Bool {
        
        if url.isFileURL {
            
            // parse eKey file
            guard let data = try? Data(contentsOf: url),
                let jsonString = String(UTF8Data: data),
                let json = try? JSON.Value(string: jsonString),
                let newKey = NewKeyInvitation(JSONValue: json)
                else { return false }
            
            // only one key per lock
            guard Store.shared[cache: newKey.lock] == nil else {
                
                self.window!.rootViewController?.showErrorAlert("You already have a key for lock \(newKey.lock).")
                return false
            }
            
            // show NewKeyReceiveVC
            let navigationController = UIStoryboard(name: "NewKeyInvitation", bundle: nil).instantiateInitialViewController() as! UINavigationController
            
            let newKeyVC = navigationController.topViewController as! NewKeyRecieveViewController
            
            newKeyVC.newKey = newKey
            
            self.window!.rootViewController?.present(navigationController, animated: true, completion: nil)
            
            return true
            
        } else {
            
            // handle custom URL
            
            return false
        }
    }
}
