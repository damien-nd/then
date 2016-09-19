//
//  ViewController.swift
//  testThen
//
//  Created by Sacha Durand Saint Omer on 06/02/16.
//  Copyright © 2016 s4cha. All rights reserved.
//

import UIKit
import then

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        fetchUserId().then(displayUserId).onError(showErrorPopup).finally(reload)
    }
    
    func displayUserId(id: Int) { print("Got user id \(id)") }
    func showErrorPopup(e: ErrorType) { print("An error occured \(e)") }
    func reload() { print("reloading the view") }
}

func fetchUserId() -> Promise<Int> {
    return Promise { resolve, reject in
        print("fetching user Id ...")
        wait { resolve(result: 1234) }
    }
}

func wait(callback:()->()) {
    let delay = 3 * Double(NSEC_PER_SEC)
    let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay))
    dispatch_after(time, dispatch_get_main_queue()) {
        callback()
    }
}
