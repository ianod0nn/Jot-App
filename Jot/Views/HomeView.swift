//
//  HomeView.swift
//  Jot
//
//  The redesigned home: wordmark + greeting, a hero composer, and a
//  "See my saved thoughts" card. Type+send or tap the card to enter chat.
//

import SwiftUI

struct HomeView: View {
    @Binding var draft: String
    var savedCount: Int
    var isRecording: Bool
    var onSend: () -> Void
    var onMic: () -> Void
    var onSeeSaved: () -> Void

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : (h < 18 ? "Good afternoon" : "Good evening")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Brand + greeting
            VStack(alignment: .leading, spacing: 0) {
                JotWordmark(size: 46)
                (Text(greeting + ".\n").foregroundColor(JotTheme.ink)
                 + Text("What's on your mind?").foregroundColor(JotTheme.secondary))
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.6)
                    .lineSpacing(4)
                    .padding(.top, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 78)

            // Hero composer, centered in the remaining space
            VStack(spacing: 12) {
                JotComposer(text: $draft, placeholder: "Type a thought or ask a question…",
                            big: true, onMic: onMic, isRecording: isRecording, onSend: onSend)
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(JotTheme.accent)
                    Text("Ask a question and Jot answers · or just jot it down.")
                        .font(.system(size: 13.5))
                        .foregroundColor(JotTheme.secondary)
                        .tracking(-0.1)
                    Spacer()
                }
                .padding(.leading, 6)
            }
            .frame(maxHeight: .infinity)

            // See my saved thoughts
            Button(action: onSeeSaved) {
                HStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(JotTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(JotTheme.accent.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("See my saved thoughts")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundColor(JotTheme.ink)
                        Text("\(savedCount) thoughts saved")
                            .font(.system(size: 13.5))
                            .foregroundColor(JotTheme.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(JotTheme.tertiary)
                }
                .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
                .background(
                    RoundedRectangle(cornerRadius: JotTheme.radius + 4)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: JotTheme.radius + 4)
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JotTheme.pageBG.ignoresSafeArea())
    }
}
