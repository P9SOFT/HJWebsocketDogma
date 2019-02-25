//
//  ViewController.swift
//  Sample
//
//  Created by Tae Hyun Na on 2018. 12. 12.
//  Copyright (c) 2014, P9 SOFT, Inc. All rights reserved.
//
//  Licensed under the MIT license.

import UIKit

class ViewController: UIViewController {
    
    fileprivate let connectServerKey = "connectServerKey"
    fileprivate let bindServerKey = "bindServerKey"
    fileprivate let wsdogma = HJWebsocketDogma(limitFrameSize: 8180, limitMessageSize: 1024*1024*10)
    fileprivate var pickPhotoAndSendBroadcast = false
    fileprivate var currentConnectedClientKey:String?
    
    @IBOutlet weak var serverAddressTextField: UITextField!
    @IBOutlet weak var sendTextField: UITextField!
    @IBOutlet weak var receiveTextView: UITextView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var receivedImageView: UIImageView!
    @IBOutlet weak var serverPortTextField: UITextField!
    @IBOutlet weak var serverSendTextField: UITextField!
    @IBOutlet weak var serverReceiveTextView: UITextView!
    @IBOutlet weak var serverBindButton: UIButton!
    @IBOutlet weak var serverReceivedImageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.automaticallyAdjustsScrollViewInsets = false;
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.tcpCommunicateManagerHandler(notification:)), name: NSNotification.Name(rawValue: HJAsyncTcpCommunicateManagerNotification), object: nil)
    }
    
    @IBAction func connectButtonTouchUpInside(_ sender: Any) {
        
        resignAllResonders()
        
        if connectButton.title(for: .normal) == "Connect" {
            if let inputString = serverAddressTextField.text, inputString.count > 0, let url = URL(string:inputString) {
                
                self.connectButton.isEnabled = false
                
                let serverAddress = url.host ?? "localhost"
                let port = (url.port ?? 8080) as NSNumber
                let endpoint = url.path
                
                // set key to given server address, port and extra parameter for websocket handshaking
                let serverInfo = HJAsyncTcpServerInfo.init(address: serverAddress, port: port, parameters: [HJWebsocketDogma.parameterOriginKey:inputString, HJWebsocketDogma.parameterEndpointKey:endpoint])
                HJAsyncTcpCommunicateManager.default().setServerInfo(serverInfo, forServerKey: connectServerKey)
                
                // request connect and regist each handlers.
                HJAsyncTcpCommunicateManager.default().connect(connectServerKey, timeout: 3.0, dogma: wsdogma, connect: { (flag, key, header, body) in
                    if flag == true { // connect ok
                        self.currentConnectedClientKey = key
                        self.connectButton.setTitle("Disconnect", for:.normal)
                        self.connectButton.isEnabled = true
                    } else { // connect failed
                        self.connectButton.isEnabled = true
                        self.showAlert("Connect Failed", completion:nil)
                    }
                }, receive: { (flag, key, header, body) in
                    if flag == true, let dataFrame = header as? HJWebsocketDataFrame { // receive ok
                        if let receivedText = dataFrame.data as? String {
                            self.receiveTextView.text += "\n- text: \(receivedText)"
                        } else if let receivedData = dataFrame.data as? Data, let image = UIImage(data: receivedData) {
                            self.receivedImageView.image = image
                        }
                    }
                }, disconnect: { (flag, key, header, body) in
                    if flag == true { // disconnect ok
                        self.currentConnectedClientKey = nil
                        let closeReason = ((header as? HJWebsocketDataFrame)?.data as? String) ?? "done"
                        self.receiveTextView.text += "\n- close: \(closeReason)"
                        self.showAlert("Disconnected", completion: { () -> Void in
                            self.connectButton.isEnabled = true
                            self.connectButton.setTitle("Connect", for:.normal)
                        })
                    }
                })
            } else {
                showAlert("Fill Server Address", completion: nil)
            }
        } else {
            // request disconnect.
            if let clientKey = currentConnectedClientKey {
                HJAsyncTcpCommunicateManager.default().disconnectClient(forClientKey: clientKey)
            }
        }
    }
    
    @IBAction func sendButtonTouchUpInside(_ sender: Any) {
        
        resignAllResonders()
        
        guard let clientKey = currentConnectedClientKey else {
            showAlert("Connect first", completion: nil)
            return
        }
        guard let text = sendTextField.text, text.count > 0 else {
            showAlert("Fill Send Text", completion:nil)
            return
        }
        
        let headerObject = HJWebsocketDataFrame(text: text, supportMode: .client)
        
        // send text
        HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toClientKey: clientKey) { (flag, key, header, body) in
            if flag == false { // send failed
                self.showAlert("Send Failed", completion:nil)
            }
        }
    }
    
    @IBAction func pickPhotoAndSendButtonTouchUpInside(_ sender: Any) {
        
        resignAllResonders()
        
        guard currentConnectedClientKey != nil else {
            showAlert("Connect first", completion: nil)
            return
        }
        
        pickPhotoAndSendBroadcast = false
        let vc = UIImagePickerController()
        vc.delegate = self
        vc.sourceType = .photoLibrary
        present(vc, animated: true, completion: nil)
    }
    
    @IBAction func serverBindButtonTouchUpInside(_ sender: Any) {
        
        resignAllResonders()
        
        if serverBindButton.title(for: .normal) == "Bind" {
            
            if let portString = serverPortTextField.text, let port = Int(portString) {
                
                self.serverBindButton.isEnabled = false
                
                // set key to given server address and port
                let serverInfo = HJAsyncTcpServerInfo.init(address: "localhost", port: port as NSNumber)
                HJAsyncTcpCommunicateManager.default().setServerInfo(serverInfo, forServerKey: bindServerKey)
                
                // request connect and regist each handlers.
                HJAsyncTcpCommunicateManager.default().bind(bindServerKey, backlog: 4, dogma: wsdogma, bind: { (flag, key, header, body) in
                    if flag == true { // bind ok
                        self.serverBindButton.setTitle("Shutdown", for:.normal)
                        self.serverBindButton.isEnabled = true
                        self.showAlert("Binded", completion:nil)
                    } else { // bind failed
                        self.serverBindButton.isEnabled = true
                        self.showAlert("Bind Failed", completion:nil)
                    }
                }, accept: { (flag, key, header, body) in
                    
                }, receive: { (flag, key, header, body) in
                    if flag == true, let clientKey = key, let dataFrame = header as? HJWebsocketDataFrame { // receive ok
                        if let receivedText = dataFrame.data as? String {
                            self.serverReceiveTextView.text += "\n- client \(clientKey) text: \(receivedText)"
                        } else if let receivedData = dataFrame.data as? Data, let image = UIImage(data: receivedData) {
                            self.serverReceiveTextView.text += "\n- client \(clientKey) image"
                            self.serverReceivedImageView.image = image
                        }
                    }
                }, disconnect: { (flag, key, header, body) in
                    
                }, shutdown: { (flag, key, header, body) in
                    if flag == true { // shutdown ok
                        self.serverBindButton.isEnabled = true
                        self.serverBindButton.setTitle("Bind", for:.normal)
                    }
                })
            } else {
                showAlert("Fill Server Port", completion: nil)
            }
            
        } else {
            // request shutdown
            HJAsyncTcpCommunicateManager.default().shutdownServer(forServerKey: bindServerKey)
        }
    }
    
    @IBAction func serverSendButtonTouchUpInside(_ sender: Any) {
        
        resignAllResonders()
        
        guard let text = serverSendTextField.text, text.count > 0 else {
            showAlert("Fill Send Text", completion:nil)
            return
        }
        
        let headerObject = HJWebsocketDataFrame(text: text, supportMode: .server)
        
        // broadcast text
        HJAsyncTcpCommunicateManager.default().broadcastHeaderObject(headerObject, bodyObject: nil, toServerKey: bindServerKey)
    }
    
    @IBAction func serverPickPhotoAndSendButtonTouchUpInside(_ sender: Any) {
        
        pickPhotoAndSendBroadcast = true
        let vc = UIImagePickerController()
        vc.delegate = self
        vc.sourceType = .photoLibrary
        present(vc, animated: true, completion: nil)
    }
    
    fileprivate func showAlert(_ message:String, completion:(() -> Void)?) {
        
        let alert = UIAlertController(title:"Alert", message:message, preferredStyle:UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title:"OK", style:UIAlertAction.Style.default, handler:nil))
        self.present(alert, animated:true, completion:completion)
    }
    
    fileprivate func resignAllResonders() {
        
        if serverAddressTextField.isFirstResponder == true {
            serverAddressTextField.resignFirstResponder()
        }
        if sendTextField.isFirstResponder == true {
            sendTextField.resignFirstResponder()
        }
        if serverPortTextField.isFirstResponder == true {
            serverPortTextField.resignFirstResponder()
        }
        if serverSendTextField.isFirstResponder == true {
            serverSendTextField.resignFirstResponder()
        }
    }
    
    @objc func tcpCommunicateManagerHandler(notification:Notification) {
        
        guard let userInfo = notification.userInfo, let serverKey = userInfo[HJAsyncTcpCommunicateManagerParameterKeyServerKey] as? String, let eventValue = userInfo[HJAsyncTcpCommunicateManagerParameterKeyEvent] as? Int, let event = HJAsyncTcpCommunicateManagerEvent(rawValue: eventValue) else {
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
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        guard let image = info[UIImagePickerController.InfoKey.originalImage] as? UIImage else {
            dismiss(animated: true) {
                self.showAlert("Picking Image Failed", completion: nil)
            }
            return
        }
        
        if let data = image.jpegData(compressionQuality: 1) {
            
            // send binary
            
            if pickPhotoAndSendBroadcast == false {
                let headerObject = HJWebsocketDataFrame(data: data, supportMode: .client)
                if let clientKey = currentConnectedClientKey {
                    HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toClientKey: clientKey) { (flag, key, header, body) in
                        if flag == false { // send failed
                            self.showAlert("Send Failed", completion:nil)
                        }
                    }
                }
            } else {
                let headerObject = HJWebsocketDataFrame(data: data, supportMode: .server)
                HJAsyncTcpCommunicateManager.default().broadcastHeaderObject(headerObject, bodyObject: nil, toServerKey: bindServerKey)
            }
        }
        
        dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        
        dismiss(animated: true, completion: nil)
    }
}
