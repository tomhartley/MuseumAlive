//
//  ViewController.swift
//  VuforiaSample
//
//  Created by Yoshihiro Kato on 2016/07/02.
//  Copyright © 2016年 Yoshihiro Kato. All rights reserved.
//

import UIKit
import SpriteKit

class ViewController: UIViewController {
    
	let vuforiaLicenseKey = "***REMOVED***"
	let vuforiaDataSetFile = "MA_device.xml"
	//let vuforiaDataSetFile = "StonesAndChips.xml"

    var vuforiaManager: VuforiaManager? = nil
    
    let boxMaterial = SCNMaterial()
    fileprivate var lastSceneName: String? = nil
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        prepare()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        do {
            try vuforiaManager?.stop()
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
            self.view = manager.eaglView
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
        guard let userInfo = userInfo else {
            print("default scene")
            return createStonesScene(with: view)
        }
		let sceneName = userInfo["scene"] as? String;
        if sceneName == "stones" {
            print("stones scene")
            return createStonesScene(with: view)
        } else if sceneName == "chips" {
            print("chips scene")
            return createChipsScene(with: view)
		} else if sceneName == "Ambassadors_A0" {
			print("ambassadors scene")
			return createAmbassadorsScene(with: view)
		} else {
			print("default scene")
			return createStonesScene(with: view)
		}
    }
    
    fileprivate func createStonesScene(with view: VuforiaEAGLView) -> SCNScene {
        let scene = SCNScene()
        
		boxMaterial.transparency = 1.0;
        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor.lightGray
        lightNode.position = SCNVector3(x:0, y:10, z:10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        let planeNode = SCNNode()
        planeNode.name = "plane"
        planeNode.geometry = SCNPlane(width: 247.0*view.objectScale, height: 173.0*view.objectScale)
        planeNode.position = SCNVector3Make(0, 0, -1)
		//let newview = UIView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
		//newview.backgroundColor = UIColor.purple
        let planeMaterial = SCNMaterial()
		//planeMaterial.diffuse.contents = newview
        planeMaterial.diffuse.contents = UIColor.green
        planeMaterial.transparency = 0.6
        planeNode.geometry?.firstMaterial = planeMaterial
        scene.rootNode.addChildNode(planeNode)
        
        let boxNode = SCNNode()
        boxNode.name = "box"
        boxNode.geometry = SCNBox(width:1, height:1, length:1, chamferRadius:0.0)
		boxMaterial.diffuse.contents = UIColor.blue
        boxNode.geometry?.firstMaterial = boxMaterial
        scene.rootNode.addChildNode(boxNode)
        
        return scene
    }
    
    fileprivate func createChipsScene(with view: VuforiaEAGLView) -> SCNScene {
        let scene = SCNScene()
        
        boxMaterial.diffuse.contents = UIColor.lightGray
        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.color = UIColor.lightGray
        lightNode.position = SCNVector3(x:0, y:10, z:10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        let planeNode = SCNNode()
        planeNode.name = "plane"
        planeNode.geometry = SCNPlane(width: 247.0*view.objectScale, height: 173.0*view.objectScale)
        planeNode.position = SCNVector3Make(0, 0, -1)
        let planeMaterial = SCNMaterial()
        planeMaterial.diffuse.contents = UIColor.red
        planeMaterial.transparency = 0.6
        planeNode.geometry?.firstMaterial = planeMaterial
        scene.rootNode.addChildNode(planeNode)
        
        let boxNode = SCNNode()
        boxNode.name = "box"
        boxNode.geometry = SCNBox(width:1, height:1, length:1, chamferRadius:0.0)
		boxMaterial.diffuse.contents = UIColor.red
        boxNode.geometry?.firstMaterial = boxMaterial
        scene.rootNode.addChildNode(boxNode)
        
        return scene
    }
	
	fileprivate func createAmbassadorsScene(with view: VuforiaEAGLView) -> SCNScene {
		let scene = SCNScene()
		let planeNode = SCNNode()
		planeNode.name = "plane"
		//does this make sth the size of the image?
		//let imw = 0950.0 //height
		//let imh = 0936.146 //width
		//If you want something to be 1m tall, height = 1000*view.objectScale
		//let's do all the maths in cm, then scale later
		let planeGeometry = SCNPlane(width: 160*view.objectScale, height: 200*view.objectScale)
		planeGeometry.cornerRadius = 20.0*view.objectScale
		planeNode.geometry = planeGeometry
		planeNode.position = SCNVector3Make(0, 0, Float(500.0*view.objectScale)) //50cm away
 		let planeMaterial = SCNMaterial()
		planeMaterial.diffuse.contents = UIColor(white: 0.91, alpha: 1.0)
		planeMaterial.transparency = 0.72
		
		planeNode.geometry?.firstMaterial = planeMaterial
		scene.rootNode.addChildNode(planeNode)
		
		let textNode = SCNNode()
		let text = SCNText(string: "The brooch on Dinteville’s cap contains a tiny skull", extrusionDepth: 0.0)
		text.font = UIFont(name: "Helvetica", size: 27)!
		textNode.geometry = text;
		textNode.scale = SCNVector3Make(Float(1*view.objectScale), Float(1*view.objectScale), Float(1*view.objectScale))
		text.containerFrame = CGRect(x: -80, y: -100, width: 160.0, height: 200)
		text.truncationMode = kCATruncationNone
		text.isWrapped = true
		text.alignmentMode = kCAAlignmentLeft
		
		let (min, max) = textNode.boundingBox
		let dx = min.x + 0.5 * (max.x - min.x)
		let dy = min.y + 0.5 * (max.y - min.y)
		let dz = min.z + 0.5 * (max.z - min.z)
		textNode.pivot = SCNMatrix4MakeTranslation(dx, dy, dz)

		
		textNode.position=SCNVector3Make(0.0, 0.0, 0.01)
		let textMat = SCNMaterial()
		textMat.diffuse.contents = UIColor(white: 0.0, alpha:1.0)
		textNode.geometry?.firstMaterial = textMat
		
		planeNode.addChildNode(textNode)
		
		let line = SCNNode()
		line.geometry = SCNGeometry.lineFrom(vector: SCNVector3Make(Float(300.0*view.objectScale), Float(-300.0*view.objectScale), 0),toVector: SCNVector3Make(0, Float(-100*view.objectScale), Float(500.0*view.objectScale)))
		let lineMat = SCNMaterial()
		lineMat.diffuse.contents = UIColor(white: 0.91, alpha:0.72)
		line.geometry?.firstMaterial = lineMat
		scene.rootNode.addChildNode(line)
		
		let overlay = SKScene(size: CGSize(width: 640, height: 1136))
		//overlay.blendMode = SKBlendMode.replace
		overlay.backgroundColor = UIColor.clear
		
		let rect = SKShapeNode(rectOf: CGSize(width: 700, height: 500))
		rect.fillColor = SKColor.purple
		rect.position = CGPoint(x: 0, y: 0)
		rect.blendMode = SKBlendMode.replace

		let rect2 = SKShapeNode(rectOf: CGSize(width: 200, height: 100))
		rect2.fillColor = SKColor.green
		rect2.position = CGPoint(x: 700, y: 500)
		rect2.blendMode = SKBlendMode.replace

		
		overlay.scaleMode = .fill
		overlay.addChild(rect)
		//overlay.addChild(rect2)

		view.overlayScene = overlay
		
		//0.950000 0.936146
		return scene
	}
	
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchDownNode node: SCNNode!) {
        print("touch down \(node.name ?? "")\n")
        boxMaterial.transparency = 0.6
    }
    
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchUp node: SCNNode!) {
        print("touch up \(node.name ?? "")\n")
        boxMaterial.transparency = 1.0
    }
    
    func vuforiaEAGLView(_ view: VuforiaEAGLView!, didTouchCancel node: SCNNode!) {
        print("touch cancel \(node.name ?? "")\n")
        boxMaterial.transparency = 1.0
    }
}

