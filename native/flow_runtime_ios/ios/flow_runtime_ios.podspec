Pod::Spec.new do |s|
  s.name = 'flow_runtime_ios'
  s.version = '1.0.0'
  s.summary = 'AIMS FLOW native iOS runtime.'
  s.description = 'Network transition events and user-visible tracking readiness.'
  s.homepage = 'https://logistic-aims.hu/flow/'
  s.license = { :type => 'Proprietary' }
  s.author = { 'AIMS' => 'office@logistic-aims.hu' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.5'
  s.swift_version = '5.0'
  s.frameworks = 'Network', 'CoreLocation', 'UserNotifications'
end
