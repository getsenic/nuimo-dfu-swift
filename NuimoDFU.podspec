Pod::Spec.new do |s|
  s.name         = "NuimoDFU"
  s.version      = "0.1.0"
  s.summary      = "Swift library for updating the firmware of Senic's Nuimo controllers"
  s.description  = <<-DESC
                     Swift library for updating the firmware of Senic's Nuimo controllers
                   DESC
  s.documentation_url = 'https://github.com/getsenic/nuimo-dfu-swift'
  s.homepage     = "https://senic.com"
  s.license      = { :type => "MIT", :file => "LICENSE" }

  s.author             = { "Lars Blumberg (Senic GmbH)" => "lars@senic.com" }
  s.social_media_url   = "http://twitter.com/heysenic"
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"

  s.source       = { :git => "https://github.com/getsenic/nuimo-dfu-swift.git", :tag => "#{s.version}" }
  s.framework    = 'CoreBluetooth'
  s.source_files = "Sources/*.swift"

  s.dependency 'Alamofire',     '~> 3.4'
  s.dependency 'iOSDFULibrary', '~> 1.0.8'
  s.dependency 'NuimoSwift',    '~> 0.7.0'
  s.dependency 'Then',          '~> 1.0.3'
end
