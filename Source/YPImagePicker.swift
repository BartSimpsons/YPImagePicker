//
//  YPImagePicker.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

public protocol YPImagePickerDelegate: AnyObject {
    func imagePickerHasNoItemsInLibrary(_ picker: YPImagePicker)
    func shouldAddToSelection(indexPath: IndexPath, numSelections: Int) -> Bool
}

open class YPImagePicker: UINavigationController {
    public typealias DidFinishPickingCompletion = (_ items: [YPMediaItem], _ cancelled: Bool) -> Void

    // MARK: - Public

    public weak var imagePickerDelegate: YPImagePickerDelegate?
    public func didFinishPicking(completion: @escaping DidFinishPickingCompletion) {
        _didFinishPicking = completion
    }

    /// Get a YPImagePicker instance with the default configuration.
    public convenience init() {
        self.init(configuration: YPImagePickerConfiguration.shared)
    }

    /// Get a YPImagePicker with the specified configuration.
    public required init(configuration: YPImagePickerConfiguration) {
        YPImagePickerConfiguration.shared = configuration
        picker = YPPickerVC()
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen // Force .fullScreen as iOS 13 now shows modals as cards by default.
        picker.pickerVCDelegate = self
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return YPImagePickerConfiguration.shared.preferredStatusBarStyle
    }

    // MARK: - Private

    private var _didFinishPicking: DidFinishPickingCompletion?

    // This nifty little trick enables us to call the single version of the callbacks.
    // This keeps the backwards compatibility keeps the api as simple as possible.
    // Multiple selection becomes available as an opt-in.
    private func didSelect(items: [YPMediaItem]) {
        _didFinishPicking?(items, false)
    }
    
    private let loadingView = YPLoadingView()
    private let picker: YPPickerVC!

    override open func viewDidLoad() {
        super.viewDidLoad()
        picker.didClose = { [weak self] in
            self?._didFinishPicking?([], true)
        }
        viewControllers = [picker]
        setupLoadingView()
        navigationBar.isTranslucent = false
        navigationBar.tintColor = .ypLabel
        view.backgroundColor = .ypSystemBackground

        /* for note */
        if #available(iOS 15.0, *) {
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithOpaqueBackground()
            self.navigationBar.scrollEdgeAppearance = navBarAppearance
        }
        /* for note */
        
        picker.didSelectItems = { [weak self] items in
            // Use Fade transition instead of default push animation
            let transition = CATransition()
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            transition.type = CATransitionType.fade
            self?.view.layer.add(transition, forKey: nil)
            
            // Multiple items flow
            if items.count > 1 {
                if YPConfig.library.skipSelectionsGallery {
                    self?.didSelect(items: items)
                    return
                } else {
                    let selectionsGalleryVC = YPSelectionsGalleryVC(items: items) { _, items in
                        self?.didSelect(items: items)
                    }
                    self?.pushViewController(selectionsGalleryVC, animated: true)
                    return
                }
            }
            
            // One item flow
            let item = items.first!
            switch item {
            case .photo(let photo):
                let completion = { (photo: YPMediaPhoto) in
                    let mediaItem = YPMediaItem.photo(p: photo)
                    // Save new image or existing but modified, to the photo album.
                    if YPConfig.shouldSaveNewPicturesToAlbum {
                        let isModified = photo.modifiedImage != nil
                        if photo.fromCamera || (!photo.fromCamera && isModified) {
//                            YPPhotoSaver.trySaveImage(photo.image, inAlbumNamed: YPConfig.albumName)

                            /* for note */
                            /// 因业务上 头像需剪切 且不需要相册多选 所以暂时这样判断 来区分相册多选
                            if case let YPCropType.rectangle(ratio) = YPConfig.showsCrop {
                                YPPhotoSaver.trySaveImage(photo.image, inAlbumNamed: YPConfig.albumName)
                                self?.didSelect(items: [mediaItem])
                            } else {
                                /// 相册多选
                                YPPhotoSaver.trySaveImageAndWait(photo.image, inAlbumNamed: YPConfig.albumName) { (assetChangeRequest) in
                                    /**
                                     在多图选择时选择相册和拍照操作同时进行  拍照的照片会和相册的选择混排，所以采取了拍照后保存在系统相册的图片会在相册选择时直接选择中
                                     以下代码是为了获取拍照图片的PHAsset
                                     */
                                    var identifier = assetChangeRequest?.placeholderForCreatedAsset?.localIdentifier ?? ""
                                    
                                    let fetchOptions = PHFetchOptions()
                                    fetchOptions.predicate = NSPredicate(format: "title = %@", YPConfig.albumName)
                                    let collection = PHAssetCollection.fetchAssetCollections(with: .album,
                                                                                             subtype: .any,
                                                                                             options: fetchOptions)
                                    
                                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.15) {
                                        if let result = collection.firstObject {
                                            let options = PHFetchOptions()
                                            options.predicate = NSPredicate.init(format: "self.localIdentifier CONTAINS %@", identifier)
                                            let asset = PHAsset.fetchAssets(in: result, options: options)
                                            photo.asset = asset.firstObject
                                        }
                                        
                                        DispatchQueue.main.async {
                                            self?.didSelect(items: [YPMediaItem.photo(p: photo)])
                                        }
                                    }
                                }
                            }
                        } else {
                            self?.didSelect(items: [mediaItem])
                        }
                    } else {
                        self?.didSelect(items: [mediaItem])
                    }
                    /* for note */
                    
//                    self?.didSelect(items: [mediaItem])
                }
                
                func showCropVC(photo: YPMediaPhoto, completion: @escaping (_ aphoto: YPMediaPhoto) -> Void) {
                    switch YPConfig.showsCrop {
                    case .rectangle, .circle:
                        let cropVC = YPCropVC(image: photo.image)
                        cropVC.didFinishCropping = { croppedImage in
                            photo.modifiedImage = croppedImage
                            completion(photo)
                        }
                        self?.pushViewController(cropVC, animated: true)
                    default:
                        completion(photo)
                    }
                }
                
                if YPConfig.showsPhotoFilters {
                    let filterVC = YPPhotoFiltersVC(inputPhoto: photo,
                                                    isFromSelectionVC: false)
                    // Show filters and then crop
                    filterVC.didSave = { outputMedia in
                        if case let YPMediaItem.photo(outputPhoto) = outputMedia {
                            showCropVC(photo: outputPhoto, completion: completion)
                        }
                    }
                    self?.pushViewController(filterVC, animated: false)
                } else {
                    showCropVC(photo: photo, completion: completion)
                }
            case .video(let video):
                if YPConfig.showsVideoTrimmer {
                    let videoFiltersVC = YPVideoFiltersVC.initWith(video: video,
                                                                   isFromSelectionVC: false)
                    videoFiltersVC.didSave = { [weak self] outputMedia in
                        self?.didSelect(items: [outputMedia])
                    }
                    self?.pushViewController(videoFiltersVC, animated: true)
                } else {
                    self?.didSelect(items: [YPMediaItem.video(v: video)])
                }
            }
        }
    }
    
    deinit {
        ypLog("Picker deinited 👍")
    }
    
    private func setupLoadingView() {
        view.subviews(
            loadingView
        )
        loadingView.fillContainer()
        loadingView.alpha = 0
    }
}

extension YPImagePicker: YPPickerVCDelegate {
    func libraryHasNoItems() {
        self.imagePickerDelegate?.imagePickerHasNoItemsInLibrary(self)
    }
    
    func shouldAddToSelection(indexPath: IndexPath, numSelections: Int) -> Bool {
        return self.imagePickerDelegate?.shouldAddToSelection(indexPath: indexPath, numSelections: numSelections)
            ?? true
    }
}
