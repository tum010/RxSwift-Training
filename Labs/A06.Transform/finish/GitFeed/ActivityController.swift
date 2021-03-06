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
import RxCocoa
import Kingfisher

class ActivityController: UITableViewController {
    
    let repo = "ReactiveX/RxSwift"
    let cacheFileName = "events.plist"
    let modifiedFileName = "modified.txt"
    
    private let lastModified = Variable<NSString?>(nil)
    private let events = Variable<[Event]>([])
    private let bag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = repo
        
        events.asObservable()
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                self?.tableView.reloadData()
                self?.refreshControl?.endRefreshing()
            })
            .disposed(by: bag)
        
        let eventArray = (NSArray(contentsOf: self.cachedFileURL(cacheFileName)) as? [[String: Any]]) ?? []
        events.value = eventArray.flatMap(Event.init)
        
        lastModified.value = try? NSString(contentsOf: cachedFileURL(modifiedFileName), usedEncoding: nil)
        
        self.refreshControl = UIRefreshControl()
        let refreshControl = self.refreshControl!
        
        refreshControl.backgroundColor = UIColor(white: 0.98, alpha: 1.0)
        refreshControl.tintColor = UIColor.darkGray
        refreshControl.attributedTitle = NSAttributedString(string: "Pull to refresh")
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        refresh()
    }
    
    func refresh() {
        fetchEvents(repo: repo)
    }
    
    func fetchEvents(repo: String) {
        let response = Observable.from([repo])
            .map { URL(string: "https://api.github.com/repos/\($0)/events")! }
            .map { [weak self] url -> URLRequest in
                var request = URLRequest(url: url)
                if let modifiedHeader = self?.lastModified.value {
                    request.addValue(modifiedHeader as String, forHTTPHeaderField: "Last-Modified")
                }
                return request
            }
            .flatMap { request -> Observable<(HTTPURLResponse, Data)> in
                return URLSession.shared.rx.response(request: request)
            }
            .shareReplay(1)
        
        response
            .filter { response, _ -> Bool in
                return 200..<300 ~= response.statusCode
            }
            .map { _, data -> [[String: Any]] in
                guard
                    let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                    let result = jsonObject as? [[String: Any]] else {
                        return []
                }
                return result
            }
            .filter { $0.count > 0 }
            .map { objects in
                objects.flatMap(Event.init)
            }
            .subscribe(onNext: { [weak self] newEvents in
                self?.processEvents(newEvents)
            })
            .disposed(by: bag)
        
        response
            .filter { response, _ in
                200..<400 ~= response.statusCode
            }
            .flatMap { response, _ -> Observable<NSString> in
                guard let lastModified = response.allHeaderFields["Last-Modified"] as? NSString else {
                    return Observable.never()
                }
                return Observable.just(lastModified)
            }
            .subscribe(onNext: { [weak self] modifiedHeader in
                guard let strongSelf = self else { return }
                strongSelf.lastModified.value = modifiedHeader
                let url = strongSelf.cachedFileURL(strongSelf.modifiedFileName)
                try? modifiedHeader.write(
                    to: url,
                    atomically: true,
                    encoding: String.Encoding.utf8.rawValue)
            })
            .disposed(by: bag)
    }
    
    func processEvents(_ newEvents: [Event]) {
        var updatedEvents = newEvents + self.events.value
        if updatedEvents.count > 50 {
            updatedEvents = Array<Event>(updatedEvents.prefix(upTo: 50))
        }
        self.events.value = updatedEvents
        let eventsArray = updatedEvents.map { $0.dictionary } as NSArray
        eventsArray.write(to: cachedFileURL(cacheFileName), atomically: true)
    }
    
    func cachedFileURL(_ fileName: String) -> URL {
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .allDomainsMask)
            .first!
            .appendingPathComponent(fileName)
        print("Cached file - \(url.absoluteString)")
        return url
    }
    
    // MARK: - Table Data Source
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return events.value.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let event = events.value[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell")!
        cell.textLabel?.text = event.name
        cell.detailTextLabel?.text = event.repo + ", " + event.action.replacingOccurrences(of: "Event", with: "").lowercased()
        cell.imageView?.kf.setImage(with: event.imageUrl, placeholder: UIImage(named: "blank-avatar"))
        return cell
    }
}
