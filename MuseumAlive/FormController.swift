//
//  FormController.swift
//  MuseumAlive
//
//  Created by Tom on 04/04/2018.
//  Copyright © 2018 Yoshihiro Kato. All rights reserved.
//

import ImageRow
import Eureka

class FormController: FormViewController {
	
	fileprivate func enableDone() {
		let titleRow : TextRow? = form.rowBy(tag: "title")
		let descRow :TextAreaRow? = form.rowBy(tag: "desc")
		if ((titleRow?.value ?? "") != "" && (descRow?.value ?? "") != "") {
			self.navigationItem.rightBarButtonItem?.isEnabled=true
		} else {
			self.navigationItem.rightBarButtonItem?.isEnabled=false
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		form +++
			Section()
			<<< TextRow() {
				$0.title = "Title"
				$0.tag = "title"
				$0.placeholder = "A brief title for the note"
				$0.cell.titleLabel?.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.headline)
				} .onChange { row in
					self.enableDone()
			}
			+++ Section ("Description")
			<<< TextAreaRow() {
				$0.tag = "desc"
				$0.placeholder = "A longer description of the interesting features of this area of the artwork"
				} .onChange { row in
					self.enableDone()
			}
			+++ Section (footer: "Optionally include an image to add detail to your note")
			<<< ImageRow() {
				$0.title = "Image"
				$0.tag = "image"
				$0.sourceTypes = [.PhotoLibrary]
				$0.allowEditor = true
				$0.useEditedImage = true
				$0.clearAction = .yes(style: .default)
				$0.cell.textLabel?.font = UIFont.preferredFont(forTextStyle: UIFontTextStyle.headline)
		}
		
		enableDone()
	}
}

