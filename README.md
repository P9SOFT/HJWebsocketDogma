HJWebsocketDogma
============

Websocket client library based on HJAsyncTcpCommunicator.

# Installation

You can download the latest framework files from our Release page.
HJWebsocketDogma also available through CocoaPods. To install it simply add the following line to your Podfile.
pod ‘HJWebsocketDogma’

# Setup

HJWebsocketDogma is library based on HJAsyncTcpCommunicator, and HJAsyncTcpCommunicator is framework based on Hydra.
Add the worker to Hydra, bind HJAsyncTcpCommunicator and start.

```swift
Hydra.default().addCommonWorker()
HJAsyncTcpCommunicateManager.default().standby(withWorkerName: HydraCommonWorkerName)
HJAsyncTcpCommunicateManager.default().bind(toHydra: Hydra.default())
Hydra.default().startAllWorkers()
```

Declare HJWebsocketDogma.

```swift
let wsdogma = HJWebsocketDogma(limitFrameSize: 8180, limitMessageSize: 1024*1024*10)
```

Register server information with key that you handling.
For example, for "http://localhost:8080/ws",

```swift
let serverKey = "MyServerKey"
let parameters:[AnyHashable:Any] = [HJWebsocketDogma.parameterOriginKey:"http://localhost:8080/ws, HJWebsocketDogma.parameterEndpointKey:"ws"];
HJAsyncTcpCommunicateManager.default().setServerAddress("localhost", port: 8080, parameters: parameters, forKey: serverKey)
let wsdogma = HJWebsocketDogma(limitFrameSize: 8180, limitMessageSize: 1024*1024*10)
```

# Play

Call HJAsyncTcpCommunicateManager interface with HJWebsocketDogma and write business code as your way.

```swift
HJAsyncTcpCommunicateManager.default().connect(toServerKey: serverKey, timeout: 3.0, dogma: wsdogma, connectHandler: { (flag, headerObject, bodyObject) in
    if flag == true { // connect ok
        print("- server \(key) connected.")
    } else { // connect failed
        print("- server \(key) connect failed.")
    }
}, receiveHandler: { (flag, headerObject, bodyObject) in
    if flag == true { // receive ok
        print("- server \(key) received.")
        if let dataFrame = headerObject as? HJWebsocketDataFrame {
            if let text = dataFrame.data as? String {
                print("- got text")
            } else if let data = dataFrame.data as? Data {
                print("- got binary")
            }
        }
    } else { // receive failed
        print("- server \(key) receive failed.")
    }
}, disconnect: { (flag, headerObject, bodyObject) in
    print("- server \(key) disconnected, \(self.wsdogma.closeReason ?? "done").")
})
```

You can also observe HJWebsocketDogma event to deal with business logic.

```swift
NotificationCenter.default.addObserver(self, selector: #selector(self.tcpCommunicateManagerHandler(notification:)), name: NSNotification.Name(rawValue: HJAsyncTcpCommunicateManagerNotification), object: nil)
```

```swift
@objc func tcpCommunicateManagerHandler(notification:Notification) {
	guard let userInfo = notification.userInfo, let key = userInfo[HJAsyncTcpCommunicateManagerParameterKeyServerKey] as? String, let event = userInfo[HJAsyncTcpCommunicateManagerParameterKeyEvent] as? Int else {
            return
        }
        
        if key == serverKey, let event = HJAsyncTcpCommunicateManagerEvent(rawValue: event) {
            switch event {
            case .connected:
                print("- server \(key) connected.")
            case .disconnected:
                print("- server \(key) disconnected.")
            case .sent:
                print("- server \(key) sent.")
            case .sendFailed:
                print("- server \(key) send failed.")
            case .received:
                print("- server \(key) received.")
            default:
                break
            }
        }
    }
```

Send text like this,

```swift
let headerObject = HJWebsocketDogma.textFrame(text: "hello")
HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toServerKey: serverKey) { (flag, headerObject, bodyObject) in
    if flag == false { // send failed
        print("- server \(key) send failed.")
    } else {
        print("- server \(key) sent.")
    }   
}
```

Send binary like this,

```swift
let headerObject = HJWebsocketDogma.binaryFrame(data: Data("hello".utf8))
HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toServerKey: serverKey) { (flag, headerObject, bodyObject) in
    if flag == false { // send failed
        print("- server \(key) send failed.")
    } else {
        print("- server \(key) sent.")
    }   
}
```

# License

MIT License, where applicable. http://en.wikipedia.org/wiki/MIT_License
