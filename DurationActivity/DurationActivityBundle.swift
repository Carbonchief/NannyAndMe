//
//  DurationActivityBundle.swift
//  DurationActivity
//
//  Created by Luan van der Walt on 2025/10/11.
//

import WidgetKit
import SwiftUI

@main
struct DurationActivityBundle: WidgetBundle {
    var body: some Widget {
        DurationActivity()
        DurationActivityControl()
        DurationActivityLiveActivity()
    }
}
