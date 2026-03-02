//
//  BoardsController.swift
//  Wired
//
//  Created by Rafael Warnault on 27/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import WiredSwift

extension Notification.Name {
    static let didStartLoadingBoards    = Notification.Name("didStartLoadingBoards")
    static let didLoadBoards            = Notification.Name("didLoadBoards")
    static let didLoadThreads           = Notification.Name("didLoadThreads")
    static let didLoadPosts             = Notification.Name("didLoadPosts")

    // Live-update notifications (server-initiated)
    static let boardAdded               = Notification.Name("boardAdded")
    static let boardRenamed             = Notification.Name("boardRenamed")
    static let boardMoved               = Notification.Name("boardMoved")
    static let boardDeleted             = Notification.Name("boardDeleted")
    static let boardInfoChanged         = Notification.Name("boardInfoChanged")
    static let threadAdded              = Notification.Name("threadAdded")
    static let threadChanged            = Notification.Name("threadChanged")
    static let threadMoved              = Notification.Name("threadMoved")
    static let threadDeleted            = Notification.Name("threadDeleted")
}


public class BoardsController: ConnectionObject, ConnectionDelegate {
    public private(set) var boards: [Board] = []
    public private(set) var boardsByPath: [String: Board] = [:]

    public let queue = DispatchQueue(label: "fr.read-write.Wired.BoardsQueue")

    var loadingThread: BoardThread? = nil


    public override init(_ connection: ServerConnection) {
        super.init(connection)
        self.connection.addDelegate(self)
    }


    // MARK: - Read operations

    public func loadBoards() {
        let message = P7Message(withName: "wired.board.get_boards", spec: self.connection.spec)

        queue.async(flags: .barrier) {
            self.boards = []
            self.boardsByPath = [:]
        }

        NotificationCenter.default.post(name: .didStartLoadingBoards, object: connection)
        _ = self.connection.send(message: message)
    }

    public func loadThreads(forBoard board: Board) {
        let message = P7Message(withName: "wired.board.get_threads", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board", value: board.path)

        queue.async(flags: .barrier) {
            board.threads = []
        }

        NotificationCenter.default.post(name: .didStartLoadingBoards, object: connection)
        _ = self.connection.send(message: message)
    }

    public func loadPosts(forThread thread: BoardThread) {
        let message = P7Message(withName: "wired.board.get_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread", value: thread.uuid)

        queue.async(flags: .barrier) {
            thread.posts       = []
            self.loadingThread = thread
        }

        NotificationCenter.default.post(name: .didStartLoadingBoards, object: connection)
        _ = self.connection.send(message: message)
    }

    public func subscribeBoards() {
        let message = P7Message(withName: "wired.board.subscribe_boards", spec: self.connection.spec)
        _ = self.connection.send(message: message)
    }

    public func unsubscribeBoards() {
        let message = P7Message(withName: "wired.board.unsubscribe_boards", spec: self.connection.spec)
        _ = self.connection.send(message: message)
    }

    public func getBoardInfo(forBoard board: Board) {
        let message = P7Message(withName: "wired.board.get_board_info", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board", value: board.path)
        _ = self.connection.send(message: message)
    }


    // MARK: - Board write operations

    public func addBoard(path: String,
                         owner: String,
                         group: String,
                         ownerRead: Bool,
                         ownerWrite: Bool,
                         groupRead: Bool,
                         groupWrite: Bool,
                         everyoneRead: Bool,
                         everyoneWrite: Bool) {
        let message = P7Message(withName: "wired.board.add_board", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board",          value: path)
        message.addParameter(field: "wired.board.owner",          value: owner)
        message.addParameter(field: "wired.board.owner.read",     value: ownerRead)
        message.addParameter(field: "wired.board.owner.write",    value: ownerWrite)
        message.addParameter(field: "wired.board.group",          value: group)
        message.addParameter(field: "wired.board.group.read",     value: groupRead)
        message.addParameter(field: "wired.board.group.write",    value: groupWrite)
        message.addParameter(field: "wired.board.everyone.read",  value: everyoneRead)
        message.addParameter(field: "wired.board.everyone.write", value: everyoneWrite)
        _ = self.connection.send(message: message)
    }

    public func deleteBoard(path: String) {
        let message = P7Message(withName: "wired.board.delete_board", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board", value: path)
        _ = self.connection.send(message: message)
    }

    public func renameBoard(path: String, newPath: String) {
        let message = P7Message(withName: "wired.board.rename_board", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board",     value: path)
        message.addParameter(field: "wired.board.new_board", value: newPath)
        _ = self.connection.send(message: message)
    }

    public func moveBoard(path: String, newPath: String) {
        let message = P7Message(withName: "wired.board.move_board", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board",     value: path)
        message.addParameter(field: "wired.board.new_board", value: newPath)
        _ = self.connection.send(message: message)
    }

    public func setBoardInfo(path: String,
                             owner: String,
                             group: String,
                             ownerRead: Bool,
                             ownerWrite: Bool,
                             groupRead: Bool,
                             groupWrite: Bool,
                             everyoneRead: Bool,
                             everyoneWrite: Bool) {
        let message = P7Message(withName: "wired.board.set_board_info", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board",          value: path)
        message.addParameter(field: "wired.board.owner",          value: owner)
        message.addParameter(field: "wired.board.owner.read",     value: ownerRead)
        message.addParameter(field: "wired.board.owner.write",    value: ownerWrite)
        message.addParameter(field: "wired.board.group",          value: group)
        message.addParameter(field: "wired.board.group.read",     value: groupRead)
        message.addParameter(field: "wired.board.group.write",    value: groupWrite)
        message.addParameter(field: "wired.board.everyone.read",  value: everyoneRead)
        message.addParameter(field: "wired.board.everyone.write", value: everyoneWrite)
        _ = self.connection.send(message: message)
    }


    // MARK: - Thread write operations

    public func addThread(toBoard board: Board, subject: String, text: String) {
        let message = P7Message(withName: "wired.board.add_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.board",   value: board.path)
        message.addParameter(field: "wired.board.subject", value: subject)
        message.addParameter(field: "wired.board.text",    value: text)
        _ = self.connection.send(message: message)
    }

    public func editThread(uuid: String, subject: String, text: String) {
        let message = P7Message(withName: "wired.board.edit_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread",  value: uuid)
        message.addParameter(field: "wired.board.subject", value: subject)
        message.addParameter(field: "wired.board.text",    value: text)
        _ = self.connection.send(message: message)
    }

    public func moveThread(uuid: String, toBoard: Board) {
        let message = P7Message(withName: "wired.board.move_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread",    value: uuid)
        message.addParameter(field: "wired.board.new_board", value: toBoard.path)
        _ = self.connection.send(message: message)
    }

    public func deleteThread(uuid: String) {
        let message = P7Message(withName: "wired.board.delete_thread", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread", value: uuid)
        _ = self.connection.send(message: message)
    }


    // MARK: - Post write operations

    public func addPost(toThread thread: BoardThread, text: String) {
        let message = P7Message(withName: "wired.board.add_post", spec: self.connection.spec)
        message.addParameter(field: "wired.board.thread",  value: thread.uuid)
        message.addParameter(field: "wired.board.subject", value: thread.subject)
        message.addParameter(field: "wired.board.text",    value: text)
        _ = self.connection.send(message: message)
    }

    public func editPost(uuid: String, subject: String, text: String) {
        let message = P7Message(withName: "wired.board.edit_post", spec: self.connection.spec)
        message.addParameter(field: "wired.board.post",    value: uuid)
        message.addParameter(field: "wired.board.subject", value: subject)
        message.addParameter(field: "wired.board.text",    value: text)
        _ = self.connection.send(message: message)
    }

    public func deletePost(uuid: String) {
        let message = P7Message(withName: "wired.board.delete_post", spec: self.connection.spec)
        message.addParameter(field: "wired.board.post", value: uuid)
        _ = self.connection.send(message: message)
    }


    // MARK: - ConnectionDelegate

    public func connectionDidConnect(connection: Connection) {
        subscribeBoards()
    }

    public func connectionDidFailToConnect(connection: Connection, error: Error) { }

    public func connectionDisconnected(connection: Connection, error: Error?) { }

    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        guard connection === self.connection else { return }

        switch message.name {

        // MARK: Board list (initial load)
        case "wired.board.board_list":
            let board = Board(message, connection: connection as! ServerConnection)
            queue.async(flags: .barrier) {
                if !board.hasParent {
                    self.boards.append(board)
                } else if let parent = self.parentBoard(forPath: board.path) {
                    parent.boards.append(board)
                }
                self.boardsByPath[board.path] = board
            }

        case "wired.board.board_list.done":
            NotificationCenter.default.post(name: .didLoadBoards, object: connection)

        // MARK: Thread list
        case "wired.board.thread_list":
            if let path  = message.string(forField: "wired.board.board"),
               let board = self.boardsByPath[path] {
                queue.async(flags: .barrier) {
                    let thread = BoardThread(message, board: board,
                                            connection: connection as! ServerConnection)
                    board.addThread(thread)
                }
            }

        case "wired.board.thread_list.done":
            NotificationCenter.default.post(name: .didLoadThreads, object: connection)

        // MARK: Posts / thread content
        case "wired.board.thread", "wired.board.post_list":
            queue.async(flags: .barrier) {
                if let thread = self.loadingThread {
                    let post = Post(message, board: thread.board, thread: thread,
                                   connection: connection as! ServerConnection)
                    if thread.posts.isEmpty {
                        post.nick = thread.nick
                    }
                    thread.posts.append(post)
                }
            }

        case "wired.board.post_list.done":
            queue.async(flags: .barrier) { self.loadingThread = nil }
            NotificationCenter.default.post(name: .didLoadPosts, object: connection)

        // MARK: Board info
        case "wired.board.board_info":
            if let path  = message.string(forField: "wired.board.board"),
               let board = self.boardsByPath[path] {
                queue.async(flags: .barrier) { board.applyInfo(message) }
                NotificationCenter.default.post(name: .boardInfoChanged, object: connection,
                                                userInfo: ["board": board])
            }

        // MARK: Live board events
        case "wired.board.board_added":
            let board = Board(message, connection: connection as! ServerConnection)
            queue.async(flags: .barrier) {
                if !board.hasParent {
                    self.boards.append(board)
                } else if let parent = self.parentBoard(forPath: board.path) {
                    parent.boards.append(board)
                }
                self.boardsByPath[board.path] = board
            }
            NotificationCenter.default.post(name: .boardAdded, object: connection,
                                            userInfo: ["board": board])

        case "wired.board.board_renamed":
            if let oldPath = message.string(forField: "wired.board.board"),
               let newPath = message.string(forField: "wired.board.new_board"),
               let board   = self.boardsByPath[oldPath] {
                queue.async(flags: .barrier) {
                    self.boardsByPath.removeValue(forKey: oldPath)
                    board.rename(to: newPath)
                    self.boardsByPath[newPath] = board
                }
                NotificationCenter.default.post(name: .boardRenamed, object: connection,
                                                userInfo: ["board": board])
            }

        case "wired.board.board_moved":
            if let oldPath = message.string(forField: "wired.board.board"),
               let newPath = message.string(forField: "wired.board.new_board"),
               let board   = self.boardsByPath[oldPath] {
                queue.async(flags: .barrier) {
                    self.boardsByPath.removeValue(forKey: oldPath)
                    board.rename(to: newPath)
                    self.boardsByPath[newPath] = board
                }
                NotificationCenter.default.post(name: .boardMoved, object: connection,
                                                userInfo: ["board": board])
            }

        case "wired.board.board_deleted":
            if let path  = message.string(forField: "wired.board.board"),
               let board = self.boardsByPath[path] {
                queue.async(flags: .barrier) {
                    self.boardsByPath.removeValue(forKey: path)
                    self.boards.removeAll { $0 === board }
                    for parent in self.boards {
                        parent.boards.removeAll { $0 === board }
                    }
                }
                NotificationCenter.default.post(name: .boardDeleted, object: connection,
                                                userInfo: ["board": board])
            }

        case "wired.board.board_info_changed":
            if let path  = message.string(forField: "wired.board.board"),
               let board = self.boardsByPath[path] {
                queue.async(flags: .barrier) {
                    if let r = message.bool(forField: "wired.board.readable") { board.readable = r }
                    if let w = message.bool(forField: "wired.board.writable") { board.writable = w }
                }
                NotificationCenter.default.post(name: .boardInfoChanged, object: connection,
                                                userInfo: ["board": board])
            }

        // MARK: Live thread events
        case "wired.board.thread_added":
            if let boardPath = message.string(forField: "wired.board.board"),
               let board     = self.boardsByPath[boardPath] {
                queue.async(flags: .barrier) {
                    let thread = BoardThread(message, board: board,
                                            connection: connection as! ServerConnection)
                    board.addThread(thread)
                }
                NotificationCenter.default.post(name: .threadAdded, object: connection,
                                                userInfo: ["boardPath": boardPath])
            }

        case "wired.board.thread_changed":
            if let uuid = message.uuid(forField: "wired.board.thread") {
                queue.async(flags: .barrier) {
                    self.findThread(uuid: uuid)?.apply(message)
                }
                NotificationCenter.default.post(name: .threadChanged, object: connection,
                                                userInfo: ["threadUUID": uuid])
            }

        case "wired.board.thread_moved":
            if let uuid         = message.uuid(forField: "wired.board.thread"),
               let newBoardPath = message.string(forField: "wired.board.new_board"),
               let newBoard     = self.boardsByPath[newBoardPath] {
                queue.async(flags: .barrier) {
                    if let thread = self.findThread(uuid: uuid) {
                        thread.board.threads.removeAll { $0 === thread }
                        thread.board = newBoard
                        newBoard.addThread(thread)
                    }
                }
                NotificationCenter.default.post(name: .threadMoved, object: connection,
                                                userInfo: ["threadUUID": uuid])
            }

        case "wired.board.thread_deleted":
            if let uuid = message.uuid(forField: "wired.board.thread") {
                queue.async(flags: .barrier) {
                    if let thread = self.findThread(uuid: uuid) {
                        thread.board.threads.removeAll { $0 === thread }
                    }
                }
                NotificationCenter.default.post(name: .threadDeleted, object: connection,
                                                userInfo: ["threadUUID": uuid])
            }

        default:
            break
        }
    }

    public func connectionDidReceiveError(connection: Connection, message: P7Message) { }


    // MARK: - Private helpers

    private func parentBoard(forPath path: String) -> Board? {
        let parentPath = (path as NSString).deletingLastPathComponent
        return boardsByPath[parentPath]
    }

    private func findThread(uuid: String) -> BoardThread? {
        for board in boardsByPath.values {
            if let t = board.threadsByUUID[uuid] { return t }
        }
        return nil
    }
}
