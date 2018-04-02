Pod::Spec.new do |s|
  s.name         = "LocoKitCore"
  s.version      = "5.1.1"
  s.summary      = "Location and activity recording framework"
  s.homepage     = "https://www.bigpaua.com/locokit/"
  s.author       = { "Matt Greenfield" => "matt@bigpaua.com" }
  s.license      = { :text => "Copyright 2018 Matt Greenfield. All rights reserved.", 
                     :type => "Commercial" }
  s.source       = { :git => 'https://github.com/sobri909/LocoKit.git', :tag => '5.1.1' }
  s.frameworks   = 'CoreLocation', 'CoreMotion' 
  s.ios.deployment_target = '10.0'
  s.ios.vendored_frameworks = 'LocoKitCore.framework'
end
