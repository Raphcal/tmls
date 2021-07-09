#!/usr/bin/swift

//
//  main.swift
//  tmls
//
//  Created by Raphaël Calabro on 13/11/2016.
//  Copyright © 2016 Raphaël Calabro. All rights reserved.
//

import Foundation

func environmentVariable(named variable: String) -> String {
    if let pwd = getenv(variable), let value = String(cString: pwd, encoding: .utf8) {
        return value
    }
    return ""
}

func hostname() -> String {
    let memory = UnsafeMutablePointer<Int8>.allocate(capacity: 256)
    if gethostname(memory, 256) == 0, let name = String(cString: memory, encoding: .utf8) {
        if let dot = name.firstIndex(of: ".") {
            return String(name[..<dot])
        } else {
            return name
        }
    }
    return ""
}

func diskNameFor(path location: String, in volumes: [String]) throws -> String {
    var diskName = ""
    var commonPathLength = 0
    let fileManager = FileManager.default
    for volume in volumes {
        let path = "/Volumes/\(volume)"
        let attributes = try fileManager.attributesOfItem(atPath: path)
        
        if let type = attributes[.type] as? FileAttributeType, type == .typeSymbolicLink {
            let destination = try fileManager.destinationOfSymbolicLink(atPath: path)
            if location.starts(with: destination) && destination.count > commonPathLength {
                diskName = volume
                commonPathLength = destination.count
            }
        }
    }
    return diskName
}

var size = winsize()
_ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &size)

var columns = Int(size.ws_col)

func print(entries: [String]) {
    let maxCount = entries.reduce(0, {(result, entry) in entry.count > result ? entry.count : result})
    
    let columnSize = maxCount + 1
    let wordCountByLine = max(columns / columnSize, 1)

    var line = ""
    var index = 0
    for entry in entries {
        let spaces = [Character](repeating: " ", count: columnSize - entry.count)
        line.append(entry)
        line.append(contentsOf: spaces)
        index += 1
        if index % wordCountByLine == 0 {
            print(line)
            line = ""
        }
    }
    if !line.isEmpty {
        print(line)
    }
}

func locationFor(path: String, relativeTo parent: String) -> String {
    if path[path.startIndex] == "/" {
        return path
    } else {
        return "\(parent)/\(path)"
    }
}

var workingDirectory = environmentVariable(named: "PWD")
let currentComputerName = hostname()

var locations = [String]()
var computerName = currentComputerName
var forcedDiskName: String? = nil
var verbose = false
var all = false

var arguments = CommandLine.arguments
arguments.removeFirst()

enum ArgumentType {
    case Location, ComputerName, DiskName
}

func printUsageAndQuit() {
    print("usage: tmls [-alv] [-c ComputerName] [-d DiskName] [-h] [location ...]")
    print("  -a, --all                     Display hidden files.")
    print("  -c, --computer <ComputerName> Name of the computer.")
    print("  -d, --disk <DiskName>         Name of the the time machine disk to use.")
    print("  -l                            Display the results in a single column.")
    print("  -h, --help                    Display this screen.")
    print("  -v, --verbose                 Display computer name and disk name")
    print("                                before listing files.")
    exit(0)
}

var nextArgumentType = ArgumentType.Location
for argument in arguments {
    if argument.first == "-" {
        let second = argument.index(after: argument.startIndex)
        if argument[second] == "-" {
            let third = argument.index(after: second)
            switch String(argument[third...]) {
            case "all":
                all = true
            case "computer":
                nextArgumentType = .ComputerName
            case "disk":
                nextArgumentType = .DiskName
            case "help":
                printUsageAndQuit()
            case "verbose":
                verbose = true
            default:
                break
            }
        }
        else {
            var waitingForNextArgument = false
            
            let modifiers = String(argument[second...])
            if modifiers.count == 1 {
                switch modifiers {
                case "d":
                    nextArgumentType = .DiskName
                    waitingForNextArgument = true
                case "c":
                    nextArgumentType = .ComputerName
                    waitingForNextArgument = true
                default:
                    break
                }
            }
            
            if !waitingForNextArgument {
                for modifier in modifiers {
                    switch modifier {
                    case "a":
                        all = true
                    case "l":
                        columns = 0
                    case "h":
                        printUsageAndQuit()
                    case "v":
                        verbose = true
                    default:
                        break
                    }
                }
            }
        }
    } else {
        switch nextArgumentType {
        case .Location:
            locations.append(locationFor(path: argument, relativeTo: workingDirectory))
        case .ComputerName:
            computerName = argument
        case .DiskName:
            forcedDiskName = argument
        }
        nextArgumentType = .Location
    }
}

if verbose {
    print("Computer Name: \(computerName)")
}

if locations.isEmpty {
    locations.append(workingDirectory)
}

let fileManager = FileManager.default
do {
    let volumes = try fileManager.contentsOfDirectory(atPath: "/Volumes")
    
    for location in locations {
        if locations.count > 1 {
            print("\(location):")
        }
        
        for volume in volumes {
            var thisComputerName = computerName
            if fileManager.isExecutableFile(atPath: "/Volumes/\(volume)/Backups.backupdb") {
                for name in try fileManager.contentsOfDirectory(atPath: "/Volumes/\(volume)/Backups.backupdb") {
                    if name.lowercased() == computerName.lowercased() {
                        thisComputerName = name
                        break
                    }
                }
            }
            let root = "/Volumes/\(volume)/Backups.backupdb/\(thisComputerName)"
            if fileManager.isExecutableFile(atPath: root) {
                print("> \(volume)")
                var lastContent: [String]? = nil
                for date in try fileManager.contentsOfDirectory(atPath: root) {
                    let diskNames: [String]
                    if let forcedDiskName = forcedDiskName {
                        diskNames = [forcedDiskName]
                    } else {
                        diskNames = try fileManager.contentsOfDirectory(atPath: "\(root)/\(date)")
                    }
                    for diskName in diskNames {
                        if verbose {
                            print("Disk Name: \(diskName)")
                        }
                        let path = "\(root)/\(date)/\(diskName)\(location)"
                        var content: [String]? = nil
                        if fileManager.isExecutableFile(atPath: path) {
                            do {
                                var files = try fileManager.contentsOfDirectory(atPath: path)
                                if !all {
                                    files = files.filter({ $0.first != "." })
                                }
                                content = files
                            } catch {
                                print("An error occured while reading \(path): \(error)")
                            }
                        }
                        if let content = content, lastContent == nil || content != lastContent! {
                            print(path)
                            print(entries: content)
                            print()
                            lastContent = content
                        }
                    }
                }
            }
        }
    }
} catch {
    print("An error occured: \(error)")
}
