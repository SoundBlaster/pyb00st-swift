import Foundation
import Darwin
import pyb00stMCP

@main
struct MoveHubMCP {
    @MainActor
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    private static func run() async throws {
        if CommandLine.arguments.dropFirst().elementsEqual(["--help"]) {
            print("pyb00st-mcp: local Move Hub MCP server over stdio. Build with --traits MCP. No arguments required.")
            return
        }
        guard CommandLine.arguments.count == 1 else { throw LaunchError.unsupportedArguments }
        #if MCP
        try await HubMCPServer().runStdio()
        #else
        throw LaunchError.traitDisabled
        #endif
    }

    enum LaunchError: Error, LocalizedError {
        case traitDisabled, unsupportedArguments
        var errorDescription: String? {
            switch self {
            case .traitDisabled: "MCP is disabled. Rebuild with swift build --package-path MCP --traits MCP --product pyb00st-mcp."
            case .unsupportedArguments: "Unsupported arguments. Use --help or start without arguments for MCP stdio."
            }
        }
    }
}
