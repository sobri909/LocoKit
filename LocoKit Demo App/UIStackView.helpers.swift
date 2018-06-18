//
//  UIStackView.helpers.swift
//  LocoKit Demo App
//
//  Created by Matt Greenfield on 5/08/17.
//  Copyright © 2017 Big Paua. All rights reserved.
//

import Anchorage

extension UIStackView {
    
    func addUnderline() {
        let underline = UIView()
        underline.backgroundColor = UIColor(white: 0.85, alpha: 1)
        addArrangedSubview(underline)
        underline.heightAnchor == 1.0 / UIScreen.main.scale
    }
    
    func addGap(height: CGFloat) {
        let gap = UIView()
        gap.backgroundColor = .white
        addArrangedSubview(gap)
        gap.heightAnchor == height
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
        views.forEach { row.addArrangedSubview($0) }
        addArrangedSubview(row)
    }
    
    @discardableResult func addRow(leftText: String? = nil, rightText: String? = nil,
                                   color: UIColor = UIColor(white: 0.1, alpha: 1),
                                   background: UIColor = .white) -> UIStackView {
        let leftLabel = UILabel()
        leftLabel.text = leftText
        leftLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        leftLabel.textColor = color
        leftLabel.backgroundColor = background
        
        let rightLabel = UILabel()
        rightLabel.text = rightText
        rightLabel.textAlignment = .right
        rightLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        rightLabel.textColor = color
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

        leftPad.widthAnchor == 8
        rightPad.widthAnchor == 8
        row.heightAnchor == 20
        
        return row
    }
}
