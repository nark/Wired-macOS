//
//  ChatController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift


public class ChatViewController: ConnectionViewController, ConnectionDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet var chatInput: NSTextField!
    @IBOutlet weak var sendButton: NSButton!
    @IBOutlet weak var messagesTableView: NSTableView!
    
    public var chatID:UInt32 = 0
    public var chatController:ChatController?

    var textDidEndEditingTimer:Timer!
    
    // MARK: - NSViewController
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.chatInput.delegate = self
        self.messagesTableView.dataSource = self
        self.messagesTableView.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(linkConnectionDidClose(_:)), name: .linkConnectionDidClose, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(linkConnectionDidReconnect(_:)), name: .linkConnectionDidReconnect, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(userJoinChat(_:)), name: .userJoinChat, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(selectedChatDidChange(_:)), name: .selectedChatDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(controlTextDidChange(_:)), name: NSTextView.didChangeSelectionNotification, object: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserNick", options: NSKeyValueObservingOptions.new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserStatus", options: NSKeyValueObservingOptions.new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserIcon", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        UserDefaults.standard.removeObserver(self, forKeyPath: "WSUserNick")
        UserDefaults.standard.removeObserver(self, forKeyPath: "WSUserStatus")
        UserDefaults.standard.removeObserver(self, forKeyPath: "WSUserIcon")
    }
    
    
    public override func viewDidAppear() {
        super.viewDidAppear()

        if let c = self.connection {
            chatInput.becomeFirstResponder()
            
            if let unreads = self.chatController?.chat?.unreads, unreads > 0 {
                AppDelegate.decrementChatUnread(withValue: unreads, forConnection: c)
            }
            
            self.chatController?.chat?.unreads = 0
            NotificationCenter.default.post(name: .chatUnreadsChanged, object: self.chatController)            
        }
    }
    
    
    public override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                                
                c.addDelegate(self)
            }
        }
    }
    
    
    
        
    // MARK: - Observers
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //print("observeValue: \(keyPath) -> \(change?[NSKeyValueChangeKey.newKey])")
        if keyPath == "WSUserNick" {
            if let nick = change?[NSKeyValueChangeKey.newKey] as? String {
                if let m = self.setNickMessage(nick) {
                  _ = self.connection.send(message: m)
                }
            }
        }
        else if keyPath == "WSUserStatus" {
            if let status = change?[NSKeyValueChangeKey.newKey] as? String {
                if let m = self.setStatusMessage(status) {
                  _ = self.connection.send(message: m)
                }
            }
        }
        else if keyPath == "WSUserIcon" {
            if let icon = change?[NSKeyValueChangeKey.newKey] as? Data {
                // NOTE : this one was a pain in the a**
                if let image = try! NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: icon) {
                    let b64String = image.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)!.base64EncodedString()
                    if let b64Data = Data(base64Encoded: b64String, options: .ignoreUnknownCharacters) {
                        if let m = self.setIconMessage(b64Data) {
                            _ = self.connection.send(message: m)
                        }
                    }
                }
            }
        }
    }

    
    
    
    
    
    // MARK: - Notification
    @objc func selectedChatDidChange(_ n:Notification) {
        if let chatController = n.object as? ChatController {
            if chatController.chat?.chatID == self.chatID {
                if self.chatController == nil {
                    self.chatController = chatController
                }
                
                self.chatInput.becomeFirstResponder()
            }
        } else {
            
            self.chatInput.becomeFirstResponder()
        }
    }
    
    
    @objc func userJoinChat(_ n:Notification) {
        if let chatController = n.object as? ChatController {
            if chatController.chat?.chatID == self.chatID {
                if self.chatController == nil {
                    self.chatController = chatController
                }

                self.chatInput.becomeFirstResponder()
            }
        }
    }
    
    
    @objc func userLeaveChat(_ n:Notification) {
        if let chatController = n.object as? ChatController {
            if chatController.chat?.chatID == self.chatID {
                self.chatController = nil
                //self.messagesTableView.reloadData()
                
                if let c = self.connection {
                    c.removeDelegate(self)
                }
            }
        }
    }

        

    @objc public func controlTextDidChange(_ n: Notification) {
        if (n.object as? NSTextField) == self.chatInput {
            self.chatInputDidEndEditing()
        }
    }
    
    @objc func linkConnectionDidClose(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            self.chatInput.isEditable = false
            
            let disconnected = NSLocalizedString("Disconnected...", comment: "")
            self.chatInput.placeholderString = disconnected
            
            let disconnectedfrom = NSLocalizedString("Disconnected from", comment: "")
            self.addMessage("<< " + disconnectedfrom + " " + "\(self.connection.serverInfo.serverName!) >>")
            
            if UserDefaults.standard.bool(forKey: "WSAutoReconnect") {
                if !self.connection.connectionWindowController!.manualyDisconnected {
                    let autoreconnecting = NSLocalizedString("Auto-reconnecting...", comment: "")
                    self.addMessage("<< " + autoreconnecting + " ⏱ >>")
                }
            }
        }
    }
    
    @objc func linkConnectionDidReconnect(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            self.chatInput.isEditable = true
            self.chatInput.placeholderString = "Type message here"
            var reconnectedto = NSLocalizedString("Auto-reconnected to", comment: "")
            
            if self.connection.connectionWindowController!.manualyReconnected {
                reconnectedto = NSLocalizedString("Reconnected to", comment: "")
                
                self.connection.connectionWindowController!.manualyReconnected = false
            }
            
            self.addMessage("<< " + reconnectedto + " \(self.connection.serverInfo.serverName!) >>")
        }
    }
    
    
    
    
    
    
    // MARK: - IBActions
    
    @IBAction func showEmojis(_ sender: Any) {
        NSApp.orderFrontCharacterPalette(self.chatInput)
    }
    
    
    
    @IBAction func chatAction(_ sender: Any) {
        if self.connection != nil && self.connection.isConnected() {
            if let textField = sender as? NSTextField, textField.stringValue.count > 0 {
                var message:P7Message? = nil
                
                if textField.stringValue.starts(with: "/") {
                    message = self.chatCommand(textField.stringValue)
                }
                else {
                    self.substituteEmojis()
                    
                    message = P7Message(withName: "wired.chat.send_say", spec: self.connection.spec)
                    
                    message!.addParameter(field: "wired.chat.id", value: self.chatController?.chat?.chatID)
                    message!.addParameter(field: "wired.chat.say", value: textField.stringValue)
                }
                
                if self.connection.isConnected() {
                    if let m = message, self.connection.send(message: m) {
                        textField.stringValue = ""
                    }
                }
            }
        }
    }
    
    

    
    
    
    
    // MARK: - Connection Delegate
    
    public func connectionDidConnect(connection: Connection) {
        self.chatInput.isEditable = true
        let disconnected = NSLocalizedString("Disconnected...", comment: "")
        self.chatInput.placeholderString = disconnected
    }
    
    
    public func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    
    public func connectionDisconnected(connection: Connection, error: Error?) {

    }
    
    
    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        if let specError = spec.error(forMessage: message), let message = specError.name {
            let alert = NSAlert()
            let wiredalert = NSLocalizedString("Wired Alert", comment: "")
            alert.messageText = wiredalert
            let wirederror = NSLocalizedString("Wired Error:", comment: "")
            alert.informativeText = wirederror + " \(message)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    
    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if  message.name == "wired.chat.say" ||
            message.name == "wired.chat.me" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else {
                return
            }
            
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            var string = message.string(forField: "wired.chat.say")
            
            if string == nil {
                string = message.string(forField: "wired.chat.me")
            }
            
            if string == nil {
                return
            }
            
            if chatID == self.chatController?.chat?.chatID {
                if let userInfo = self.chatController?.usersController.user(forID: userID) {
                    self.addMessage(message, sent: userID == self.connection.userID)

                    // add unread
                    if userInfo.userID != self.connection.userID {
                        if self.chatInput.currentEditor() == nil || NSApp.isActive == false || self.view.window?.isKeyWindow == false {
                            self.chatController?.chat?.unreads += 1
                            NotificationCenter.default.post(name: .chatUnreadsChanged, object: self.chatController)
                            
                            AppDelegate.incrementChatUnread(forConnection: connection)
                            AppDelegate.notify(identifier: "chatMessage", title: NSLocalizedString("New Chat Message", comment: ""), subtitle: userInfo.nick!, text: string!, connection: connection)
                        }
                    }
                }
            }
        }
        else if message.name == "wired.chat.topic" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else {
                return
            }
            
            if chatID == self.chatController?.chat?.chatID {
                self.addMessage(message, sent: false)
            }
        }
        else if  message.name == "wired.chat.user_list" {

        }
        else if  message.name == "wired.chat.user_status" {

        }
        else if message.name == "wired.chat.user_join" {
            guard let chatID = message.uint32(forField: "wired.chat.id") else {
                return
            }
            
            if chatID == self.chatController?.chat?.chatID {
                let userInfo = UserInfo(message: message)
                
                self.addMessage(message)
                
                NotificationCenter.default.post(name: NSNotification.Name("UserJoinedPublicChat"), object: [self.connection, userInfo])
            }
        }
        else if message.name == "wired.chat.user_leave" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }

            if let uc = self.chatController?.usersController {
                if let u = uc.user(forID: userID) {
                    message.addParameter(field: "wired.user.nick", value: u.nick!)

                    self.addMessage(message)

                    uc.userLeave(message: message)

                    NotificationCenter.default.post(name: NSNotification.Name("UserLeftPublicChat"), object: self.connection)
                }
            }
        }
        
    }
    
    
    
    
    
    // MARK: - NSTableView Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return self.numberOfMessages()
    }
    
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: MessageCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "EventCell"), owner: self) as? MessageCellView
        
        if let message = self.chatController?.messages[row] as? P7Message {
            
            if message.name == "wired.chat.say" || message.name == "wired.chat.me" {
                let sentOrReceived = self.chatController!.receivedMessages.contains(message
                    ) ? "ReceivedMessageCell" : "SentMessageCell"
                                        
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: sentOrReceived), owner: self) as? MessageCellView
                
                if let userID = message.uint32(forField: "wired.user.id") {
                    if let userInfo = self.chatController?.usersController.user(forID: userID) {
                        if let string = message.string(forField: "wired.chat.say") {
                            // we received HTML image
                            if string.starts(with: "<img src='data:image/png;base64,") {
                                let base64String = String(string.dropFirst(32).dropLast(3))
                                if let data = Data(base64Encoded: base64String, options: Data.Base64DecodingOptions.ignoreUnknownCharacters) {
                                    let textAttachment = NSTextAttachment()
                                    textAttachment.image = NSImage(data: data)
                                    textAttachment.setImageHeight(height: 350)
                                    view?.textField?.attributedStringValue =  NSAttributedString(attachment: textAttachment)
                                }
                                
                            } else {
                                if let attrString = string.substituteURL() {
                                    view?.textField?.attributedStringValue = attrString
                                }
                            }
                        }
                        
                        if let string = message.string(forField: "wired.chat.me") {
                            view?.textField?.stringValue = "* \(userInfo.nick!) \(string)"
                        }
                        
                        if let base64ImageString = userInfo.icon?.base64EncodedData() {
                            if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                                view?.imageView?.image = NSImage(data: data)
                            }
                        }
                        
                        view?.nickLabel.stringValue = userInfo.nick
                    }
                }
                
            }
            else if message.name == "wired.chat.topic" {
                if  let userNick = message.string(forField: "wired.user.nick"),
                    let chatTopic = message.string(forField: "wired.chat.topic.topic"),
                    let chatTime = message.date(forField: "wired.chat.topic.time") {
                    let topicstring = NSLocalizedString("Topic:", comment: "")
                    let bystring = NSLocalizedString("by", comment: "")
                    
                    if let time = AppDelegate.dateTimeFormatter.string(for: chatTime) {
                        view?.textField?.stringValue = "<< " + topicstring + " \(chatTopic) " + bystring + " \(userNick) - \(time) >>"
                    }
                } else {
                    view?.textField?.stringValue = "<< No topic yet >>"
                }
                
            }
            else if message.name == "wired.chat.user_join" {
                let userInfo = UserInfo(message: message)
                let joinedthechat = NSLocalizedString("joined the chat", comment: "")
                view?.textField?.stringValue = "<< \(userInfo.nick!) " + joinedthechat + " >>"
            }
            else if message.name == "wired.chat.user_leave" {
                if let nick = message.string(forField: "wired.user.nick") {
                    let leftthechat = NSLocalizedString("left the chat", comment: "")
                    view?.textField?.stringValue = "<< \(nick) " + leftthechat + " >>"
                }
            }
        } else if let string = self.chatController?.messages[row] as? String {
            view?.textField?.stringValue = string
        }
        
        view?.textField?.isEditable = false
        view?.textField?.isSelectable = true
        view?.textField?.allowsEditingTextAttributes = true
        
        return view
    }
    
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return UnselectedTableRowView()
    }
    
    
    public func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        return true
    }
    
    
    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 80 // minimum row size
    }
    

    
    
    
    
    // MARK: - Privates
    private func setNickMessage(_ nick:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_nick", spec: self.connection.spec)
        message.addParameter(field: "wired.user.nick", value: nick)

        if UserDefaults.standard.string(forKey: "WSUserNick") == nick {
            UserDefaults.standard.set(nick, forKey: "WSUserNick")
        }

        return message
    }
    
    
    private func setStatusMessage(_ status:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_status", spec: self.connection.spec)
        message.addParameter(field: "wired.user.status", value: status)

        if UserDefaults.standard.string(forKey: "WSUserStatus") == status {
            UserDefaults.standard.set(status, forKey: "WSUserStatus")
        }


        return message
    }
    
    
    private func setIconMessage(_ icon:Data) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_icon", spec: self.connection.spec)
        
        message.addParameter(field: "wired.user.icon", value: icon)
        
        return message
    }
    
    
    private func chatCommand(_ command: String) -> P7Message? {
        let comps = command.split(separator: " ")
        
        if comps[0] == "/me" {
            let message = P7Message(withName: "wired.chat.send_me", spec: self.connection.spec)
            let value = command.deletingPrefix(comps[0]+" ")
            
            message.addParameter(field: "wired.chat.id", value: self.chatController?.chat?.chatID)
            message.addParameter(field: "wired.chat.me", value: value)
            
            return message
        }
        
        else if comps[0] == "/nick" {
            let value = command.deletingPrefix(comps[0]+" ")
            
            UserDefaults.standard.set(value, forKey: "WSUserNick")
            
            return self.setNickMessage(value)
        }
            
        else if comps[0] == "/status" {
            let value = command.deletingPrefix(comps[0]+" ")
            
            UserDefaults.standard.set(value, forKey: "WSUserStatus")
            
            return self.setStatusMessage(value)
        }
        
        else if comps[0] == "/topic" {
            let message = P7Message(withName: "wired.chat.set_topic", spec: self.connection.spec)
            let value = command.deletingPrefix(comps[0]+" ")
            
            message.addParameter(field: "wired.chat.id", value: self.chatController?.chat?.chatID)
            message.addParameter(field: "wired.chat.topic.topic", value: value)
            
            return message
        }
        
        return nil
    }
    
    private func addMessage(_ message:Any, sent: Bool = false) {
        if let chatController = self.chatController {
            chatController.messages.append(message)

            if let m = message as? P7Message {
                if sent {
                    chatController.sentMessages.append(m)
                } else {
                    chatController.receivedMessages.append(m)
                }
            }

//            self.messagesTableView.beginUpdates()
//            self.messagesTableView.insertRows(at: [self.numberOfMessages() - 1], withAnimation: NSTableView.AnimationOptions.effectFade)
//            self.messagesTableView.endUpdates()
            self.messagesTableView.noteNumberOfRowsChanged()

            self.messagesTableView.scrollToBottom()
        }
    }
    
    
    private func numberOfMessages() -> Int {
        return self.chatController?.messages.count ?? 0
    }
    
    
    private func chatInputDidEndEditing() {
        if self.chatInput.stringValue.count >= 2 {
            if textDidEndEditingTimer != nil {
                textDidEndEditingTimer.invalidate()
                textDidEndEditingTimer = nil
            }
            
            if UserDefaults.standard.bool(forKey: "WSEmojiSubstitutionsEnabled") {
                textDidEndEditingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { (timer) in
                    self.substituteEmojis()
                }
            }

        }
    }
    
    
    private func substituteEmojis() {
        if UserDefaults.standard.bool(forKey: "WSEmojiSubstitutionsEnabled") {
            if let lastWord = self.chatInput.stringValue.split(separator: " ").last {
                if let emoji = AppDelegate.emoji(forKey: String(lastWord)) {
                    let string = (self.chatInput.stringValue as NSString).replacingOccurrences(of: String(lastWord), with: emoji)
                    self.chatInput.stringValue = string
                }
            }
        }
    }
}
