HJWebsocketDogma
============

Websocket client/server library based on HJAsyncTcpCommunicator.

# Installation

You can download the latest framework files from our Release page.
HJWebsocketDogma also available through CocoaPods. To install it simply add the following line to your Podfile.  
pod 'Hydra', :modular_headers => true  
pod 'HJAsyncTcpCommunicator', :modular_headers => true  
pod 'HJWebsocketDogma' 

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
let parameters:[AnyHashable:Any] = [HJWebsocketDogma.parameterOriginKey:"http://localhost:8080/ws", HJWebsocketDogma.parameterEndpointKey:"ws"];
let serverInfo = HJAsyncTcpServerInfo.init(address: "localhost", port: 8080, parameters: parameters)
HJAsyncTcpCommunicateManager.default().setServerInfo(serverInfo, forServerKey: serverKey)
```

# Play

Using websocket by client side,
Call HJAsyncTcpCommunicateManager interface with HJWebsocketDogma and write business code as your way.

```swift
HJAsyncTcpCommunicateManager.default().connect(serverKey, timeout: 3.0, dogma: wsdogma, connect: { (flag, key, header, body) in
    if flag == true { // connect ok
        print("- client \(key) connected.")
    } else { // connect failed
        print("- connect failed.")
    }
}, receive: { (flag, key, header, body) in
    if flag == true { // receive ok
        print("- client \(key) received.")
        if let dataFrame = headerObject as? HJWebsocketDataFrame {
            if let text = dataFrame.data as? String {
                print("- got text")
            } else if let data = dataFrame.data as? Data {
                print("- got binary")
            }
        }
    }
}, disconnect: { (flag, key, header, body) in
    if flag == true {
        let closeReason = ((header as? HJWebsocketDataFrame)?.data as? String) ?? "done"
        print("- client \(key) disconnected, \(closeReason").")
    }
})
```

After connect, you can get client key in connect handler or notification handler.
You can send data to client by that client key each other.

Send text like this,

```swift
let headerObject = HJWebsocketDogma.textFrame(text: "hello", supportMode: .client)
HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toClientKey: clientKey) { (flag, key, header, body) in
    if flag == false { // send failed
        print("- client \(key) send failed.")
    } else {
        print("- client \(key) sent.")
    }   
}
```

Send binary like this,

```swift
let headerObject = HJWebsocketDogma.binaryFrame(data: Data("hello".utf8), supportMode: .client)
HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toClientKey: serverKey) { (flag, key, header, body) in
    if flag == false { // send failed
        print("- client \(key) send failed.")
    } else {
        print("- client \(key) sent.")
    }   
}
```

Using websocket by server side,
Call HJAsyncTcpCommunicateManager interface with HJWebsocketDogma and write business code as your way.

```swift
let serverInfo = HJAsyncTcpServerInfo.init(address: "localhost", port: 8080)
HJAsyncTcpCommunicateManager.default().setServerInfo(serverInfo, forServerKey: serverKey)

HJAsyncTcpCommunicateManager.default().bind(serverKey, backlog: 4, dogma: wsdogma, bind: { (flag, key, header, body) in
    if flag == true { // bind ok
        print("- server \(key) bind ok.")
    } else { // bind failed
        print("- server \(key) bind failed.")
    }
}, accept: { (flag, key, header, body) in
    if flag == true {
       print("- client \(key) accepted" );
    }
}, receive: { (flag, key, header, body) in
    if flag == true, let clientKey = key, let dataFrame = header as? HJWebsocketDataFrame { // receive ok
        if let receivedText = dataFrame.data as? String {
            print("- client \(key) receive text: \(receivedText)")
        } else if let receivedData = dataFrame.data as? Data {
            print("- client \(key) receive binary")
        }
    }
}, disconnect: { (flag, key, header, body) in
    if flag == true {
        print("- client \(key) disconnected.")
    }
}, shutdown: { (flag, key, header, body) in
    if flag == true { // shutdown ok
        print("- server \(key) shutdowned.")
    }
})
```

Send data from server is same with client side.
Only different thing is setting supportMode to .server like above.
And you can get client key in accept handler or notification handler.

```swift
let headerObject = HJWebsocketDogma.textFrame(text: "hello", supportMode: .server)
let headerObject = HJWebsocketDogma.binaryFrame(data: Data("hello".utf8), supportMode: .server)
```

You can also broadcast data to all connected client.

```swift
let headerObject = HJWebsocketDogma.textFrame(text: "hello", supportMode: .server)
HJAsyncTcpCommunicateManager.default().broadcastHeaderObject(headerObject, bodyObject: nil, toServerKey: serverKey)
```

You can also observe HJWebsocketDogma event to deal with business logic.

```swift
NotificationCenter.default.addObserver(self, selector: #selector(self.tcpCommunicateManagerHandler(notification:)), name: NSNotification.Name(rawValue: HJAsyncTcpCommunicateManagerNotification), object: nil)
```

```swift
@objc func tcpCommunicateManagerHandler(notification:Notification) {
    guard let userInfo = notification.userInfo,
          let serverKey = userInfo[HJAsyncTcpCommunicateManagerParameterKeyServerKey] as? String,
          let eventValue = userInfo[HJAsyncTcpCommunicateManagerParameterKeyEvent] as? Int,
          let event = HJAsyncTcpCommunicateManagerEvent(rawValue: eventValue) else {
            return
    }
    let clientKey = userInfo[HJAsyncTcpCommunicateManagerParameterKeyClientKey] as? String ?? "--"
    switch event {
    case .connected:
        print("- server \(serverKey) client \(clientKey) connected.")
    case .disconnected:
        print("- server \(serverKey) client \(clientKey) disconnected.")
    case .sent:
        print("- server \(serverKey) client \(clientKey) sent.")
    case .sendFailed:
        print("- server \(serverKey) client \(clientKey) send failed.")
    case .received:
        print("- server \(serverKey) client \(clientKey) received.")
    case .binded:
        print("- server \(serverKey) binded.")
    case .accepted:
        print("- server \(serverKey) client \(clientKey) accepted.")
    case .shutdowned:
        print("- server \(serverKey) shutdowned.")
    default:
        break
    }
}
```

# License

MIT License, where applicable. http://en.wikipedia.org/wiki/MIT_License
