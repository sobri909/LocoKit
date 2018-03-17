//
//  UIStackView.helpers.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 5/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Cartography

extension UIStackView {
    
    func addUnderline() {
        let underline = UIView()
        underline.backgroundColor = UIColor(white: 0.85, alpha: 1)
        addArrangedSubview(underline)
        
        constrain(underline) { underline in
            underline.height == 0.5
        }
    }
    
    func addGap(height: CGFloat) {
        let gap = UIView()
        gap.backgroundColor = .white
        addArrangedSubview(gap)
        
        constrain(gap) { gap in
            gap.height == height
        }
    }

    func addHeading(title: String, alignment: NSTextAlignment = .left) {
        let header = UILabel()
        header.backgroundColor = .white
        header.font = UIFont.preferredFont(forTextStyle: .headline)
        header.textAlignment = alignment
        header.text = title
        addArrangedSubview(header)
    }
    
    func addSubheading(title: String, alignment: NSTextAlignment = .left, color: UIColor = .black) {
        let header = UILabel()
        header.backgroundColor = .white
        header.font = UIFont.preferredFont(forTextStyle: .subheadline)
        header.textAlignment = alignment
        header.textColor = color
        header.text = title
        addArrangedSubview(header)
    }
    
    func addRow(views: [UIView]) {
        let row = UIStackView()
        row.distribution = .fillEqually
        row.spacing = 0.5
        
        for view in views {
            row.addArrangedSubview(view)
        }
        
        addArrangedSubview(row)
    }
    
    @discardableResult func addRow(leftText: String? = nil, rightText: String? = nil, background: UIColor = .white) -> UIStackView {
        let leftLabel = UILabel()
        leftLabel.text = leftText
        leftLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        leftLabel.textColor = UIColor(white: 0.1, alpha: 1)
        leftLabel.backgroundColor = background
        
        let rightLabel = UILabel()
        rightLabel.text = rightText
        rightLabel.textAlignment = .right
        rightLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        rightLabel.textColor = UIColor(white: 0.1, alpha: 1)
        rightLabel.backgroundColor = background
        
        let leftPad = UIView()
        leftPad.backgroundColor = background
        
        let rightPad = UIView()
        rightPad.backgroundColor = background
        
        let row = UIStackView()
        row.addArrangedSubview(leftPad)
        row.addArrangedSubview(leftLabel)
        row.addArrangedSubview(rightLabel)
        row.addArrangedSubview(rightPad)
        addArrangedSubview(row)
        
        constrain(row, leftPad, rightPad) { row, leftPad, rightPad in
            leftPad.width == 8
            rightPad.width == 8
            row.height == 20
        }
        
        return row
    }
}
