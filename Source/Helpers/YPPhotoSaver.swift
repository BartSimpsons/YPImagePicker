//
//  YPPhotoSaver.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 10/11/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit
import Photos

public class YPPhotoSaver {
    class func trySaveImageAndWait(_ image: UIImage, inAlbumNamed: String, completion: @escaping ((PHAssetChangeRequest?) -> Void)) {
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            if let album = album(named: inAlbumNamed) {
                saveImageAndWait(image, toAlbum: album) { (assetChangeRequest) in
                    completion(assetChangeRequest)
                }
            } else {
                createAlbum(withName: inAlbumNamed) {
                    if let album = album(named: inAlbumNamed) {
                        saveImageAndWait(image, toAlbum: album, completion: completion)
                    }
                }
            }
        }
    }
    
    fileprivate class func saveImageAndWait(_ image: UIImage, toAlbum album: PHAssetCollection,  completion: @escaping ((PHAssetChangeRequest?) -> Void)) {
        do {
            try PHPhotoLibrary.shared().performChangesAndWait({
                let changeRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
                let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
                let enumeration: NSArray = [changeRequest.placeholderForCreatedAsset!]
                albumChangeRequest?.addAssets(enumeration)

                completion(changeRequest)
            })
        }
        catch let error {
            print("saveImage: there was a problem: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    /// 原代码
    class func trySaveImage(_ image: UIImage, inAlbumNamed: String) {
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            if let album = album(named: inAlbumNamed) {
                saveImage(image, toAlbum: album)
            } else {
                createAlbum(withName: inAlbumNamed) {
                    if let album = album(named: inAlbumNamed) {
                        saveImage(image, toAlbum: album)
                    }
                }
            }
        }
    }

    /// 原代码
    fileprivate class func saveImage(_ image: UIImage, toAlbum album: PHAssetCollection) {
        PHPhotoLibrary.shared().performChanges({
            let changeRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)
            let enumeration: NSArray = [changeRequest.placeholderForCreatedAsset!]
            albumChangeRequest?.addAssets(enumeration)
        })
    }
    
    fileprivate class func createAlbum(withName name: String, completion:@escaping () -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
        }, completionHandler: { success, _ in
            if success {
                completion()
            }
        })
    }
    
    fileprivate class func album(named: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", named)
        let collection = PHAssetCollection.fetchAssetCollections(with: .album,
                                                                 subtype: .any,
                                                                 options: fetchOptions)
        return collection.firstObject
    }
}
