//
//  ViewController.swift
//  VuforiaSample
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

import UIKit
import SpriteKit
import FirebaseAuthUI
import FirebaseGoogleAuthUI
import SwiftMessages
import Presentr
import ChameleonFramework

class ViewController: UIViewController, FUIAuthDelegate {
	
	@IBOutlet weak var deleteButton: BackgroundHighlightedButton!
	
	@IBOutlet weak var tapView: UIView!
	
	
	@IBOutlet var blurViewCentered: NSLayoutConstraint!

	@IBOutlet var blurViewOffscreen: NSLayoutConstraint!
	
	@IBOutlet weak var blurView: UIVisualEffectView!
	@IBOutlet weak var titleLabel: UILabel!
	@IBOutlet weak var descLabel: UILabel!
	@IBOutlet weak var imView: ScaleAspectFitImageView!
	@IBOutlet weak var addButton: UIButton!
	@IBOutlet weak var addDescription: UILabel!
	@IBOutlet weak var buttonWidth: NSLayoutConstraint!
	
	var isAdding = false
	var savedPoint : SCNVector3? = nil
	
	let vuforiaLicenseKey = "ADD_KEY_HERE"
	
	let vuforiaDataSetFile = "MA_device.xml"
	//let vuforiaDataSetFile = "StonesAndChips.xml"

    var vuforiaManager: VuforiaManager? = nil
	var picNode: SCNNode = SCNNode()
	
	var dataConn : DataConnector?
	var currentPainting: MAPainting? = nil
	var currentNote: MANote? = nil
	fileprivate var lastSceneName: String? = nil

	var nc: UINavigationController? = nil
	let sc = SettingsViewController()
	var onlyCurator = false
	
	let presenter = Presentr(presentationType: .popup)
	
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
	
	@IBAction func deleteNote(_ sender: Any) {
		if (self.currentNote != nil) {
			dataConn?.deleteNote(self.currentNote!)
		}
		self.popupTapped(sender)
	}
	
	@IBAction func showSettings(_ sender: Any) {
		presenter.dismissOnTap = false;
		NotificationCenter.default.addObserver(self, selector: #selector(self.hideSettings), name:NSNotification.Name(rawValue: "hideSettingsNotification"), object: nil)
		customPresentViewController(presenter, viewController: sc, animated: true, completion: nil)
	}
	
	func hideSettings() {
		onlyCurator = sc.curatorOnly.isOn
		vuforiaManager?.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : currentPainting!.id])
	}
	
	func updateData() {
		//do something
		if (currentPainting != nil) {
			let newPainting = dataConn?.getPaintingForID(currentPainting!.id)
			if (newPainting != nil) {
				if (newPainting != currentPainting) {
					currentPainting = newPainting
					vuforiaManager?.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : newPainting!.id])
					dataConn?.downloadImagesForPainting(newPainting!)
				} else {
					//They're the same
				}
			} else { //the painting has been removed? don't expect this to happen
				vuforiaManager?.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : "nullpainting"])
			}
  		}
	}
	
	func authUI(_ authUI: FUIAuth, didSignInWith user: User?, error: Error?) {
		enterAddMode(attemptLogin: false) //give us the adds!
	}

	@IBAction func addButtonPressed(_ sender: Any) {
		if (!isAdding) {
			enterAddMode(attemptLogin: true)
		} else {
			leaveAddMode()
		}
	}
	
	func enterAddMode(attemptLogin: Bool) {
		if (isAdding) {
			return //we're already adding
		}
		if (Auth.auth().currentUser != nil) {
			//we're signed in!
			addButton.setTitle("Cancel", for: .normal)
			isAdding=true
			UIView.animate(withDuration: 0.15, delay: 0.0, options:.curveEaseInOut, animations: {
				self.buttonWidth.constant = 80
				self.addDescription.alpha = 1.0
				self.view.layoutIfNeeded()
			})
		} else if (attemptLogin == true) {
			//Present Sign In UI
			let authUI = FUIAuth.defaultAuthUI()
			authUI?.delegate = self
			let providers: [FUIAuthProvider] = [
				FUIGoogleAuth(),
				]
			authUI?.providers = providers
			let authViewController = authUI!.authViewController()
			self.present(authViewController, animated: true, completion: nil);
		}
		//if not, we just don't enter add mode, prevents us getting into loops
	}
	
	func leaveAddMode() {
		if (!isAdding) {
			return //we aren't adding, how can we leave
		}
		addButton.setTitle("Add", for: .normal)
		isAdding = false
		UIView.animate(withDuration: 0.15, delay: 0.0, options:.curveEaseInOut, animations: {
			self.buttonWidth.constant = 51
			self.addDescription.alpha = 0.0
			self.view.layoutIfNeeded()
		})
	}
	
	override func viewDidLoad() {
        super.viewDidLoad()
		let appDelegate = UIApplication.shared.delegate as! AppDelegate
		dataConn = appDelegate.dataConn
		dataConn!.target = self as AnyObject
		dataConn!.selector = #selector(updateData)
		//dataConn = DataConnector(updateSel: #selector(updateData), target: self as AnyObject)
        prepare()
    }

	@IBAction func popupTapped(_ sender: Any) {
		//hide popup
		self.currentNote = nil
		self.tapView.isHidden = true;
		UIView.animate(withDuration: 0.22, delay: 0.0, options:.curveLinear, animations: {
			self.blurViewCentered.isActive=false
			self.blurViewOffscreen.isActive=true
			self.addButton.isHidden = false
			self.addButton.alpha = 1.0
			self.view.layoutIfNeeded()
		}, completion: { (finished: Bool) in
			self.blurView.isHidden = true
		})
	}
	
	override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
		do {
			try vuforiaManager?.resume()
		}catch let error {
			print("\(error)")
		}

    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        do {
            try vuforiaManager?.pause()
        }catch let error {
            print("\(error)")
        }
    }
}


private extension ViewController {
    func prepare() {
        vuforiaManager = VuforiaManager(licenseKey: vuforiaLicenseKey, dataSetFile: vuforiaDataSetFile)
        if let manager = vuforiaManager {
            manager.delegate = self
            manager.eaglView.sceneSource = self
            manager.eaglView.delegate = self
			manager.eaglView.setupRenderer()
			manager.eaglView.frame = CGRect(origin: CGPoint.zero, size: self.view.bounds.size)
			self.view.insertSubview(manager.eaglView, at: 0)
        }
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(didRecieveWillResignActiveNotification),
                                       name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        
        notificationCenter.addObserver(self, selector: #selector(didRecieveDidBecomeActiveNotification),
                                       name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        
        vuforiaManager?.prepare(with: .portrait)
		
    }
    
    func pause() {
        do {
            try vuforiaManager?.pause()
        }catch let error {
            print("\(error)")
        }
    }
    
    func resume() {
        do {
            try vuforiaManager?.resume()
        }catch let error {
            print("\(error)")
        }
    }
}

extension ViewController {
    func didRecieveWillResignActiveNotification(_ notification: Notification) {
        pause()
    }
    
    func didRecieveDidBecomeActiveNotification(_ notification: Notification) {
        resume()
    }
}

extension ViewController: VuforiaManagerDelegate {
    func vuforiaManagerDidFinishPreparing(_ manager: VuforiaManager!) {
        print("did finish preparing\n")

        do {
            try vuforiaManager?.start()
            vuforiaManager?.setContinuousAutofocusEnabled(true)
			vuforiaManager?.setExtendedTrackingEnabled(false);
        }catch let error {
            print("\(error)")
        }
    }
    
    func vuforiaManager(_ manager: VuforiaManager!, didFailToPreparingWithError error: Error!) {
        print("did faid to preparing \(error)\n")
    }
    
    func vuforiaManager(_ manager: VuforiaManager!, didUpdateWith state: VuforiaState!) {
        for index in 0 ..< state.numberOfTrackableResults {
            let result = state.trackableResult(at: index)
            let trackerableName = result?.trackable.name
            //print("\(trackerableName)")
            if trackerableName != lastSceneName {
				manager.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : trackerableName!])
				lastSceneName = trackerableName;
            }
		}
    }
}

extension SCNGeometry {
	class func lineFrom(vector vector1: SCNVector3, toVector vector2: SCNVector3) -> SCNGeometry {
		let indices: [Int32] = [0, 1]
		
		let source = SCNGeometrySource(vertices: [vector1, vector2], count: 2)
		let element = SCNGeometryElement(indices: indices, primitiveType: .line)
		
		return SCNGeometry(sources: [source], elements: [element])
	}
}

extension ViewController: VuforiaEAGLViewSceneSource, VuforiaEAGLViewDelegate {
    
    func scene(for view: VuforiaEAGLView!, userInfo: [String : Any]?) -> SCNScene! {
		let defaultScene = SCNScene()
        guard let userInfo = userInfo else {
            print("default scene")
            return defaultScene
        }
		if let sceneName = userInfo["scene"] as? String {
			currentPainting = dataConn?.getPaintingForID(sceneName)
			
			if (currentPainting != nil) {
				dataConn?.downloadImagesForPainting(currentPainting!)
				return createPaintingScene(with: view)
			}
		}
		
		return defaultScene
    }
	
	fileprivate func createPaintingScene(with view: VuforiaEAGLView) -> SCNScene {
		picNode = SCNNode()
		let scene = SCNScene()
		if (currentPainting == nil) {
			return scene
		}

		
		let planeNode = SCNNode()
		planeNode.name = "hitplane"
		let planeGeometry = SCNPlane(width: CGFloat(currentPainting!.width*1000), height: CGFloat(currentPainting!.height*1000))
		planeNode.geometry = planeGeometry
		planeNode.position = SCNVector3Make(0, 0, 0) //short distance away so it's in front at least -- 0,0 x-y is the middle of the painting
		let planeMaterial = SCNMaterial()
		//planeMaterial.diffuse.contents = UIColor.white
		planeMaterial.transparency = 0.0
		
		planeNode.geometry?.firstMaterial = planeMaterial
		picNode.addChildNode(planeNode)
		
		picNode.scale = SCNVector3Make(Float(view.objectScale),Float(view.objectScale),Float(view.objectScale))
		
		for note in currentPainting!.notes {
			var imname = "blue_pin.png"
			var isNormalNote = true;
			if (Auth.auth().currentUser?.uid == note.creator_id) {
				imname = "red_pin.png"
				isNormalNote = false;
			} else if (note.viewCount>0) {
				imname = "noshadow_pin.png"
			} else if let creator=note.creator_id {
				if (dataConn?.users[creator] ?? false == true) {
					imname = "yellow_pin.png"
					isNormalNote = false
				}
			}
			if (isNormalNote && onlyCurator) {
				continue
			}
			
			var im = UIImage(named: imname)
			im = im?.withRenderingMode(.alwaysTemplate)
			
			let markerNode = SCNNode()
			markerNode.name=note.id
			
			let markerGeo = SCNPlane(width:im!.size.width/3.5, height:im!.size.height/3.5)
			markerNode.eulerAngles = SCNVector3Make(GLKMathDegreesToRadians(0), 0.0, GLKMathDegreesToRadians(Float(note.id.hashValue)))
			let markerMat = SCNMaterial()
			markerMat.diffuse.contents = im
			markerGeo.firstMaterial = markerMat
			markerNode.geometry = markerGeo
			markerNode.pivot = SCNMatrix4MakeTranslation(0, Float(-markerGeo.height/2), 0.0) //move the pivot to the point
			markerNode.position = SCNVector3Make(note.x, note.y, 0.001) //so it's in front of the hitplane
			
			picNode.addChildNode(markerNode)
		}
		
		scene.rootNode.addChildNode(picNode)
		
		return scene
	}
	
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchDown res: SCNHitTestResult!) {
        print("touch down \(res.node.name ?? "")\n")
    }
	
	func doneVC() {//copy contents out of it
		let fc : FormController? = nc?.visibleViewController as? FormController
		let vals = fc?.form.values()
		
		if let title = vals?["title"] as? String,
			let desc = vals?["desc"] as? String {
			if (title != title.censored() || desc != desc.censored()) {
				let view = MessageView.viewFromNib(layout: .messageView)
				view.configureTheme(.error)
				view.configureContent(title: "Error adding note", body: "Please remove profanity from your note before uploading")
				SwiftMessages.show(view: view)
				return
			}
		}
		
		self.nc?.dismiss(animated: true, completion: nil)
		
		if let title = vals?["title"] as? String,
		    let point = savedPoint {
			let desc = vals?["desc"] as? String
			let newNote = MANote(x: point.x, y: point.y, title: title, desc: desc)
			if let im = vals?["image"] as? UIImage {
				newNote.hasImage = true
				newNote.img = im
			} else {
				newNote.hasImage = false
			}
			newNote.creator_id = Auth.auth().currentUser?.uid
			newNote.painting_id = currentPainting?.id
			dataConn?.addNoteToDB(note: newNote)
		}
	}
	
	func cancelVC() {//ignore its contents
		self.nc?.dismiss(animated: true, completion: nil)
	}

	func presentNote(note : MANote) {
		titleLabel.text = note.title
		descLabel.text = note.desc
		imView.image = note.img
		self.blurView.isHidden = false
		self.view.layoutIfNeeded()
		self.leaveAddMode()
		self.tapView.isHidden = false
		tapView.superview?.bringSubview(toFront: tapView)
		tapView.superview?.bringSubview(toFront: blurView) //blur view in front with tap view behind
		if (note.creator_id == Auth.auth().currentUser?.uid || dataConn!.isCurator()) {
			deleteButton.isHidden = false
		} else {
			deleteButton.isHidden = true
		}
		self.currentNote = note
		note.viewCount+=1
		vuforiaManager?.eaglView.setNeedsChangeSceneWithUserInfo(["scene" : currentPainting!.id])
		UIView.animate(withDuration: 0.22, delay: 0.0, options:.curveLinear, animations: {
			self.blurViewCentered.isActive=true
			self.blurViewOffscreen.isActive=false
			self.addButton.alpha = 0.0
			self.view.layoutIfNeeded()
		} , completion: { (finished: Bool) in
			self.addButton.isHidden = true
		})
	}
	
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchUp res: SCNHitTestResult!) {
        //print("touch up \(res.node.name ?? "")\n")
		
		let nodename = res.node.name ?? "";
		
		if (nodename=="hitplane") {
			if (!isAdding) { //if we aren't adding new markers
				return
			}
			
			savedPoint = res.localCoordinates
			
			let fc = FormController()
			nc = UINavigationController(rootViewController: fc)
			let doneBut = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.doneVC))
			doneBut.title = "Share"
			//doneBut.tintColor = UIColor.white
			let cancelBut = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelVC))
			//cancelBut.tintColor = UIColor.white
			fc.navigationItem.rightBarButtonItem = doneBut
			fc.navigationItem.leftBarButtonItem = cancelBut
			fc.navigationItem.title = "Add new note"
			customPresentViewController(presenter, viewController: nc!, animated: true, completion: nil)
			
			//self.present(nc!, animated: true, completion: nil)
		} else {
			if let note = self.currentPainting?.getNoteForID(nodename) {
				presentNote(note: note)
			}
		}
    }
    
	func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchCancel node: SCNNode!) {
        print("touch cancel \(node.name ?? "")\n")
    }
}

