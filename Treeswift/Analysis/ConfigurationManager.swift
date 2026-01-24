//
//  ConfigurationManager.swift
//  Treeswift
//
//  Manages the list of saved configurations and handles persistence via UserDefaults
//

import Combine
import Foundation
import SwiftUI

@Observable
@MainActor
final class ConfigurationManager {
	private static let configurationsKey = "savedConfigurations"
	private static let currentConfigurationIndexKey = "currentConfigurationIndex"

	var configurations: [PeripheryConfiguration] = []
	private var currentConfigurationIndex: Int = 0

	init() {
		loadConfigurations()
		// If no configurations exist, create a default demo configuration
		if configurations.isEmpty {
			configurations = [PeripheryConfiguration.demo()]
			currentConfigurationIndex = 0
			saveConfigurations()
		}
	}

	// MARK: - Persistence

	private func loadConfigurations() {
		if let data = UserDefaults.standard.data(forKey: Self.configurationsKey),
		   let decoded = try? JSONDecoder().decode([PeripheryConfiguration].self, from: data) {
			configurations = decoded
		}

		currentConfigurationIndex = UserDefaults.standard.integer(forKey: Self.currentConfigurationIndexKey)

		// Validate index
		if currentConfigurationIndex >= configurations.count {
			currentConfigurationIndex = max(0, configurations.count - 1)
		}
	}

	private func saveConfigurations() {
		if let encoded = try? JSONEncoder().encode(configurations) {
			UserDefaults.standard.set(encoded, forKey: Self.configurationsKey)
		}
		UserDefaults.standard.set(currentConfigurationIndex, forKey: Self.currentConfigurationIndexKey)
	}

	// MARK: - Configuration Management

	func addConfiguration(_ config: PeripheryConfiguration) {
		configurations.append(config)
		saveConfigurations()
	}

	func updateConfiguration(at index: Int, with config: PeripheryConfiguration) {
		guard index < configurations.count else { return }
		configurations[index] = config
		saveConfigurations()
	}

	func deleteConfiguration(at index: Int, scanStateManager: ScanStateManager) {
		guard index < configurations.count else { return }
		let configID = configurations[index].id

		// Clean up scan state
		scanStateManager.removeState(for: configID)

		configurations.remove(at: index)

		// Adjust current index if needed
		if currentConfigurationIndex >= configurations.count {
			currentConfigurationIndex = max(0, configurations.count - 1)
		}

		saveConfigurations()
	}

	func moveConfiguration(from source: IndexSet, to destination: Int) {
		configurations.move(fromOffsets: source, toOffset: destination)
		saveConfigurations()
	}
}
