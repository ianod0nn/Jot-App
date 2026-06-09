//
//  ChecklistBubbleView.swift
//  Jot
//
//  Renders a list-type capture (e.g. a grocery list) as a card of checkable
//  rows inline in the chat. Tapping a row toggles it. When every item is
//  checked, the caller clears the list from the database (option B).
//

import SwiftUI

struct ChecklistBubbleView: View {
    let title: String
    let items: [ListItem]
    let onToggle: (UUID) -> Void

    private var remaining: Int { items.filter { !$0.isChecked }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(remaining == 0 ? "all done" : "\(remaining) left")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(items) { item in
                Button(action: { onToggle(item.id) }) {
                    HStack(spacing: 10) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundColor(item.isChecked ? .green : .secondary)
                        Text(item.text)
                            .strikethrough(item.isChecked, color: .secondary)
                            .foregroundColor(item.isChecked ? .secondary : .primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .frame(maxWidth: 320, alignment: .leading)
    }
}
