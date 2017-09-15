//
//  ToggleBox.swift
//  ArcKit Demo App
//
//  Created by Matt Greenfield on 5/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Cartography

class ToggleBox: UIView {
    
    let toggle = UISwitch()
    
    init(dotColors: [UIColor] = [], text: String, toggleDefault: Bool = true, onChange: @escaping ((Bool) -> Void)) {
        super.init(frame: CGRect.zero)
        
        backgroundColor = .white
        
        var lastDot: UIView?
        for color in dotColors {
            let dot = self.dot(color: color)
            let dotWidth = dot.frame.size.width
            addSubview(dot)
            
            constrain(dot) { dot in
                dot.centerY == dot.superview!.centerY
                dot.height == dotWidth
                dot.width == dotWidth
            }
            
            if let lastDot = lastDot {
                constrain(dot, lastDot) { dot, lastDot in
                    dot.left == lastDot.right - 4
                }
            } else {
                constrain(dot) { dot in
                    dot.left == dot.superview!.left + 8
                }
            }
            
            lastDot = dot
        }
        
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = UIColor(white: 0.1, alpha: 1)
        
        toggle.isOn = toggleDefault
        toggle.onControlEvent(.valueChanged) { [unowned self] in
            onChange(self.toggle.isOn)
        }
        
        addSubview(label)
        addSubview(toggle)
        
        if let lastDot = lastDot {
            constrain(lastDot, label) { dot, label in
                label.left == dot.right + 5
            }
            
        } else {
            constrain(label, toggle) { label, toggle in
                label.left == label.superview!.left + 9
            }
        }
        
        constrain(label, toggle) { label, toggle in
            label.top == label.superview!.top
            label.bottom == label.superview!.bottom
            label.height == 44
            
            toggle.centerY == toggle.superview!.centerY
            toggle.right == toggle.superview!.right - 10
            toggle.left == label.right
        }
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

