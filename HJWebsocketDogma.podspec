Pod::Spec.new do |s|

  s.name         = "HJWebsocketDogma"
  s.version      = "1.0.1"
  s.summary      = "Websocket library based on HJAsyncTcpCommunicator."
  s.homepage     = "https://github.com/P9SOFT/HJWebsocketDogma"
  s.license      = { :type => 'MIT' }
  s.author       = { "Tae Hyun Na" => "taehyun.na@gmail.com" }

  s.ios.deployment_target = '8.0'

  s.source       = { :git => "https://github.com/P9SOFT/HJWebsocketDogma.git", :tag => "1.0.1" }
  s.swift_version = "4.2"
  s.source_files  = "Sources/*.swift"

  s.dependency 'HJAsyncTcpCommunicator', '~> 1.2.0'

end
