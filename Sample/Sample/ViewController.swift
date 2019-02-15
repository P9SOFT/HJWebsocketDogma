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
    
    let serverKey = "test"
    let wsdogma = HJWebsocketDogma(limitFrameSize: 8180, limitMessageSize: 1024*1024*10)
    
    @IBOutlet weak var serverAddressTextField: UITextField!
    @IBOutlet weak var sendTextField: UITextField!
    @IBOutlet weak var receiveTextView: UITextView!
    @IBOutlet weak var connectButton: UIButton!
    @IBOutlet weak var receivedImageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.automaticallyAdjustsScrollViewInsets = false;
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.tcpCommunicateManagerHandler(notification:)), name: NSNotification.Name(rawValue: HJAsyncTcpCommunicateManagerNotification), object: nil)
    }
    
    @IBAction func connectButtonTouchUpInside(_ sender: Any) {
        
        if serverAddressTextField.isFirstResponder == true {
            serverAddressTextField.resignFirstResponder()
        }
        if sendTextField.isFirstResponder == true {
            sendTextField.resignFirstResponder()
        }
        
        if connectButton.title(for: UIControl.State()) == "Connect" {
            if let inputString = serverAddressTextField.text, inputString.count > 0, let url = URL(string:inputString) {
                
                self.connectButton.isEnabled = false
                
                let serverAddress = url.host ?? "localhost"
                let port = (url.port ?? 80) as NSNumber
                let endpoint = url.path
                
                // set extra paramter for websocket handshaking
                let parameters:[AnyHashable:Any] = [HJWebsocketDogma.parameterOriginKey:inputString, HJWebsocketDogma.parameterEndpointKey:endpoint];
                
                // set key to given server address and port
                HJAsyncTcpCommunicateManager.default().setServerAddress(serverAddress, port: port, parameters: parameters, forKey: serverKey)
                
                // request connect and regist each handlers.
                HJAsyncTcpCommunicateManager.default().connect(toServerKey: serverKey, timeout: 3.0, dogma: wsdogma, connect: { (flag, key, header, body) in
                    if flag == true { // connect ok
                        self.connectButton.setTitle("Disconnect", for:UIControl.State())
                        self.connectButton.isEnabled = true
                        self.showAlert("Connected", completion:nil)
                    } else { // connect failed
                        self.connectButton.isEnabled = true
                        self.showAlert("Connect Failed", completion:nil)
                    }
                }, receive: { (flag, key, header, body) in
                    if flag == true { // receive ok
                        if let dataFrame = header as? HJWebsocketDataFrame {
                            if let receivedText = dataFrame.data as? String {
                                self.receiveTextView.text += "\n- text: \(receivedText)"
                            } else if let receivedData = dataFrame.data as? Data, let image = UIImage(data: receivedData) {
                                self.receivedImageView.image = image
                            }
                        }
                    } else { // receive failed
                        self.showAlert("Receive Failed", completion:nil)
                    }
                }, disconnect: { (flag, key, header, body) in
                    if flag == true { // disconnect ok
                        if let closeReason = self.wsdogma.closeReason {
                            self.receiveTextView.text += "\n- close: \(closeReason)"
                        }
                        self.showAlert("Disconnected", completion: { () -> Void in
                            self.connectButton.isEnabled = true
                            self.connectButton.setTitle("Connect", for:UIControl.State())
                        })
                    }
                })
            } else {
                showAlert("Fill Server Address", completion: nil)
            }
        } else {
            // request disconnect.
            HJAsyncTcpCommunicateManager.default().disconnectFromServer(forKey: serverKey)
        }
    }
    
    @IBAction func sendButtonTouchUpInside(_ sender: Any) {
        
        if serverAddressTextField.isFirstResponder == true {
            serverAddressTextField.resignFirstResponder()
        }
        if sendTextField.isFirstResponder == true {
            sendTextField.resignFirstResponder()
        }
        
        guard let text = sendTextField.text, text.count > 0 else {
            showAlert("Fill Send Text", completion:nil)
            return
        }
        
        let headerObject = HJWebsocketDataFrame(text: text, supportMode: .client)
        
        // send text
        HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toServerKey: serverKey) { (flag, key, header, body) in
            if flag == false { // send failed
                self.showAlert("Send Failed", completion:nil)
            }
        }
    }
    
    @IBAction func pickPhotoAndSendButtonTouchUpInside(_ sender: Any) {
        
        let vc = UIImagePickerController()
        vc.delegate = self
        vc.sourceType = .photoLibrary
        present(vc, animated: true, completion: nil)
    }
    
    func showAlert(_ message:String, completion:(() -> Void)?) {
        
        let alert = UIAlertController(title:"Alert", message:message, preferredStyle:UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title:"OK", style:UIAlertAction.Style.default, handler:nil))
        self.present(alert, animated:true, completion:completion)
    }
    
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
            
            let headerObject = HJWebsocketDataFrame(data: data, supportMode: .client)
            
            // send binary
            HJAsyncTcpCommunicateManager.default().sendHeaderObject(headerObject, bodyObject: nil, toServerKey: serverKey) { (flag, key, header, body) in
                if flag == false { // send failed
                    self.showAlert("Send Failed", completion:nil)
                }
            }
        }
        
        dismiss(animated: true, completion: nil)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        
        dismiss(animated: true, completion: nil)
    }
}
