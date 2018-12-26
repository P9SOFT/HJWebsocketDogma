//
//  HJWebsocketDogma.swift
//
//
//  Created by Tae Hyun Na on 2018. 12. 12.
//  Copyright (c) 2014, P9 SOFT, Inc. All rights reserved.
//
//  Licensed under the MIT license.

import UIKit
import CommonCrypto

class HJWebsocketDataFrame: NSObject {
    
    fileprivate enum Opcode:UInt8 {
                    case continuation = 0x0
                    case text = 0x1
                    case binary = 0x2
                    case close = 0x8
                    case ping = 0x9
                    case pong = 0xa
                    func isControl() -> Bool {
                        switch self {
                        case .close, .ping, .pong:
                            return true
                        default :
                            break
                        }
                        return false
                    }
    }
    
    fileprivate var fin:Bool = true
    fileprivate var opcode:Opcode = .close
    fileprivate var payload:Data?
    
    @objc var data:Any? {
        get {
            guard let payload = payload else {
                return nil
            }
            switch opcode {
            case .text :
                return String.init(data: payload, encoding: String.Encoding.utf8)
            case .binary :
                return payload
            default :
                break
            }
            return nil
        }
    }
}

class HJWebsocketDogma: HJAsyncTcpCommunicateDogma {
    
    fileprivate let maskFin:UInt8 = 0x80
    fileprivate let maskOpcode:UInt8 = 0x0f
    fileprivate let maskRsv1:UInt8 = 0x40
    fileprivate let maskRsv2:UInt8 = 0x20
    fileprivate let maskRsv3:UInt8 = 0x10
    fileprivate let maskMask:UInt8 = 0x80
    fileprivate let maskPayloadlen:UInt8 = 0x7f
    
    fileprivate class FragmentHandler: HJAsyncTcpCommunicateFragmentHandlerProtocol {
        
        var isControlFrame:Bool = false
        var limitLength:UInt = 0
        var payloadLength:UInt = 0
        var alreadySentLength:UInt = 0
        var leftPayloadLength:UInt = 0
        var lastReservedPayloadLength:UInt = 0
        
        init(isControlFrame:Bool, payloadLength:UInt, limitLength:UInt) {
            
            self.isControlFrame = isControlFrame
            if self.isControlFrame == false {
                self.payloadLength = payloadLength
                self.leftPayloadLength = payloadLength
                self.limitLength = limitLength
            }
        }
        
        func haveWritableFragment() -> Bool {
            
            if isControlFrame == true {
                return true
            }
            return (leftPayloadLength > 0)
        }
        
        func reserveFragment() -> UInt {
            
            lastReservedPayloadLength = 0
            if isControlFrame == true {
                return 2
            }
            if leftPayloadLength > 0 {
                var wbytes = (leftPayloadLength > limitLength) ? limitLength : leftPayloadLength
                lastReservedPayloadLength = wbytes
                if 126 <= wbytes && wbytes <= UINT16_MAX {
                    wbytes += UInt(MemoryLayout<UInt16>.stride)
                } else if wbytes > UINT16_MAX {
                    wbytes += UInt(MemoryLayout<UInt64>.stride)
                }
                wbytes += (UInt(MemoryLayout<UInt8>.stride)*4)
                return (2+wbytes)
            }
            return 0
        }
        
        func flushFragment() {
            
            if isControlFrame == true {
                isControlFrame = false
            } else {
                if leftPayloadLength > lastReservedPayloadLength {
                    leftPayloadLength -= lastReservedPayloadLength
                    alreadySentLength += lastReservedPayloadLength
                } else {
                    leftPayloadLength = 0
                    alreadySentLength = payloadLength
                }
            }
            lastReservedPayloadLength = 0
        }
    }
    
    fileprivate var handshakeDone:Bool = false
    fileprivate var lastFrame:HJWebsocketDataFrame?
    fileprivate var limitFrameSize:Int = 8180
    fileprivate var limitMessageSize:Int = (1024*1024*10)
    
    @objc static let parameterOriginKey = "origin"
    @objc static let parameterEndpointKey = "endpoint"
    @objc var closeReason:String?
    
    @objc static func textFrame(text: String) -> HJWebsocketDataFrame? {
        
        guard let payload = text.data(using: String.Encoding.utf8) else {
            return nil
        }
        
        let dataFrame = HJWebsocketDataFrame()
        dataFrame.opcode = .text
        dataFrame.payload = payload
        return dataFrame
    }
    
    @objc static func binaryFrame(data: Data) -> HJWebsocketDataFrame? {
        
        let dataFrame = HJWebsocketDataFrame()
        dataFrame.opcode = .binary
        dataFrame.payload = data
        return dataFrame
    }
    
    @objc public convenience init(limitFrameSize:Int, limitMessageSize:Int) {
        self.init()
        self.limitFrameSize = limitFrameSize
        self.limitMessageSize = limitMessageSize
    }
    
    override func methodType() -> HJAsyncTcpCommunicateDogmaMethodType {
        
        return .headerWithBody
    }
    
    override func prepareAfterConnected() -> Bool {
        
        closeReason = nil
        return true
    }
    
    override func needHandshake(_ anQuery: Any?) -> Bool {
        
        return (handshakeDone == false)
    }
    
    override func firstHandshakeObject(afterConnected anQuery: Any?) -> Any? {
        
        guard let query = anQuery as? HYQuery, let info = query.parameter(forKey: HJAsyncTcpCommunicateExecutorParameterKeyServerInfo) as? HJAsyncTcpServerInfo, let secWebsocketKeyData = NSMutableData.init(length: 16) else {
            return false
        }
        if SecRandomCopyBytes(kSecRandomDefault, secWebsocketKeyData.length, secWebsocketKeyData.mutableBytes) != 0 {
            return false
        }
        let secWebSocketKeyString = secWebsocketKeyData.base64EncodedString(options: [])
        let host = "\(info.address ?? "localhost"):\(info.port ?? 80)"
        let origin = info.parameters?[HJWebsocketDogma.parameterOriginKey] as? String ?? "http://\(host)"
        var endpoint = info.parameters?[HJWebsocketDogma.parameterEndpointKey] as? String ?? "/"
        if endpoint.hasPrefix("/") == false {
            endpoint = "/\(endpoint)"
        }
        let body = "GET \(endpoint) HTTP/1.1\r\nHost: \(host)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(secWebSocketKeyString)\r\nOrigin: \(origin)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        return body as NSString
    }
    
    override func nextHandshakeObjectAfterUpdateHandshakeStatus(from handshakeObject: Any?) -> Any? {
        
        if let body = handshakeObject as? NSString {
            handshakeDone = (body.range(of: "HTTP/1.1 101 Switching Protocols").location != NSNotFound)
        }
        return nil
    }
    
    override func lengthOfHandshake(fromStream stream: UnsafeMutablePointer<UInt8>?, streamLength: UInt, appendedLength: UInt) -> UInt {
        
        guard let stream = stream, let string = NSString(bytes:stream, length:Int(streamLength), encoding:String.Encoding.utf8.rawValue) else {
            return 0
        }
        let range = string.range(of: "\r\n\r\n")
        return (range.location == NSNotFound) ? 0 : UInt(range.location+range.length)
    }
    
    override func handshakeObject(fromHeaderStream stream: UnsafeMutablePointer<UInt8>?, streamLength: UInt) -> Any? {
        
        guard let stream = stream, streamLength > 0, let body = NSString(bytes:stream, length:Int(streamLength), encoding:String.Encoding.utf8.rawValue) else {
            return nil
        }
        return body
    }
    
    override func isBrokenHandshakeObject(_ handshakeObject: Any?) -> Bool {
        
        guard let body = handshakeObject as? NSString, body.length > 0 else {
            return true
        }
        return false
    }
    
    override func lengthOfHeader(fromStream stream:UnsafeMutablePointer<UInt8>?, streamLength:UInt, appendedLength:UInt) -> UInt {
        
        guard let stream = stream, streamLength >= 2 else {
            return 0
        }
        let masked = ((stream[1] & maskMask) != 0)
        var extraHeaderLength = UInt32(masked ? MemoryLayout<UInt32>.stride : 0)
        var payloadLength = UInt64(stream[1] & maskPayloadlen)
        switch payloadLength {
        case 126:
            extraHeaderLength += UInt32(MemoryLayout<UInt16>.stride)
            var len:UInt16 = 0
            memcpy(&len, stream+2, MemoryLayout<UInt16>.stride)
            payloadLength = UInt64(CFSwapInt16HostToBig(len))
        case 127:
            extraHeaderLength += UInt32(MemoryLayout<UInt64>.stride)
            var len:UInt64 = 0
            memcpy(&len, stream+2, MemoryLayout<UInt64>.stride)
            payloadLength = CFSwapInt64HostToBig(len)
        default:
            break
        }
        let headerLength = 2 + UInt(extraHeaderLength) + UInt(payloadLength)
        if headerLength <= streamLength {
            return UInt(headerLength)
        }
        return 0
    }
    
    override func headerObject(fromHeaderStream stream:UnsafeMutablePointer<UInt8>?, streamLength:UInt) -> Any? {
        
        guard let stream = stream, streamLength >= 2 else {
            return nil
        }
        
        let rsv1 = ((stream[0] & maskRsv1) != 0)
        let rsv2 = ((stream[0] & maskRsv2) != 0)
        let rsv3 = ((stream[0] & maskRsv3) != 0)
        if rsv2 == true || rsv3 == true {
            return nil
        }
        let frame = lastFrame ?? HJWebsocketDataFrame()
        frame.fin = ((stream[0] & maskFin) != 0)
        
        var opcode = HJWebsocketDataFrame.Opcode(rawValue: UInt8(stream[0] & maskOpcode)) ?? .close
        if opcode == .continuation {
            opcode = frame.opcode
        } else {
            frame.opcode = opcode
        }
        if opcode.isControl() == true, rsv1 == true {
            return nil
        }
        
        let masked = ((stream[1] & maskMask) != 0)
        var payloadLength = UInt64(stream[1] & maskPayloadlen)
        var extraHeaderLength = UInt32(masked ? MemoryLayout<UInt32>.stride : 0)
        switch payloadLength {
        case 126:
            extraHeaderLength += UInt32(MemoryLayout<UInt16>.stride)
            var len:UInt16 = 0
            memcpy(&len, stream+2, MemoryLayout<UInt16>.stride)
            payloadLength = UInt64(CFSwapInt16HostToBig(len))
        case 127:
            extraHeaderLength += UInt32(MemoryLayout<UInt64>.stride)
            var len:UInt64 = 0
            memcpy(&len, stream+2, MemoryLayout<UInt64>.stride)
            payloadLength = CFSwapInt64HostToBig(len)
        default:
            break
        }
        switch opcode {
        case .close :
            var closeCode:UInt16 = 0
            memcpy(&closeCode, stream+2, MemoryLayout<UInt16>.stride)
            frame.payload = Data(bytes: stream+2+MemoryLayout<UInt16>.stride, count: Int(payloadLength)-Int(MemoryLayout<UInt16>.stride))
            closeReason = String.init(data: frame.payload as Data? ?? Data(), encoding: String.Encoding.utf8)
        case .text, .binary :
            if frame.payload != nil {
                frame.payload!.append(stream+2+Int(extraHeaderLength), count: Int(payloadLength))
            } else {
                frame.payload = Data(bytes: stream+2+Int(extraHeaderLength), count: Int(payloadLength))
            }
        default :
            break
        }
        lastFrame = (frame.fin == true) ? nil : frame
        return frame
    }
    
    override func isBrokenHeaderObject(_ headerObject:Any?) -> Bool {
        
        guard (headerObject as? HJWebsocketDataFrame) != nil else {
            return true
        }
        return false
    }
    
    override func isControlHeaderObject(_ headerObject: Any?) -> Bool {
        
        guard let frame = headerObject as? HJWebsocketDataFrame else {
            return false
        }
        return ((frame.fin == false) || frame.opcode.isControl())
    }
    
    override func controlHeaderObjectHandling(_ headerObject: Any?) -> Any? {
        
        guard let frame = headerObject as? HJWebsocketDataFrame else {
            return nil
        }
        
        let feedback = HJWebsocketDataFrame()
        switch frame.opcode {
        case .ping:
            feedback.opcode = .pong
        case .pong:
            feedback.opcode = .ping
        default:
            return nil
        }
        return feedback
    }
    
    override func lengthOfHeader(fromHeaderObject headerObject:Any?) -> UInt {
        
        if let frame = headerObject as? HJWebsocketDataFrame {
            var len:UInt = 2
            if let payload = frame.payload, payload.count > 0 {
                if payload.count >= 126, payload.count <= UINT16_MAX {
                    len += UInt(MemoryLayout<UInt16>.stride)
                } else if payload.count > UINT16_MAX {
                    len += UInt(MemoryLayout<UInt64>.stride)
                }
                len += (UInt(MemoryLayout<UInt8>.stride*4) + UInt(payload.count))
            }
            return len
        }
        return 0
    }
    
    override func lengthOfHandshake(fromHandshakeObject handshakeObject: Any?) -> UInt {
        
        guard let handshakeString = handshakeObject as? NSString else {
            return 0
        }
        return UInt(handshakeString.lengthOfBytes(using: String.Encoding.utf8.rawValue))
    }
    
    override func fragmentHandler(fromHeaderObject headerObject: Any?, bodyObject: Any?) -> Any? {
        
        guard limitFrameSize >= 2, let frame = headerObject as? HJWebsocketDataFrame else {
            return nil
        }
        return FragmentHandler(isControlFrame: frame.opcode.isControl(), payloadLength: UInt(frame.payload?.count ?? 0), limitLength: UInt(limitFrameSize))
    }
    
    override func writeBuffer(_ writeBuffer: UnsafeMutablePointer<UInt8>?, bufferLength: UInt, fromHeaderObject headerObject: Any?, bodyObject: Any?, fragmentHandler: Any?) -> UInt {
        
        guard let plook = writeBuffer, bufferLength > 0 else {
            return 0
        }
        
        if fragmentHandler == nil, let headerString = headerObject as? NSString {
            let wbytes = headerString.lengthOfBytes(using: String.Encoding.utf8.rawValue)
            memcpy(plook, headerString.utf8String, wbytes)
            return UInt(wbytes);
        }
        
        guard let frame = headerObject as? HJWebsocketDataFrame, let fragmentHandler = fragmentHandler as? FragmentHandler else {
            return 0
        }
        
        var opcode = frame.opcode
        if fragmentHandler.alreadySentLength > 0 {
            opcode = .continuation
        }
        if opcode.isControl() == true {
            plook[0] = 0
            plook[0] |= maskFin
            plook[0] |= (maskOpcode & opcode.rawValue)
            plook[1] = 0
            return 2
        }
        
        guard let payload = frame.payload, payload.count > 0, (opcode == .text || opcode == .binary || opcode == .continuation), fragmentHandler.lastReservedPayloadLength <= INT_MAX else {
            return 0
        }
        
        let currentBytes = Int(fragmentHandler.lastReservedPayloadLength)
        var lookIndex:Int = 2
        plook[0] = 0
        frame.fin = (fragmentHandler.leftPayloadLength - fragmentHandler.lastReservedPayloadLength) > 0 ? false : true
        if frame.fin == true {
            plook[0] |= maskFin
        }
        plook[0] |= (maskOpcode & opcode.rawValue)
        plook[1] = 0
        if currentBytes < 126 {
            plook[1] = UInt8(currentBytes)
        } else if currentBytes <= UINT16_MAX {
            plook[1] = 126
            var len = CFSwapInt16BigToHost(UInt16(currentBytes))
            memcpy(plook+lookIndex, &len, Int(MemoryLayout<UInt16>.stride))
            lookIndex += Int(MemoryLayout<UInt16>.stride)
        } else {
            plook[1] = 127
            var len = CFSwapInt64BigToHost(UInt64(currentBytes))
            memcpy(plook+lookIndex, &len, Int(MemoryLayout<UInt64>.stride))
            lookIndex += Int(MemoryLayout<UInt64>.stride)
        }
        guard let secMaskKey = NSMutableData.init(length: Int(MemoryLayout<UInt8>.stride)*4) else {
            return 0
        }
        if SecRandomCopyBytes(kSecRandomDefault, secMaskKey.length, secMaskKey.mutableBytes) != 0 {
            return 0
        }
        plook[1] |= maskMask
        memcpy( plook+lookIndex, secMaskKey.mutableBytes.assumingMemoryBound(to: UInt8.self), secMaskKey.length)
        lookIndex += secMaskKey.length
        _ = payload.withUnsafeBytes { (unsafePointer: UnsafePointer<UInt8>) in
            memcpy( plook+lookIndex, unsafePointer+Int(fragmentHandler.alreadySentLength), Int(currentBytes))
        }
        let maskBuff:UnsafeMutablePointer<UInt8> = secMaskKey.mutableBytes.assumingMemoryBound(to: UInt8.self)
        let maskBufflen:Int = secMaskKey.length
        for i:Int in 0..<currentBytes {
            let index = lookIndex + i
            plook[index] = plook[index] ^ maskBuff[i%maskBufflen]
        }
        
        return UInt(lookIndex+currentBytes)
    }
    
    override func resetAfterDisconnected() {
        
        handshakeDone = false
    }
}
