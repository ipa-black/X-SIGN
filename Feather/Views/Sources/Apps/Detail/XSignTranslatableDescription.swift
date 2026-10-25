import SwiftUI
import Translation

struct XSignTranslatableDescription: View {
    let text: String
    let accentColor: Color

    @State private var isTranslationPresented = false
    @State private var translatedText: String?
    @State private var isExpanded = false

    var body: some View {
        Group {
            if #available(iOS 17.4, macOS 14.4, *) {
                content
                    .translationPresentation(
                        isPresented: $isTranslationPresented,
                        text: text
                    ) { result in
                        translatedText = result
                        isExpanded = true
                        isTranslationPresented = false
                    }
            } else {
                content
            }
        }
        .onChange(of: text) { _ in
            isTranslationPresented = false
            translatedText = nil
            isExpanded = false
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("الوصف")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                if #available(iOS 17.4, macOS 14.4, *) {
                    Button {
                        isTranslationPresented = true
                    } label: {
                        Label("ترجمة الوصف", systemImage: "translate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(accentColor)
                    .buttonStyle(.plain)
                    .disabled(
                        text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                    )
                }
            }

            Text(verbatim: translatedText ?? text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(5)
                .lineLimit(isExpanded ? nil : 6)
                .textSelection(.enabled)

            HStack(spacing: 18) {
                Button(isExpanded ? "عرض أقل" : "المزيد") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

                if translatedText != nil {
                    Button("عرض الأصل") {
                        translatedText = nil
                    }
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(accentColor)
            .buttonStyle(.plain)
        }
    }
}
