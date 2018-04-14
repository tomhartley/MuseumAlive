//
//  MAButton.swift
//  MuseumAlive
//
//  Created by Tom on 10/04/2018.
//  Copyright © 2018 Yoshihiro Kato. All rights reserved.
//

import Foundation

class BackgroundHighlightedButton: UIButton {
	@IBInspectable var highlightedBackgroundColor :UIColor?
	@IBInspectable var nonHighlightedBackgroundColor :UIColor?
	override var isHighlighted :Bool {
		get {
			return super.isHighlighted
		}
		set {
			if newValue {
				self.backgroundColor = highlightedBackgroundColor
			}
			else {
				self.backgroundColor = nonHighlightedBackgroundColor
			}
			super.isHighlighted = newValue
		}
	}
}

