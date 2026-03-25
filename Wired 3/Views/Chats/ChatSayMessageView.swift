//
//  ChatMessageView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI
import Foundation
import CryptoKit

struct ChatSayMessageView: View {
    @Environment(ConnectionRuntime.self) private var runtime
    @AppStorage("TimestampEveryMessage") var timestampEveryMessage: Bool = false
    @AppStorageCodable(key: "ChatHighlightRules", defaultValue: [])
    
    private var highlightRules: [ChatHighlightRule]
    
    var message: ChatEvent
    var showNickname: Bool = true
    var showAvatar: Bool = true
    var isGroupedWithNext: Bool = false
    
    @State var isHovered: Bool = false

    private var primaryImageURL: URL? {
        message.text.detectedHTTPImageURLs().first
    }

    private var trimmedMessageText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isImageOnlyMessage: Bool {
        guard let primaryImageURL else { return false }
        return trimmedMessageText == primaryImageURL.absoluteString
    }

    private var shouldShowTextBubble: Bool {
        !isImageOnlyMessage
    }
    
    var body: some View {
        let isFromYou = message.user.id == runtime.userID
        let matchedRule = matchedHighlightRule(in: message.text)
        let bubbleFillColor = matchedRule?.color.swiftUIColor
        let bubbleTextColor = matchedRule?.color.contrastTextColor
        let linkColor = bubbleTextColor ?? (isFromYou ? .white : .blue)
        
        VStack(alignment: isFromYou ? .trailing : .leading) {
            HStack(alignment: .bottom) {
                if isFromYou {
                    Spacer()
                    VStack(alignment: .trailing) {
                        if showNickname {
                            Text(message.user.nick)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .padding(.trailing, 10)
                        }
                        messageContentStack(
                            isFromYou: isFromYou,
                            linkColor: linkColor,
                            bubbleFillColor: bubbleFillColor,
                            bubbleTextColor: bubbleTextColor
                        )
                    }
                    .padding(.bottom, isGroupedWithNext ? 2 : 8)
                    
                    avatarView
                    
                } else {
                    avatarView

                    VStack(alignment: .leading) {
                        if showNickname {
                            Text(message.user.nick)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .padding(.leading, 10)
                        }
                        messageContentStack(
                            isFromYou: isFromYou,
                            linkColor: linkColor,
                            bubbleFillColor: bubbleFillColor,
                            bubbleTextColor: bubbleTextColor
                        )
                    }
                    .padding(.bottom, isGroupedWithNext ? 2 : 8)
                    Spacer()
                }
            }
            
            if timestampEveryMessage {
                HoverableRelativeDateText(date: message.date)
                    .foregroundStyle(.gray)
                    .monospacedDigit()
                    .font(.caption)
                    .padding(.bottom, 3)
                    .padding(isFromYou ? .trailing : .leading, 45)
            }
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .id(message.id)
        .animation(nil, value: showNickname)
        .animation(nil, value: showAvatar)
        .animation(nil, value: isGroupedWithNext)
        .onHover { isHover in
            isHovered = isHover
        }
    }

    private func matchedHighlightRule(in text: String) -> ChatHighlightRule? {
        let loweredText = text.lowercased()
        return highlightRules.first { rule in
            let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !keyword.isEmpty else { return false }
            return loweredText.contains(keyword)
        }
    }

    @ViewBuilder
    private func messageContentStack(
        isFromYou: Bool,
        linkColor: Color,
        bubbleFillColor: Color?,
        bubbleTextColor: Color?
    ) -> some View {
        VStack(alignment: isFromYou ? .trailing : .leading, spacing: 6) {
            if shouldShowTextBubble {
                Text(message.text.attributedWithDetectedLinks(linkColor: linkColor))
                    .messageBubbleStyle(
                        isFromYou: isFromYou,
                        customFillColor: bubbleFillColor,
                        customForegroundColor: bubbleTextColor,
                        showsTail: primaryImageURL == nil && !isGroupedWithNext
                    )
                    .containerRelativeFrame(
                        .horizontal,
                        count: 4,
                        span: 3,
                        spacing: 0,
                        alignment: isFromYou ? .trailing : .leading
                    )
            }

            if let primaryImageURL {
                ChatRemoteImageBubbleView(
                    url: primaryImageURL,
                    isFromYou: isFromYou,
                    showsTail: !isGroupedWithNext
                )
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if showAvatar {
            if let icon = Image(data: message.user.icon) {
                icon
                    .resizable()
                    .frame(width: 32, height: 32)
                    .padding(.bottom, 6)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        } else {
            Color.clear
                .frame(width: 32, height: 32)
                .padding(.bottom, 6)
        }
    }
}

actor ChatRemoteImageCache {
    static let shared = ChatRemoteImageCache()

    private let memoryCache = NSCache<NSURL, NSData>()
    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL

    init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectoryURL = cachesDirectory.appendingPathComponent("ChatRemoteImages", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
        memoryCache.countLimit = 128
        memoryCache.totalCostLimit = 64 * 1024 * 1024
    }

    func data(for url: URL) -> Data? {
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return Data(referencing: cached)
        }

        let fileURL = cachedFileURL(for: url)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    func store(_ data: Data, for url: URL) {
        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        let fileURL = cachedFileURL(for: url)
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        let pathExtension = url.pathExtension.isEmpty ? "bin" : url.pathExtension.lowercased()
        return cacheDirectoryURL.appendingPathComponent("\(key).\(pathExtension)", isDirectory: false)
    }
}

@MainActor
final class ChatRemoteImageLoader: NSObject, ObservableObject, @preconcurrency URLSessionDataDelegate {
    enum Phase {
        case idle
        case loading(progress: Double?)
        case success(PlatformImage)
        case failure
    }

    @Published private(set) var phase: Phase = .idle

    private let url: URL
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var receivedData = Data()
    private var expectedContentLength: Int64 = NSURLSessionTransferSizeUnknown
    private var didStart = false

    init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        dataTask?.cancel()
        session?.invalidateAndCancel()
    }

    func loadIfNeeded() {
        guard !didStart else { return }
        didStart = true

        Task {
            if let cachedData = await ChatRemoteImageCache.shared.data(for: url),
               let image = AppImageCodec.platformImage(from: cachedData) {
                phase = .success(image)
                return
            }

            startNetworkLoad()
        }
    }

    func cancel() {
        dataTask?.cancel()
        dataTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func startNetworkLoad() {
        phase = .loading(progress: nil)
        receivedData = Data()
        expectedContentLength = NSURLSessionTransferSizeUnknown

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let task = session.dataTask(with: request)
        dataTask = task
        task.resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        if let mimeType = response.mimeType?.lowercased(),
           !mimeType.hasPrefix("image/") {
            phase = .failure
            return .cancel
        }

        expectedContentLength = response.expectedContentLength
        phase = .loading(progress: progressValue)
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        phase = .loading(progress: progressValue)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            dataTask = nil
            session.finishTasksAndInvalidate()
            self.session = nil
        }

        guard error == nil else {
            phase = .failure
            return
        }

        guard !receivedData.isEmpty,
              let image = AppImageCodec.platformImage(from: receivedData) else {
            phase = .failure
            return
        }

        let finalData = receivedData
        Task {
            await ChatRemoteImageCache.shared.store(finalData, for: url)
        }
        phase = .success(image)
    }

    private var progressValue: Double? {
        guard expectedContentLength > 0 else { return nil }
        return min(max(Double(receivedData.count) / Double(expectedContentLength), 0), 1)
    }
}

struct ChatRemoteImageBubbleView: View {
    let url: URL
    let isFromYou: Bool
    let showsTail: Bool

    @StateObject private var loader: ChatRemoteImageLoader

    private let maxBubbleWidth: CGFloat = 280
    private let maxBubbleHeight: CGFloat = 360
    private let placeholderSize = CGSize(width: 280, height: 190)

    init(url: URL, isFromYou: Bool, showsTail: Bool) {
        self.url = url
        self.isFromYou = isFromYou
        self.showsTail = showsTail
        _loader = StateObject(wrappedValue: ChatRemoteImageLoader(url: url))
    }

    private func resolvedSize(for image: PlatformImage) -> CGSize {
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return placeholderSize }
        let ratio = natural.height / natural.width
        var w = min(natural.width, maxBubbleWidth)
        var h = w * ratio
        if h > maxBubbleHeight {
            h = maxBubbleHeight
            w = h / ratio
        }
        return CGSize(width: ceil(w), height: ceil(h))
    }

    private var currentSize: CGSize {
        if case .success(let image) = loader.phase {
            return resolvedSize(for: image)
        }
        return placeholderSize
    }

    var body: some View {
        Link(destination: url) {
            bubbleContent
        }
        .buttonStyle(.plain)
        .frame(width: currentSize.width, height: currentSize.height)
        .contextMenu { contextMenuItems }
        .onAppear {
            loader.loadIfNeeded()
        }
        .onDisappear {
            loader.cancel()
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
#if os(macOS)
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label("Open in Browser", systemImage: "safari")
        }
        Button {
            downloadImage()
        } label: {
            Label("Download Image", systemImage: "square.and.arrow.down")
        }
#endif
    }

#if os(macOS)
    @MainActor
    private func downloadImage() {
        Task {
            let imageData: Data?
            if let cached = await ChatRemoteImageCache.shared.data(for: url) {
                imageData = cached
            } else {
                imageData = try? await URLSession.shared.data(from: url).0
            }
            guard let data = imageData else { return }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = url.lastPathComponent.isEmpty ? "image" : url.lastPathComponent
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let saveURL = panel.url {
                try? data.write(to: saveURL, options: .atomic)
            }
        }
    }
#endif

    private var bubbleContent: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.secondary.opacity(0.18),
                    Color.secondary.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            switch loader.phase {
            case .idle, .loading:
                loadingOverlay
            case .success(let image):
                imageView(image)
            case .failure:
                failureOverlay
            }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .mask(bubbleMask)
        .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
    }

    private var bubbleMask: some View {
        MessageBubble(showsTail: showsTail)
            .fill(Color.white)
            .rotation3DEffect(isFromYou ? .degrees(0) : .degrees(180), axis: (x: 0, y: 1, z: 0))
    }

    private func imageView(_ image: PlatformImage) -> some View {
        let size = resolvedSize(for: image)
        return Group {
            #if os(iOS)
            Image(uiImage: image)
                .resizable()
            #else
            Image(nsImage: image)
                .resizable()
            #endif
        }
        .scaledToFit()
        .frame(width: size.width, height: size.height)
    }

    private var loadingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.03))

            VStack(spacing: 10) {
                switch loader.phase {
                case .loading(let progress):
                    if let progress {
                        ProgressView(value: progress, total: 1)
                            .progressViewStyle(.linear)
                            .frame(width: 120)
                    } else {
                        ProgressView()
                            .controlSize(.regular)
                    }
                default:
                    ProgressView()
                        .controlSize(.regular)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var failureOverlay: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.08))

            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title3)
                Text(url.lastPathComponent.isEmpty ? (url.host ?? "Image") : url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(16)
        }
    }
}
