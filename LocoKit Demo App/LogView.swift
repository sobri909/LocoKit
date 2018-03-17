//
//  LogView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import SwiftNotes
import Cartography

class LogView: UIScrollView {

    lazy var label: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.black
        label.font = UIFont(name: "Menlo", size: 8)
        label.numberOfLines = 0
        return label
    }()

    init() {
        super.init(frame: CGRect.zero)
        backgroundColor = .white
        alwaysBounceVertical = true

        when(.logFileUpdated) { _ in
            onMain { self.update() }
        }

        update()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        addSubview(label)
        constrain(label, superview!) { rows, superview in
            rows.top == rows.superview!.top + 10
            rows.bottom == rows.superview!.bottom - 10
            rows.left == rows.superview!.left + 8
            rows.right == rows.superview!.right - 8
            rows.right == superview.right - 8
        }
    }

    func update() {
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        guard let logString = try? String(contentsOf: DebugLog.logFile) else {
            label.text = ""
            return
        }

        label.text = logString
    }
}
