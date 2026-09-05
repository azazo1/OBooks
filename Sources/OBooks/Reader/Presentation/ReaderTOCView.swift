import SwiftUI

struct ReaderTOCView: View {
    let entries: [ReaderTOCIndex.Entry]
    let currentEntryID: UUID?
    let onNavigate: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        Button {
                            onNavigate(entry.item.href)
                        } label: {
                            Text(entry.item.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, CGFloat(12 + entry.depth * 12))
                                .padding(.trailing, 12)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .background(
                                    entry.id == currentEntryID
                                        ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                                        : .clear,
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(entry.id == currentEntryID ? .isSelected : [])
                        .id(entry.id)
                    }
                }
                .padding(7)
            }
            .onAppear {
                if let currentEntryID { proxy.scrollTo(currentEntryID, anchor: .center) }
            }
            .onChange(of: currentEntryID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}
