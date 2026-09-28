import ClaudePetCore
import Foundation
#if canImport(ServiceManagement)
import ServiceManagement
#endif

let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    사용법: claude-pet <명령>
      install-hooks [claude|codex]
                           펫 훅을 추가한다 (백업 생성). 인자가 없으면 Claude 와,
                           ~/.codex 가 있으면 Codex 도 함께 설치한다
      uninstall-hooks [claude|codex]
                           펫 훅만 제거한다 (백업 생성). 대상 선택은 install-hooks 와 같다
      add <id>             codex-pets.net 에서 펫을 받아 설치한다 (예: add guga)
      use <id>             기본 펫을 지정한다
      list                 설치된 펫을 보여준다
      login-item on|off    로그인 시 자동 실행
      status               훅 설치 여부와 살아 있는 세션 상태
      hook [--agent claude|codex]   (내부용) 에이전트 훅 이벤트를 상태 파일로 기록한다
    """)
    exit(2)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("claude-pet: \(message)\n".utf8))
    exit(1)
}

func allPets() -> [InstalledPet] {
    PetLibrary.discover(userDirectory: Paths.petsDirectory, codexDirectory: Paths.codexPetsDirectory,
                        builtinDirectory: BundleLayout.builtinPetDirectory(executable: executable))
}

final class ErrorBox: @unchecked Sendable { var error: Error? }

func runAsync(_ body: @escaping @Sendable () async throws -> Void) -> Never {
    let sem = DispatchSemaphore(value: 0)
    let box = ErrorBox()
    Task { do { try await body() } catch { box.error = error }; sem.signal() }
    sem.wait()
    if let error = box.error { fail("\(error)") }
    exit(0)
}

/// `install-hooks codex` 처럼 하나를 고르거나, 인자가 없으면 이 컴퓨터에서 쓰는 에이전트 전부.
func hookTargets() -> [Agent] {
    guard args.count >= 2 else { return Agent.installTargets() }
    guard args.count == 2, let agent = Agent(rawValue: args[1]) else {
        fail("모르는 에이전트입니다: \(args.dropFirst().joined(separator: " ")) (claude 또는 codex)")
    }
    return [agent]
}

guard let command = args.first else { usage() }

switch command {
case "install-hooks":
    do {
        #if os(Windows)
        // Windows 는 셸 스크립트 대신 이 실행 파일의 `hook` 서브커맨드를 건다. Claude Code 가 훅을 어떤 셸로
        // 돌릴지는 Git Bash 유무로 정해지므로 같은 순서로 찾아 항목의 shell 을 맞춘다.
        let hookExe = BundleLayout.hookExecutable(executable: executable)
        guard FileManager.default.fileExists(atPath: hookExe.path) else { fail("훅 실행 파일이 없습니다: \(hookExe.path)") }
        let shell = GitBash.claudeShell()
        let platform = HookPlatform.windows(hookExecutable: hookExe, claudeShell: shell)
        if shell == .powershell {
            print("Git Bash 를 찾지 못해 Claude Code 훅을 PowerShell 로 겁니다. Claude Code 가 Git Bash 를 쓰는 기계라면 Git for Windows 를 설치한 뒤 다시 실행하세요.")
        }
        #else
        let script = BundleLayout.hookScript(executable: executable)
        guard FileManager.default.fileExists(atPath: script.path) else { fail("훅 스크립트가 없습니다: \(script.path)") }
        let platform = HookPlatform.macOS(hookScript: script)
        #endif
        for agent in hookTargets() {
            let backup = try HooksInstaller.installFile(at: agent.settingsFile, platform: platform, agent: agent, now: Date())
            print("\(agent.displayName) 훅을 설치했습니다. 백업: \(backup.path)")
            if let note = agent.postInstallNote { print("  → \(note)") }
        }
        print("새로 시작하는 세션부터 반영됩니다.")
    } catch { fail("설치 실패: \(error)") }

case "uninstall-hooks":
    do {
        for agent in hookTargets() {
            if let backup = try HooksInstaller.uninstallFile(at: agent.settingsFile, now: Date()) {
                print("\(agent.displayName) 훅을 제거했습니다. 백업: \(backup.path)")
            } else {
                print("\(agent.displayName) 에 설치된 펫 훅이 없습니다.")
            }
        }
    } catch { fail("제거 실패: \(error)") }

case "add":
    guard args.count == 2 else { usage() }
    runAsync {
        let pet = try await PetInstaller.live(petsDirectory: Paths.petsDirectory).add(id: args[1])
        print("설치했습니다: \(pet.manifest.displayName) → \(pet.directory.path)")
        if Preferences.shared.selectedPetId == nil {
            Preferences.shared.selectedPetId = pet.id
            Preferences.shared.postChanged()
            print("기본 펫으로 지정했습니다.")
        } else {
            print("적용하려면: claude-pet use \(pet.id)")
        }
    }

case "use":
    guard args.count == 2 else { usage() }
    guard allPets().contains(where: { $0.id == args[1] }) else { fail("설치되지 않은 펫입니다: \(args[1]) (claude-pet list 로 확인)") }
    Preferences.shared.selectedPetId = args[1]
    Preferences.shared.postChanged()
    print("기본 펫: \(args[1])")

case "list":
    let selected = Preferences.shared.selectedPetId
    let pets = allPets()
    if pets.isEmpty { print("설치된 펫이 없습니다. claude-pet add guga") }
    for pet in pets {
        let mark = pet.id == selected ? "*" : " "
        print("\(mark) \(pet.id.padding(toLength: 16, withPad: " ", startingAt: 0)) \(pet.manifest.displayName)  [\(pet.source.rawValue)]")
    }

case "login-item":
    guard args.count == 2, ["on", "off"].contains(args[1]) else { usage() }
    #if canImport(ServiceManagement)
    guard BundleLayout.appBundle(containing: executable) != nil else { fail("앱 번들 안에서만 동작합니다. scripts/install.sh 로 설치한 뒤 실행하세요.") }
    do {
        if args[1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        print("로그인 시 실행: \(args[1])")
    } catch { fail("변경 실패: \(error.localizedDescription)") }
    #elseif os(Windows)
    // HKCU Run 키. 앱 exe 는 CLI 옆에 있어야 한다.
    let appExe = executable.deletingLastPathComponent().appendingPathComponent("ClaudePetWin.exe")
    guard FileManager.default.fileExists(atPath: appExe.path) else { fail("ClaudePetWin.exe 가 CLI 옆에 없습니다: \(appExe.path)") }
    do {
        if args[1] == "on" { try LoginItem.enable(appExecutable: appExe) } else { try LoginItem.disable() }
        print("로그인 시 실행: \(args[1])")
    } catch { fail("변경 실패: 레지스트리를 쓸 수 없습니다") }
    #else
    fail("이 플랫폼에서는 지원하지 않습니다.")
    #endif

case "status":
    for agent in Agent.allCases {
        let installed = HooksInstaller.isInstalled(file: agent.settingsFile)
        let unused = agent.isAvailable(home: Paths.home) ? "" : "  — ~/.codex 없음, 설치 대상 아님"
        print("\(agent.displayName) 훅: \(installed ? "설치됨" : "미설치") (\(agent.settingsFile.path))\(unused)")
    }
    let now = Date()
    let probe = ProcessProbe()
    let agg = StateAggregator.aggregate(StateStore(directory: Paths.stateDirectory).loadAll(),
                                        now: now, liveness: probe.liveness(of:))
    print("합성 상태: \(agg.state.rawValue)  (살아 있는 세션 \(agg.liveSessionCount), 대기 \(agg.waitingCount))")
    for summary in agg.sessions {
        let s = summary.session
        let age = Int(now.timeIntervalSince(s.timestamp))
        // 프로세스를 확인해 살아 있다고 본 세션인지 표시한다. 오래 조용한 세션이 왜 남아 있는지 알 수 있다.
        let how = probe.liveness(of: s) == .alive ? "프로세스 확인" : "최근 신호"
        print("  \(s.agent.rawValue.padding(toLength: 7, withPad: " ", startingAt: 0)) \(summary.state.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(s.projectName.padding(toLength: 24, withPad: " ", startingAt: 0)) \(s.tool.padding(toLength: 10, withPad: " ", startingAt: 0)) \(age)s 전  \(how)  \(s.sessionId)")
    }

case "hook":
    // 내부용. Claude Code / Codex 가 이벤트마다 부른다. 어떤 경우에도 exit 0, stdout 없음.
    var hookAgent = Agent.claude
    if args.count >= 3, args[1] == "--agent", let a = Agent(rawValue: args[2]) { hookAgent = a }
    let hookInput = FileHandle.standardInput.readDataToEndOfFile()
    #if os(Windows)
    let hookAncestry: ProcessAncestry = WindowsProcessAncestry()
    let hookRule = HostAppRule.windows
    #else
    let hookAncestry: ProcessAncestry = DarwinProcessAncestry()
    let hookRule = HostAppRule.macOS
    #endif
    let hookAction = HookRunner.decide(
        input: hookInput,
        agent: hookAgent,
        environment: ProcessInfo.processInfo.environment,
        ancestry: hookAncestry,
        selfPid: ProcessInfo.processInfo.processIdentifier,
        hostRule: hookRule,
        now: Date()
    )
    HookRunner.perform(hookAction, stateDirectory: Paths.stateDirectory)
    exit(0)

case "help", "-h", "--help":
    usage()

default:
    usage()
}
