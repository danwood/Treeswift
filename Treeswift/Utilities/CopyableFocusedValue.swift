//
//  CopyableFocusedValue.swift
//  Treeswift
//
//  FocusedValue extensions for copyable text and menu title
//

import SwiftUI

struct CopyableTextKey: FocusedValueKey {
	typealias Value = String
}

struct CopyMenuTitleKey: FocusedValueKey {
	typealias Value = String
}

extension FocusedValues {
	var copyableText: CopyableTextKey.Value? {
		get { self[CopyableTextKey.self] }
		set { self[CopyableTextKey.self] = newValue }
	}

	var copyMenuTitle: CopyMenuTitleKey.Value? {
		get { self[CopyMenuTitleKey.self] }
		set { self[CopyMenuTitleKey.self] = newValue }
	}
}
