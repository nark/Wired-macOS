//
//  ConnectionWindowController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift



private extension ConnectionWindowController {
    // MARK: -
    @objc private func didToggleLeftSidebarView(_ n:Notification) {
        if let splitViewController = self.contentViewController as? NSSplitViewController {
            splitViewController.splitViewItems.first?.isCollapsed = !splitViewController.splitViewItems.first!.isCollapsed
        }
    }

    
    
    @objc private func linkConnectionDidClose(notification: Notification) -> Void {
        if let c = notification.object as? Connection, c == self.connection {
            if let item = self.toolbarItem(withIdentifier: "Disconnect") {
                item.image = NSImage(named: "Reconnect")
                item.label = "Reconnect"
                
                if self.manualyDisconnected == false {
                    if UserDefaults.standard.bool(forKey: "WSAutoReconnect") {
                        self.startAutoReconnect()
                        
                    } else {
                        AppDelegate.notify(identifier: "connection", title: "Server Disconnected", text: "You have been disconnected form \(self.connection.serverInfo.serverName!)", connection: self.connection)
                    }
                }
                
                self.manualyDisconnected = false
                
                self.validate()
            }
        }
    }
    
    
    
    
    
    
    private func startAutoReconnect() {
        self.stopAutoReconnect()
        
        let interval = 10.0
        
        self.autoreconnectTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { (timer) in
            print("Try to auto-reconnect every \(interval) sec. (\(self.reconnectCounter))...")
            
            self.reconnect()
        }
    }
    
    private func stopAutoReconnect() {
        self.reconnectCounter = 0
        
        if self.autoreconnectTimer != nil {
            self.autoreconnectTimer.invalidate()
            self.autoreconnectTimer = nil
        }
    }
    
    
    private func reconnect() {
        self.reconnectCounter += 1
        
        if let item = self.toolbarItem(withIdentifier: "Disconnect") {
            if !self.connection.isConnected() {
                item.isEnabled = false
                item.label = "Reconnecting"
                
                DispatchQueue.global().async {
                    if self.connection.reconnect() {
                        print("reconnect OK")
                        
                        DispatchQueue.main.async {
                            self.stopAutoReconnect()
                                                        
                            NotificationCenter.default.post(name: .linkConnectionDidReconnect, object: self.connection)
                            
                            item.image = NSImage(named: "Disconnect")
                            item.label = "Disconnect"
                            item.isEnabled = true
                            
                            self.validate()
                        }
                    } else {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .linkConnectionDidFailReconnect, object: self.connection)
                            item.isEnabled = true
                            item.label = "Reconnect"
                            
                            self.validate()
                        }
                    }
                }
            }
        }
    }
}



extension ConnectionWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    private func toolbarItem(withIdentifier: String) -> NSToolbarItem? {
        if let w = self.window {
            if let toolbar = w.toolbar {
                for item in toolbar.visibleItems! {
                    if item.itemIdentifier.rawValue == withIdentifier {
                        return item
                    }
                }
            }
        }
        return nil
    }
    
    
    private func validateCustomToolbarItem(_ item: NSToolbarItem) {
        if item.itemIdentifier.rawValue == "Settings" {
            item.isEnabled =    self.connection != nil &&
                                self.connection.isConnected() &&
                                self.connection.hasAdministrationPrivileges()
        }
    }
    
    public func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        return true
    }
    
    
    
    private func validate() {
        if let items = self.window?.toolbar?.visibleItems {
            for item in items {
                self.validateCustomToolbarItem(item)
            }
        }
    }
    
    
    public func setBanner(image:NSImage) {
        if let bannerItem = self.toolbarItem(withIdentifier: "Banner") {
            if let imageView = bannerItem.view as? NSImageView {
                if self.connection.serverInfo.serverBanner != nil {
                    imageView.image = image
                }
            }
        }
    }
}



extension ConnectionWindowController: NSWindowDelegate {
    // MARK: -
    public func windowDidBecomeMain(_ notification: Notification) {
        if self.window == notification.object as? NSWindow {
            self.validate()
        
            // handle unreads
            if let splitViewController = self.contentViewController as? NSSplitViewController {
              if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                  // check if selected toolbar identifier is selected
                  if let identifier = tabViewController.tabView.tabViewItem(at: tabViewController.selectedTabViewItemIndex).identifier as? String {
                      if identifier == "Chat" {
                          if self.connection != nil {
                              // unread selected chat if any
                              if let splitViewController2 = tabViewController.tabViewItems.first?.viewController as? NSSplitViewController {
                                  if let chatsViewController = splitViewController2.splitViewItems.first?.viewController as? ChatsViewController {
                                      if self.connection == chatsViewController.connection {
                                          if let item = chatsViewController.selectedItem() as? Chat {
                                              if item.unreads > 0 {
                                                  AppDelegate.decrementChatUnread(withValue: item.unreads, forConnection: self.connection)
                                                  
                                                  item.unreads = 0
                                                  
                                                  chatsViewController.chatsOutlineView.reloadItem(item)
                                              }
                                          }
                                      }
                                  }
                              }
                          }
                      }
                      else if identifier == "Messages" {
                          // hmm, we prefer to unread them by conversation, right ?
                          if let messageSplitView = tabViewController.tabViewItems[1].viewController as? MessagesSplitViewController {
                              if let conversationsViewController = messageSplitView.splitViewItems[1].viewController as? ConversationsViewController {
                                  if let conversation = conversationsViewController.selectedConversation {
                                      // mark conversation messages as read, only if conversation is selected
                                      DispatchQueue.global(qos: .userInitiated).async {
                                          _ = conversation.markAllAsRead()
                                          
                                          DispatchQueue.main.async {
                                              try? AppDelegate.shared.persistentContainer.viewContext.save()
                                              
                                              if let index = ConversationsController.shared.conversations().index(of: conversation) {
                                                  conversationsViewController.conversationsTableView.reloadData(forRowIndexes: [index], columnIndexes: [0])
                                                  AppDelegate.updateUnreadMessages(forConnection: self.connection)
                                              }
                                          }
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
          }
      }
    }


    @objc private func windowWillClose(notification: Notification) -> Void {
        if let w = notification.object as? NSWindow {
            if w == self.window {
                self.disconnect()
                
                if self.connection != nil {
                    ConnectionsController.shared.removeConnection(self.connection)
                }
                
                NSApp.removeWindowsItem(w)

                self.window = nil

                NotificationCenter.default.removeObserver(self)
            }
        }
    }
}



extension ConnectionWindowController: ServerInfoDelegate {
    public func serverInfoDidChange(for connection: Connection) {
        if let bannerImage = NSImage(data: self.connection.serverInfo.serverBanner) {
            self.setBanner(image: bannerImage)
        }
    }
}



public class ConnectionWindowController: NSWindowController {
    public var connection: ServerConnection!
    public var bookmark: Bookmark!
    
    public var settingsWindowController:SettingWindowController!

    var autoreconnectTimer:Timer!
    var reconnectCounter = 0
    
    public var manualyDisconnected  = false
    public var manualyReconnected   = false
    
    
    // MARK: -
    public static func connectConnectionWindowController(withBookmark bookmark:Bookmark) -> ConnectionWindowController? {
        if let cwc = AppDelegate.windowController(forBookmark: bookmark) {
            if let tabGroup = cwc.window?.tabGroup {
                tabGroup.selectedWindow = cwc.window
            }
            return cwc
        }
                
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        guard let connectionWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConnectionWindowController")) as? ConnectionWindowController else {
            return nil
        }
        
        let url = bookmark.url()
        
        connectionWindowController.connection = ServerConnection(withSpec: spec, delegate: connectionWindowController as? ConnectionDelegate)
        connectionWindowController.connection.clientInfoDelegate = AppDelegate.shared
        connectionWindowController.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? connectionWindowController.connection.nick
        connectionWindowController.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? connectionWindowController.connection.status
        
        connectionWindowController.connection.connectionWindowController = connectionWindowController
        
        if let b64string = AppDelegate.currentIcon?.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)?.base64EncodedString() {
            connectionWindowController.connection.icon = b64string
        }
            
        DispatchQueue.global().async {
            if connectionWindowController.connection.connect(withUrl: url) == true {
                DispatchQueue.main.async {
                    if let bannerItem = connectionWindowController.toolbarItem(withIdentifier: "Banner") {
                        if let imageView = bannerItem.view as? NSImageView {
                            if connectionWindowController.connection.serverInfo.serverBanner != nil {
                                imageView.image = NSImage(data: connectionWindowController.connection.serverInfo.serverBanner)
                            }
                        }
                    }
                    
                    ConnectionsController.shared.addConnection(connectionWindowController.connection)
                    
                    connectionWindowController.attach(connection: connectionWindowController.connection)
                    connectionWindowController.showWindow(connectionWindowController)
                }
            } else {
                DispatchQueue.main.async {
                    if let wiredError = connectionWindowController.connection.socket.errors.first {
                        AppDelegate.showWiredError(wiredError)
                    }
                    
                    connectionWindowController.disconnect()
                    connectionWindowController.connection = nil
                    
                    if let w = connectionWindowController.window {
                        NSApp.removeWindowsItem(w)
                    }

                    connectionWindowController.window = nil

                    NotificationCenter.default.removeObserver(connectionWindowController)
                    
                    connectionWindowController.close()
                }
            }
        }
            
        return connectionWindowController
    }
    
        
    override public func windowDidLoad() {
        super.windowDidLoad()
            
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(notification:)),
            name: NSWindow.willCloseNotification, object: self.window)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionDidClose(notification:)) ,
            name: .linkConnectionDidClose, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(didToggleLeftSidebarView(_:)),
            name: .didToggleLeftSidebarView, object: nil)
        
        self.window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(rawValue: "Chat")
    }
    
    
    
    public override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowSettings" {
            if let settingWindowController = segue.destinationController as? SettingWindowController {
                if let tabViewController = settingWindowController.contentViewController as? TabViewController {
                    for item in tabViewController.tabViewItems {
                        if let connectionViewController = item.viewController as? ConnectionViewController {
                            connectionViewController.representedObject = self.connection
                        }
                    }
                }
            }
        }
    }
    
    
  
    
    // MARK: -
    @IBAction func settings(_ sender: Any) {
        if !self.connection.hasAdministrationPrivileges() {
            return
        }
        
        if self.settingsWindowController == nil {
            let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
            if let settingWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("SettingWindowController")) as? SettingWindowController {
                self.settingsWindowController = settingWindowController
            }
        }
        
        if let tabViewController = settingsWindowController.contentViewController as? TabViewController {
            for item in tabViewController.tabViewItems {
                if let connectionViewController = item.viewController as? ConnectionViewController {
                    connectionViewController.representedObject = self.connection
                }
            }
        }
        
        self.settingsWindowController.showWindow(self)
    }
    
    
    @IBAction func tabAction(_ sender: Any) {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: "SelectedToolbarItemChanged"), object: self.window)
    }
    
    
    
    @IBAction func disconnect(_ sender: Any) {
        if let item = self.toolbarItem(withIdentifier: "Disconnect") {
            print("self.connection : \(self.connection) \(self.connection.isConnected())")
            
            if self.connection != nil {
                if self.connection.isConnected() {
                    if UserDefaults.standard.bool(forKey: "WSCheckActiveConnectionsBeforeQuit") == true {
                        let alert = NSAlert()
                        alert.messageText = NSLocalizedString("Are you sure you want to disconnect?", comment: "")
                        alert.informativeText = NSLocalizedString("Every running transfers may be stopped", comment: "")
                        alert.alertStyle = .warning
                        let YesButtonText = NSLocalizedString("Yes", comment: "")
                        alert.addButton(withTitle: YesButtonText)
                        let CancelButtonText = NSLocalizedString("Cancel", comment: "")
                        alert.addButton(withTitle: CancelButtonText)
                        
                        if let window = self.window {
                            alert.beginSheetModal(for: window) { (modalResponse: NSApplication.ModalResponse) -> Void in
                                if modalResponse == .alertFirstButtonReturn {
                                    self.manualyDisconnected = true
                                    self.connection.disconnect()
                                    item.image = NSImage(named: "Reconnect")
                                    item.label = "Reconnect"
                                }
                            }
                        } else {
                            if alert.runModal() == .alertFirstButtonReturn {
                                self.manualyDisconnected = true
                                self.connection.disconnect()
                                item.image = NSImage(named: "Reconnect")
                                item.label = "Reconnect"
                            }
                        }

                    } else {
                        self.manualyDisconnected = true
                        self.connection.disconnect()
                        item.image = NSImage(named: "Reconnect")
                        item.label = "Reconnect"
                    }
        
                } else {
                    self.manualyReconnected = true
                    self.reconnect()
                }
            }
        }
    }
    
    
    
    
    // MARK: -
    public func attach(connection:ServerConnection) {
        self.connection = connection
        self.connection.serverInfoDelegate = self
        
        self.window?.title = self.connection.serverInfo.serverName
        
        if self.connection.serverInfo.serverBanner != nil {
            if let image = NSImage(data: self.connection.serverInfo.serverBanner) {
                self.setBanner(image: image)
            }
        }
        
        if let splitViewController = self.contentViewController as? NSSplitViewController {
            if let resourcesController = splitViewController.splitViewItems[0].viewController as? ResourcesController {
                  resourcesController.representedObject = self.connection
            }
              
            if let tabViewController = splitViewController.splitViewItems[1].viewController as? NSTabViewController {
                if let splitViewController2 = tabViewController.tabViewItems[0].viewController as? NSSplitViewController {
                    if let chatsController = splitViewController2.splitViewItems[0].viewController as? ChatsViewController {
                        chatsController.representedObject = self.connection
                    }
                }
                
                for item in tabViewController.tabViewItems {
                    if let connectionController = item.viewController as? InfosViewController {
                        connectionController.representedObject = self.connection
                    }
                    else if let messagesSplitViewController = item.viewController as? MessagesSplitViewController {
                        if let conversationsViewController = messagesSplitViewController.splitViewItems[1].viewController as? ConversationsViewController {
                            conversationsViewController.representedObject = self.connection
                        }
                    }
                    else if let boardsSplitViewController = item.viewController as? BoardsSplitViewController {
                        if let boardsViewController = boardsSplitViewController.splitViewItems[0].viewController as? BoardsViewController {
                            boardsViewController.representedObject = self.connection
                            
                            if let threadsSplitViewController = boardsSplitViewController.splitViewItems[1].viewController as? NSSplitViewController {
                                if let threadsViewController = threadsSplitViewController.splitViewItems[0].viewController as? ThreadsViewController {
                                    boardsViewController.threadsViewsController = threadsViewController
                                    threadsViewController.representedObject = self.connection
                                    
                                    if let postsViewController = threadsSplitViewController.splitViewItems[1].viewController as? PostsViewController {
                                        threadsViewController.postsViewController = postsViewController
                                        postsViewController.representedObject = self.connection
                                    }
                                }
                                
                            }
                        }
                    }
                    else if let connectionController = item.viewController as? FilesViewController {
                        connectionController.representedObject = self.connection
                    }
                    else if let connectionController = item.viewController as? ConsoleViewController {
                        connectionController.representedObject = self.connection
                    }
                }
            }
            
            AppDelegate.updateUnreadMessages(forConnection: connection)
        }
    }
    
    
    public override func close() {
        //self.connection.removeDelegate(self)
        
        super.close()
    }
    
    
    public func disconnect() {
        if self.connection != nil {
            //ConnectionsController.shared.removeConnection(self.connection)
            self.connection.disconnect()
        }
    }
}
