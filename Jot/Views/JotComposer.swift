//
//  JotComposer.swift
//  Jot
//
//  The pill text field with mic + send, used on Home and at the bottom of chat.
//

import SwiftUI

struct JotComposer: View {
    @Binding var text: String
    var placeholder: String
    var big: Bool = false
    var onMic: () -> Void = {}
    var isRecording: Bool = false
    var onSend: () -> Void

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: big ? 18 : 16))
                .tracking(-0.3)
                .foregroundColor(JotTheme.ink)
                .submitLabel(.send)
                .onSubmit { if hasText { onSend() } }
                .padding(.vertical, 6)

            if !hasText {
                Button(action: onMic) {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(isRecording ? JotTheme.overdue : JotTheme.secondary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }

            Button(action: { if hasText { onSend() } }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: big ? 20 : 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: big ? 44 : 40, height: big ? 44 : 40)
                    .background(Circle().fill(hasText ? JotTheme.accent : Color(hex: 0xE5E5EA)))
            }
            .buttonStyle(.plain)
            .disabled(!hasText)
        }
        .padding(big ? EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 8)
                     : EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 7))
        .background(
            RoundedRectangle(cornerRadius: JotTheme.radius + 6)
                .fill(JotTheme.fieldBG)
                .overlay(RoundedRectangle(cornerRadius: JotTheme.radius + 6)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        )
    }
}
