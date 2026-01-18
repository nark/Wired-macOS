//
//  ServerSettingsViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift


// MARK: -
private extension ServerSettingsViewController {
    private func getSettings() {
        if self.connection.hasPrivilege(key: "wired.account.settings.get_settings") {
            let message = P7Message(withName: "wired.settings.get_settings", spec: self.connection.spec)
            
            self.connection.send(message: message)
        }
    }
    
    
    private func setSettings() {
        if self.connection.hasPrivilege(key: "wired.account.settings.set_settings") {
            let message = P7Message(withName: "wired.settings.set_settings", spec: self.connection.spec)
            message.addParameter(field: "wired.info.name", value: self.serverNameTextField.stringValue)
            message.addParameter(field: "wired.info.description", value: self.serverDescriptionTextField.stringValue)
            
            if let data = self.bannerImageView.image?.tiffRepresentation {
                message.addParameter(field: "wired.info.banner", value: data)
            }
            
            self.connection.send(message: message)
        }
    }
}



// MARK: -
extension ServerSettingsViewController: ConnectionDelegate {
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if connection == self.connection && connection.isConnected() {
            if message.name == "wired.settings.settings" {
                print(message)
                
                if let serverName = message.string(forField: "wired.info.name") {
                    self.serverNameTextField.stringValue = serverName
                }
                
                if let serverDescription = message.string(forField: "wired.info.description") {
                    self.serverDescriptionTextField.stringValue = serverDescription
                }
                
                if let serverBanner = message.data(forField: "wired.info.banner") {
                    self.bannerImageView.image = NSImage(data: serverBanner)
                }
                
                if let v = message.uint32(forField: "wired.info.downloads") {
                    self.downloadsTextField.stringValue = "\(v)"
                }
                
                if let v = message.uint32(forField: "wired.info.uploads") {
                    self.uploadsTextField.stringValue = "\(v)"
                }
                
                if let v = message.uint32(forField: "wired.info.download_speed") {
                    self.downloadSpeedTextField.stringValue = "\(v)"
                }
                
                if let v = message.uint32(forField: "wired.info.upload_speed") {
                    self.uploadSpeedTextField.stringValue = "\(v)"
                }
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}




// MARK: -
extension ServerSettingsViewController: NSControlTextEditingDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        if let _ = obj.object as? NSTextField {
            self.setSettings()
        }
    }
    
}




// MARK: -
class ServerSettingsViewController: ConnectionViewController {
    @IBOutlet weak var serverNameTextField: NSTextField!
    @IBOutlet weak var serverDescriptionTextField: NSTextField!
    @IBOutlet weak var bannerImageView: NSImageView!
    
    @IBOutlet weak var downloadsTextField: NSTextField!
    @IBOutlet weak var uploadsTextField: NSTextField!
    @IBOutlet weak var downloadSpeedTextField: NSTextField!
    @IBOutlet weak var uploadSpeedTextField: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    
    
    // MARK: -
    override var representedObject: Any? {
        didSet {
            if let connection = self.representedObject as? ServerConnection {
                self.connection = connection
                self.connection.addDelegate(self)
                
                self.getSettings()
            }
        }
    }
    

    
    
    // MARK: -
    @IBAction func banner(_ sender: Any) {
        if let data = bannerImageView.image?.tiffRepresentation {
            if data != self.connection.serverInfo.serverBanner {
                self.setSettings()
            }
        }
    }
}
