RUBY_VERSION_PARTS = RUBY_VERSION.split('.')
ENV['LC_ALL'] = 'it_IT.UTF-8'
if RUBY_VERSION >= "1.9"  
	Encoding.default_external = Encoding::UTF_8  
	#Encoding.default_internal = Encoding::UTF_8  
end 
$SPIDER_PATH ||= File.expand_path(File.dirname(__FILE__)+'/../..')
$SPIDER_PATHS ||= {}
$SPIDER_PATHS[:core_apps] ||= File.join($SPIDER_PATH, 'apps')
$SPIDER_LIB = $SPIDER_PATH+'/lib'
$SPIDER_RUN_PATH ||= Dir.pwd
ENV['GETTEXT_PATH'] += ',' if (ENV['GETTEXT_PATH'])
ENV['GETTEXT_PATH'] ||= ''
ENV['GETTEXT_PATH'] += $SPIDER_PATH+'/data/locale,'+$SPIDER_RUN_PATH+'/data/locale'
#$:.push($SPIDER_LIB+'/spiderfw')
$:.push($SPIDER_RUN_PATH)

$:.push($SPIDER_PATH)
# Dir.chdir($SPIDER_RUN_PATH)

$SPIDER_RUNMODE ||= ENV['SPIDER_RUNMODE']
$SPIDER_CONFIG_SETS = ENV['SPIDER_CONFIG_SETS'].split(/\s+,\s+/) if ENV['SPIDER_CONFIG_SETS']

$SPIDER_SCRIPT = $0
if $SPIDER_SCRIPT =~ /Rack|Passenger/
    $SPIDER_RACK = true
    $SPIDER_SCRIPT = ::File.expand_path('./bin/spider')
    $SPIDER_NO_RESPAWN = true
end
