/*
Copyright (c) 2023 European Commission

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//  Helpers.swift
import Foundation
import CoreBluetooth
import Combine
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation

/// Helper methods
public class Helpers {
	/// Returns the number of blocks that dataLength bytes of data can be split into, given a maximum block size of maxBlockSize bytes.
	/// - Parameters:
	///   - dataLength: Length of data to be split
	///   - maxBlockSize: The maximum block size
	/// - Returns: Number of blocks 
	public static func CountNumBlocks(dataLength: Int, maxBlockSize: Int) -> Int {
		let blockSize = maxBlockSize
		var numBlocks = 0
		if dataLength > maxBlockSize {
			numBlocks = dataLength / blockSize;
			if numBlocks * blockSize < dataLength {
				numBlocks += 1
			}
		} else if dataLength > 0 {
			numBlocks = 1
		}
		return numBlocks
	}
	
	/// Creates a block for a given block id from a data object. The block size is limited to maxBlockSize bytes.
	/// - Parameters:
	///   - data: The data object to be sent
	///   - blockId: The id (number) of the block to be sent
	///   - maxBlockSize: The maximum block size
	/// - Returns: (chunk:The data block, bEnd: True if this is the last block, false otherwise)
	public static func CreateBlockCommand(data: Data, blockId: Int, maxBlockSize: Int) -> (Data, Bool) {
		let start = blockId * maxBlockSize
		var end = (blockId+1) * maxBlockSize
		var bEnd = false
		if end >= data.count {
			end = data.count
			bEnd = true
		}
		let chunk = data.subdata(in: start..<end)
		return (chunk,bEnd)
	}
	
	#if os(iOS)
	
	/// Check if BLE access is allowed, and if not, present a dialog that opens settings
	/// - Parameters:
	///   - vc: The view controller that will present the settings
	///   - action: The action to perform
	public static func checkBleAccess(_ vc: UIViewController, action: @escaping ()->Void) {
		switch CBManager.authorization {
		case .denied:
			// "Denied, request permission from settings"
			presentSettings(vc, msg: NSLocalizedString("Bluetooth access is denied", comment: ""))
		case .restricted:
			logger.warning("Restricted, device owner must approve")
		case .allowedAlways:
			// "Authorized, proceed"
			DispatchQueue.main.async { action() }
		case .notDetermined:
			DispatchQueue.main.async { action() }
		@unknown default:
			logger.info("Unknown authorization status")
		}
	}
	
	/// Check if the user has given permission to access the camera. If not, ask them to go to the settings app to give permission.
	/// - Parameters:
	///   - vc:  The view controller that will present the settings
	///   - action: The action to perform
	public static func checkCameraAccess(_ vc: UIViewController, action: @escaping ()->Void) {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .denied:
			// "Denied, request permission from settings"
			presentSettings(vc, msg: NSLocalizedString("Camera access is denied", comment: ""))
		case .restricted:
			logger.warning("Restricted, device owner must approve")
		case .authorized:
			// "Authorized, proceed"
			DispatchQueue.main.async { action() }
		case .notDetermined:
			AVCaptureDevice.requestAccess(for: .video) { success in
				if success {
					DispatchQueue.main.async { action() }
				} else {
					logger.info("Permission denied")
				}
			}
		@unknown default:
			logger.info("Unknown authorization status")
		}
	}
	
	/// Present an alert controller with a message, and two actions, one to cancel, and one to go to the settings page.
	/// - Parameters:
	///   - vc: The view controller that will present the settings
	///   - msg: The message to show
	public static func presentSettings(_ vc: UIViewController, msg: String) {
		let alertController = UIAlertController(title: NSLocalizedString("error", comment: ""), message: msg, preferredStyle: .alert)
		alertController.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .default))
		alertController.addAction(UIAlertAction(title: NSLocalizedString("settings", comment: ""), style: .cancel) { _ in
			if let url = URL(string: UIApplication.openSettingsURLString) {
				UIApplication.shared.open(url, options: [:], completionHandler: { _ in
					// Handle
				})
			}
		})
		vc.present(alertController, animated: true)
	}
	
	/// Finds the top view controller in the view hierarchy of the app. It is used to present a new view controller on top of any existing view controllers.
	public static func getTopViewController(base: UIViewController? = UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController) -> UIViewController? {
		if let nav = base as? UINavigationController {
			return getTopViewController(base: nav.visibleViewController)
		} else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
			return getTopViewController(base: selected)
		} else if let presented = base?.presentedViewController {
			return getTopViewController(base: presented)
		}
		return base
	}
	
	#endif
}
