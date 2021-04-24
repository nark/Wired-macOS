//
//  ViewController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 15/07/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift



class ConnectController: ConnectionViewController, ConnectionDelegate {
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var addressField: NSTextField!
    @IBOutlet weak var loginField: NSTextField!
    @IBOutlet weak var passwordField: NSSecureTextField!
    @IBOutlet weak var connectButton: NSButton!
    
    public var connectionWindowController:ConnectionWindowController!
    
    
    
    public static func connectController(withBookmark bookmark:Bookmark) -> ConnectController? {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        if let connectWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConnectWindowController")) as? NSWindowController {
            if let connectViewController = connectWindowController.window?.contentViewController as? ConnectController {
                let url = bookmark.url()
                
                connectViewController.addressField.stringValue  = url.hostname
                connectViewController.loginField.stringValue    = url.login
                connectViewController.passwordField.stringValue = url.password
                
                connectWindowController.showWindow(self)
                
                return connectViewController
//                connectViewController.connectionWindowController = self
//
//                if let window = self.window, let connectWindow = connectWindowController.window {
//                    window.beginSheet(connectWindow) { (modalResponse) in
//                        if modalResponse == .cancel {
//                            //self.close()
//                        }
//                    }
//                }
            }
        }
        
        
            
//        let url = bookmark.url()
//
//        connectionWindowController.connection = ServerConnection(withSpec: spec, delegate: connectionWindowController as? ConnectionDelegate)
//        connectionWindowController.connection.clientInfoDelegate = AppDelegate.shared
//        connectionWindowController.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? connectionWindowController.connection.nick
//        connectionWindowController.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? connectionWindowController.connection.status
//
//        connectionWindowController.connection.connectionWindowController = connectionWindowController
//
//        if let b64string = AppDelegate.currentIcon?.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)?.base64EncodedString() {
//            connectionWindowController.connection.icon = b64string
//        }
//
//        return connectionWindowController
        return nil
    }
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    

    
    @IBAction func connect(_ sender: Any) {
        if addressField.stringValue.count == 0 {
            return
        }
        
        let url = Url(withString: "wired://\(addressField.stringValue)")
        
        if loginField.stringValue.count == 0 {
            // force guest login by default
            url.login = "guest"
        } else {
            url.login = loginField.stringValue
        }
        
        url.password = passwordField.stringValue
        
        self.connection = ServerConnection(withSpec: spec, delegate: self)
        self.connection.nick = UserDefaults.standard.string(forKey: "WSUserNick") ?? self.connection.nick
        self.connection.status = UserDefaults.standard.string(forKey: "WSUserStatus") ?? self.connection.status
        
        if let b64string = AppDelegate.currentIcon?.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)?.base64EncodedString() {
            self.connection.icon = b64string
        }
            
        self.progressIndicator.startAnimation(sender)
        connectButton.isEnabled = false
                
        DispatchQueue.global().async {
            if self.connection.connect(withUrl: url) {
                DispatchQueue.main.async {
                    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
                    guard let connectionWindowController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConnectionWindowController")) as? ConnectionWindowController else {
                        return
                    }
                    self.connectionWindowController = connectionWindowController
                    self.connection.connectionWindowController = self.connectionWindowController
                    ConnectionsController.shared.addConnection(self.connection)
                    
                    self.progressIndicator.stopAnimation(sender)
                    
                    self.view.window?.orderOut(sender)
                    self.view.window?.close()
                    
                    // distribute connection to sub components
                    self.connectionWindowController.attach(connection: self.connection)
                    self.connectionWindowController.showWindow(self)
                }
            } else {
                DispatchQueue.main.async {
//                    if let wiredError = self.connection.socket.errors.first {
//                        AppDelegate.showWiredError(wiredError)
//                    }
                    
                    self.connectButton.isEnabled = true
                    self.progressIndicator.stopAnimation(self)
                }
            }
        }
    }
    
    
    @IBAction func cancel(_ sender: Any) {
        self.view.window?.orderOut(sender)
        self.view.window?.close()
    }
    
    
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        if let e = error as? WiredError {
            AppDelegate.showWiredError(e, modalFor: self.view.window)
        } else {
            WiredSwift.Logger.error(error.localizedDescription)
        }
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        // print("connectionDisconnected")
        //ConnectionsController.shared.removeConnection(connection as! ServerConnection)
    }
    
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveMessage")
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        // print("connectionDidReceiveError")
    }

}

