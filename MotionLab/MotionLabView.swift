import SwiftUI

struct MotionLabView: View {
    private let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
    private let ink = Color(red: 0.17, green: 0.22, blue: 0.18)
    private let matcha = Color(red: 0.37, green: 0.44, blue: 0.29)

    var body: some View {
        ZStack {
            paper.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("雨施流形")
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)

                Text("Motion Lab")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(ink)

                Capsule()
                    .fill(matcha)
                    .frame(width: 36, height: 2)

                Text("预览链路已就绪")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.58))
            }
            .padding(32)
        }
    }
}

#Preview {
    MotionLabView()
}
