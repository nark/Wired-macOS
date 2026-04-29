//
//  ServerInfoView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 07/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct ServerInfoView: View {
    @Environment(ConnectionRuntime.self) private var runtime

    /// Stored TOFU fingerprint for this server, if any.
    private var serverTrustFingerprint: String? {
        guard let config = runtime.connectionController.configuration(for: runtime.id) else {
            return nil
        }
        return ServerTrustStore.storedFingerprint(host: config.hostname, port: config.url.port)
    }

    var body: some View {
        Group {
            if let serverInfo = runtime.serverInfo {
                ScrollView {
                    VStack(spacing: 0) {
                        // MARK: Header
                        Image(data: serverInfo.serverBanner)

                        VStack(spacing: 4) {
                            Text(serverInfo.serverName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(serverInfo.serverDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                        // SECURITY (A_009): Server identity badge
                        serverIdentityBadge
                            .padding(.bottom, 20)

                        // MARK: Info sections
                        VStack(spacing: 14) {

                            infoSection("Application") {
                                infoRow("Name", value: serverInfo.applicationName)
                                infoRow("Version", value: serverInfo.serverVersion)
                                if let spec = runtime.connection?.spec {
                                    if let p7 = spec.builtinProtocolVersion {
                                        infoRow("P7 Protocol", value: p7)
                                    }
                                    if let name = spec.protocolName, let ver = spec.protocolVersion {
                                        infoRow("Wired Protocol", value: "\(name) \(ver)")
                                    }
                                }
                            }

                            infoSection("System") {
                                infoRow("OS", value: serverInfo.osName)
                                infoRow("OS Version", value: serverInfo.osVersion)
                                infoRow("Architecture", value: serverInfo.arch)
                            }

                            infoSection("Files") {
                                infoRow("Count", value: "\(serverInfo.filesCount) files")
                                infoRow("Size", value: ByteCountFormatter().string(fromByteCount: Int64(serverInfo.filesSize)))
                                infoTimerRow("Uptime", since: serverInfo.startTime)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading server information…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .task(id: "\(runtime.status)-\(runtime.selectedTab)") {
            await refreshServerInfoIfNeeded()
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func infoSection(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                rows()
            }
            .padding(.top, 4)
        } label: {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .gridColumnAlignment(.leading)
                .frame(minWidth: 110, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .gridColumnAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func infoTimerRow(_ label: String, since date: Date) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .gridColumnAlignment(.leading)
                .frame(minWidth: 110, alignment: .leading)

            Text(date, style: .timer)
                .font(.subheadline)
                .gridColumnAlignment(.leading)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Identity badge

    @ViewBuilder
    private var serverIdentityBadge: some View {
        if let fingerprint = serverTrustFingerprint {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .imageScale(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Verified Identity")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Text(fingerprint)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.green.opacity(0.30), lineWidth: 1)
            )
        } else {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Identity not verified")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Data loading

    @MainActor
    private func refreshServerInfoIfNeeded() async {
        guard runtime.status == .connected else { return }
        guard runtime.selectedTab == .infos else { return }
        guard runtime.serverInfo == nil else { return }

        if let serverInfo = runtime.connection?.serverInfo {
            runtime.serverInfo = serverInfo
            return
        }

        // Slow or remote servers may expose serverInfo slightly later than first render.
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            guard runtime.status == .connected, runtime.selectedTab == .infos else { return }
            if runtime.serverInfo != nil { return }
            if let serverInfo = runtime.connection?.serverInfo {
                runtime.serverInfo = serverInfo
                return
            }
        }
    }
}
