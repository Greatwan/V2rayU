//
//  Launch.swift
//  V2rayU
//
//  Created by yanue on 2018/10/17.
//  Copyright © 2018 yanue. All rights reserved.
//

import Cocoa
import SystemConfiguration
import Alamofire
import Swifter

let LAUNCH_AGENT_DIR = "/Library/LaunchAgents/"
let LAUNCH_AGENT_PLIST = "yanue.v2rayu.v2ray-core.plist"
let LAUNCH_AGENT_PRIVOXY_PLIST = "yanue.v2rayu.privoxy.plist"
let LAUNCH_HTTP_PLIST = "yanue.v2rayu.http.plist" // simple http server
let logFilePath = NSHomeDirectory() + "/Library/Logs/v2ray-core.log"
let launchAgentDirPath = NSHomeDirectory() + LAUNCH_AGENT_DIR
let launchAgentPlistFile = launchAgentDirPath + LAUNCH_AGENT_PLIST
let launchHttpPlistFile = launchAgentDirPath + LAUNCH_HTTP_PLIST
let launchAgentPrivoxyPlistFile = launchAgentDirPath + LAUNCH_AGENT_PRIVOXY_PLIST
let AppResourcesPath = Bundle.main.bundlePath + "/Contents/Resources"
let v2rayCorePath = AppResourcesPath + "/v2ray-core"
let v2rayCoreFile = v2rayCorePath + "/v2ray"
let trojanPath = AppResourcesPath + "/trojan"
let trojanFile = trojanPath + "/trojan"
var HttpServerPacPort = UserDefaults.get(forKey: .localPacPort) ?? "10810"
let cmdSh = AppResourcesPath + "/cmd.sh"
let cmdAppleScript = "do shell script \"" + cmdSh + "\" with administrator privileges"
let JsonConfigFilePath = AppResourcesPath + "/config.json"
let privoxyPath = AppResourcesPath + "/privoxy"
let privoxyFile = privoxyPath + "/privoxy"
let PrivoxyConfigFilePath = privoxyPath + "/config.conf"
let PrivoxyLogFilePath = NSHomeDirectory() + "/Library/Logs/v2ray-privoxy.log"

var webServer = HttpServer()

enum RunMode: String {
    case global
    case off
    case manual
    case pac
    case backup
    case restore
}

class V2rayLaunch: NSObject {
    static func generateLaunchAgentPlist() {
        // Ensure launch agent directory is existed.
        let fileMgr = FileManager.default
        if !fileMgr.fileExists(atPath: launchAgentDirPath) {
            try! fileMgr.createDirectory(atPath: launchAgentDirPath, withIntermediateDirectories: true, attributes: nil)
        }
        
        // write launch agent
        let currentApplication = UserDefaults.get(forKey: .currentApplication) ?? "v2ray"
        var agentArguments = ["./v2ray-core/v2ray", "-config", JsonConfigFilePath]
        if "trojan" == currentApplication {
            agentArguments = ["./trojan/trojan", "--config", JsonConfigFilePath]
        }

        let dictAgent: NSMutableDictionary = [
            "Label": LAUNCH_AGENT_PLIST.replacingOccurrences(of: ".plist", with: ""),
            "WorkingDirectory": AppResourcesPath,
            "StandardOutPath": logFilePath,
            "StandardErrorPath": logFilePath,
            "ProgramArguments": agentArguments,
            "KeepAlive": true,
        ]

        dictAgent.write(toFile: launchAgentPlistFile, atomically: true)

        // if old launchHttpPlistFile exist
        if fileMgr.fileExists(atPath: launchHttpPlistFile) {
            print("launchHttpPlistFile exist", launchHttpPlistFile)
            _ = shell(launchPath: "/bin/launchctl", arguments: ["unload", launchHttpPlistFile])
            _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.http.plist"])
            try! fileMgr.removeItem(atPath: launchHttpPlistFile)
        }

        // permission
        _ = shell(launchPath: "/bin/bash", arguments: ["-c", "cd " + AppResourcesPath + " && /bin/chmod -R 755 ."])
    }
    
    // 生成配置文件
    static func generateLaunchAgentPrivoxyPlist() {
        let agentArguments = ["./privoxy/privoxy", "--no-daemon", PrivoxyConfigFilePath]
        let dictAgent: NSMutableDictionary = [
            "Label": LAUNCH_AGENT_PRIVOXY_PLIST.replacingOccurrences(of: ".plist", with: ""),
            "WorkingDirectory": AppResourcesPath,
            "StandardOutPath": logFilePath,
            "StandardErrorPath": logFilePath,
            "ProgramArguments": agentArguments,
            "KeepAlive": true,
        ]

        dictAgent.write(toFile: launchAgentPrivoxyPlistFile, atomically: true)
        
        // permission
        _ = shell(launchPath: "/bin/bash", arguments: ["-c", "cd " + AppResourcesPath + " && /bin/chmod -R 755 ./privoxy"])
    }
    
    // 启动服务
    static func startPrivoxyServer() {
        
        _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.privoxy"])
        _ = shell(launchPath: "/bin/launchctl", arguments: ["unload", launchAgentPrivoxyPlistFile])
        
        let task = Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["load", "-wF", launchAgentPrivoxyPlistFile])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Start privoxy succeeded.")
        } else {
            NSLog("Start privoxy failed.")
        }
    }
    
    static func stopPrivoxyServer() {
        _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.privoxy"])
        
        // cmd: /bin/launchctl unload /Library/LaunchAgents/yanue.v2rayu.privoxy.plist
        let task = Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["unload", "-wF", launchAgentPrivoxyPlistFile])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Stop privoxy succeeded.")
        } else {
            NSLog("Stop privoxy failed.")
        }
    }

    static func Start() {
        // permission: make v2ray execable
        // ~/LaunchAgents/yanue.v2rayu.v2ray-core.plist
        let currentApplication = UserDefaults.get(forKey: .currentApplication) ?? "v2ray"
        if "trojan" == currentApplication {
            _ = shell(launchPath: "/bin/bash", arguments: ["-c", "cd " + AppResourcesPath + " && /bin/chmod -R 755 ./v2ray-core"])
        } else {
            _ = shell(launchPath: "/bin/bash", arguments: ["-c", "cd " + AppResourcesPath + " && /bin/chmod -R 755 ./trojan"])
        }
        
        self.generateLaunchAgentPlist()
        
        self.generateLaunchAgentPrivoxyPlist()
        
        self.startHttpServer()
        
        self.startPrivoxyServer()

        // unload first
        _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.v2ray-core"])
        _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.http.plist"])
        _ = shell(launchPath: "/bin/launchctl", arguments: ["unload", launchAgentPlistFile])


        let task = Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["load", "-wF", launchAgentPlistFile])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Start v2ray-core succeeded.")
        } else {
            NSLog("Start v2ray-core failed.")
        }
    }

    static func Stop() {
        _ = shell(launchPath: "/bin/launchctl", arguments: ["unload", launchHttpPlistFile])
	
        // stop pac server
        webServer.stop()
        
        _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.v2ray-core"])
        _ = shell(launchPath: "/bin/launchctl", arguments: ["remove", "yanue.v2rayu.http.plist"])
        self.stopPrivoxyServer()

        // cmd: /bin/launchctl unload /Library/LaunchAgents/yanue.v2rayu.v2ray-core.plist
        let task = Process.launchedProcess(launchPath: "/bin/launchctl", arguments: ["unload", launchAgentPlistFile])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("Stop v2ray-core succeeded.")
        } else {
            NSLog("Stop v2ray-core failed.")
        }
    }

    static func OpenLogs() {
        if !FileManager.default.fileExists(atPath: logFilePath) {
            let txt = ""
            try! txt.write(to: URL.init(fileURLWithPath: logFilePath), atomically: true, encoding: String.Encoding.utf8)
        }

        let task = Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [logFilePath])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("open logs succeeded.")
        } else {
            NSLog("open logs failed.")
        }
    }

    static func ClearLogs() {
        let txt = ""
        try! txt.write(to: URL.init(fileURLWithPath: logFilePath), atomically: true, encoding: String.Encoding.utf8)
    }

    static func chmodCmdPermission() {
        // Ensure launch agent directory is existed.
        if !FileManager.default.fileExists(atPath: cmdSh) {
            return
        }

        let res = shell(launchPath: "/bin/bash", arguments: ["-c", "cd " + AppResourcesPath + " && ls -la ./V2rayUTool | awk '{print $3,$4}'"])
        NSLog("Permission is " + (res ?? ""))
        if res == "root admin" {
            NSLog("Permission is ok")
            return
        }

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: cmdAppleScript) {
            let output: NSAppleEventDescriptor = scriptObject.executeAndReturnError(&error)
            print(output.stringValue ?? "")
            if (error != nil) {
                print("error: \(String(describing: error))")
            }
        } else {
            print("error scriptObject")
        }
    }

    // 配置代理模式，取消原有的http的代理功能
    static func setSystemProxy(mode: RunMode, httpPort: String = "", sockPort: String = "") {
        let httpPorts = ""
        let task = Process.launchedProcess(launchPath: AppResourcesPath + "/V2rayUTool", arguments: ["-mode", mode.rawValue, "-pac-url", PACUrl, "-http-port", httpPorts, "-sock-port", sockPort])
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            NSLog("setSystemProxy " + mode.rawValue + " succeeded.")
        } else {
            NSLog("setSystemProxy " + mode.rawValue + " failed.")
        }
    }

    // start http server for pac
    static func startHttpServer() {
        do {
            // stop first
            webServer.stop()

            // then new HttpServer
            webServer = HttpServer()
            webServer["/:path"] = shareFilesFromDirectory(AppResourcesPath)
            webServer["/pac/:path"] = shareFilesFromDirectory(AppResourcesPath + "/pac")

            let pacPort = UInt16(UserDefaults.get(forKey: .localPacPort) ?? "10810") ?? 10810
            try webServer.start(pacPort)
            print("webServer.start at:\(pacPort)")
        } catch let error {
            print("webServer.start error:\(error)")
        }
    }

    static func checkPorts() -> Bool {
        // stop old v2ray process
        self.Stop()
        // stop pac server
        webServer.stop()

        let localSockPort = UserDefaults.get(forKey: .localSockPort) ?? "10808"
        let localSockHost = UserDefaults.get(forKey: .localSockHost) ?? "127.0.0.1"
        let localHttpPort = UserDefaults.get(forKey: .localHttpPort) ?? "10809"
        let localHttpHost = UserDefaults.get(forKey: .localHttpHost) ?? "127.0.0.1"
        let localPacPort = UserDefaults.get(forKey: .localPacPort) ?? "10810"

        // check same port
        if localSockPort == localHttpPort {
            makeToast(message: "the ports (sock,http) cannot be the same: " + localHttpPort)
            return false
        }

        if localHttpPort == localPacPort {
            makeToast(message: "the ports (http,pac) cannot be the same:" + localPacPort)
            return false
        }

        if localSockPort == localPacPort {
            makeToast(message: "the ports (sock,pac) cannot be the same:" + localPacPort)
            return false
        }

        // check port is used
        if !self.checkPort(host: localSockHost, port: localSockPort, tip: "socks") {
            return false
        }

        if !self.checkPort(host: localHttpHost, port: localHttpPort, tip: "http") {
            return false
        }

        if !self.checkPort(host: "0.0.0.0", port: localPacPort, tip: "pac") {
            return false
        }

        return true
    }

    static func checkPort(host: String, port: String, tip: String) -> Bool {
        // shell("/bin/bash",["-c","cd ~ && ls -la"])
        let cmd = "cd " + AppResourcesPath + " && chmod +x ./V2rayUHelper && ./V2rayUHelper -cmd port -h " + host + " -p " + port
        let res = shell(launchPath: "/bin/bash", arguments: ["-c", cmd])

        NSLog("checkPort: res=(\(String(describing: res))) cmd=(\(cmd))")

        if res != "ok" {
            makeToast(message: tip + " error - " + (res ?? ""), displayDuration: 5)
            return false
        }
        return true
    }
}
