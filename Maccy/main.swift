import Foundation

let cliArgs = CommandLine.arguments
if cliArgs.count > 1, ["rules", "terminals", "plugins", "folders"].contains(cliArgs[1]) {
  exit(ActionsCLI.run(Array(cliArgs.dropFirst())))
}
if cliArgs.count > 1, cliArgs[1] == "history" {
  exit(HistoryAPI.runCLI(Array(cliArgs.dropFirst(2))))
}
MaccyApp.main()
