import SwiftUI

if CommandLine.arguments.contains("--smc-helper") {
    SMCHelperMode.run()
}

MystralApp.main()
