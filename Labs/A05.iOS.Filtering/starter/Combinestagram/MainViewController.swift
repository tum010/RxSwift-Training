/*
 * Copyright (c) 2016 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import UIKit
import RxSwift

class MainViewController: UIViewController {
    
    @IBOutlet weak var imagePreview: UIImageView!
    @IBOutlet weak var buttonClear: UIButton!
    @IBOutlet weak var buttonSave: UIButton!
    @IBOutlet weak var itemAdd: UIBarButtonItem!
    @IBOutlet weak var labelTotalPhoto: UILabel!
    
    private let bag = DisposeBag()
    private let images = Variable<[UIImage]>([])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 11.0, *) {
            self.navigationController?.navigationBar.prefersLargeTitles = true
        }
        
        images.asObservable()
            .subscribe(onNext: { [weak self] photos in
                guard let preview = self?.imagePreview else { return }
                preview.image = UIImage.collage(images: photos, size: preview.frame.size)
            })
            .disposed(by: bag)
        
        images.asObservable()
            .subscribe(onNext: { photos in
                self.updateUI(photos: photos)
            })
            .disposed(by: bag)
    }
    
    private func updateUI(photos: [UIImage]) {
        buttonSave.isEnabled = photos.count > 0 && photos.count % 2 == 0
        buttonClear.isEnabled = photos.count > 0
        itemAdd.isEnabled = photos.count < 6
        labelTotalPhoto.text = "\(photos.count)  photo\(photos.count < 2 ? "" : "s")"
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("resources: \(RxSwift.Resources.total)")
    }
    
    @IBAction func actionClear() {
        images.value = []
    }
    
    @IBAction func actionAdd() {
        let photoViewController = self.storyboard?.instantiateViewController(withIdentifier: "PhotosViewController") as! PhotosViewController
        navigationController?.pushViewController(photoViewController, animated: true)
        
        photoViewController.selectedPhoto
            .subscribe(onNext: { [weak self] newImage in
                guard let images = self?.images else {return }
                images.value.append(newImage)
            }, onDisposed: {
                print("Complete photo selection.")
            })
            .disposed(by: photoViewController.bag)
    }
    
    @IBAction func actionSave() {
        guard let image = imagePreview.image else { return }
        PhotoWriter.save(image)
            .subscribe(onError: { [weak self] error in
                if let view = self {
                    view.showMessage(title: "Error", description: error.localizedDescription)
                        .subscribe().disposed(by: view.bag)
                }
                }, onCompleted: { [weak self] in
                    if let view = self {
                        view.showMessage(title: "Save", description: "")
                            .subscribe()
                            .disposed(by: view.bag)
                        view.actionClear()
                    }
            })
            .disposed(by: bag)
    }
}
