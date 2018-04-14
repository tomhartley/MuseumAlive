//
//  SettingsViewController.swift
//  MuseumAlive
//
//  Created by Tom on 12/04/2018.
//  Copyright © 2018 Yoshihiro Kato. All rights reserved.
//

import UIKit
import FirebaseAuth
import FirebaseAuthUI
import FirebaseGoogleAuthUI

class SettingsViewController: UIViewController, FUIAuthDelegate {

	
	@IBOutlet var signInOutText: UILabel!
	@IBOutlet var signInOut: BackgroundHighlightedButton!
	@IBOutlet var curatorOnly: UISwitch!
	
	var signedIn = false;
	
	override func viewDidLoad() {
        super.viewDidLoad()
		setupText()
		//do stuff
        // Do any additional setup after loading the view.
    }

	override func viewWillAppear(_ animated: Bool) {
		setupText()
	}
	
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
	@IBAction func didTapDone(_ sender: UIBarButtonItem) {
		NotificationCenter.default.post(name: NSNotification.Name(rawValue: "hideSettingsNotification"), object: nil)
		self.dismiss(animated: true, completion: nil)
	}
	
	@IBAction func signInOutTapped(_ sender: Any) {
		if (signedIn) {
			do {
			try Auth.auth().signOut()
			}catch let error {
			print("\(error)")
			}
			setupText()
		} else {
			let authUI = FUIAuth.defaultAuthUI()
			authUI?.delegate = self
			let providers: [FUIAuthProvider] = [
				FUIGoogleAuth(),
				]
			authUI?.providers = providers
			let authViewController = authUI!.authViewController()
			self.present(authViewController, animated: true, completion: nil);
		}
	}
	
	func authUI(_ authUI: FUIAuth, didSignInWith user: User?, error: Error?) {
		setupText()
	}

	
	func setupText() {
		if (Auth.auth().currentUser != nil) {
			//signed in
			signedIn = true
			signInOut.setTitle("Sign Out", for: .normal)
			signInOutText.text = "You are currently signed in as " + (Auth.auth().currentUser!.displayName ?? "user")
		} else {
			signedIn = false
			signInOut.setTitle("Sign In", for: .normal)
			signInOutText.text = "You are currently signed out"
		}
	}
	
	/*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
