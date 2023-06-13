//
//  AlertFactory.swift
//  Openscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation

protocol AlertFactory {
    typealias ActionHandler = (UIAlertAction) -> Void
}
