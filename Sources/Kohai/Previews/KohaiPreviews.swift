import SwiftUI

// Xcode canvas previews. Same entries the snapshot test renders to PNG.

#Preview("01 Dropdown") { PreviewCatalog.main.make(false) }
#Preview("02 First-run hint") { PreviewCatalog.firstRunHint.make(false) }
#Preview("03 Empty") { PreviewCatalog.empty.make(false) }
#Preview("04 Hooks not installed") { PreviewCatalog.hooksNotInstalled.make(false) }
#Preview("05 App / socket error") { PreviewCatalog.socketError.make(false) }
#Preview("06 Automation denied") { PreviewCatalog.automationDenied.make(false) }
#Preview("07 20+ sessions") { PreviewCatalog.manySessions.make(false) }
#Preview("08 Long project names") { PreviewCatalog.longNames.make(false) }
#Preview("09 Unknown agent") { PreviewCatalog.unknownAgent.make(false) }
#Preview("10 Icon hidden in overflow") { PreviewCatalog.overflowHidden.make(false) }
#Preview("11 Menu bar icon") { PreviewCatalog.menuBarIcon.make(false) }
#Preview("12 Mascot placeholders") { PreviewCatalog.mascotSheet.make(false) }
#Preview("13 Increase Contrast") { PreviewCatalog.mainIncreasedContrast.make(false) }
#Preview("14 Lifted material") { PreviewCatalog.mainLifted.make(false) }
#Preview("15 Serious mode") { PreviewCatalog.mainSerious.make(false) }
#Preview("16 Empty, serious") { PreviewCatalog.emptySerious.make(false) }
#Preview("17 Hooks, serious") { PreviewCatalog.hooksSerious.make(false) }
