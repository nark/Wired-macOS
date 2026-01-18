//
//  TransfersView.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 14/01/2026.
//  Copyright © 2026 Read-Write. All rights reserved.
//

import SwiftUI

struct TransfersView: View {
    @EnvironmentObject private var transfers: TransferManager
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(transfers.transfers) { transfer in
                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: transfer.type == .download ? "arrow.down.square.fill" : "arrow.up.square.fill")
                                .foregroundStyle(transfer.type == .download ? .blue : .red)
                            
                            Text(transfer.name)
                            
                            Spacer()
                            
                            Text(transfer.uri ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ProgressView(value: transfer.percent, total: 100)
                        
                        HStack {
                            Text(transfer.transferStatus())
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                }
            }
            .alternatingRowBackgrounds()
            
            Divider()
            
            HStack {
                Button {
                    transfers.clear()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                
                Spacer()
            }
            .padding(10)
        }
    }
}
