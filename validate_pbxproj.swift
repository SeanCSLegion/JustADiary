#!/usr/bin/env swift
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("usage: validate_pbxproj.swift <path>")
    exit(2)
}
let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
do {
    _ = try PropertyListSerialization.propertyList(from: data, format: nil)
    print("PARSE OK")
} catch {
    print("ERROR: \(error)")
    exit(1)
}
