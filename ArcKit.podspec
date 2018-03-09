Pod::Spec.new do |s|
  s.name         = "ArcKit"
  s.version      = "5.0.0.pre.7"
  s.summary      = "Location and activity recording framework"
  s.homepage     = "https://arc-web.herokuapp.com"
  s.author       = { "Matt Greenfield" => "matt@bigpaua.com" }
  s.license      = { :text => "Copyright 2018 Matt Greenfield. All rights reserved.", 
                     :type => "Commercial" }
  s.source       = { :git => 'https://github.com/sobri909/ArcKit.git', :tag => '5.0.0.pre.7' }
  s.frameworks   = 'CoreLocation', 'CoreMotion' 
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '4.0' }
  s.ios.deployment_target = '10.0'
  s.default_subspec = 'Base'
  s.subspec 'Base' do |sp|
    sp.source_files = 'ArcKit/Base/**/*'
    sp.dependency 'ArcKitCore', '5.0.0.pre.2'
    sp.dependency 'ReachabilitySwift', '~> 4.1'
    sp.dependency 'Upsurge', '~> 0.10'
  end
  s.subspec 'LocalStore' do |sp|
    sp.source_files = 'ArcKit/LocalStore/**/*'
    sp.dependency 'ArcKit/Base'
    sp.dependency 'GRDB.swift', '~> 2.8'
  end
end
