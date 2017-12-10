Pod::Spec.new do |s|
  s.name         = "ArcKit"
  s.version      = "4.1.0.pre.7"
  s.summary      = "Location and activity recording framework"
  s.homepage     = "https://arc-web.herokuapp.com"
  s.author       = { "Matt Greenfield" => "matt@bigpaua.com" }
  s.license      = { :text => "Copyright 2017 Matt Greenfield. All rights reserved.", 
                     :type => "Commercial" }
  s.source       = { :git => 'https://github.com/sobri909/ArcKit.git', :tag => '4.1.0.pre.7' }
  s.source_files = 'ArcKit/**/*'
  s.frameworks   = 'CoreLocation', 'CoreMotion' 
  s.ios.deployment_target = '10.0'
  s.dependency 'ArcKitCore', '4.1.0.pre.4'
  s.dependency 'ReachabilitySwift', '~> 4.1'
  s.dependency 'Upsurge', '~> 0.10'
end
