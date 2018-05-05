//
//  LogView.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 12/12/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import LocoKit
import Anchorage
import SwiftNotes

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
        label.topAnchor == label.superview!.topAnchor + 10
        label.bottomAnchor == label.superview!.bottomAnchor - 10
        label.leftAnchor == label.superview!.leftAnchor + 8
        label.rightAnchor == label.superview!.rightAnchor - 8
        label.rightAnchor == superview!.rightAnchor - 8
    }

    func update() {
        guard UIApplication.shared.applicationState == .active else { return }

        guard let logString = try? String(contentsOf: DebugLog.logFile) else {
            label.text = ""
            return
        }

        label.text = logString
    }
}
