//
//  RowCopy.swift
//  LocoKit
//
//  Created by Matt Greenfield on 1/05/18.
//

import GRDB

internal class RowCopy: FetchableRecord {

    internal let row: Row

    required init(row: Row) {
        self.row = row.copy()
    }

}
