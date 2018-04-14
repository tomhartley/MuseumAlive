//
//  MANote.swift
//  MuseumAlive
//
//  Created by Tom on 04/04/2018.
//  Copyright © 2018 Yoshihiro Kato. All rights reserved.
//

import Foundation
import FirebaseDatabase
import FirebaseAuth
import FirebaseStorage

class DataConnector {
	private var ref: DatabaseReference!
	private var refHandle: UInt = 0;
	var paintings : [MAPainting] = []
	var users : [String : Bool] = [:]
	var target: AnyObject?
	var selector: Selector?
	
	convenience init () {
		self.init(updateSel: nil, newtarget: nil)
	}
	
	init (updateSel: Selector?, newtarget: AnyObject?) {
		self.target = newtarget
		self.selector = updateSel
		ref = Database.database().reference()
		var firstTime = true
		//first fetch all the paintings
		refHandle = ref.observe(DataEventType.value, with: { (snapshot) in
			self.assignData(snapshot: snapshot)
			if (firstTime == true) {
				firstTime = false
			} else {
				if (self.selector != nil && self.target != nil) {
					_ = self.target!.perform(self.selector)
				}
			}
		})

	}
	
	deinit {
		ref.removeObserver(withHandle: refHandle)
	}
	
	func assignData (snapshot : DataSnapshot) {
		let postDict = snapshot.value as? [String : AnyObject] ?? [:]
		
		for (id, d) in (postDict["users"] as? [String : AnyObject] ?? [:]) {
			let details = d as? [String : AnyObject] ?? [:]
			if let curator = details["curator"] as? Bool {
				users[id]=curator
			}
		}
		
		var newpaintings : [MAPainting] = []
		for (id, d) in (postDict["paintings"] as? [String : AnyObject] ?? [:]) {
			let details = d as? [String : AnyObject] ?? [:]
			if let height = details["height"] as? Float, let width = details["width"] as? Float {
				let newpaint = MAPainting(id: id, width: width, height: height)
				newpaint.artist = details["artist"] as? String
				newpaint.name = details["name"] as? String
				newpaint.year = details["year"] as? String
				
				for (note_id, note_d) in (details["notes"] as? [String : AnyObject] ?? [:]) {
					let note_details = note_d as? [String : AnyObject] ?? [:]
					if 	let x = note_details["x"] as? Float,
						let y = note_details["y"] as? Float,
						let title = note_details["title"] as? String
					{
						let note = MANote(id: note_id, x: x, y: y, title: title, desc: note_details["desc"] as? String)
						note.creator_id = note_details["creator"] as? String
						note.painting_id = id
						if let hasIm = note_details["has_image"] as? Bool {
							note.hasImage = hasIm
						}
						//at this point, if the node is identical to one we already have, just copy it to preserve im & view count
						let oldpaint = self.getPaintingForID(id) //the old painting
						let oldnote = oldpaint?.getNoteForID(note.id)
						if (oldnote == note) {
							newpaint.notes.append(oldnote!)
						} else {
							newpaint.notes.append(note)
						}
						//we have not fetched the image yet (if it exists)
					}
				}
				
				newpaintings.append(newpaint)
			}
		}
		paintings = newpaintings
	}
	
	func addNoteToDB (note: MANote) {
		//do some stuff to add it
		//let's assume that the note has a painting ID attached to it and use that
		
		//should probably add the image as well. Ah hey, next time.
		var willupload = false
		if (note.hasImage) {
			if (note.img == nil) {
				note.hasImage = false
			} else {
				let storage = Storage.storage()
				let imref = storage.reference().child("note_images").child(note.creator_id!).child(note.id + ".jpg")
				var compression = 0.8
				if note.img!.size.width > 1000.0 {
					compression = 0.5
				}
				if let imageData = UIImageJPEGRepresentation(note.img!, CGFloat(compression)) {
					willupload = true
					imref.putData(imageData, metadata: nil, completion: { (metadata, error) in
						if let error = error {
							//couldn't upload, hey ho
							print(error)
							note.hasImage = false
						}
						self.ref.child("paintings").child(note.painting_id!).child("notes").child(note.id).setValue(note.asDict())
					})
				}
			}
			
		}
		if (willupload == false) {
			self.ref.child("paintings").child(note.painting_id!).child("notes").child(note.id).setValue(note.asDict())
		}
	}
	
	func getPaintingForID (_ id: String) -> MAPainting? {
		for i in paintings {
			if (i.id==id) {
				return i
			}
		}
		return nil
	}
	
	func deleteNote (_ note: MANote) {
		if ((Auth.auth().currentUser?.uid != note.creator_id) && (!isCurator())) {
			return
		}
		
		if (note.hasImage) {
			let storage = Storage.storage()
			//remove the image first
			let imref = storage.reference().child("note_images").child(note.creator_id!).child(note.id + ".jpg")
			imref.delete()
		}
		self.ref.child("paintings").child(note.painting_id!).child("notes").child(note.id).removeValue()
		
	}

	func isCurator() -> Bool {
		if let cur_id = Auth.auth().currentUser?.uid {
			if users[cur_id] ?? false == true {
				return true
			} else {
				return false
			}
		} else {
			return false
		}
	}
	
	func downloadImagesForPainting(_ painting : MAPainting) {
		let storage = Storage.storage()
		for i in painting.notes {
			if (i.hasImage && (i.img == nil)) {
				let imref = storage.reference().child("note_images").child(i.creator_id!).child(i.id + ".jpg")
				// Download in memory with a maximum allowed size of 1MB (1 * 1024 * 1024 bytes)
				imref.getData(maxSize: 4 * 1024 * 1024) { data, error in
					if let error = error {
						print(error)
						i.hasImage = false
					} else {
						// Data for "images/island.jpg" is returned
						i.img = UIImage(data: data!)
					}
				}
			}
		}
	}
	
}

class MANote {
	// class definition goes here
	var id : String
	
	var painting_id : String?
	var creator_id : String?
	
	var x : Float
	var y : Float
	
	var title : String
	var desc : String?

	var hasImage : Bool = false
	
	var img : UIImage?
	
	var viewCount : UInt = 0
	
	var editable : Bool {
		if (creator_id != nil) {
			if let curr_user = Auth.auth().currentUser?.uid {
				return creator_id == curr_user;
			}
		}
		return false //if user isn't signed in, or no creator data available, it's not editable
	}

	
	func asDict () -> [String : AnyObject] { //suitable for uploading
		var data : [String : AnyObject] = ["x": x as AnyObject, "y":y as AnyObject, "title":title as AnyObject, "has_image":hasImage as AnyObject]
		if (desc != nil) {
			data["desc"] = desc as AnyObject
		}
		if (creator_id != nil) {
			data["creator"] = creator_id as AnyObject
		}
		return data;
	}
	
	init(id: String, x: Float, y: Float, title: String, desc: String?) { // Constructor
		self.id = id
		self.x = x
		self.y = y
		self.title = title
		self.desc = desc
	}
	
	convenience init(x: Float, y: Float, title: String, desc: String?) {
		let uuid = UUID().uuidString
		self.init(id: uuid, x:x, y:y, title:title, desc:desc)
		self.creator_id = Auth.auth().currentUser?.uid
	}
}

extension MANote: Equatable {
	static func == (lhs: MANote, rhs: MANote) -> Bool {
		return 	lhs.id == rhs.id &&
				lhs.x == rhs.x &&
				lhs.y == rhs.y &&
				lhs.painting_id == rhs.painting_id &&
				lhs.creator_id == rhs.creator_id &&
				lhs.title == rhs.title &&
				lhs.desc == rhs.desc &&
				lhs.hasImage == rhs.hasImage
	}
}


class MAPainting {
	var id : String
	
	var width : Float
	var height : Float
	
	var name : String?
	var artist : String?
	var year : String?
	
	var notes : [MANote] = []
	
	init(id: String, width: Float, height: Float) {
		self.id = id
		self.width = width
		self.height = height
	}
	
	func getNoteForID(_ id : String) -> MANote? {
		for i in notes {
			if (i.id==id) {
				return i
			}
		}
		return nil
	}
	
}

extension MAPainting: Equatable {
	static func == (lhs: MAPainting, rhs: MAPainting) -> Bool {
		return 	lhs.id == rhs.id &&
				lhs.width == rhs.width &&
				lhs.height == rhs.height &&
				lhs.name == rhs.name &&
				lhs.artist == rhs.artist &&
				lhs.year == rhs.year &&
				lhs.notes == rhs.notes
	}
}

