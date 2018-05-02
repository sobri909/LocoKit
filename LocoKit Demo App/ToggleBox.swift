//
//  ToggleBox.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 5/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Anchorage

class ToggleBox: UIView {
    
    let toggle = UISwitch()
    var onChange: (Bool) -> Void

    var disabled: Bool {
        get {
            return toggle.alpha < 1
        }
        set(disable) {
            toggle.isEnabled = !disable
            subviews.forEach { $0.alpha = disable ? 0.45 : 1 }
        }
    }
    
    init(dotColors: [UIColor] = [], text: String, toggleDefault: Bool = true, onChange: @escaping ((Bool) -> Void)) {
        self.onChange = onChange

        super.init(frame: CGRect.zero)
        
        backgroundColor = .white
        
        var lastDot: UIView?
        for color in dotColors {
            let dot = self.dot(color: color)
            let dotWidth = dot.frame.size.width
            addSubview(dot)
            
            dot.centerYAnchor == dot.superview!.centerYAnchor
            dot.heightAnchor == dotWidth
            dot.widthAnchor == dotWidth

            if let lastDot = lastDot {
                dot.leftAnchor == lastDot.rightAnchor - 4
            } else {
                dot.leftAnchor == dot.superview!.leftAnchor + 8
            }
            
            lastDot = dot
        }
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = UIColor(white: 0.1, alpha: 1)
        
        toggle.isOn = toggleDefault
        toggle.addTarget(self, action: #selector(ToggleBox.triggerOnChange), for: .valueChanged)

        addSubview(label)
        addSubview(toggle)
        
        if let lastDot = lastDot {
            label.leftAnchor == lastDot.rightAnchor + 5

        } else {
            label.leftAnchor == label.superview!.leftAnchor + 9
        }
        
        label.topAnchor == label.superview!.topAnchor
        label.bottomAnchor == label.superview!.bottomAnchor
        label.heightAnchor == 44
        
        toggle.centerYAnchor == toggle.superview!.centerYAnchor
        toggle.rightAnchor == toggle.superview!.rightAnchor - 10
        toggle.leftAnchor == label.rightAnchor
    }

    @objc func triggerOnChange() {
        onChange(toggle.isOn)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dot(color: UIColor) -> UIView {
        let dot = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
        
        let shape = CAShapeLayer()
        shape.fillColor = color.cgColor
        shape.path = UIBezierPath(roundedRect: dot.bounds, cornerRadius: 7).cgPath
        shape.strokeColor = UIColor.white.cgColor
        shape.lineWidth = 2
        dot.layer.addSublayer(shape)
        
        return dot
    }
}

