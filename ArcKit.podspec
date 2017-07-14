Pod::Spec.new do |s|
  s.name         = "ArcKit"
  s.version      = "0.1.0"
  s.summary      = "Location and activity recording framework"
  s.homepage     = "https://github.com/sobri909/ArcKit"
  s.author       = { "Matt Greenfield" => "matt@bigpaua.com" }
  s.license      = { :text => "Copyright 2017 Matt Greenfield. All rights reserved.", :type => "Commercial" }
  s.source       = { :http => "https://github.com/sobri909/ArcKit/raw/0.1.0/ArcKit.zip" }
  s.frameworks   = 'CoreLocation', 'CoreMotion'
  s.ios.deployment_target = '10.0'
  s.ios.vendored_frameworks = 'ArcKit.framework'
end
