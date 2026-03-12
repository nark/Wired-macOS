//
//  MessageBubble.swift
//  Wired 3
//
//  Created by Rafaël Warnault on 25/12/2025.
//  Copyright © 2025 Read-Write. All rights reserved.
//

import SwiftUI

struct MessageBubble: Shape {
    let showsTail: Bool
    private let cornerRadius: Double = 10
    private let tailWidth: Double = 8

    init(showsTail: Bool = true) {
        self.showsTail = showsTail
    }

    func path(in rect: CGRect) -> Path {
        if !showsTail {
            return Path(
                roundedRect: CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width - tailWidth,
                    height: rect.height
                ),
                cornerRadius: cornerRadius
            )
        }

        let path = Path { path in
            let tailHeight = cornerRadius
            let bubbleWidth = rect.width - tailWidth

            // these required a little geometry to find the midpoint of an arc,
            // the formula also requires that the angle be in radians (not degrees) which is why
            // we are using pi / 4 (radians) in the forumula below (which is equivalent to 45 degrees)
            let tailEndpointX = (bubbleWidth - cornerRadius) + cornerRadius * cos(.pi / 4)
            let tailEndpointY = (rect.height - cornerRadius) + cornerRadius * sin(.pi / 4)
            
            path.move(to: CGPoint(x: cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: bubbleWidth - cornerRadius, y: rect.minY))
            
            // Top-right corner
            path.addArc(
                center: CGPoint(x: bubbleWidth - cornerRadius, y: cornerRadius),
                radius: cornerRadius,
                startAngle: Angle(degrees: -90),
                endAngle: Angle(degrees: 0),
                clockwise: false
            )
            
            path.addLine(to: CGPoint(x: bubbleWidth, y: cornerRadius))
            path.addLine(to: CGPoint(x: bubbleWidth, y: rect.height - cornerRadius))
            
            // Tail
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: rect.height),
                control: CGPoint(x: bubbleWidth, y: rect.height - (tailHeight / 2))
            )
            path.addQuadCurve(
                to: CGPoint(x: tailEndpointX, y: tailEndpointY),
                control: CGPoint(x: bubbleWidth, y: rect.height)
            )
            
            // Bottom-right corner
            path.addArc(
                center: CGPoint(x: bubbleWidth - cornerRadius, y: rect.height - cornerRadius),
                radius: cornerRadius,
                startAngle: Angle(degrees: 45),
                endAngle: Angle(degrees: 90),
                clockwise: false
            )
            
            path.addLine(to: CGPoint(x: bubbleWidth - cornerRadius - tailWidth, y: rect.height))
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.height))
            
            // Bottom-left corner
            path.addArc(
                center: CGPoint(x: cornerRadius, y: rect.height - cornerRadius),
                radius: cornerRadius,
                startAngle: Angle(degrees: 90),
                endAngle: Angle(degrees: 180),
                clockwise: false
            )
            
            path.addLine(to: CGPoint(x: rect.minX, y: rect.height - cornerRadius))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            
            // Top-left corner
            path.addArc(
                center: CGPoint(x: cornerRadius, y: cornerRadius),
                radius: cornerRadius,
                startAngle: Angle(degrees: 180),
                endAngle: Angle(degrees: 270),
                clockwise: false
            )
            
            path.closeSubpath()
        }
        
        return path
    }
}


struct MessageBubbleStyle: ViewModifier {
    let isFromYou: Bool
    let shouldSendInTheFuture: Bool
    let customFillColor: Color?
    let customForegroundColor: Color?
    let showsTail: Bool

    var messageFillColor: Color {
        if shouldSendInTheFuture {
            return Color.clear
        } else if let customFillColor {
            return customFillColor
        } else if isFromYou {
            return Color.blue
        } else {
            return Color.secondary.opacity(0.2)
        }
    }
    var forgroundColor: Color {
        if shouldSendInTheFuture {
            return Color.blue
        } else if let customForegroundColor {
            return customForegroundColor
        } else if isFromYou {
            return Color.white
        } else {
            return Color.primary
        }
    }
    
    func body(content: Content) -> some View {
            content
                .foregroundStyle(forgroundColor)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
                .padding(isFromYou ? .trailing : .leading, 8) // keep alignment with and without tail
                .background(
                    MessageBubble(showsTail: showsTail)
                        .fill(messageFillColor)
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: shouldSendInTheFuture ? 1 : 0, dash: [6]))
                        .rotation3DEffect(isFromYou ? .degrees(0) : .degrees(180), axis: (x: 0, y: 1, z: 0))
                )
    }
}

extension View {
    func messageBubbleStyle(
        isFromYou: Bool,
        shouldSendInTheFuture: Bool = false,
        customFillColor: Color? = nil,
        customForegroundColor: Color? = nil,
        showsTail: Bool = true
    ) -> some View {
        modifier(
            MessageBubbleStyle(
                isFromYou: isFromYou,
                shouldSendInTheFuture: shouldSendInTheFuture,
                customFillColor: customFillColor,
                customForegroundColor: customForegroundColor,
                showsTail: showsTail
            )
        )
    }
}
