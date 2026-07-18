import SwiftUI

@main
struct YushiApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .tint(PaperTheme.matchaDeep)
                // 奶油宣纸是浅色纸面；纸质深色主题以后单独设计，不吃系统自动反色
                .preferredColorScheme(.light)
        }
    }
}
