import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        // * 對 App badge 進行計數, 原則上通過 APNs 的都會經過這層, 當然推播物件要加上 mutable_content 允許 NSE 做事
        // * 不管 App 是否開啟, 背景模式 or not, 所有推播都會經過這層 
        var count = 0
        if let userDefaults = UserDefaults(suiteName: "YOUR_APPGROUP_INDENTIFY") {
            count = userDefaults.integer(forKey: "count") + 1
            userDefaults.set(count, forKey: "count")
            userDefaults.synchronize()
        }
        //
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let safeBestAttemptContent = bestAttemptContent {
            // * 對推播物件 badge 進行操作, 由本地進行未讀計數
            // * 計數由套件呼叫內部方法減少或歸零
            safeBestAttemptContent.badge = count as NSNumber
            // * 推播解析, 判斷推播物件是否帶有補充信息
            guard let info = request.content.userInfo["aps"] as? NSDictionary, let alert = info["alert"] as? Dictionary<String,String> else {
                contentHandler(safeBestAttemptContent)
                return
            }
            // * 推播檢查機制, 由推播物件帶有的特定 push_id, 反向通知後端推播狀況
            if let push_id = alert["push_id"], let url = URL(string: "notify-calculation.com") {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.httpMethod = "POST"
                request.addValue("UserAgent", forHTTPHeaderField: "User-Agent")

                var httpBody = "push_id=\(push_id)"
                request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = httpBody.data(using: .utf8)

                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in

                }
                DispatchQueue.global().async {
                    task.resume()
                }
            }
            // ! 附檔一次只能一種喔, 魚和熊掌不能兼得, 要同時拿到魚和熊掌的話, 要另外用 NCE 寫自訂 type 引用
            // * 目前以圖片優先度較為高
            // * 圖片附加檔案機制, 根據推播訊息夾帶圖片遠端位址, 至用戶手機後再進行下載動作, 注意圖片有 10 MB 的限制
            if let imageURLString = alert["image"],let imageURL = URL(string: imageURLString) {
                // * 註冊圖片下載任務
                let imageDataTask = URLSession.shared.dataTask(with: imageURL) { (data, response, error) in
                    guard let fileURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(imageURL.lastPathComponent) else {
                        contentHandler(safeBestAttemptContent)
                        return
                    }
                    
                    guard (try? data?.write(to: fileURL)) != nil else {
                        contentHandler(safeBestAttemptContent)
                        return
                    }
                    
                    guard let attachment = try? UNNotificationAttachment(identifier: "image", url: fileURL, options: nil) else {
                        contentHandler(safeBestAttemptContent)
                        return
                    }

                    // * 更改推播附檔屬性
                    safeBestAttemptContent.categoryIdentifier = "image"
                    safeBestAttemptContent.attachments = [attachment]                
                    contentHandler(safeBestAttemptContent)
                }
                // * 執行圖片下載任務
                imageDataTask.resume()
            }
            // * 影片附加檔案機制, 根據推播訊息夾帶影音遠端位址, 至用戶手機後再進行下載動作, 注意影片有 50 MB 的限制 ( 別想放廣告 :X )
            guard let movieURLString = alert["movie"],let movieURL = URL(string: movieURLString) else {
                contentHandler(safeBestAttemptContent)
                return
            }
            // * 註冊影片下載任務
            let movieDataTask = URLSession.shared.dataTask(with: movieURL) { (data, response, error) in
                guard let fileURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(movieURL.lastPathComponent) else {
                    contentHandler(safeBestAttemptContent)
                    return
                }
                
                guard (try? data?.write(to: fileURL)) != nil else {
                    contentHandler(safeBestAttemptContent)
                    return
                }
                
                guard let attachment = try? UNNotificationAttachment(identifier: "movie", url: fileURL, options: nil) else {
                    contentHandler(safeBestAttemptContent)
                    return
                }
                
                // * 更改推播附檔屬性
                safeBestAttemptContent.categoryIdentifier = "movie"
                safeBestAttemptContent.attachments = [attachment]                
                contentHandler(safeBestAttemptContent)
            }
            // * 執行影片下載任務
            movieDataTask.resume()
        }
    }
    // * 沒時間解釋了 快上車, 來不及的推播任務請走這裡, 原則上攔住推播的第 29.9 秒會觸發這裡, 預設為返還最原始的推播訊息
    override func serviceExtensionTimeWillExpire() { 
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}
