import SwiftUI

// MARK: - 1.タブバー設定
struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Namespace private var animation // スライドアニメーション用

    var body: some View {
        HStack(spacing: 20) {
            TabButton(title: "Recordings", icon: "mic.fill", isSelected: selectedTab == 0, animation: animation) {
                selectedTab = 0
            }
            
            TabButton(title: "Collections", icon: "square.stack.fill", isSelected: selectedTab == 1, animation: animation) {
                selectedTab = 1
            }

            TabButton(title: "Settings", icon: "gearshape.fill", isSelected: selectedTab == 2, animation: animation) {
                selectedTab = 2
            }
        }
        .padding(6)
        .background(.ultraThinMaterial) // バー自体の色
        .clipShape(Capsule())
        .overlay(
            Capsule()
            .stroke(Color.white.opacity(0.3), lineWidth: 0.5) // バーの枠線
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedTab)
    }
}

// MARK: - 2.タブボタン設定
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let animation: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(isSelected ? .blue : .white)
            .frame(width: 100, height: 54) // ボタン自体のフレームを固定
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .matchedGeometryEffect(id: "TabBackground", in: animation)
                }
            }
        }
    }
}