//
//  Helpers.swift
import Foundation
import CoreBluetooth
import Combine
#if canImport(UIKit)
import UIKit
#endif
import AVFoundation

public class Helpers {
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
	
	public static func CreateBlockCommand(data: [UInt8], blockId: Int, maxBlockSize: Int) -> (ArraySlice<UInt8>, Bool) {
		let start = blockId * maxBlockSize
		var end = (blockId+1) * maxBlockSize
		var bEnd = false
		if end >= data.count {
			end = data.count
			bEnd = true
		}
		let blockData = data[start..<end]
		return (blockData,bEnd)
	}
	
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
	
	public class func isConnectedToInternet() -> Bool {
		true // todo
	}
	
	public static func checkBleAccess(vc: AnyObject, action: @escaping ()->Void) {
		switch CBManager.authorization {
		case .denied:
			// "Denied, request permission from settings"
			if let ui_vc = vc as? UIViewController { presentSettings(ui_vc, msg: NSLocalizedString("Bluetooth access is denied", comment: ""))}
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
	
	public static func checkCameraAccess(vc: AnyObject, action: @escaping ()->Void) {
		switch AVCaptureDevice.authorizationStatus(for: .video) {
		case .denied:
			// "Denied, request permission from settings"
			if let ui_vc = vc as? UIViewController { presentSettings(ui_vc, msg: NSLocalizedString("Camera access is denied", comment: ""))}
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
	
}
