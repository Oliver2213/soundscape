//
//  BeaconTitleContentViewDelegate.swift
//  Openscape
//
//  Copyright (c) Microsoft Corporation.
//  Licensed under the MIT License.
//

import Foundation

protocol BeaconTitleContentViewDelegate: AnyObject {
    func onAccessibilityElementDidLoseFocus()
    func onAccessibilityActivate()
}
