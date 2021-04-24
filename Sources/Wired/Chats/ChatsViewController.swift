//
//  ChatsViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 11/04/2021.
//  Copyright © 2021 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

extension Notification.Name {
    static let selectedChatDidChange = Notification.Name("selectedChatDidChange")
    static let userJoinChat = Notification.Name("userJoinChat")
    static let userLeaveChat = Notification.Name("userLeaveChat")
    static let userCreatePrivateChat = Notification.Name("userCreatePrivateChat")
    static let userPrivateChatCreated = Notification.Name("userPrivateChatCreated")
    static let chatUnreadsChanged = Notification.Name("chatUnreadsChanged")
}

class ChatsViewController: ConnectionViewController, NSOutlineViewDelegate, NSOutlineViewDataSource, ConnectionDelegate, NSUserInterfaceValidations {
    @IBOutlet weak var chatsOutlineView: NSOutlineView!

    public var chatsController:ChatsController?
    public var publicChatController:ChatController?
    public var chatControllers:[UInt32:ChatController] = [:]
    public var selectedChatController:ChatController?
    public var currentInvitationPrivateChatController:PrivateChatController?
    
    struct ResourceIdentifiers {
        static let publicChats  = NSLocalizedString("PUBLIC CHATS", comment: "")
        static let privateChats = NSLocalizedString("PRIVATE CHATS", comment: "")
    }
    
    let categories = [
        ResourceIdentifiers.publicChats,
        ResourceIdentifiers.privateChats,
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        
        chatsOutlineView.target = self
        chatsOutlineView.doubleAction = #selector(doubleClickChat)
        
        NotificationCenter.default.addObserver(self, selector:#selector(linkConnectionDidClose(notification:)), name: .linkConnectionDidClose, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(linkConnectionDidReconnect(_:)), name: .linkConnectionDidReconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userCreatePrivateChat(_:)), name: .userCreatePrivateChat, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userPrivateChatCreated(_:)), name: .userPrivateChatCreated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(chatUnreadsChanged(_:)), name: .chatUnreadsChanged, object: nil)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
                
        self.reloadDataRetainingSelection()
        self.chatsOutlineView.expandItem(nil, expandChildren: true)
    }
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                self.connection.addDelegate(self)
                
                if let tabViewController = self.chatsTabViewController() {
                    if let chatPlaceholderViewController = tabViewController.tabViewItems[0].viewController as? ChatPlaceholderViewController {
                        chatPlaceholderViewController.connection = c
                    }
                }

                self.chatsController = ConnectionsController.shared.chatsController(forConnection: self.connection)
                self.chatsController?.getChats()
            }
        }
    }
    
    
    // MARK: - Notification
    @objc private func linkConnectionDidClose(notification: Notification) -> Void {
        if let c = notification.object as? Connection, c == self.connection {
            self.reloadDataRetainingSelection()
            
            self.updateChatController()
        }
    }
    
    @objc func linkConnectionDidReconnect(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            self.chatsController?.getChats()
        }
    }
    
    @objc func userCreatePrivateChat(_ n: Notification) {
        if let privateChatController = n.object as? PrivateChatController, privateChatController.connection == self.connection {
            self.currentInvitationPrivateChatController = privateChatController
            self.currentInvitationPrivateChatController?.createChat()
        }
    }
    
    @objc func userPrivateChatCreated(_ n: Notification) {
        if let privateChatController = n.object as? PrivateChatController, privateChatController.connection == self.connection {
            // TODO: understand why this condition does not work
            // related to `wired.chat.invitation` message where is set currentInvitationPrivateChatController
            //if privateChatController == self.currentInvitationPrivateChatController {
                self.chatsController?.addPrivateChat(privateChatController.chat! as! PrivateChat)
                self.reloadDataRetainingSelection()
                
                self.chatControllers[privateChatController.chat!.chatID] = privateChatController
                
                self.selectedChatController = privateChatController
                self.selectChatItem(item: privateChatController.chat!)
            
                self.joinChatController(chatController: privateChatController)
                
                self.currentInvitationPrivateChatController = nil
            //}
        }
    }
    
    @objc func chatUnreadsChanged(_ n: Notification) {
        if let chatController = n.object as? ChatController, chatController.connection == self.connection {
            //let indexSet = IndexSet(integer: chatsOutlineView.row(forItem: chatController.chat))
            chatsOutlineView.reloadItem(chatController.chat)
            
        }
    }
    
    
    
    // MARK: -
    @objc private func doubleClickChat() {
        self.joinChat(self)
    }
    
    
    @IBAction func joinChat(_ sender: Any) {
        if let clickedItem = self.selectedItem() {
            if let chat = clickedItem as? PublicChat {
                var chatController = chatControllers[chat.chatID]

                if chatController == nil {
                    chatController = ChatController(self.connection, chat: chat)
                    
                    chatControllers[chat.chatID] = chatController
                    
                    if chat.chatID == 1 {
                        self.publicChatController = chatController
                    }
                    
                    self.selectedChatController = chatController
                                        
                    self.joinChatController(chatController: chatController!)
                }
            }
        }
    }
    
    
    private func joinChatController(chatController: ChatController) {
        chatController.join()
                
        self.updateChatController()
    }
    
    
    @IBAction func leaveChat(_ sender: Any) {
        if let clickedItem = chatsOutlineView.item(atRow: chatsOutlineView.clickedRow) {
            if let chat = clickedItem as? Chat {
                if chat.chatID != 1 { // you cannot leave the main public chat
                    if let chatController = chatControllers[chat.chatID] {
                        chatControllers[chat.chatID] = nil

                        chatController.leave()
                        
                        self.updateChatController()
                        
                        guard let tabViewController = self.chatsTabViewController() else {
                            return
                        }
                        
                        tabViewController.removeTabViewItem(tabViewController.tabViewItem(for: self.selectedChatController!.chatSplitViewController)!)
                        
                        self.selectedChatController = self.publicChatController
                                                
                        chatController.chatViewController.chatController = nil
                        chatController.usersViewController.chatController = nil
                        
                        self.connection.removeDelegate(chatController.chatViewController)
                        self.connection.removeDelegate(chatController.usersViewController)
                        
                        NotificationCenter.default.post(name: .userLeaveChat, object: chatController)
                        
                        if let privateChat = chat as? PrivateChat {
                            self.chatsController?.removePrivateChat(privateChat)
                            self.reloadDataRetainingSelection()

                            self.selectPublicChat()
                            tabViewController.selectedTabViewItemIndex = 1
                            
                            self.selectedChatController = self.publicChatController
                            self.updateChatController()
                        } else {
                            tabViewController.selectedTabViewItemIndex = 0
                        }
                    }
                }
            }
        }
    }
    
    
    
    // MARK: -
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        let selectedRowIndexes = chatsOutlineView.selectedRowIndexes
        
        if message.name == "wired.chat.chat_list" || message.name == "wired.chat.public_chat_created" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else { return }
            
            if chatsController?.chats[chatID] == nil {
                let chat = PublicChat(message: message)
                
                // prepare public chat controller
                if chat.chatID == 1 && self.chatControllers[chatID] == nil {
                    self.publicChatController = ChatController(self.connection, chat: chat)
                    self.chatControllers[chatID] = self.publicChatController
                    self.selectedChatController = self.publicChatController
                }
                
                self.chatsController?.addPublicChat(chat)
            }
            
            self.reloadDataRetainingSelection()
        }
        else if message.name == "wired.chat.chat_list.done" {
            if selectedRowIndexes.count > 0 {
                chatsOutlineView.selectRowIndexes(selectedRowIndexes, byExtendingSelection: false)
            } else {
                self.selectPublicChat()
            }
            
            for (_, controller) in self.chatControllers {
                self.joinChatController(chatController: controller)
            }
            
            self.reloadDataRetainingSelection()
        }
        else if message.name == "wired.chat.invitation" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else { return }
            guard let userID = message.uint32(forField: "wired.user.id") else { return }
            guard let user = publicChatController?.usersController.user(forID: userID) else { return }
            
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Private Chat Invitation", comment: "")
            alert.informativeText = NSLocalizedString("\(user.nick!) sent you a chat invitation.", comment: "")
            alert.alertStyle = .informational
            
            alert.addButton(withTitle: NSLocalizedString("Accept", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Decline", comment: ""))

            if alert.runModal() == .alertFirstButtonReturn {
                let c = PrivateChatController(self.connection, message: message, creator: user)
                self.currentInvitationPrivateChatController = c
                
            } else {
                
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    
    
    // MARK: NSValidatedUserInterfaceItem
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if self.connection != nil && self.connection.isConnected() {
            if let publicChat = self.selectedItem() as? PublicChat {
                if item.action == #selector(joinChat(_:)) {
                    return self.chatControllers[publicChat.chatID] == nil
                }
                else if item.action == #selector(leaveChat(_:)) {
                    return self.chatControllers[publicChat.chatID] != nil && publicChat.chatID != 1
                }
            }
            else if let privateChat = self.selectedItem() as? PrivateChat {
                if item.action == #selector(joinChat(_:)) {
                    return false
                }
                else if item.action == #selector(leaveChat(_:)) {
                    return self.chatControllers[privateChat.chatID] != nil
                }
            }
        }
           
        return false
    }
    
    
    
    
    
    // MARK: OutlineView DataSource & Delegate -
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let c = item as? String {
            if c == ResourceIdentifiers.publicChats {
                return self.chatsController?.publicChats.count ?? 0
            }
            else if c == ResourceIdentifiers.privateChats {
                return self.chatsController?.privateChats.count ?? 0
            }
        }

        return self.categories.count
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let c = item as? String {
            if c == ResourceIdentifiers.publicChats {
                return self.chatsController!.publicChats[index]
            }
            else if c == ResourceIdentifiers.privateChats {
                return self.chatsController!.privateChats[index]
            }
        }

        return self.categories[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let s = item as? String, self.categories.contains(s) {
            return true
        }
        
        return false
    }


    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let _ = item as? String {
            return false
        }
        return true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let _ = item as? String {
            return true
        }
        return false
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?

        
        if let resource = item as? String {
            view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "HeaderCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = resource
        }
        else if let publicChat = item as? PublicChat {
            if let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatCellView"), owner: self) as? ChatCellView {
                cell.nameTextField.stringValue = publicChat.name
                
                if publicChat.unreads > 0 {
                    cell.unreadsTextField.stringValue = "\(publicChat.unreads)"
                    cell.unreadsTextField.isHidden = false
                } else {
                    cell.unreadsTextField.stringValue = ""
                    cell.unreadsTextField.isHidden = true
                }
                
                view = cell
            }
        }
        else if let privateChat = item as? PrivateChat {
            if let cell = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatCellView"), owner: self) as? ChatCellView {

                if let chatController = self.chatControllers[privateChat.chatID] as? PrivateChatController {
                    if chatController.creatorUser?.userID == self.connection.userInfo?.userID {
                        cell.nameTextField?.stringValue = "\(chatController.inviteUser!.nick!)"
                    }
                    else {
                        cell.nameTextField?.stringValue = "\(chatController.creatorUser!.nick!)"
                    }

                    if chatController.usersController.numberOfUsers() > 2 {
                        if let string = view?.textField?.stringValue {
                            view?.textField?.stringValue = string.appending(", and \(chatController.usersController.numberOfUsers() - 2) more")
                        }
                    }
                    
                    if privateChat.unreads > 0 {
                        cell.unreadsTextField.stringValue = "\(privateChat.unreads)"
                        cell.unreadsTextField.isHidden = false
                    } else {
                        cell.unreadsTextField.stringValue = ""
                        cell.unreadsTextField.isHidden = true
                    }
                }
            
                view = cell
            }
        }
        
        return view
    }
    
    
    
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return 24
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        self.selectedChatController = nil
        
        if let item = self.selectedItem() {
            if let publicChat = item as? Chat {
                let chatController = self.chatControllers[publicChat.chatID]
                
                self.selectedChatController = chatController
            }
        }
        
        self.updateChatController()
    }
    
    
    
    // MARK: -
    private func updateChatController() {
        if self.selectedChatController != nil {
            guard let splitViewController = self.parent as? NSSplitViewController else {
                return
            }
                        
            guard let tabViewController = splitViewController.splitViewItems.last?.viewController as? NSTabViewController else {
                return
            }
            
            var currentTabViewItem = tabViewController.tabViewItem(for: self.selectedChatController!.chatSplitViewController)
                        
            if currentTabViewItem == nil {
                currentTabViewItem = NSTabViewItem(viewController: self.selectedChatController!.chatSplitViewController)
                tabViewController.addTabViewItem(currentTabViewItem!)
            }
            
            if let index = tabViewController.tabViewItems.index(of: currentTabViewItem!) {
                tabViewController.selectedTabViewItemIndex = index
            }

            self.selectedChatController!.chatSplitViewController.addSplitViewItem(NSSplitViewItem(viewController: self.selectedChatController!.chatViewController))
            self.selectedChatController!.chatSplitViewController.addSplitViewItem(NSSplitViewItem(viewController: self.selectedChatController!.usersViewController))
            
            NotificationCenter.default.post(name: .selectedChatDidChange, object: self.selectedChatController)
        } else {
            guard let tabViewController = self.chatsTabViewController() else {
                return
            }
            
            tabViewController.selectedTabViewItemIndex = 0
            
            NotificationCenter.default.post(name: .selectedChatDidChange, object: nil)
        }
    }
    
    
    public func selectedItem() -> Any? {
        var selectedIndex = chatsOutlineView.clickedRow
                
        if selectedIndex == -1 {
            selectedIndex = chatsOutlineView.selectedRow
        }
        
        if selectedIndex == -1 {
            return nil
        }
                
        return chatsOutlineView.item(atRow: selectedIndex)
    }
    
    
    private func reloadDataRetainingSelection() {
        let index = chatsOutlineView.selectedRowIndexes
        
        chatsOutlineView.reloadData()
        
        chatsOutlineView.selectRowIndexes(index, byExtendingSelection: true)
        chatsOutlineView.becomeFirstResponder()
    }
    
    
    private func chatsTabViewController() -> NSTabViewController? {
        guard let splitViewController = self.parent as? NSSplitViewController else {
            return nil
        }
            
        return splitViewController.splitViewItems.last?.viewController as? NSTabViewController
    }
    
    
    private func selectPublicChat() {
        if let item = chatsController?.publicChats.first {
            self.selectChatItem(item: item)
        }
    }
    
    
    private func selectChatItem(item:Chat) {
        chatsOutlineView.selectRowIndexes(IndexSet(integer: chatsOutlineView.row(forItem: item)), byExtendingSelection: false)
    }
}
