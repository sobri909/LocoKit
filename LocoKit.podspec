Pod::Spec.new do |s|
  s.name         = "LocoKit"
  s.version      = "7.0.0"
  s.summary      = "Location and activity recording framework"
  s.homepage     = "https://www.bigpaua.com/locokit/"
  s.author       = { "Matt Greenfield" => "matt@bigpaua.com" }
  s.license      = { :text => "Copyright 2018 Matt Greenfield. All rights reserved.", 
                     :type => "Commercial" }
  
  s.source       = { :git => 'https://github.com/sobri909/LocoKit.git', :tag => '7.0.0' }
  s.frameworks   = 'CoreLocation', 'CoreMotion' 
  s.swift_version = '4.2'
  s.ios.deployment_target = '10.0'
  s.default_subspec = 'Base'

  s.subspec 'Base' do |sp|
    sp.source_files = 'LocoKit/Base/**/*'
    sp.dependency 'LocoKitCore', '7.0.0'
    sp.dependency 'Upsurge', '~> 0.10'
  end
  
  s.subspec 'Timelines' do |sp|
    sp.source_files = 'LocoKit/Timelines/**/*'
    sp.dependency 'LocoKit/Base'
    sp.dependency 'GRDB.swift', '~> 4'
  end
end
