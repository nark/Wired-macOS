//
//  UsersViewController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

public class UsersViewController: ConnectionViewController, ConnectionDelegate, NSTableViewDelegate, NSTableViewDataSource, NSUserInterfaceValidations {
    @IBOutlet weak var usersTableView: NSTableView!
    
    public var chatID:UInt32 = 0
    public var chatController:ChatController?
    var selectedUser:UserInfo!
    
    
    

    // MARK: - View Controller
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(userLeftPublicChat(_:)),
            name: NSNotification.Name("UserLeftPublicChat"), object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionDidClose(notification:)) ,
            name: .linkConnectionDidClose, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(selectedChatDidChange(_:)) ,
            name: .selectedChatDidChange, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(userJoinChat(_:)) ,
            name: .userJoinChat, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(userLeaveChat(_:)) ,
            name: .userLeaveChat, object: nil)
        
        self.usersTableView.target = self
        self.usersTableView.doubleAction = #selector(doubleClickAction(_:))
    }
    
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    
    override public var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                self.connection.addDelegate(self)
            }
        }
    }
    
    
    
    
    
    // MARK: - Notification
    
    @objc func selectedChatDidChange(_ n:Notification) {
        if let chatController = n.object as? ChatController {
            if chatController.chat?.chatID == self.chatID {
                if self.chatController == nil {
                    self.chatController = chatController
                    self.usersTableView.reloadData()
                }
            }
        } else {
            self.usersTableView.reloadData()
        }
    }
    
    
    @objc func userJoinChat(_ n:Notification) {
        if let chatController = n.object as? ChatController {
            if chatController.chat?.chatID == self.chatID {
                if self.chatController == nil {
                    self.chatController = chatController
                }
                self.usersTableView.reloadData()
            }
        }
    }
    
    
    @objc func userLeaveChat(_ n:Notification) {
        if let chatController = n.object as? ChatController {
            if chatController.chat?.chatID == self.chatID {
                self.chatController = nil
                self.usersTableView.reloadData()
                
                if let c = self.connection {
                    c.removeDelegate(self)
                }
            }
        }
    }
    
    
    @objc func linkConnectionDidReconnect(_ notification: Notification) {
        if let c = notification.object as? Connection, c == self.connection {
            self.usersTableView.reloadData()
        }
    }
    
    
    @objc private func linkConnectionDidClose(notification: Notification) -> Void {
        if let c = notification.object as? Connection, c == self.connection {
            self.chatController?.usersController.removeAllUsers()
            
            //self.chatController = nil
                        
            self.usersTableView.reloadData()
        }
    }
    
    
    @objc func userLeftPublicChat(_ n:Notification) {
        if let c = n.object as? Connection, self.connection == c {
            self.usersTableView.reloadData()
        }
    }

    
    
    
    
    // MARK: - IBAction
    
    @IBAction func doubleClickAction(_ sender: Any) {
        self.selectedUser = self.selectedItem()
        
        self.showPrivateMessages(sender)
    }
    
    @IBAction func showPrivateMessages(_ sender: Any) {
        if let selectedUser = self.selectedUser {
            _ = ConversationsController.shared.openConversation(onConnection: self.connection, withUser: selectedUser)
            
            self.selectedUser = nil
        }
    }
    
    
    @IBAction func inviteToPrivateChat(_ sender: Any) {
        if self.selectedUser != nil {
            // create private chat
            let privateChatController = PrivateChatController(self.connection, creator: self.connection.userInfo, invite: self.selectedUser)
            
            NotificationCenter.default.post(name: .userCreatePrivateChat, object: privateChatController)
            
            self.selectedUser = nil
        }
    }
    
    
    @IBAction func getUserInfo(_ sender: Any) {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: Bundle.main)
        if let userInfoViewController = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("UserInfoViewController")) as? UserInfoViewController {
            let popover = NSPopover()
            popover.contentSize = userInfoViewController.view.frame.size
            popover.behavior = .transient
            popover.animates = true
            popover.contentViewController = userInfoViewController
            
            userInfoViewController.connection = self.connection
            userInfoViewController.user = self.selectedUser
            self.selectedUser = nil
            
            popover.show(relativeTo: self.usersTableView.frame, of: self.usersTableView, preferredEdge: .minX)
        }
    }
    
    @IBAction func kickUser(_ sender: Any) {
        if let user = self.selectedItem() {
            let message = P7Message(withName: "wired.chat.kick_user", spec: spec)
            message.addParameter(field: "wired.chat.id", value: self.chatController?.chat?.chatID)
            message.addParameter(field: "wired.user.id", value: user.userID)
            message.addParameter(field: "wired.user.disconnect_message", value: "")
            _ = self.connection.send(message: message)
        }
    }
    
    @IBAction func banUser(_ sender: Any) {
        print("banUser")
    }
    
    
    
    
    
    // MARK: - connection Delegate
    
    public func connectionDidConnect(connection: Connection) {
        
    }
    
    public func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    public func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if  message.name == "wired.chat.user_list" ||
            message.name == "wired.chat.user_join"  {
                        
            guard let chatID = message.uint32(forField: "wired.chat.id") else { return }
            
            if chatID == self.chatID {
                self.chatController?.usersController.userJoin(message: message)
                        
                self.usersTableView.reloadData()
            }
        }
        else if  message.name == "wired.chat.user_status" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else { return }
            
            if chatID == self.chatID {
                self.chatController?.usersController.updateStatus(message: message)
                
                self.usersTableView.reloadData()
            }
        }
        else if  message.name == "wired.chat.user_icon" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else { return }
            
            if chatID == self.chatID {
                self.chatController?.usersController.updateStatus(message: message)
                
                self.usersTableView.reloadData()
            }
        }
        else if message.name == "wired.chat.user_leave" {
             //self.chatController?.usersController.userLeave(message: message)
             self.usersTableView.reloadData()
        }
        else if message.name == "wired.account.privileges" {

        }
        else if message.name == "wired.chat.user_list.done" {
            self.usersTableView.reloadData()
        }
    }
    
    
    
    
    
    // MARK: NSValidatedUserInterfaceItem
    
    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let user = self.selectedItem() {
            self.selectedUser = user
            
            if item.action == #selector(showPrivateMessages(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(inviteToPrivateChat(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(getUserInfo(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(kickUser(_:)) {
                return connection.isConnected()
            }
            else if item.action == #selector(banUser(_:)) {
                return connection.isConnected()
            }
        }
        return false
    }
    
    
    
    
    // MARK: - Table View
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return self.chatController?.usersController.numberOfUsers() ?? 0
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: UserCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "UserCell"), owner: self) as? UserCellView
        
        if let uc = self.chatController?.usersController, let user = uc.user(at: row) {
            view?.userNick?.stringValue = user.nick
            view?.userNick?.textColor = NSColor.color(forEnum: user.color)
            view?.userStatus?.stringValue = user.status
            
            if let base64ImageString = user.icon?.base64EncodedData() {
                if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                    view?.userIcon?.image = NSImage(data: data)
                }
            }
                        
            if user.idle == true {
                view?.alphaValue = 0.5
            } else {
                view?.alphaValue = 1.0
            }
        }

        return view
    }
    
    
    
    // MARK: - Privates
    
    private func selectedItem() -> UserInfo? {
        var selectedIndex = usersTableView.clickedRow
                
        if selectedIndex == -1 {
            selectedIndex = usersTableView.selectedRow
        }
        
        if selectedIndex == -1 {
            return nil
        }
                
        return self.chatController?.usersController.user(at: selectedIndex)
    }
}
